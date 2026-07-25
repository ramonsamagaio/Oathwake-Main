extends "res://tools/content_editor/ContentEditorPlayerVisualSuite.gd"


func _build_vfx_profile_form() -> void:
	super._build_vfx_profile_form()
	if str(current_record.get("id", "default")) != "default":
		return
	var world_visuals := _record_dictionary(current_record, "world_visuals")
	var post := _record_dictionary(world_visuals, "post_processing")

	_add_subsection_title("Selective Emissive Bloom")
	var bloom_note := Label.new()
	bloom_note.text = "Extracts bright or strongly chromatic emissive pixels while suppressing neutral terrain. Additive glows, campfires, crystals and magic naturally pass the gate."
	bloom_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(bloom_note)
	_add_check_box("Bloom Enabled", "post_bloom_enabled", bool(post.get("bloom_enabled", true)))
	_add_check_box("Selective Bloom Enabled", "post_selective_bloom", bool(post.get("selective_bloom_enabled", true)))
	_add_float_spin_box("Bloom Threshold", "post_bloom_threshold", float(post.get("bloom_threshold", 0.72)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Bloom Intensity", "post_bloom_intensity", float(post.get("bloom_intensity", 1.15)), 0.0, 5.0, 0.01)
	_add_float_spin_box("Bloom Mix", "post_bloom_mix", float(post.get("glow_mix_amount", 0.28)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Blur Size", "post_blur_size", float(post.get("blur_size", 0.0036)), 0.0, 0.03, 0.0001)
	_add_spin_box("Blur Iterations", "post_blur_iterations", int(post.get("blur_iterations", 1)), 1, 4, 1)
	_add_spin_box("Blur Subdivisions", "post_blur_subdivisions", int(post.get("blur_subdivisions", 8)), 4, 16, 1)
	_add_float_spin_box("Colored Glow Boost", "post_colored_boost", float(post.get("colored_glow_boost", 0.34)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Emissive Chroma Threshold", "post_chroma_threshold", float(post.get("emissive_chroma_threshold", 0.18)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Emissive Luminance Threshold", "post_luminance_threshold", float(post.get("emissive_luminance_threshold", 0.60)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Neutral Suppression", "post_neutral_suppression", float(post.get("neutral_suppression", 0.88)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Warm Emissive Boost", "post_warm_emissive_boost", float(post.get("warm_emissive_boost", 0.34)), 0.0, 2.0, 0.01)

	_add_subsection_title("Time-Aware Color Grading")
	var grading_note := Label.new()
	grading_note.text = "Interpolates between day and night grading. Night shadows become cooler while warm local lights retain their authored color and readability."
	grading_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(grading_note)
	_add_check_box("Color Grading Enabled", "post_grading_enabled", bool(post.get("grading_enabled", true)))
	_add_content_color_picker("Day Tint", "post_day_tint", _color_from_value(post.get("day_tint", "#FFF8EBFF"), Color(1.0, 0.973, 0.922, 1.0)))
	_add_content_color_picker("Night Tint", "post_night_tint", _color_from_value(post.get("night_tint", "#B8C8FFFF"), Color(0.72, 0.78, 1.0, 1.0)))
	_add_float_spin_box("Day Saturation", "post_day_saturation", float(post.get("day_saturation", 1.04)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Night Saturation", "post_night_saturation", float(post.get("night_saturation", 0.84)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Day Contrast", "post_day_contrast", float(post.get("day_contrast", 1.03)), 0.5, 2.0, 0.01)
	_add_float_spin_box("Night Contrast", "post_night_contrast", float(post.get("night_contrast", 1.10)), 0.5, 2.0, 0.01)
	_add_float_spin_box("Day Brightness", "post_day_brightness", float(post.get("day_brightness", 0.012)), -0.5, 0.5, 0.005)
	_add_float_spin_box("Night Brightness", "post_night_brightness", float(post.get("night_brightness", -0.018)), -0.5, 0.5, 0.005)
	_add_float_spin_box("Warm Light Preservation", "post_warm_preservation", float(post.get("warm_light_preservation", 0.82)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Night Shadow Lift", "post_shadow_lift", float(post.get("night_shadow_lift", 0.045)), 0.0, 0.25, 0.005)
	_add_float_spin_box("Cool Shadow Strength", "post_cool_shadow_strength", float(post.get("night_cool_shadow_strength", 0.34)), 0.0, 1.0, 0.01)


func _get_vfx_profile_form_record() -> Dictionary:
	var record := super._get_vfx_profile_form_record()
	if str(record.get("id", "default")) != "default" or not field_controls.has("post_bloom_enabled"):
		return record
	var world_visuals := _record_dictionary(record, "world_visuals")
	world_visuals["post_processing"] = {
		"bloom_enabled": _get_check_box_pressed("post_bloom_enabled"),
		"selective_bloom_enabled": _get_check_box_pressed("post_selective_bloom"),
		"bloom_threshold": _get_spin_box_value("post_bloom_threshold"),
		"bloom_intensity": _get_spin_box_value("post_bloom_intensity"),
		"glow_mix_amount": _get_spin_box_value("post_bloom_mix"),
		"blur_size": _get_spin_box_value("post_blur_size"),
		"blur_iterations": _get_spin_box_int("post_blur_iterations"),
		"blur_subdivisions": _get_spin_box_int("post_blur_subdivisions"),
		"colored_glow_boost": _get_spin_box_value("post_colored_boost"),
		"emissive_chroma_threshold": _get_spin_box_value("post_chroma_threshold"),
		"emissive_luminance_threshold": _get_spin_box_value("post_luminance_threshold"),
		"neutral_suppression": _get_spin_box_value("post_neutral_suppression"),
		"warm_emissive_boost": _get_spin_box_value("post_warm_emissive_boost"),
		"grading_enabled": _get_check_box_pressed("post_grading_enabled"),
		"day_tint": _get_content_color_html("post_day_tint"),
		"night_tint": _get_content_color_html("post_night_tint"),
		"day_saturation": _get_spin_box_value("post_day_saturation"),
		"night_saturation": _get_spin_box_value("post_night_saturation"),
		"day_contrast": _get_spin_box_value("post_day_contrast"),
		"night_contrast": _get_spin_box_value("post_night_contrast"),
		"day_brightness": _get_spin_box_value("post_day_brightness"),
		"night_brightness": _get_spin_box_value("post_night_brightness"),
		"warm_light_preservation": _get_spin_box_value("post_warm_preservation"),
		"night_shadow_lift": _get_spin_box_value("post_shadow_lift"),
		"night_cool_shadow_strength": _get_spin_box_value("post_cool_shadow_strength"),
	}
	record["world_visuals"] = world_visuals
	return record
