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

@export_category("World Anchoring")
@export var anchor_to_world := true:
	set(value):
		anchor_to_world = value
		_apply_settings()
@export_range(0.0, 2.0, 0.01) var world_anchor_strength := 1.0:
	set(value):
		world_anchor_strength = value
		_apply_settings()

@onready var fog_rect: ColorRect = $FogRect

var _last_camera_offset := Vector2(INF, INF)


func _ready() -> void:
	_apply_settings()
	_update_world_anchor(true)
	set_process(true)


func _process(_delta: float) -> void:
	if effect_enabled:
		_update_world_anchor(false)


func refresh_from_settings() -> void:
	_apply_settings()
	_update_world_anchor(true)


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
	shader_material.set_shader_parameter("world_anchor_strength", world_anchor_strength if anchor_to_world else 0.0)


func _update_world_anchor(force_update: bool) -> void:
	if not is_node_ready() or fog_rect == null:
		return
	var shader_material := fog_rect.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return
	if not anchor_to_world:
		if force_update or _last_camera_offset != Vector2.ZERO:
			_last_camera_offset = Vector2.ZERO
			shader_material.set_shader_parameter("camera_offset", Vector2.ZERO)
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var inverse_canvas := viewport.get_canvas_transform().affine_inverse()
	var world_top_left := inverse_canvas * Vector2.ZERO
	var world_bottom_right := inverse_canvas * viewport_size
	var world_span := (world_bottom_right - world_top_left).abs()
	world_span.x = maxf(world_span.x, 1.0)
	world_span.y = maxf(world_span.y, 1.0)
	var camera_offset := Vector2(
		world_top_left.x / world_span.x,
		world_top_left.y / world_span.y
	)
	if not force_update and camera_offset.is_equal_approx(_last_camera_offset):
		return
	_last_camera_offset = camera_offset
	shader_material.set_shader_parameter("camera_offset", camera_offset)
	shader_material.set_shader_parameter("world_anchor_strength", world_anchor_strength)
