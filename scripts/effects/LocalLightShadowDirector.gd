class_name LocalLightShadowDirector
extends Node

const ActiveFrameShadowScript := preload("res://scripts/effects/ActiveFrameProjectedShadow.gd")
const CASTER_GROUP := "projected_shadow_caster"
const EMITTER_GROUP := "world_light_emitter"

var _elapsed := 0.0
var _emitter_cache_dirty := true
var _local_shadows: Dictionary = {}
var _emitter_cache: Array[Dictionary] = []
var _config: Dictionary = {}


func _ready() -> void:
	add_to_group("local_light_shadow_director")
	_reload_config()
	_connect_content_reload()
	_connect_tree_changes()
	_refresh_emitter_cache()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _emitter_cache_dirty or _emitter_cache.is_empty():
		_refresh_emitter_cache()
	var interval := maxf(float(_config.get("update_interval", 0.08)), 0.03)
	if _elapsed < interval:
		return
	_elapsed = 0.0
	_update_local_light_shadows()


func refresh_from_content() -> void:
	_reload_config()
	_emitter_cache_dirty = true
	_refresh_emitter_cache()
	_update_local_light_shadows()


func get_active_local_shadow_count() -> int:
	var count := 0
	for shadow_value in _local_shadows.values():
		if shadow_value == null or not is_instance_valid(shadow_value):
			continue
		var shadow := shadow_value as Node
		if shadow != null:
			count += 1
	return count


func _reload_config() -> void:
	_config.clear()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var shadow_value: Variant = profile.get("directional_shadow", {})
	if not (shadow_value is Dictionary):
		return
	var local_value: Variant = (shadow_value as Dictionary).get("local_lights", {})
	if local_value is Dictionary:
		_config = (local_value as Dictionary).duplicate(true)


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "refresh_from_content")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func _connect_tree_changes() -> void:
	var tree := get_tree()
	var added_callback := Callable(self, "_on_tree_node_changed")
	var removed_callback := Callable(self, "_on_tree_node_changed")
	if not tree.node_added.is_connected(added_callback):
		tree.node_added.connect(added_callback)
	if not tree.node_removed.is_connected(removed_callback):
		tree.node_removed.connect(removed_callback)


func _on_tree_node_changed(_node: Node) -> void:
	# Rebuild once on the next process tick instead of traversing the scene tree
	# periodically. Enabled state and energy are still checked from the cache.
	_emitter_cache_dirty = true


func _update_local_light_shadows() -> void:
	var night_strength := _night_strength()
	if not bool(_config.get("enabled", true)) or night_strength <= 0.01:
		_clear_local_shadows()
		return

	var active_keys: Dictionary = {}
	var emitters := _active_emitters()
	var max_emitters := maxi(int(_config.get("max_emitters_per_caster", 4)), 1)
	for caster_value in get_tree().get_nodes_in_group(CASTER_GROUP):
		if caster_value == null or not is_instance_valid(caster_value):
			continue
		var caster := caster_value as Node
		if caster == null or not caster.has_method("get_shadow_target"):
			continue
		var target_value: Variant = caster.call("get_shadow_target")
		var source_value: Variant = caster.call("get_shadow_source")
		if target_value == null or source_value == null or not is_instance_valid(target_value) or not is_instance_valid(source_value):
			continue
		var target := target_value as Node2D
		var source := source_value as CanvasItem
		if target == null or source == null or not target.is_visible_in_tree():
			continue
		var candidates: Array[Dictionary] = []
		for emitter_entry in emitters:
			if _emitter_belongs_to_target(emitter_entry, target):
				continue
			var radius := _emitter_radius(emitter_entry)
			if radius <= 1.0:
				continue
			var emitter_position := _emitter_position(emitter_entry)
			var distance := emitter_position.distance_to(target.global_position)
			if distance >= radius:
				continue
			candidates.append({
				"entry": emitter_entry,
				"distance": distance,
				"radius": radius,
			})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
		for index in range(mini(candidates.size(), max_emitters)):
			var candidate := candidates[index]
			var emitter_entry := candidate["entry"] as Dictionary
			var light := _valid_light_from_entry(emitter_entry)
			if light == null:
				continue
			var distance := float(candidate["distance"])
			var radius := float(candidate["radius"])
			var key := "%s:%s" % [str(caster.get_instance_id()), str(light.get_instance_id())]
			active_keys[key] = true
			_sync_local_shadow(key, caster, target, source, emitter_entry, distance, radius, night_strength)
	_remove_stale_shadows(active_keys)


func _sync_local_shadow(
	key: String,
	caster: Node,
	target: Node2D,
	source: CanvasItem,
	emitter_entry: Dictionary,
	distance: float,
	radius: float,
	night_strength: float
) -> void:
	var light := _valid_light_from_entry(emitter_entry)
	if light == null:
		return
	var shadow: Polygon2D = null
	var stored_shadow: Variant = _local_shadows.get(key)
	if stored_shadow != null and is_instance_valid(stored_shadow):
		shadow = stored_shadow as Polygon2D
	if shadow == null:
		shadow = ActiveFrameShadowScript.new() as Polygon2D
		target.add_child(shadow)
		_local_shadows[key] = shadow
	var emitter_position := light.global_position
	var direction_vector := target.global_position - emitter_position
	if direction_vector.length_squared() <= 0.001:
		direction_vector = Vector2.DOWN
	var attenuation := pow(
		clampf(1.0 - (distance / maxf(radius, 1.0)), 0.0, 1.0),
		float(_config.get("distance_falloff", 1.25))
	)
	var source_strength := _emitter_strength(emitter_entry)
	var weight := clampf(
		night_strength * attenuation * source_strength * float(_config.get("opacity_multiplier", 0.72)),
		0.0,
		float(_config.get("maximum_mask_weight", 0.85))
	)
	var caster_config := caster.call("get_shadow_config") as Dictionary
	var local_config := {
		"enabled": weight > 0.001,
		"local_light_shadow": true,
		"direction_degrees": rad_to_deg(direction_vector.angle()),
		"stretch": maxf(float(_config.get("stretch", 0.72)), 0.05),
		"width_scale": maxf(float(_config.get("width_scale", 1.0)), 0.05),
		"root_overlap": maxf(float(_config.get("root_overlap", 4.0)), 0.0),
		"opacity": float(caster_config.get("opacity", 0.30)),
		"mask_weight": weight,
		"offset": caster_config.get("offset", {}),
		"z_index": int(caster_config.get("z_index", -1)),
	}
	var foot_offset := caster.call("get_shadow_foot_offset") as Vector2
	shadow.call("configure", target, source, local_config, foot_offset)
	shadow.name = "LocalLightShadow_%s" % str(light.get_instance_id())
	shadow.set_meta("local_light_emitter_id", light.get_instance_id())
	shadow.set_meta("local_light_attenuation", attenuation)
	shadow.set_meta("local_light_energy", light.energy)


func _refresh_emitter_cache() -> void:
	_emitter_cache_dirty = false
	_emitter_cache.clear()
	var seen: Dictionary = {}
	for value in get_tree().get_nodes_in_group(EMITTER_GROUP):
		if value == null or not is_instance_valid(value):
			continue
		var host := value as Node
		if host == null:
			continue
		_collect_lights_from_node(host, host as Node2D, seen)

	# Authored and runtime lights should join the emitter group, but this fallback
	# also catches an imported scene whose PointLight2D was not wrapped by GlowOverlay.
	var scene_root := get_tree().current_scene
	if scene_root != null:
		_collect_lights_from_node(scene_root, null, seen)


func _collect_lights_from_node(node: Node, preferred_host: Node2D, seen: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is PointLight2D:
		var light := node as PointLight2D
		var light_id := light.get_instance_id()
		if not seen.has(light_id):
			var host := preferred_host
			if host == null:
				host = light.get_parent() as Node2D
			if host == null:
				host = light
			_emitter_cache.append({"host": host, "light": light})
			seen[light_id] = true
	for child in node.get_children():
		if child is Node and is_instance_valid(child):
			_collect_lights_from_node(child as Node, preferred_host, seen)


func _active_emitters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _emitter_cache:
		var light := _valid_light_from_entry(entry)
		if light == null or not light.is_visible_in_tree():
			continue
		if not light.enabled or light.energy <= 0.001 or light.texture == null:
			continue
		var texture_size := light.texture.get_size()
		if texture_size.x <= 0.0 or texture_size.y <= 0.0:
			continue
		result.append(entry)
	return result


func _valid_light_from_entry(entry: Dictionary) -> PointLight2D:
	var light_value: Variant = entry.get("light")
	if light_value == null or not is_instance_valid(light_value):
		return null
	return light_value as PointLight2D


func _emitter_position(entry: Dictionary) -> Vector2:
	var light := _valid_light_from_entry(entry)
	return light.global_position if light != null else Vector2.ZERO


func _emitter_radius(entry: Dictionary) -> float:
	var light := _valid_light_from_entry(entry)
	if light == null or light.texture == null:
		return 0.0
	var texture_size := light.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return 0.0
	var scale_value := maxf(absf(light.global_scale.x), absf(light.global_scale.y))
	return maxf(texture_size.x, texture_size.y) * 0.5 * light.texture_scale * scale_value


func _emitter_strength(entry: Dictionary) -> float:
	var light := _valid_light_from_entry(entry)
	if light == null:
		return 0.0
	var reference_energy := maxf(float(_config.get("reference_energy", 0.25)), 0.01)
	var normalized_energy := maxf(light.energy / reference_energy, 0.0)
	return clampf(sqrt(normalized_energy), 0.0, 1.0)


func _emitter_belongs_to_target(entry: Dictionary, target: Node) -> bool:
	var host_value: Variant = entry.get("host")
	var light_value: Variant = entry.get("light")
	if target == null or light_value == null or not is_instance_valid(light_value):
		return false
	var light := light_value as Node
	if light == null:
		return false
	if target == light or target.is_ancestor_of(light) or light.is_ancestor_of(target):
		return true
	if host_value == null or not is_instance_valid(host_value):
		return false
	var host := host_value as Node
	return host != null and (target == host or target.is_ancestor_of(host) or host.is_ancestor_of(target))


func _night_strength() -> float:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if cycle != null and cycle.has_method("get_night_strength"):
		return clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	return 0.0


func _remove_stale_shadows(active_keys: Dictionary) -> void:
	for key_value in _local_shadows.keys():
		var key := str(key_value)
		if active_keys.has(key):
			continue
		var shadow_value: Variant = _local_shadows.get(key)
		if shadow_value != null and is_instance_valid(shadow_value):
			var shadow := shadow_value as Node
			if shadow != null:
				shadow.queue_free()
		_local_shadows.erase(key)


func _clear_local_shadows() -> void:
	for shadow_value in _local_shadows.values():
		if shadow_value == null or not is_instance_valid(shadow_value):
			continue
		var shadow := shadow_value as Node
		if shadow != null:
			shadow.queue_free()
	_local_shadows.clear()
