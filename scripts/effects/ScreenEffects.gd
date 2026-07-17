@tool
extends CanvasLayer

@onready var settings: Node = $Settings
@onready var gaussian_glow: ColorRect = $GaussianGlow
@onready var speed_lines: ColorRect = $SpeedLines

var _dash_tween: Tween


func _ready() -> void:
	add_to_group("screen_effects")
	_sync_settings()
	if speed_lines != null:
		speed_lines.visible = false
		speed_lines.modulate.a = 0.0


func refresh_from_settings() -> void:
	_sync_settings()


func play_dash_lines(custom_duration := -1.0) -> void:
	_sync_settings()
	if settings == null or speed_lines == null:
		return
	if not bool(settings.get("dash_lines_enabled")):
		return

	var duration := float(settings.get("dash_effect_duration"))
	if custom_duration > 0.0:
		duration = custom_duration
	duration = maxf(duration, 0.04)

	if _dash_tween != null:
		_dash_tween.kill()
		_dash_tween = null

	speed_lines.visible = true
	speed_lines.modulate.a = 0.0
	_dash_tween = create_tween()
	_dash_tween.tween_property(speed_lines, "modulate:a", 1.0, minf(0.035, duration * 0.25))
	_dash_tween.tween_interval(maxf(duration - 0.07, 0.0))
	_dash_tween.tween_property(speed_lines, "modulate:a", 0.0, minf(0.035, duration * 0.25))
	_dash_tween.tween_callback(_finish_dash_lines)


func _finish_dash_lines() -> void:
	if speed_lines != null:
		speed_lines.visible = false
	_dash_tween = null


func _sync_settings() -> void:
	if not is_node_ready() or settings == null:
		return
	_sync_speed_lines_material()
	_sync_glow_material()


func _sync_speed_lines_material() -> void:
	if speed_lines == null:
		return
	var shader_material := speed_lines.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return
	shader_material.set_shader_parameter("enabled", bool(settings.get("dash_lines_enabled")))
	shader_material.set_shader_parameter("noise", settings.get("dash_noise_texture"))
	shader_material.set_shader_parameter("line_color", settings.get("dash_line_color"))
	shader_material.set_shader_parameter("line_count", float(settings.get("dash_line_count")))
	shader_material.set_shader_parameter("line_density", float(settings.get("dash_line_density")))
	shader_material.set_shader_parameter("line_falloff", float(settings.get("dash_line_falloff")))
	shader_material.set_shader_parameter("mask_size", float(settings.get("dash_mask_size")))
	shader_material.set_shader_parameter("mask_edge", float(settings.get("dash_mask_edge")))
	shader_material.set_shader_parameter("animation_speed", float(settings.get("dash_animation_speed")))


func _sync_glow_material() -> void:
	if gaussian_glow == null:
		return
	gaussian_glow.visible = bool(settings.get("glow_enabled"))
	var shader_material := gaussian_glow.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return
	shader_material.set_shader_parameter("enabled", bool(settings.get("glow_enabled")))
	shader_material.set_shader_parameter("bloom_threshold", float(settings.get("bloom_threshold")))
	shader_material.set_shader_parameter("bloom_intensity", float(settings.get("bloom_intensity")))
	shader_material.set_shader_parameter("blur_iterations", int(settings.get("blur_iterations")))
	shader_material.set_shader_parameter("blur_size", float(settings.get("blur_size")))
	shader_material.set_shader_parameter("blur_subdivisions", int(settings.get("blur_subdivisions")))
	shader_material.set_shader_parameter("mix_amount", float(settings.get("glow_mix_amount")))
