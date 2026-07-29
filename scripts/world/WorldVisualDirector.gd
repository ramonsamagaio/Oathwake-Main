extends Node2D

const AmbientParticleFieldScript := preload("res://scripts/effects/AmbientParticleField.gd")
const FoliageWindShader := preload("res://shaders/foliage_wind_2d.gdshader")
const WaterSurfaceShader := preload("res://shaders/water_surface_2d.gdshader")
const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")

var map_id := ""
var _config: Dictionary = {}
var _occlusion_config: Dictionary = {}
var _wind_config: Dictionary = {}
var _particle_config: Dictionary = {}
var _water_config: Dictionary = {}
var _micro_config: Dictionary = {}
var _occluders: Array[Dictionary] = []
var _occluder_target_ids: Dictionary = {}
var _micro_targets: Array[Dictionary] = []
var _micro_target_ids: Dictionary = {}
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
	_update_micro_motion()


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
	_water_config = _dictionary(_config, "water")
	_micro_config = _dictionary(_config, "micro_motion")
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
	match category:
		"water":
			configure_water_canvas_item(sprite)
		"vegetation_large":
			configure_foliage_canvas_item(sprite, "large")
		"vegetation_small":
			configure_foliage_canvas_item(sprite, "small")
			register_micro_target(sprite, sprite, _micro_kind_from_name(str(sprite.name)))
		"micro":
			register_micro_target(sprite, sprite, _micro_kind_from_name(str(sprite.name)))

	# Every substantial authored prop participates in player occlusion. Tiny floor
	# decoration and water remain untouched, while trees, roofs, rocks, fences,
	# buildings and other tall props fade consistently when covering the player.
	var size := _estimate_canvas_item_size(sprite)
	var should_occlude := category != "water" and category != "micro" and size.y >= 40.0
	if should_occlude:
		var kind := "roof" if category == "roof" else ("tree" if category == "vegetation_large" else "element")
		register_occluder(sprite, sprite, kind, size, true)


func register_authored_foliage_layer(layer: CanvasItem) -> void:
	register_authored_environment_layer(layer)


func register_authored_environment_layer(layer: CanvasItem) -> void:
	if layer == null:
		return
	var name_text := str(layer.name).to_lower()
	if _contains_any(name_text, ["water", "river", "lake", "pond", "stream", "rivera", "agua", "água"]):
		configure_water_canvas_item(layer)
	elif _contains_any(name_text, ["grass", "foliage", "vegetation", "erva", "folhagem"]):
		configure_foliage_canvas_item(layer, "small")


func register_resource_visual(owner: Node2D, target: CanvasItem, kind: String, fade_when_player_behind := true) -> void:
	if owner == null or target == null:
		return
	register_occluder(owner, target, kind, Vector2.ZERO, fade_when_player_behind)


func register_micro_target(owner: Node2D, target: CanvasItem, kind := "plant") -> void:
	if owner == null or target == null or not (target is Node2D):
		return
	var target_id := target.get_instance_id()
	if _micro_target_ids.has(target_id):
		return
	_micro_target_ids[target_id] = true
	var target_node := target as Node2D
	_micro_targets.append({
		"owner": owner,
		"target": target_node,
		"kind": kind,
		"base_rotation": target_node.rotation,
		"base_scale": target_node.scale,
		"phase": float(target_id % 1009) / 1009.0 * TAU,
	})
	target.set_meta("world_micro_motion", true)


