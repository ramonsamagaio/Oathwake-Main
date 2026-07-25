extends Node2D

const AmbientParticleFieldScript := preload("res://scripts/effects/AmbientParticleField.gd")
const FoliageWindShader := preload("res://shaders/foliage_wind_2d.gdshader")

var map_id := ""
var _config: Dictionary = {}
var _occlusion_config: Dictionary = {}
var _wind_config: Dictionary = {}
var _particle_config: Dictionary = {}
var _occluders: Array[Dictionary] = []
var _occluder_target_ids: Dictionary = {}
var _player: Node2D
var _ambient_field: Node2D
var _time := 0.0


func configure_map(new_map_id: String) -> void:
	map_id = new_map_id
	_reload_configuration()


func _ready() -> void:
	add_to_group("world_visual_director")
	z_as_relative = false
	z_index = 0
	_reload_configuration()
	_connect_content_reload()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_update_occlusion(delta)


func _reload_configuration() -> void:
	var profile: Dictionary = {}
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		profile = content_db.get_vfx_profile("default")
	var value: Variant = profile.get("world_visuals", {})
	_config = (value as Dictionary).duplicate(true) if value is Dictionary else {}
	_occlusion_config = _dictionary(_config, "occlusion")
	_wind_config = _dictionary(_config, "wind")
	_particle_config = _dictionary(_config, "particles")
	_ensure_ambient_field()
	_refresh_registered_materials()


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "_reload_configuration")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func register_authored_sprite(sprite: Sprite2D) -> void:
	if sprite == null or sprite.texture == null:
		return
	var category := _classify_visual(str(sprite.name))
	if category == "vegetation_large":
		configure_foliage_canvas_item(sprite, "large")
		register_occluder(sprite, sprite, "tree")
	elif category == "vegetation_small":
		configure_foliage_canvas_item(sprite, "small")
	elif category == "roof":
		register_occluder(sprite, sprite, "roof")


func register_authored_foliage_layer(layer: CanvasItem) -> void:
	if layer == null:
		return
	configure_foliage_canvas_item(layer, "small")


func register_resource_visual(owner: Node2D, target: CanvasItem, kind: String) -> void:
	if owner == null or target == null:
		return
	if kind == "tree":
		register_occluder(owner, target, "tree")


func register_occluder(owner: Node2D, target: CanvasItem, kind := "tree", size_hint := Vector2.ZERO) -> void:
	if owner == null or target == null:
		return
	var target_id := target.get_instance_id()
	if _occluder_target_ids.has(target_id):
		return
	_occluder_target_ids[target_id] = true
	_occluders.append({
		"owner": owner,
		"target": target,
		"kind": kind,
		"size_hint": size_hint,
		"base_alpha": target.modulate.a,
	})
	target.set_meta("world_occlusion_target", true)


func configure_foliage_canvas_item(item: CanvasItem, size_class := "small") -> void:
	if item == null or not bool(_wind_config.get("enabled", true)):
		return
	var material := item.material as ShaderMaterial
	if material == null or material.shader != FoliageWindShader:
		material = ShaderMaterial.new()
		material.resource_local_to_scene = true
		material.shader = FoliageWindShader
		item.material = material
	_apply_wind_parameters(material, size_class, float(item.get_instance_id() % 997) / 997.0 * TAU)
	item.set_meta("world_wind_size_class", size_class)


func configure_foliage_material(material: ShaderMaterial, size_class: String, phase_offset := 0.0) -> void:
	if material == null:
		return
	_apply_wind_parameters(material, size_class, phase_offset)


func get_wind_vector() -> Vector2:
	if not bool(_wind_config.get("enabled", true)):
		return Vector2.ZERO
	var direction := _vector_from_value(_wind_config.get("direction", {}), Vector2(1.0, 0.16))
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var strength := maxf(float(_wind_config.get("strength", 0.85)), 0.0)
	var gust_strength := maxf(float(_wind_config.get("gust_strength", 0.34)), 0.0)
	var gust_speed := maxf(float(_wind_config.get("gust_speed", 0.42)), 0.01)
	var gust := 1.0 + sin(_time * gust_speed * TAU) * gust_strength
	return direction * strength * gust * 18.0


func get_wind_strength() -> float:
	return get_wind_vector().length() / 18.0


func _apply_wind_parameters(material: ShaderMaterial, size_class: String, phase_offset: float) -> void:
	var direction := _vector_from_value(_wind_config.get("direction", {}), Vector2(1.0, 0.16))
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	var amplitude_scale := float(_wind_config.get("large_amplitude_scale", 1.0)) if size_class == "large" else float(_wind_config.get("small_amplitude_scale", 0.78))
	material.set_shader_parameter("enabled", bool(_wind_config.get("enabled", true)))
	material.set_shader_parameter("wind_direction", direction.normalized())
	material.set_shader_parameter("wind_strength", maxf(float(_wind_config.get("strength", 0.85)), 0.0) * maxf(amplitude_scale, 0.0))
	material.set_shader_parameter("gust_strength", maxf(float(_wind_config.get("gust_strength", 0.34)), 0.0))
	material.set_shader_parameter("gust_speed", maxf(float(_wind_config.get("gust_speed", 0.42)), 0.01))
	material.set_shader_parameter("phase_offset", phase_offset)


