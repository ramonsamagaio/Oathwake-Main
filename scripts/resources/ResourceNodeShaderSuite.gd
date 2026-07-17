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


func _process(delta: float) -> void:
	super._process(delta)
	_update_fallback_sway(delta)


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

	sprite.material = shader_material


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

	_fallback_sway_phase += delta * maxf(float(foliage_settings.get("time_scale")) * 7.5, 0.05)
	var amplitude := float(foliage_settings.get("large_amplitude")) if size_class == "large" else float(foliage_settings.get("small_amplitude"))
	var sway := sin(_fallback_sway_phase + global_position.x * 0.012 + global_position.y * 0.008) * amplitude * 0.42
	for target in _fallback_sway_targets:
		target.rotation = float(_fallback_base_rotations.get(target, 0.0)) + sway


func _restore_fallback_rotations() -> void:
	for target in _fallback_sway_targets:
		target.rotation = float(_fallback_base_rotations.get(target, 0.0))
