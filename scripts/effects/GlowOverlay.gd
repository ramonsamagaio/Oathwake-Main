@tool
extends Node2D

enum Mode { TEXTURE, PROCEDURAL, BOTH }

const GLOW_WINDOW_TEXTURE := "res://assets/sprites/effects/glows/Glow1.png"
const GLOW_LAMP_TEXTURE := "res://assets/sprites/effects/glows/glow2.png"
const GLOW_MAGIC_TEXTURE := "res://assets/sprites/effects/glows/glow3.png"
const PROCEDURAL_SHADER := "res://shaders/effects/glow_procedural.gdshader"
const PROCEDURAL_BASE_TEXTURE: Texture2D = preload("res://assets/sprites/effects/glows/glow2.png")
const POINT_LIGHT_TEXTURE: Texture2D = preload("res://assets/sprites/effects/glows/glow2.png")

@export_enum("Texture", "Procedural", "Both") var mode: int = Mode.TEXTURE
@export var glow_texture: Texture2D = preload("res://assets/sprites/effects/glows/glow2.png")
@export var glow_color: Color = Color(1.0, 0.68, 0.28, 1.0)
@export_range(0.0, 8.0, 0.05) var intensity: float = 1.0
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.75
@export_range(0.05, 8.0, 0.05) var scale_multiplier: float = 1.0
@export var stretch: Vector2 = Vector2.ONE
@export var flicker_enabled: bool = false
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.08
@export_range(0.05, 12.0, 0.05) var flicker_speed: float = 2.0
@export var use_point_light: bool = false
@export_range(0.0, 8.0, 0.05) var point_light_energy: float = 0.65
@export_range(0.05, 8.0, 0.05) var point_light_scale: float = 1.2
@export var z_index_value: int = 0

@onready var _texture_glow: Sprite2D = $TextureGlow
@onready var _procedural_glow: Sprite2D = $ProceduralGlow
@onready var _point_light: PointLight2D = $PointLight2D

var _time: float = 0.0
var _phase: float = 0.0
var _additive_material: CanvasItemMaterial
var _procedural_material: ShaderMaterial


func _ready() -> void:
	_phase = randf() * TAU
	_ensure_additive_material()
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


func apply_window_preset() -> void:
	mode = Mode.TEXTURE
	glow_texture = _load_texture(GLOW_WINDOW_TEXTURE)
	glow_color = Color(1.0, 0.55, 0.22, 1.0)
	intensity = 0.85
	alpha = 0.58
	scale_multiplier = 1.0
	stretch = Vector2(1.75, 0.75)
	flicker_enabled = false
	flicker_amount = 0.03
	flicker_speed = 1.0
	use_point_light = false
	_update_visuals(1.0)


func apply_lamp_preset() -> void:
	mode = Mode.TEXTURE
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
	point_light_energy = 0.55
	point_light_scale = 1.0
	_update_visuals(1.0)


func apply_magic_preset() -> void:
	mode = Mode.BOTH
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
	point_light_energy = 0.7
	point_light_scale = 1.35
	_update_visuals(1.0)


func apply_soft_fire_preset() -> void:
	mode = Mode.TEXTURE
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
	point_light_energy = 0.6
	point_light_scale = 1.05
	_update_visuals(1.0)


func _ensure_additive_material() -> void:
	if _additive_material != null:
		return
	_additive_material = CanvasItemMaterial.new()
	_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


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
	_ensure_additive_material()

	var current_alpha := clampf(alpha * flicker_value, 0.0, 1.0)
	var current_intensity := maxf(0.0, intensity * flicker_value)
	var current_scale := Vector2(scale_multiplier, scale_multiplier) * stretch
	if flicker_enabled:
		current_scale *= 1.0 + ((flicker_value - 1.0) * 0.35)

	var texture_enabled := mode == Mode.TEXTURE or mode == Mode.BOTH
	var procedural_enabled := mode == Mode.PROCEDURAL or mode == Mode.BOTH
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
	_texture_glow.material = _additive_material
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
	_point_light.texture = POINT_LIGHT_TEXTURE
	_point_light.visible = true
	_point_light.enabled = true
	_point_light.color = glow_color
	_point_light.energy = point_light_energy * current_intensity * current_alpha
	_point_light.scale = sprite_scale * point_light_scale
	_point_light.z_index = z_index_value


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return glow_texture
	return ResourceLoader.load(path) as Texture2D
