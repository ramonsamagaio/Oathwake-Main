@tool
extends CanvasLayer

@onready var settings: Node = $Settings
@onready var back_buffer_copy: BackBufferCopy = $BackBufferCopy
@onready var gaussian_glow: ColorRect = $GaussianGlow
@onready var speed_lines: ColorRect = $SpeedLines

const DEFAULT_PLAYER_READABILITY_RADIUS_WORLD := Vector2(22.0, 38.0)
const DEFAULT_PLAYER_READABILITY_OFFSET_WORLD := Vector2(0.0, -1.0)
const MAX_ENVIRONMENT_GRADING_PROTECTION := 0.28
const MAX_ENVIRONMENT_SCENE_LIFT := 0.012

var _dash_tween: Tween
var _post_processing_config: Dictionary = {}
var _night_strength := 0.0
var _last_applied_night_strength := -1.0
var _local_light_source: Node2D
var _player_readability_source: Node2D


func _ready() -> void:
	add_to_group("screen_effects")
	add_to_group("world_post_process")
	_reload_post_processing_config()
	_connect_content_reload()
	_sync_settings()
	if speed_lines != null:
		speed_lines.visible = false
		speed_lines.modulate.a = 0.0
	set_process(true)


func _process(_delta: float) -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	var target_strength := 0.0
	if cycle != null and cycle.has_method("get_night_strength"):
		target_strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	set_day_night_strength(target_strength)
	_sync_local_light_grading_mask()
	_sync_player_readability_mask()


func set_day_night_strength(strength: float) -> void:
	_night_strength = clampf(strength, 0.0, 1.0)
	if absf(_night_strength - _last_applied_night_strength) < 0.001:
		return
	_last_applied_night_strength = _night_strength
	_sync_dynamic_grading()


func refresh_from_settings() -> void:
	_post_processing_config.clear()
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


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "_on_content_reloaded")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func _on_content_reloaded() -> void:
	_reload_post_processing_config()
	_sync_settings()


func _reload_post_processing_config() -> void:
	_post_processing_config.clear()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var world_value: Variant = profile.get("world_visuals", {})
	if not (world_value is Dictionary):
		return
	var post_value: Variant = (world_value as Dictionary).get("post_processing", {})
	if post_value is Dictionary:
		_post_processing_config = (post_value as Dictionary).duplicate(true)


func _sync_settings() -> void:
	if not is_node_ready() or settings == null:
		return
	_sync_speed_lines_material()
	_sync_glow_material()


func _sync_speed_lines_material() -> void:
	if speed_lines == null:
		return
	var enabled := bool(settings.get("dash_lines_enabled"))
	var shader_material := speed_lines.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		speed_lines.visible = false
		return
	shader_material.set_shader_parameter("enabled", enabled)
	shader_material.set_shader_parameter("line_color", settings.get("dash_line_color"))
	shader_material.set_shader_parameter("line_count", float(settings.get("dash_line_count")))
	shader_material.set_shader_parameter("line_density", float(settings.get("dash_line_density")))
	shader_material.set_shader_parameter("line_falloff", float(settings.get("dash_line_falloff")))
	shader_material.set_shader_parameter("mask_size", float(settings.get("dash_mask_size")))
	shader_material.set_shader_parameter("mask_edge", float(settings.get("dash_mask_edge")))
	shader_material.set_shader_parameter("animation_speed", float(settings.get("dash_animation_speed")))
	if not enabled:
		speed_lines.visible = false