func _refresh_registered_materials() -> void:
	for entry in _occluders:
		var target: Variant = entry.get("target")
		if target is CanvasItem and is_instance_valid(target):
			var item := target as CanvasItem
			if item.has_meta("world_wind_size_class"):
				configure_foliage_canvas_item(item, str(item.get_meta("world_wind_size_class", "small")))
	for item in get_tree().get_nodes_in_group("world_foliage"):
		if item is CanvasItem:
			configure_foliage_canvas_item(item as CanvasItem, str(item.get_meta("world_wind_size_class", "small")))


func _update_occlusion(delta: float) -> void:
	if _player == null:
		return
	var enabled := bool(_occlusion_config.get("enabled", true))
	var fade_speed := maxf(float(_occlusion_config.get("fade_speed", 5.5)), 0.01)
	var horizontal_ratio := maxf(float(_occlusion_config.get("horizontal_ratio", 0.38)), 0.05)
	var vertical_ratio := maxf(float(_occlusion_config.get("vertical_ratio", 0.78)), 0.1)
	var front_margin := float(_occlusion_config.get("front_margin", 8.0))
	for index in range(_occluders.size() - 1, -1, -1):
		var entry := _occluders[index]
		var owner: Variant = entry.get("owner")
		var target: Variant = entry.get("target")
		if not (owner is Node2D) or not (target is CanvasItem) or not is_instance_valid(owner) or not is_instance_valid(target):
			_occluders.remove_at(index)
			continue
		var owner_node := owner as Node2D
		var target_item := target as CanvasItem
		var base_alpha := float(entry.get("base_alpha", 1.0))
		if not target_item.visible:
			target_item.modulate.a = base_alpha
			continue
		var size := entry.get("size_hint", Vector2.ZERO) as Vector2
		if size.length_squared() <= 0.01:
			size = _estimate_canvas_item_size(target_item)
		var depth_y := float(owner_node.get_meta("world_depth_y", owner_node.global_position.y + size.y * 0.38))
		var player_delta := _player.global_position - owner_node.global_position
		var horizontal_limit := maxf(size.x * horizontal_ratio, float(_occlusion_config.get("minimum_radius", 22.0)))
		var upper_limit := depth_y - maxf(size.y * vertical_ratio, 28.0)
		var lower_limit := depth_y + front_margin
		var should_fade := enabled and absf(player_delta.x) <= horizontal_limit and _player.global_position.y >= upper_limit and _player.global_position.y <= lower_limit
		var kind := str(entry.get("kind", "tree"))
		var faded_alpha := float(_occlusion_config.get("roof_alpha", 0.30)) if kind == "roof" else float(_occlusion_config.get("tree_alpha", 0.38))
		var target_alpha := clampf(faded_alpha, 0.05, base_alpha) if should_fade else base_alpha
		target_item.modulate.a = move_toward(target_item.modulate.a, target_alpha, fade_speed * delta)
		target_item.set_meta("world_occluded", should_fade)


func _ensure_ambient_field() -> void:
	if _ambient_field == null or not is_instance_valid(_ambient_field):
		_ambient_field = AmbientParticleFieldScript.new()
		_ambient_field.name = "AmbientParticleField"
		add_child(_ambient_field)
	if _ambient_field.has_method("configure"):
		_ambient_field.call("configure", _particle_config, self)


func _classify_visual(name_value: String) -> String:
	var text := name_value.to_lower()
	for token in ["house", "casa", "roof", "telhado"]:
		if text.contains(token):
			return "roof"
	for token in ["tree", "pine", "pinheiro", "sapling"]:
		if text.contains(token):
			return "vegetation_large"
	for token in ["shrub", "arbusto", "bush", "grass", "foliage", "folha", "plant"]:
		if text.contains(token):
			return "vegetation_small"
	return ""


func _estimate_canvas_item_size(item: CanvasItem) -> Vector2:
	if item is Sprite2D:
		var sprite := item as Sprite2D
		if sprite.texture != null:
			return sprite.texture.get_size() * Vector2(absf(sprite.global_scale.x), absf(sprite.global_scale.y))
	if item is Polygon2D:
		var polygon := (item as Polygon2D).polygon
		if not polygon.is_empty():
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon:
				bounds = bounds.expand(point)
			return bounds.size * Vector2(absf((item as Node2D).global_scale.x), absf((item as Node2D).global_scale.y))
	return Vector2(96.0, 128.0)


func _dictionary(record: Dictionary, key: String) -> Dictionary:
	var value: Variant = record.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback
