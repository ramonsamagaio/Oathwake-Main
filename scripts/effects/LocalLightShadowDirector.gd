class_name LocalLightShadowDirector
extends Node

const DynamicShadowScript := preload("res://scripts/effects/DynamicProjectedSpriteShadow.gd")
const CASTER_GROUP := "projected_shadow_caster"
const EMITTER_GROUP := "world_light_emitter"

var _elapsed := 0.0
var _local_shadows: Dictionary = {}
var _config: Dictionary = {}


func _ready() -> void:
	add_to_group("local_light_shadow_director")
	_reload_config()
	_connect_content_reload()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	var interval := maxf(float(_config.get("update_interval", 0.10)), 0.03)
	if _elapsed < interval:
		return
	_elapsed = 0.0
	_update_local_light_shadows()


func refresh_from_content() -> void:
	_reload_config()
	_update_local_light_shadows()


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


func _update_local_light_shadows() -> void:
	var night_strength := _night_strength()
	if not bool(_config.get("enabled", true)) or night_strength <= 0.01:
		_clear_local_shadows()
		return

	var active_keys: Dictionary = {}
	var emitters := _active_emitters()
	var max_emitters := maxi(int(_config.get("max_emitters_per_caster", 4)), 1)
	for caster_value in get_tree().get_nodes_in_group(CASTER_GROUP):
		var caster := caster_value as Node
		if caster == null or not is_instance_valid(caster) or not caster.has_method("get_shadow_target"):
			continue
		var target := caster.call("get_shadow_target") as Node2D
		var source := caster.call("get_shadow_source") as CanvasItem
		if target == null or source == null or not is_instance_valid(target) or not is_instance_valid(source) or not target.is_visible_in_tree():
			continue
		var candidates: Array[Dictionary] = []
		for emitter in emitters:
			if _emitter_belongs_to_target(emitter, target):
				continue
			var radius := _emitter_radius(emitter)
			if radius <= 1.0:
				continue
			var distance := emitter.global_position.distance_to(target.global_position)
			if distance >= radius:
				continue
			candidates.append({"emitter": emitter, "distance": distance, "radius": radius})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
		for index in range(mini(candidates.size(), max_emitters)):
			var candidate := candidates[index]
			var emitter := candidate["emitter"] as Node2D
			var distance := float(candidate["distance"])
			var radius := float(candidate["radius"])
			var key := "%s:%s" % [str(caster.get_instance_id()), str(emitter.get_instance_id())]
			active_keys[key] = true
			_sync_local_shadow(key, caster, target, source, emitter, distance, radius, night_strength)
	_remove_stale_shadows(active_keys)


func _sync_local_shadow(
	key: String,
	caster: Node,
	target: Node2D,
	source: CanvasItem,
	emitter: Node2D,
	distance: float,
	radius: float,
	night_strength: float
) -> void:
	var shadow := _local_shadows.get(key) as Polygon2D
	if shadow == null or not is_instance_valid(shadow):
		shadow = DynamicShadowScript.new() as Polygon2D
		shadow.name = "LocalLightShadow_%s" % str(emitter.get_instance_id())
		target.add_child(shadow)
		_local_shadows[key] = shadow
	var direction_vector := target.global_position - emitter.global_position
	if direction_vector.length_squared() <= 0.001:
		direction_vector = Vector2.DOWN
	var attenuation := pow(clampf(1.0 - (distance / maxf(radius, 1.0)), 0.0, 1.0), float(_config.get("distance_falloff", 1.35)))
	var source_strength := _emitter_strength(emitter)
	var weight := clampf(
		night_strength * attenuation * source_strength * float(_config.get("opacity_multiplier", 0.28)),
		0.0,
		float(_config.get("maximum_mask_weight", 0.32))
	)
	var caster_config := caster.call("get_shadow_config") as Dictionary
	var local_config := {
		"enabled": weight > 0.001,
		"local_light_shadow": true,
		"direction_degrees": rad_to_deg(direction_vector.angle()),
		"stretch": maxf(float(_config.get("stretch", 0.82)), 0.05),
		"opacity": float(caster_config.get("opacity", 0.30)),
		"mask_weight": weight,
		"offset": caster_config.get("offset", {}),
		"z_index": int(caster_config.get("z_index", -1)),
	}
	var foot_offset := caster.call("get_shadow_foot_offset") as Vector2
	shadow.call("configure", target, source, local_config, foot_offset)
	shadow.set_meta("local_light_emitter_id", emitter.get_instance_id())
	shadow.set_meta("local_light_attenuation", attenuation)


func _active_emitters() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for value in get_tree().get_nodes_in_group(EMITTER_GROUP):
		var emitter := value as Node2D
		if emitter == null or not emitter.is_visible_in_tree():
			continue
		var point_light := emitter.get_node_or_null("PointLight2D") as PointLight2D
		if point_light == null or not point_light.enabled or point_light.energy <= 0.001 or point_light.texture == null:
			continue
		result.append(emitter)
	return result


func _emitter_radius(emitter: Node2D) -> float:
	var point_light := emitter.get_node_or_null("PointLight2D") as PointLight2D
	if point_light == null or point_light.texture == null:
		return 0.0
	var texture_size := point_light.texture.get_size()
	var scale_value := maxf(absf(emitter.global_scale.x), absf(emitter.global_scale.y))
	return maxf(texture_size.x, texture_size.y) * 0.5 * point_light.texture_scale * scale_value


func _emitter_strength(emitter: Node2D) -> float:
	var point_light := emitter.get_node_or_null("PointLight2D") as PointLight2D
	if point_light == null:
		return 0.0
	return clampf(point_light.energy / maxf(float(_config.get("reference_energy", 1.0)), 0.01), 0.0, 1.0)


func _emitter_belongs_to_target(emitter: Node, target: Node) -> bool:
	return emitter == target or target.is_ancestor_of(emitter) or emitter.is_ancestor_of(target)


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
		var shadow := _local_shadows[key] as Node
		if shadow != null and is_instance_valid(shadow):
			shadow.queue_free()
		_local_shadows.erase(key)


func _clear_local_shadows() -> void:
	for shadow_value in _local_shadows.values():
		var shadow := shadow_value as Node
		if shadow != null and is_instance_valid(shadow):
			shadow.queue_free()
	_local_shadows.clear()
