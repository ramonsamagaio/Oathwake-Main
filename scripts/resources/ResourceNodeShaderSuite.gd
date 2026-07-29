extends "res://scripts/resources/ResourceNodeEnhanced.gd"

const FoliageWindShader := preload("res://shaders/foliage_wind_2d.gdshader")

@onready var foliage_settings: Node = get_node_or_null("FoliageWindSettings")

var _fallback_sway_phase := 0.0
var _fallback_sway_targets: Array[Node2D] = []
var _fallback_base_rotations: Dictionary = {}


func _ready() -> void:
	_fallback_sway_phase = randf_range(0.0, TAU)
	super._ready()
	_cache_fallback_sway_targets()
	call_deferred("_register_world_visuals")


func _process(delta: float) -> void:
	super._process(delta)
	_update_fallback_sway(delta)


func _on_content_reloaded() -> void:
	super._on_content_reloaded()
	call_deferred("_register_world_visuals")


func _apply_content_sprite_material(sprite: Sprite2D) -> void:
	if sprite == null:
		return
	var size_class := _get_foliage_size_class()
	if size_class.is_empty():
		sprite.material = null
		return

	var shader_material := ShaderMaterial.new()
	shader_material.resource_local_to_scene = true
	shader_material.shader = FoliageWindShader
	shader_material.set_shader_parameter("enabled", bool(foliage_settings.get("effect_enabled")))
	shader_material.set_shader_parameter("time_scale", float(foliage_settings.get("time_scale")))
	shader_material.set_shader_parameter("noise_scale", float(foliage_settings.get("noise_scale")))
	shader_material.set_shader_parameter("render_noise", bool(foliage_settings.get("render_noise_debug")))

	if size_class == "large":
		shader_material.set_shader_parameter("amplitude", float(foliage_settings.get("large_amplitude")))
		shader_material.set_shader_parameter("rotation_strength", float(foliage_settings.get("large_rotation_strength")))
		shader_material.set_shader_parameter("rotation_pivot", foliage_settings.get("large_rotation_pivot"))
	else:
		shader_material.set_shader_parameter("amplitude", float(foliage_settings.get("small_amplitude")))
		shader_material.set_shader_parameter("rotation_strength", float(foliage_settings.get("small_rotation_strength")))
		shader_material.set_shader_parameter("rotation_pivot", foliage_settings.get("small_rotation_pivot"))

	var director := _get_world_visual_director()
	if director != null and director.has_method("configure_foliage_material"):
		director.call("configure_foliage_material", shader_material, size_class, _fallback_sway_phase)
	sprite.material = shader_material
	sprite.add_to_group("world_foliage")
	sprite.set_meta("world_wind_size_class", size_class)


func _get_foliage_size_class() -> String:
	if foliage_settings == null or not bool(foliage_settings.get("effect_enabled")):
		return ""
	if foliage_settings.has_method("get_size_class"):
		return str(foliage_settings.call("get_size_class", resource_type_id))
	var large_ids: PackedStringArray = foliage_settings.get("large_resource_ids")
	var small_ids: PackedStringArray = foliage_settings.get("small_resource_ids")
	if large_ids.has(resource_type_id):
		return "large"
	if small_ids.has(resource_type_id):
		return "small"
	return ""


func _cache_fallback_sway_targets() -> void:
	_fallback_sway_targets.clear()
	_fallback_base_rotations.clear()

	var visual_root := get_node_or_null("VisualRoot") as Node2D
	if visual_root != null:
		_fallback_sway_targets.append(visual_root)
	else:
		for node_name in ["Crown", "Leaves", "Accent"]:
			var target := get_node_or_null(node_name) as Node2D
			if target != null:
				_fallback_sway_targets.append(target)

	for target in _fallback_sway_targets:
		_fallback_base_rotations[target] = target.rotation


func _update_fallback_sway(delta: float) -> void:
	if content_sprite != null or _fallback_sway_targets.is_empty():
		return
	var size_class := _get_foliage_size_class()
	if size_class.is_empty():
		_restore_fallback_rotations()
		return

	var director := _get_world_visual_director()
	var shared_strength := 1.0
	var horizontal_direction := 1.0
	if director != null:
		if director.has_method("get_wind_strength"):
			shared_strength = maxf(float(director.call("get_wind_strength")), 0.0)
		if director.has_method("get_wind_vector"):
			var wind_vector: Vector2 = director.call("get_wind_vector")
			if absf(wind_vector.x) > 0.001:
				horizontal_direction = signf(wind_vector.x)
	_fallback_sway_phase += delta * maxf(float(foliage_settings.get("time_scale")) * 7.5, 0.05)
	var amplitude := float(foliage_settings.get("large_amplitude")) if size_class == "large" else float(foliage_settings.get("small_amplitude"))
	var sway := sin(_fallback_sway_phase + global_position.x * 0.012 + global_position.y * 0.008) * amplitude * 0.42 * shared_strength * horizontal_direction
	for target in _fallback_sway_targets:
		target.rotation = float(_fallback_base_rotations.get(target, 0.0)) + sway


func _restore_fallback_rotations() -> void:
	for target in _fallback_sway_targets:
		target.rotation = float(_fallback_base_rotations.get(target, 0.0))


func _register_world_visuals() -> void:
	var director := _get_world_visual_director()
	if director == null:
		return
	var size_class := _get_foliage_size_class()
	var target: CanvasItem = null
	if layered_canopy_sprite != null and layered_canopy_sprite.visible:
		target = layered_canopy_sprite
	elif content_sprite != null and content_sprite.visible:
		target = content_sprite
	else:
		for target_name in ["Crown", "Leaves", "Accent"]:
			var fallback := get_node_or_null(target_name) as CanvasItem
			if fallback != null and fallback.visible:
				target = fallback
				break
	if target == null:
		return

	var sprite_id := str(resource_data.get("sprite_id", ""))
	if sprite_id.is_empty():
		var layered_value: Variant = resource_data.get("layered_visual", {})
		if layered_value is Dictionary:
			var layered := layered_value as Dictionary
			sprite_id = str(layered.get("canopy_sprite_id", layered.get("trunk_sprite_id", "")))
	var fade_when_player_behind := true
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and not sprite_id.is_empty() and content_db.has_method("has_sprite") and content_db.has_sprite(sprite_id):
		var sprite_record: Dictionary = content_db.get_sprite(sprite_id)
		fade_when_player_behind = bool(sprite_record.get("fade_when_player_behind", true))
	target.set_meta("content_sprite_id", sprite_id)
	target.set_meta("world_occlusion_enabled", fade_when_player_behind)

	if director.has_method("register_resource_visual"):
		director.call("register_resource_visual", self, target, resource_type_id, fade_when_player_behind)
	if size_class == "small" and director.has_method("register_micro_target"):
		director.call("register_micro_target", self, target, resource_type_id)


func _get_world_visual_director() -> Node:
	return get_tree().get_first_node_in_group("world_visual_director")
