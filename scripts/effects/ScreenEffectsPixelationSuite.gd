extends "res://scripts/effects/ScreenEffects.gd"

var _pixelation_runtime_override: Variant = null


func _sync_glow_material() -> void:
	super._sync_glow_material()
	_apply_pixelation_to_compositor()


func set_pixelation_runtime_enabled(enabled: bool) -> void:
	_pixelation_runtime_override = enabled
	_apply_pixelation_to_compositor()


func clear_pixelation_runtime_override() -> void:
	_pixelation_runtime_override = null
	_apply_pixelation_to_compositor()


func is_pixelation_enabled() -> bool:
	if _pixelation_runtime_override is bool:
		return bool(_pixelation_runtime_override)
	return bool(_post_processing_config.get("pixelation_enabled", false))


func get_pixelation_settings() -> Dictionary:
	return {
		"enabled": is_pixelation_enabled(),
		"pixel_size": clampf(round(float(_post_processing_config.get("pixelation_pixel_size", 4.0))), 1.0, 32.0),
		"strength": clampf(float(_post_processing_config.get("pixelation_strength", 1.0)), 0.0, 1.0),
		"pixel_aspect": clampf(float(_post_processing_config.get("pixelation_aspect", 1.0)), 0.5, 2.0),
		"color_steps": clampf(float(_post_processing_config.get("pixelation_color_steps", 0.0)), 0.0, 32.0),
		"dither_strength": clampf(float(_post_processing_config.get("pixelation_dither_strength", 0.0)), 0.0, 1.0),
	}


func _apply_pixelation_to_compositor() -> void:
	if gaussian_glow == null or not (gaussian_glow.material is ShaderMaterial):
		return
	var material := gaussian_glow.material as ShaderMaterial
	var config := get_pixelation_settings()
	var pixelation_active := bool(config.get("enabled", false)) and float(config.get("strength", 1.0)) > 0.0
	material.set_shader_parameter("pixelation_enabled", pixelation_active)
	material.set_shader_parameter("pixelation_pixel_size", float(config.get("pixel_size", 4.0)))
	material.set_shader_parameter("pixelation_strength", float(config.get("strength", 1.0)))
	material.set_shader_parameter("pixelation_aspect", float(config.get("pixel_aspect", 1.0)))
	material.set_shader_parameter("pixelation_color_steps", float(config.get("color_steps", 0.0)))
	material.set_shader_parameter("pixelation_dither_strength", float(config.get("dither_strength", 0.0)))

	# The original compositor only stays visible for bloom or grading. Pixelation
	# is now part of the same pass, so it must keep that compositor and its one
	# proven BackBufferCopy alive even when bloom/grading are disabled.
	if pixelation_active:
		gaussian_glow.visible = true
		if back_buffer_copy != null:
			back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