func register_occluder(
	owner: Node2D,
	target: CanvasItem,
	kind := "element",
	size_hint := Vector2.ZERO,
	fade_when_player_behind := true
) -> void:
	if owner == null or target == null:
		return
	var target_id := target.get_instance_id()
	if _occluder_target_ids.has(target_id):
		for index in range(_occluders.size()):
			var existing_target: Variant = _occluders[index].get("target")
			if existing_target == target:
				_occluders[index]["owner"] = owner
				_occluders[index]["kind"] = kind
				_occluders[index]["size_hint"] = size_hint
				_occluders[index]["fade_enabled"] = fade_when_player_behind
				target.set_meta("world_occlusion_enabled", fade_when_player_behind)
				return
		return
	_occluder_target_ids[target_id] = true
	_occluders.append({
		"owner": owner,
		"target": target,
		"kind": kind,
		"size_hint": size_hint,
		"base_alpha": target.modulate.a,
		"fade_enabled": fade_when_player_behind,
	})
	target.set_meta("world_occlusion_target", true)
	target.set_meta("world_occlusion_enabled", fade_when_player_behind)


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
	item.add_to_group("world_foliage")


func configure_foliage_material(material: ShaderMaterial, size_class: String, phase_offset := 0.0) -> void:
	if material == null:
		return
	_apply_wind_parameters(material, size_class, phase_offset)


func configure_water_canvas_item(item: CanvasItem) -> void:
	if item == null:
		return
	var material := item.material as ShaderMaterial
	if material == null or material.shader != WaterSurfaceShader:
		material = ShaderMaterial.new()
		material.resource_local_to_scene = true
		material.shader = WaterSurfaceShader
		item.material = material
	_apply_water_parameters(material)
	item.add_to_group("water_surface")
	item.set_meta("world_water_surface", true)


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


func _apply_water_parameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter("enabled", bool(_water_config.get("enabled", true)))
	material.set_shader_parameter("shallow_color", _color_from_value(_water_config.get("shallow_color", "#347184E0"), Color(0.20, 0.43, 0.53, 0.88)))
	material.set_shader_parameter("deep_color", _color_from_value(_water_config.get("deep_color", "#14304FF0"), Color(0.08, 0.19, 0.30, 0.94)))
	material.set_shader_parameter("highlight_color", _color_from_value(_water_config.get("highlight_color", "#94D1E0B8"), Color(0.58, 0.82, 0.88, 0.72)))
	material.set_shader_parameter("flow_direction", _vector_from_value(_water_config.get("flow_direction", {}), Vector2(1.0, 0.18)))
	material.set_shader_parameter("flow_speed", maxf(float(_water_config.get("flow_speed", 0.36)), 0.0))
	material.set_shader_parameter("ripple_scale", maxf(float(_water_config.get("ripple_scale", 28.0)), 1.0))
	material.set_shader_parameter("ripple_strength", maxf(float(_water_config.get("ripple_strength", 0.008)), 0.0))
	material.set_shader_parameter("reflection_strength", maxf(float(_water_config.get("reflection_strength", 0.24)), 0.0))
	material.set_shader_parameter("caustic_strength", maxf(float(_water_config.get("caustic_strength", 0.18)), 0.0))
	material.set_shader_parameter("edge_fade", clampf(float(_water_config.get("edge_fade", 0.06)), 0.0, 0.5))
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	var night_strength := 0.0
	if cycle != null and cycle.has_method("get_night_strength"):
		night_strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	material.set_shader_parameter("night_strength", night_strength)


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
	for item in get_tree().get_nodes_in_group("water_surface"):
		if item is CanvasItem:
			configure_water_canvas_item(item as CanvasItem)


