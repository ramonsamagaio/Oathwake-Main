@tool
extends CanvasLayer

@export_category("Fog Overlay")
@export var effect_enabled := false:
	set(value):
		effect_enabled = value
		_apply_settings()
@export_range(0.0, 1.0, 0.01) var density := 0.10:
	set(value):
		density = value
		_apply_settings()
@export var speed := Vector2(0.008, 0.004):
	set(value):
		speed = value
		_apply_settings()
@export var fog_color := Color(0.62, 0.68, 0.72, 0.28):
	set(value):
		fog_color = value
		_apply_settings()
@export var noise_texture: Texture2D:
	set(value):
		noise_texture = value
		_apply_settings()

@onready var fog_rect: ColorRect = $FogRect


func _ready() -> void:
	_apply_settings()


func refresh_from_settings() -> void:
	_apply_settings()


func _apply_settings() -> void:
	visible = effect_enabled
	if not is_node_ready() or fog_rect == null:
		return
	fog_rect.visible = effect_enabled
	fog_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	var shader_material := fog_rect.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		fog_rect.visible = false
		return
	shader_material.set_shader_parameter("enabled", effect_enabled)
	shader_material.set_shader_parameter("density", density)
	shader_material.set_shader_parameter("speed", speed)
	shader_material.set_shader_parameter("fog_color", fog_color)
	shader_material.set_shader_parameter("noise_texture", noise_texture)
