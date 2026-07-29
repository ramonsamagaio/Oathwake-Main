class_name LocalLightShadowDirector
extends Node

const LocalLightShadowGroupScript := preload("res://scripts/effects/LocalLightShadowGroup.gd")

var _shadow_group: CanvasGroup
var _proxies: Dictionary = {}
var _config: Dictionary = {}


func _ready() -> void:
	name = "LocalLightShadowDirector"
	add_to_group("local_light_shadow_director")
	_ensure_shadow_group()
	_reload_from_content()
	_connect_content_reload()
	process_priority = 950
	set_process(true)


func _exit_tree() -> void:
	for proxy_value in _proxies.values():
		var proxy := proxy_value as Polygon2D
		if proxy != null and is_instance_valid(proxy):
			proxy.queue_free()
	_proxies.clear()


func _process(_delta: float) -> void:
	_ensure_shadow_group()
	if _shadow_group == null:
		return
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	var night_strength := 0.0
	if cycle != null and cycle.has_method("get_night_strength"):
		night_strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	if not bool(_config.get("local_light_shadows_enabled", true)) or night_strength <= 0.18:
		_hide_all_proxies()
		return
	_sync_local_shadows()


func _sync_local_shadows() -> void:
	var active_keys: Dictionary = {}
	var emitters := get_tree().get_nodes_in_group("world_light_emitter")
	var casters := get_tree().get_nodes_in_group("projected_shadow_caster")
	var base_stretch := maxf(float(_config.get("local_light_shadow_stretch", 0.72)), 0.05)

	for emitter_value in emitters:
		var emitter := emitter_value as Node2D
		if emitter == null or not is_instance_valid(emitter):
			continue
		if not emitter.has_method("is_night_shadow_emitter_active") or not bool(emitter.call("is_night_shadow_emitter_active")):
			continue
		var radius := float(emitter.call("get_light_radius_world")) if emitter.has_method("get_light_radius_world") else 0.0
		if radius <= 1.0:
			continue
		var emitter_owner := emitter.call("get_light_owner") as Node2D if emitter.has_method("get_light_owner") else emitter.get_parent() as Node2D

		for caster_value in casters:
			var caster := caster_value as Node2D
			if caster == null or not is_instance_valid(caster):
				continue
			if not caster.has_method("is_shadow_caster_active") or not bool(caster.call("is_shadow_caster_active")):
				continue
			var caster_owner := caster.call("get_shadow_owner") as Node2D if caster.has_method("get_shadow_owner") else caster.get_parent() as Node2D
			if caster_owner == null or caster_owner == emitter_owner:
				continue
			var offset := caster_owner.global_position - emitter.global_position
			var distance := offset.length()
			if distance <= 1.0 or distance > radius:
				continue
			var direction := offset / distance
			var distance_ratio := clampf(distance / radius, 0.0, 1.0)
			var stretch_amount := base_stretch * lerpf(0.58, 1.18, distance_ratio)
			var key := "%s:%s" % [str(emitter.get_instance_id()), str(caster.get_instance_id())]
			var proxy := _ensure_proxy(key)
			if proxy == null:
				continue
			var populated := bool(caster.call("populate_external_projection_proxy", proxy, _shadow_group, direction, stretch_amount))
			proxy.visible = populated
			if populated:
				proxy.set_meta("local_light_emitter_id", emitter.get_instance_id())
				proxy.set_meta("local_light_distance_ratio", distance_ratio)
				active_keys[key] = true

	for key_value in _proxies.keys():
		var key := str(key_value)
		if active_keys.has(key):
			continue
		var stale_proxy := _proxies[key] as Polygon2D
		if stale_proxy != null and is_instance_valid(stale_proxy):
			stale_proxy.visible = false


func _ensure_proxy(key: String) -> Polygon2D:
	var existing := _proxies.get(key) as Polygon2D
	if existing != null and is_instance_valid(existing) and existing.get_parent() == _shadow_group:
		return existing
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	var proxy := Polygon2D.new()
	proxy.name = "LocalShadow_%s" % key.replace(":", "_")
	proxy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	proxy.color = Color.WHITE
	proxy.self_modulate = Color.WHITE
	proxy.z_index = 0
	_shadow_group.add_child(proxy)
	_proxies[key] = proxy
	return proxy


func _ensure_shadow_group() -> void:
	if _shadow_group != null and is_instance_valid(_shadow_group):
		return
	var existing := get_tree().get_first_node_in_group("local_light_shadow_group") as CanvasGroup
	if existing != null:
		_shadow_group = existing
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	_shadow_group = LocalLightShadowGroupScript.new() as CanvasGroup
	host.add_child(_shadow_group)


func _hide_all_proxies() -> void:
	for proxy_value in _proxies.values():
		var proxy := proxy_value as Polygon2D
		if proxy != null and is_instance_valid(proxy):
			proxy.visible = false


func _reload_from_content() -> void:
	_config.clear()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var value: Variant = profile.get("directional_shadow", {})
	if value is Dictionary:
		_config = (value as Dictionary).duplicate(true)


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_signal("content_reloaded"):
		return
	var callback := Callable(self, "_reload_from_content")
	if not content_db.content_reloaded.is_connected(callback):
		content_db.content_reloaded.connect(callback)