func _update_micro_motion() -> void:
	var enabled := bool(_micro_config.get("enabled", true))
	var sway_speed := maxf(float(_micro_config.get("sway_speed", 0.85)), 0.01)
	var breathe_speed := maxf(float(_micro_config.get("breathe_speed", 0.72)), 0.01)
	var wind_influence := maxf(float(_micro_config.get("wind_influence", 0.55)), 0.0)
	var wind_vector := get_wind_vector()
	var wind_direction := signf(wind_vector.x) if absf(wind_vector.x) > 0.001 else 1.0
	var wind_strength := get_wind_strength()
	for index in range(_micro_targets.size() - 1, -1, -1):
		var entry := _micro_targets[index]
		var target: Variant = entry.get("target")
		if not (target is Node2D) or not is_instance_valid(target):
			_micro_targets.remove_at(index)
			continue
		var node := target as Node2D
		var base_rotation := float(entry.get("base_rotation", 0.0))
		var base_scale: Vector2 = entry.get("base_scale", Vector2.ONE)
		if not enabled:
			node.rotation = base_rotation
			node.scale = base_scale
			continue
		var phase := float(entry.get("phase", 0.0))
		var kind := str(entry.get("kind", "plant"))
		var rotation_degrees := float(_micro_config.get("plant_rotation_degrees", 0.8))
		var scale_amount := 0.0
		if kind.contains("flower"):
			scale_amount = float(_micro_config.get("flower_scale_amount", 0.024))
		elif kind.contains("mushroom") or kind.contains("fungus") or kind.contains("cogumelo"):
			scale_amount = float(_micro_config.get("fungus_scale_amount", 0.018))
		else:
			scale_amount = float(_micro_config.get("plant_scale_amount", 0.010))
		var sway := sin((_time * sway_speed) + phase) * deg_to_rad(rotation_degrees) * (0.45 + wind_strength * wind_influence) * wind_direction
		var breathe := sin((_time * breathe_speed) + phase * 1.37) * scale_amount
		node.rotation = base_rotation + sway
		node.scale = base_scale * (1.0 + breathe)


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
			_occluder_target_ids.erase((target as Object).get_instance_id() if target is Object and is_instance_valid(target) else -1)
			_occluders.remove_at(index)
			continue
		var owner_node := owner as Node2D
		var target_item := target as CanvasItem
		var base_alpha := float(entry.get("base_alpha", 1.0))
		var fade_enabled := bool(entry.get("fade_enabled", target_item.get_meta("world_occlusion_enabled", true)))
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
		var should_fade := enabled and fade_enabled and absf(player_delta.x) <= horizontal_limit and _player.global_position.y >= upper_limit and _player.global_position.y <= lower_limit
		var kind := str(entry.get("kind", "element"))
		var legacy_alpha := float(_occlusion_config.get("roof_alpha", 0.30)) if kind == "roof" else float(_occlusion_config.get("tree_alpha", 0.38))
		var faded_alpha := float(target_item.get_meta("world_occlusion_alpha", _occlusion_config.get("default_alpha", legacy_alpha)))
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
	if _contains_any(text, ["water", "river", "lake", "pond", "stream", "agua", "água"]):
		return "water"
	if _contains_any(text, ["house", "casa", "roof", "telhado"]):
		return "roof"
	if _contains_any(text, ["tree", "pine", "pinheiro", "sapling"]):
		return "vegetation_large"
	if _contains_any(text, ["shrub", "arbusto", "bush", "plant", "herb", "flower", "flor", "mushroom", "fungus", "cogumelo"]):
		return "vegetation_small"
	if _contains_any(text, ["grass", "foliage", "folha"]):
		return "micro"
	return ""


func _micro_kind_from_name(name_value: String) -> String:
	var text := name_value.to_lower()
	if _contains_any(text, ["flower", "flor"]):
		return "flower"
	if _contains_any(text, ["mushroom", "fungus", "cogumelo"]):
		return "mushroom"
	if _contains_any(text, ["shrub", "arbusto", "bush"]):
		return "shrub"
	return "plant"


func _contains_any(text: String, tokens: Array) -> bool:
	for token in tokens:
		if text.contains(str(token)):
			return true
	return false


func _estimate_canvas_item_size(item: CanvasItem) -> Vector2:
	if item is Sprite2D:
		var sprite := item as Sprite2D
		return WorldDepthRuntime.get_sprite_visual_size(sprite) * Vector2(absf(sprite.global_scale.x), absf(sprite.global_scale.y))
	if item is AnimatedSprite2D:
		return WorldDepthRuntime.get_animated_sprite_visual_size(item as AnimatedSprite2D)
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


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)
