@tool
extends Node2D

enum Mode { TEXTURE, PROCEDURAL, BOTH }
enum BlendStyle { MIX, ADDITIVE }

const GLOW_WINDOW_TEXTURE := "res://assets/sprites/effects/glows/Glow1.png"
const GLOW_LAMP_TEXTURE := "res://assets/sprites/effects/glows/glow2.png"
const GLOW_MAGIC_TEXTURE := "res://assets/sprites/effects/glows/glow3.png"
const PROCEDURAL_SHADER := "res://shaders/effects/glow_procedural.gdshader"
const PROCEDURAL_BASE_TEXTURE: Texture2D = preload("res://assets/sprites/effects/glows/glow2.png")
const POINT_LIGHT_TEXTURE: Texture2D = preload("res://assets/sprites/effects/glows/glow2.png")

@export var visual_enabled: bool = true
@export_enum("Texture", "Procedural", "Both") var mode: int = Mode.TEXTURE
@export_enum("Mix", "Additive") var blend_style: int = BlendStyle.ADDITIVE
@export var glow_texture: Texture2D = preload("res://assets/sprites/effects/glows/glow2.png")
@export var glow_color: Color = Color(1.0, 0.68, 0.28, 1.0)
@export_range(0.0, 8.0, 0.05) var intensity: float = 1.0
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.75
@export_range(0.05, 8.0, 0.05) var scale_multiplier: float = 1.0
@export var stretch: Vector2 = Vector2.ONE
@export var flicker_enabled: bool = false
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.08
@export_range(0.05, 12.0, 0.05) var flicker_speed: float = 2.0
@export var use_point_light: bool = true
@export_range(0.0, 8.0, 0.05) var point_light_energy: float = 1.0
@export_range(0.05, 8.0, 0.05) var point_light_scale: float = 1.8
@export_range(0.0, 4.0, 0.01) var day_light_multiplier: float = 0.18
@export_range(0.0, 4.0, 0.01) var night_light_multiplier: float = 1.0
@export var z_index_value: int = 60

@onready var _texture_glow: Sprite2D = $TextureGlow
@onready var _procedural_glow: Sprite2D = $ProceduralGlow
@onready var _point_light: PointLight2D = $PointLight2D

var _time: float = 0.0
var _phase: float = 0.0
var _night_strength: float = 0.0
var _visual_material: CanvasItemMaterial
var _procedural_material: ShaderMaterial


func _ready() -> void:
	add_to_group("world_light_emitter")
	_phase = randf() * TAU
	_ensure_visual_material()
	_sync_initial_day_night_strength()
	_update_visuals(1.0)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	var flicker_value := 1.0
	if flicker_enabled:
		var wave := sin((_time * flicker_speed) + _phase)
		var soft_wave := sin((_time * flicker_speed * 0.37) + (_phase * 1.7))
		flicker_value = 1.0 + (((wave * 0.65) + (soft_wave * 0.35)) * flicker_amount)
	_update_visuals(flicker_value)


func refresh_from_config() -> void:
	_ensure_visual_material()
	_update_visuals(1.0)


func set_day_night_strength(strength: float) -> void:
	_night_strength = clampf(strength, 0.0, 1.0)
	_update_visuals(1.0)


func apply_window_preset() -> void:
	mode = Mode.TEXTURE
	blend_style = BlendStyle.ADDITIVE
	glow_texture = _load_texture(GLOW_WINDOW_TEXTURE)
	glow_color = Color(1.0, 0.55, 0.22, 1.0)
	intensity = 0.85
	alpha = 0.58
	scale_multiplier = 1.0
	stretch = Vector2(1.75, 0.75)
	flicker_enabled = false
	flicker_amount = 0.03
	flicker_speed = 1.0
	use_point_light = true
	point_light_energy = 0.75
	point_light_scale = 1.55
	day_light_multiplier = 0.14
	night_light_multiplier = 1.0
	_update_visuals(1.0)


func apply_lamp_preset() -> void:
	mode = Mode.TEXTURE
	blend_style = BlendStyle.ADDITIVE
	glow_texture = _load_texture(GLOW_LAMP_TEXTURE)
	glow_color = Color(1.0, 0.78, 0.32, 1.0)
	intensity = 1.15
	alpha = 0.72
	scale_multiplier = 0.9
	stretch = Vector2.ONE
	flicker_enabled = true
	flicker_amount = 0.06
	flicker_speed = 2.0
	use_point_light = true
	point_light_energy = 1.0
	point_light_scale = 1.8
	day_light_multiplier = 0.18
	night_light_multiplier = 1.0
	_update_visuals(1.0)


func apply_magic_preset() -> void:
	mode = Mode.BOTH
	blend_style = BlendStyle.ADDITIVE
	glow_texture = _load_texture(GLOW_MAGIC_TEXTURE)
	glow_color = Color(0.55, 0.35, 1.0, 1.0)
	intensity = 1.45
	alpha = 0.78
	scale_multiplier = 1.1
	stretch = Vector2(1.1, 1.0)
	flicker_enabled = true
	flicker_amount = 0.08
	flicker_speed = 0.9
	use_point_light = true
	point_light_energy = 1.15
	point_light_scale = 2.0
	day_light_multiplier = 0.22
	night_light_multiplier = 1.0
	_update_visuals(1.0)


func apply_soft_fire_preset() -> void:
	mode = Mode.TEXTURE
	blend_style = BlendStyle.ADDITIVE
	glow_texture = _load_texture(GLOW_LAMP_TEXTURE)
	glow_color = Color(1.0, 0.36, 0.12, 1.0)
	intensity = 1.25
	alpha = 0.7
	scale_multiplier = 0.85
	stretch = Vector2(1.05, 0.9)
	flicker_enabled = true
	flicker_amount = 0.1
	flicker_speed = 3.0
	use_point_light = true
	point_light_energy = 1.35
	point_light_scale = 2.25
	day_light_multiplier = 0.22
	night_light_multiplier = 1.0
	_update_visuals(1.0)


func _ensure_visual_material() -> void:
	if _visual_material == null:
		_visual_material = CanvasItemMaterial.new()
	_visual_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if blend_style == BlendStyle.ADDITIVE else CanvasItemMaterial.BLEND_MODE_MIX


func _ensure_procedural_material() -> ShaderMaterial:
	if _procedural_material != null:
		return _procedural_material
	if not ResourceLoader.exists(PROCEDURAL_SHADER):
		return null
	var shader := ResourceLoader.load(PROCEDURAL_SHADER) as Shader
	if shader == null:
		return null
	_procedural_material = ShaderMaterial.new()
	_procedural_material.shader = shader
	return _procedural_material


func _release_hidden_procedural_resources() -> void:
	if _procedural_glow != null:
		_procedural_glow.visible = false
		_procedural_glow.texture = null
		_procedural_glow.material = null
	_procedural_material = null


func _update_visuals(flicker_value: float) -> void:
	if not is_inside_tree():
		return
	_ensure_visual_material()

	var current_alpha := clampf(alpha * flicker_value, 0.0, 1.0)
	var current_intensity := maxf(0.0, intensity * flicker_value)
	var current_scale := Vector2(scale_multiplier, scale_multiplier) * stretch
	if flicker_enabled:
		current_scale *= 1.0 + ((flicker_value - 1.0) * 0.35)

	var texture_enabled := visual_enabled and (mode == Mode.TEXTURE or mode == Mode.BOTH)
	var procedural_enabled := visual_enabled and (mode == Mode.PROCEDURAL or mode == Mode.BOTH)
	_configure_texture_sprite(texture_enabled, current_scale, current_alpha, current_intensity)
	_configure_procedural_sprite(procedural_enabled, current_scale, current_alpha, current_intensity)
	_configure_point_light(current_alpha, current_intensity, current_scale)


func _configure_texture_sprite(should_show: bool, sprite_scale: Vector2, current_alpha: float, current_intensity: float) -> void:
	if _texture_glow == null:
		return
	_texture_glow.visible = should_show
	if not should_show:
		_texture_glow.material = null
		return
	_texture_glow.z_index = z_index_value
	_texture_glow.scale = sprite_scale
	_texture_glow.material = _visual_material
	_texture_glow.texture = glow_texture
	_texture_glow.modulate = Color(
		glow_color.r * current_intensity,
		glow_color.g * current_intensity,
		glow_color.b * current_intensity,
		current_alpha
	)


func _configure_procedural_sprite(should_show: bool, sprite_scale: Vector2, current_alpha: float, current_intensity: float) -> void:
	if _procedural_glow == null:
		return
	if not should_show:
		_release_hidden_procedural_resources()
		return
	var procedural_material := _ensure_procedural_material()
	if procedural_material == null:
		_procedural_glow.visible = false
		return
	_procedural_glow.visible = true
	_procedural_glow.z_index = z_index_value
	_procedural_glow.scale = sprite_scale
	_procedural_glow.texture = PROCEDURAL_BASE_TEXTURE
	_procedural_glow.material = procedural_material
	_procedural_glow.modulate = Color.WHITE
	procedural_material.set_shader_parameter("glow_color", glow_color)
	procedural_material.set_shader_parameter("intensity", current_intensity)
	procedural_material.set_shader_parameter("alpha", current_alpha)
	procedural_material.set_shader_parameter("stretch", stretch)


func _configure_point_light(current_alpha: float, current_intensity: float, sprite_scale: Vector2) -> void:
	if _point_light == null:
		return
	if not use_point_light:
		_point_light.visible = false
		_point_light.enabled = false
		_point_light.texture = null
		return
	var day_night_multiplier := lerpf(day_light_multiplier, night_light_multiplier, _night_strength)
	_point_light.texture = POINT_LIGHT_TEXTURE
	_point_light.visible = true
	_point_light.enabled = true
	_point_light.color = glow_color
	_point_light.energy = point_light_energy * current_intensity * current_alpha * day_night_multiplier
	_point_light.texture_scale = maxf(sprite_scale.x, sprite_scale.y) * point_light_scale
	_point_light.z_index = z_index_value
	_set_optional_property(_point_light, "range_z_min", -4096)
	_set_optional_property(_point_light, "range_z_max", 4096)


func _sync_initial_day_night_strength() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if cycle != null and cycle.has_method("get_night_strength"):
		_night_strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)


func _set_optional_property(target: Object, property_name: StringName, value: Variant) -> void:
	for property_info in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			target.set(property_name, value)
			return


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return glow_texture
	return ResourceLoader.load(path) as Texture2D
