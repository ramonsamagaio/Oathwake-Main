extends "res://tools/content_editor/ContentEditorPlayerVisualSuite.gd"


func _build_vfx_profile_form() -> void:
	super._build_vfx_profile_form()
	if str(current_record.get("id", "default")) != "default":
		return
	var world_visuals := _record_dictionary(current_record, "world_visuals")
	var post := _record_dictionary(world_visuals, "post_processing")

	_add_subsection_title("Final Pixelation Filter")
	var pixelation_note := Label.new()
	pixelation_note.text = "Filtro final aplicado ao mundo depois de fog, shafts, bloom e color grading. HUD, inventario e menus ficam limpos porque sao desenhados acima deste passe."
	pixelation_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(pixelation_note)
	_add_check_box("Pixelation Enabled by Default", "post_pixelation_enabled", bool(post.get("pixelation_enabled", false)))
	_add_post_parameter_help("Define se o filtro ja inicia ligado ao entrar no gameplay. O botao PIXEL FILTER no menu lateral pode sobrescrever isso temporariamente durante o teste.")
	_add_spin_box("Pixel Size", "post_pixelation_pixel_size", int(post.get("pixelation_pixel_size", 4)), 1, 32, 1)
	_add_post_parameter_help("Tamanho do bloco em pixels da tela. 1 praticamente preserva a resolucao original; 4 agrupa a imagem em blocos de 4x4; valores maiores deixam o pixel visualmente mais grosso.")
	_add_float_spin_box("Strength", "post_pixelation_strength", float(post.get("pixelation_strength", 1.0)), 0.0, 1.0, 0.01)
	_add_post_parameter_help("Mistura entre a imagem normal e a pixelizada. 0 = efeito invisivel; 0.5 = meio termo; 1 = pixelizacao completa.")
	_add_float_spin_box("Pixel Aspect", "post_pixelation_aspect", float(post.get("pixelation_aspect", 1.0)), 0.5, 2.0, 0.01)
	_add_post_parameter_help("Formato horizontal de cada bloco. 1 = pixel quadrado. Abaixo de 1 deixa o bloco mais estreito; acima de 1 deixa o bloco mais largo, util para testar estéticas de displays antigos.")
	_add_spin_box("Color Steps", "post_pixelation_color_steps", int(post.get("pixelation_color_steps", 0)), 0, 32, 1)
	_add_post_parameter_help("Reducao opcional de cores por canal RGB. 0 = nao reduz cores. Valores baixos, como 4 ou 8, deixam a paleta mais limitada e retro; 16 ou 32 preservam mais gradacoes.")
	_add_float_spin_box("Dither Strength", "post_pixelation_dither_strength", float(post.get("pixelation_dither_strength", 0.0)), 0.0, 1.0, 0.01)
	_add_post_parameter_help("Adiciona uma variacao discreta entre blocos para quebrar faixas de cor criadas por Color Steps. So tem efeito perceptivel quando a reducao de cores esta ativa. 0 = desligado.")

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

	_add_subsection_title("Local Light Night Mask")
	var mask_note := Label.new()
	mask_note.text = "Uses the player PointLight2D as a radial mask against the night grading pass. The world is still dark, but the already-lit pixels remain clean instead of receiving a second blue-dark filter."
	mask_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(mask_note)
	_add_check_box("Protect Player-Lit Area", "post_local_light_mask_enabled", bool(post.get("local_light_grading_mask_enabled", true)))
	_add_float_spin_box("Night Filter Protection", "post_local_light_protection", float(post.get("local_light_grading_protection", 0.92)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Mask Edge Softness", "post_local_light_softness", float(post.get("local_light_mask_softness", 0.42)), 0.01, 1.0, 0.01)
	_add_float_spin_box("Protected Scene Lift", "post_local_light_lift", float(post.get("local_light_scene_lift", 0.035)), 0.0, 0.25, 0.005)


func _get_vfx_profile_form_record() -> Dictionary:
	var record := super._get_vfx_profile_form_record()
	if str(record.get("id", "default")) != "default" or not field_controls.has("post_bloom_enabled"):
		return record
	var world_visuals := _record_dictionary(record, "world_visuals")
	var post := _record_dictionary(world_visuals, "post_processing")
	post["pixelation_enabled"] = _get_check_box_pressed("post_pixelation_enabled")
	post["pixelation_pixel_size"] = _get_spin_box_int("post_pixelation_pixel_size")
	post["pixelation_strength"] = _get_spin_box_value("post_pixelation_strength")
	post["pixelation_aspect"] = _get_spin_box_value("post_pixelation_aspect")
	post["pixelation_color_steps"] = _get_spin_box_int("post_pixelation_color_steps")
	post["pixelation_dither_strength"] = _get_spin_box_value("post_pixelation_dither_strength")
	post["bloom_enabled"] = _get_check_box_pressed("post_bloom_enabled")
	post["selective_bloom_enabled"] = _get_check_box_pressed("post_selective_bloom")
	post["bloom_threshold"] = _get_spin_box_value("post_bloom_threshold")
	post["bloom_intensity"] = _get_spin_box_value("post_bloom_intensity")
	post["glow_mix_amount"] = _get_spin_box_value("post_bloom_mix")
	post["blur_size"] = _get_spin_box_value("post_blur_size")
	post["blur_iterations"] = _get_spin_box_int("post_blur_iterations")
	post["blur_subdivisions"] = _get_spin_box_int("post_blur_subdivisions")
	post["colored_glow_boost"] = _get_spin_box_value("post_colored_boost")
	post["emissive_chroma_threshold"] = _get_spin_box_value("post_chroma_threshold")
	post["emissive_luminance_threshold"] = _get_spin_box_value("post_luminance_threshold")
	post["neutral_suppression"] = _get_spin_box_value("post_neutral_suppression")
	post["warm_emissive_boost"] = _get_spin_box_value("post_warm_emissive_boost")
	post["grading_enabled"] = _get_check_box_pressed("post_grading_enabled")
	post["day_tint"] = _get_content_color_html("post_day_tint")
	post["night_tint"] = _get_content_color_html("post_night_tint")
	post["day_saturation"] = _get_spin_box_value("post_day_saturation")
	post["night_saturation"] = _get_spin_box_value("post_night_saturation")
	post["day_contrast"] = _get_spin_box_value("post_day_contrast")
	post["night_contrast"] = _get_spin_box_value("post_night_contrast")
	post["day_brightness"] = _get_spin_box_value("post_day_brightness")
	post["night_brightness"] = _get_spin_box_value("post_night_brightness")
	post["warm_light_preservation"] = _get_spin_box_value("post_warm_preservation")
	post["night_shadow_lift"] = _get_spin_box_value("post_shadow_lift")
	post["night_cool_shadow_strength"] = _get_spin_box_value("post_cool_shadow_strength")
	post["local_light_grading_mask_enabled"] = _get_check_box_pressed("post_local_light_mask_enabled")
	post["local_light_grading_protection"] = _get_spin_box_value("post_local_light_protection")
	post["local_light_mask_softness"] = _get_spin_box_value("post_local_light_softness")
	post["local_light_scene_lift"] = _get_spin_box_value("post_local_light_lift")
	world_visuals["post_processing"] = post
	record["world_visuals"] = world_visuals
	return record


func _add_post_parameter_help(text: String) -> void:
	var help := Label.new()
	help.text = text
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(0.72, 0.76, 0.82, 1.0)
	form_container.add_child(help)