func _sync_glow_material() -> void:
	if gaussian_glow == null:
		return
	gaussian_glow.color = Color(0.0, 0.0, 0.0, 0.0)
	var shader_material := gaussian_glow.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		gaussian_glow.visible = false
		if back_buffer_copy != null:
			back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return
	var bloom_enabled := bool(_post_processing_config.get("bloom_enabled", settings.get("glow_enabled")))
	var grading_enabled := bool(_post_processing_config.get("grading_enabled", settings.get("grading_enabled")))
	var effects_enabled := bloom_enabled or grading_enabled
	if back_buffer_copy != null:
		back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if effects_enabled else BackBufferCopy.COPY_MODE_DISABLED
	gaussian_glow.visible = effects_enabled
	shader_material.set_shader_parameter("enabled", effects_enabled)
	shader_material.set_shader_parameter("bloom_enabled", bloom_enabled)
	shader_material.set_shader_parameter("selective_bloom_enabled", bool(_post_processing_config.get("selective_bloom_enabled", settings.get("selective_bloom_enabled"))))
	shader_material.set_shader_parameter("bloom_threshold", _float_setting("bloom_threshold"))
	shader_material.set_shader_parameter("bloom_intensity", _float_setting("bloom_intensity"))
	shader_material.set_shader_parameter("blur_iterations", int(_post_processing_config.get("blur_iterations", settings.get("blur_iterations"))))
	shader_material.set_shader_parameter("blur_size", _float_setting("blur_size"))
	shader_material.set_shader_parameter("blur_subdivisions", int(_post_processing_config.get("blur_subdivisions", settings.get("blur_subdivisions"))))
	shader_material.set_shader_parameter("mix_amount", _float_setting("glow_mix_amount"))
	shader_material.set_shader_parameter("colored_glow_boost", _float_setting("colored_glow_boost"))
	shader_material.set_shader_parameter("emissive_chroma_threshold", _float_setting("emissive_chroma_threshold"))
	shader_material.set_shader_parameter("emissive_luminance_threshold", _float_setting("emissive_luminance_threshold"))
	shader_material.set_shader_parameter("neutral_suppression", _float_setting("neutral_suppression"))
	shader_material.set_shader_parameter("warm_emissive_boost", _float_setting("warm_emissive_boost"))
	shader_material.set_shader_parameter("grading_enabled", grading_enabled)
	shader_material.set_shader_parameter("day_tint", _color_setting("day_tint"))
	shader_material.set_shader_parameter("night_tint", _color_setting("night_tint"))
	shader_material.set_shader_parameter("day_saturation", _float_setting("day_saturation"))
	shader_material.set_shader_parameter("night_saturation", _float_setting("night_saturation"))
	shader_material.set_shader_parameter("day_contrast", _float_setting("day_contrast"))
	shader_material.set_shader_parameter("night_contrast", _float_setting("night_contrast"))
	shader_material.set_shader_parameter("day_brightness", _float_setting("day_brightness"))
	shader_material.set_shader_parameter("night_brightness", _float_setting("night_brightness"))
	shader_material.set_shader_parameter("warm_light_preservation", _float_setting("warm_light_preservation"))
	shader_material.set_shader_parameter("night_shadow_lift", _float_setting("night_shadow_lift"))
	shader_material.set_shader_parameter("night_cool_shadow_strength", _float_setting("night_cool_shadow_strength"))
	shader_material.set_shader_parameter("local_light_grading_mask_enabled", bool(_post_processing_config.get("local_light_grading_mask_enabled", true)))
	var authored_environment_protection := float(_post_processing_config.get("local_light_grading_protection", 0.92))
	var environment_protection_scale := float(_post_processing_config.get("local_light_environment_protection_scale", 0.26))
	var environment_protection := clampf(authored_environment_protection * environment_protection_scale, 0.0, MAX_ENVIRONMENT_GRADING_PROTECTION)
	var authored_environment_lift := float(_post_processing_config.get("local_light_scene_lift", 0.035))
	var environment_lift_scale := float(_post_processing_config.get("local_light_environment_lift_scale", 0.30))
	var environment_lift := clampf(authored_environment_lift * environment_lift_scale, 0.0, MAX_ENVIRONMENT_SCENE_LIFT)
	shader_material.set_shader_parameter("local_light_grading_protection", environment_protection)
	shader_material.set_shader_parameter("local_light_mask_softness", float(_post_processing_config.get("local_light_mask_softness", 0.42)))
	shader_material.set_shader_parameter("local_light_scene_lift", environment_lift)
	shader_material.set_shader_parameter("player_readability_mask_enabled", bool(_post_processing_config.get("player_readability_mask_enabled", true)))
	shader_material.set_shader_parameter("player_readability_protection", float(_post_processing_config.get("player_readability_protection", 0.985)))
	shader_material.set_shader_parameter("player_readability_mask_softness", float(_post_processing_config.get("player_readability_mask_softness", 0.22)))
	shader_material.set_shader_parameter("player_readability_scene_lift", float(_post_processing_config.get("player_readability_scene_lift", 0.012)))
	_sync_dynamic_grading()
	_sync_local_light_grading_mask()
	_sync_player_readability_mask()


func _sync_dynamic_grading() -> void:
	if gaussian_glow == null or not (gaussian_glow.material is ShaderMaterial):
		return
	(gaussian_glow.material as ShaderMaterial).set_shader_parameter("night_strength", _night_strength)


