@tool
extends CanvasLayer

@export_category("Fog Overlay")
@export var effect_enabled := true:
	set(value):
		effect_enabled = value
		_apply_settings()
@export_range(0.0, 1.0, 0.01) var density := 0.45:
	set(value):
		density = value
		_apply_settings()
@export var speed := Vector2(0.018, 0.007):
	set(value):
		speed = value
		_apply_settings()
@export var fog_color := Color(0.62, 0.68, 0.72, 0.18):
	set(value):
		fog_color = value
		_apply_settings()
@export_range(0.25, 12.0, 0.05) var fog_scale := 3.25:
	set(value):
		fog_scale = value
		_apply_settings()
@export_range(0.0, 1.0, 0.01) var coverage := 0.48:
	set(value):
		coverage = value
		_apply_settings()
@export_range(0.01, 0.75, 0.01) var softness := 0.24:
	set(value):
		softness = value
		_apply_settings()
@export_range(0.0, 1.0, 0.01) var detail_mix := 0.42:
	set(value):
		detail_mix = value
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
	fog_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	var shader_material := fog_rect.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		fog_rect.visible = false
		return
	fog_rect.visible = effect_enabled
	shader_material.set_shader_parameter("enabled", effect_enabled)
	shader_material.set_shader_parameter("density", density)
	shader_material.set_shader_parameter("speed", speed)
	shader_material.set_shader_parameter("fog_color", fog_color)
	shader_material.set_shader_parameter("fog_scale", fog_scale)
	shader_material.set_shader_parameter("coverage", coverage)
	shader_material.set_shader_parameter("softness", softness)
	shader_material.set_shader_parameter("detail_mix", detail_mix)