func _sync_local_light_grading_mask() -> void:
	if gaussian_glow == null or not (gaussian_glow.material is ShaderMaterial):
		return
	var material := gaussian_glow.material as ShaderMaterial
	if not bool(_post_processing_config.get("local_light_grading_mask_enabled", true)) or _night_strength <= 0.001:
		material.set_shader_parameter("local_light_source_active", false)
		return
	if _local_light_source == null or not is_instance_valid(_local_light_source):
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			_local_light_source = player.get_node_or_null("NightLight") as Node2D
	if _local_light_source == null or not is_instance_valid(_local_light_source):
		material.set_shader_parameter("local_light_source_active", false)
		return
	var point_light := _local_light_source.get_node_or_null("PointLight2D") as PointLight2D
	if point_light == null or not point_light.enabled or point_light.energy <= 0.001 or point_light.texture == null:
		material.set_shader_parameter("local_light_source_active", false)
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		material.set_shader_parameter("local_light_source_active", false)
		return
	var canvas_transform := get_viewport().get_canvas_transform()
	var screen_position := canvas_transform * _local_light_source.global_position
	var screen_uv := Vector2(screen_position.x / viewport_size.x, screen_position.y / viewport_size.y)
	var texture_size := point_light.texture.get_size()
	var source_scale := Vector2(absf(_local_light_source.global_scale.x), absf(_local_light_source.global_scale.y))
	var radius_world := Vector2(texture_size.x, texture_size.y) * 0.5 * point_light.texture_scale * source_scale
	var radius_pixels := Vector2(
		radius_world.x * canvas_transform.x.length(),
		radius_world.y * canvas_transform.y.length()
	)
	var radius_uv := Vector2(radius_pixels.x / viewport_size.x, radius_pixels.y / viewport_size.y)
	var source_strength := clampf(point_light.energy * 1.55, 0.0, 1.0)
	material.set_shader_parameter("local_light_source_active", true)
	material.set_shader_parameter("local_light_screen_position", screen_uv)
	material.set_shader_parameter("local_light_radius_uv", radius_uv.max(Vector2(0.001, 0.001)))
	material.set_shader_parameter("local_light_source_strength", source_strength)
	material.set_meta("local_light_mask_scale", source_scale)


func _sync_player_readability_mask() -> void:
	if gaussian_glow == null or not (gaussian_glow.material is ShaderMaterial):
		return
	var material := gaussian_glow.material as ShaderMaterial
	if not bool(_post_processing_config.get("player_readability_mask_enabled", true)) or _night_strength <= 0.001:
		material.set_shader_parameter("player_readability_source_active", false)
		return
	if _player_readability_source == null or not is_instance_valid(_player_readability_source):
		_player_readability_source = get_tree().get_first_node_in_group("player") as Node2D
	if _player_readability_source == null or not is_instance_valid(_player_readability_source):
		material.set_shader_parameter("player_readability_source_active", false)
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		material.set_shader_parameter("player_readability_source_active", false)
		return
	var canvas_transform := get_viewport().get_canvas_transform()
	var offset_world := _vector_config("player_readability_offset_world", DEFAULT_PLAYER_READABILITY_OFFSET_WORLD)
	var source_position := _player_readability_source.global_position + offset_world
	var screen_position := canvas_transform * source_position
	var screen_uv := Vector2(screen_position.x / viewport_size.x, screen_position.y / viewport_size.y)
	var source_scale := Vector2(absf(_player_readability_source.global_scale.x), absf(_player_readability_source.global_scale.y))
	var radius_world := _vector_config("player_readability_radius_world", DEFAULT_PLAYER_READABILITY_RADIUS_WORLD) * source_scale
	var radius_pixels := Vector2(
		radius_world.x * canvas_transform.x.length(),
		radius_world.y * canvas_transform.y.length()
	)
	var radius_uv := Vector2(radius_pixels.x / viewport_size.x, radius_pixels.y / viewport_size.y)
	material.set_shader_parameter("player_readability_source_active", true)
	material.set_shader_parameter("player_readability_screen_position", screen_uv)
	material.set_shader_parameter("player_readability_radius_uv", radius_uv.max(Vector2(0.001, 0.001)))
	material.set_meta("player_readability_radius_world", radius_world)
	material.set_meta("player_readability_source_id", _player_readability_source.get_instance_id())


func _float_setting(key: String) -> float:
	return float(_post_processing_config.get(key, settings.get(key)))


func _color_setting(key: String) -> Color:
	var fallback: Variant = settings.get(key)
	var value: Variant = _post_processing_config.get(key, fallback)
	if value is Color:
		return value
	return Color.from_string(str(value), fallback as Color)


func _vector_config(key: String, fallback: Vector2) -> Vector2:
	var value: Variant = _post_processing_config.get(key, fallback)
	if value is Vector2:
		return value as Vector2
	if value is Dictionary:
		var data := value as Dictionary
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))
	return fallback
