extends "res://tools/content_editor/ContentEditorShaderSuite.gd"


func _build_monster_form() -> void:
	super._build_monster_form()
	_add_subsection_title("Ground Shadow")
	var shadow := _record_dictionary(current_record, "shadow")
	var shadow_offset := _dictionary_vector(shadow, "offset", Vector2(0.0, 12.0))
	var shadow_scale := _dictionary_vector(shadow, "scale", Vector2(0.9, 0.34))
	_add_check_box("Shadow Enabled", "content_shadow_enabled", bool(shadow.get("enabled", true)))
	_add_float_spin_box("Shadow Opacity", "content_shadow_opacity", float(shadow.get("opacity", 0.42)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Shadow Offset X", "content_shadow_offset_x", shadow_offset.x, -512.0, 512.0, 0.5)
	_add_float_spin_box("Shadow Offset Y", "content_shadow_offset_y", shadow_offset.y, -512.0, 512.0, 0.5)
	_add_float_spin_box("Shadow Scale X", "content_shadow_scale_x", shadow_scale.x, 0.01, 16.0, 0.01)
	_add_float_spin_box("Shadow Scale Y", "content_shadow_scale_y", shadow_scale.y, 0.01, 16.0, 0.01)
	_add_spin_box("Shadow Z Index", "content_shadow_z", int(shadow.get("z_index", 0)), -4096, 4096, 1)
	_add_content_glow_fields(_record_dictionary(current_record, "glow"), "Monster Glow & Real Light", 24)


func _get_monster_form_record() -> Dictionary:
	var record := super._get_monster_form_record()
	record["shadow"] = {
		"enabled": _get_check_box_pressed("content_shadow_enabled"),
		"opacity": _get_spin_box_value("content_shadow_opacity"),
		"offset": {
			"x": _get_spin_box_value("content_shadow_offset_x"),
			"y": _get_spin_box_value("content_shadow_offset_y"),
		},
		"scale": {
			"x": _get_spin_box_value("content_shadow_scale_x"),
			"y": _get_spin_box_value("content_shadow_scale_y"),
		},
		"z_index": _get_spin_box_int("content_shadow_z"),
	}
	record["glow"] = _get_content_glow_record()
	return record


func _build_building_form() -> void:
	super._build_building_form()
	_add_content_glow_fields(_record_dictionary(current_record, "glow"), "Natural Glow & Real Light", 24)


func _get_building_form_record() -> Dictionary:
	var record := super._get_building_form_record()
	record["glow"] = _get_content_glow_record()
	return record


func _add_content_glow_fields(glow: Dictionary, heading: String, default_z: int) -> void:
	_add_subsection_title(heading)
	var note := Label.new()
	note.text = "The additive aura is drawn above the sprite. PointLight2D brightens the map, player and nearby objects. Day/Night multipliers control how much light survives the world tint."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	var offset := _dictionary_vector(glow, "offset", Vector2.ZERO)
	var stretch := _dictionary_vector(glow, "stretch", Vector2.ONE)
	_add_check_box("Glow Enabled", "content_glow_enabled", bool(glow.get("enabled", false)))
	_add_check_box("Visual Aura Enabled", "content_glow_visual_enabled", bool(glow.get("visual_enabled", true)))
	_add_string_option_button("Visual Mode", "content_glow_visual_mode", ["texture", "procedural", "both"], str(glow.get("visual_mode", "texture")))
	_add_string_option_button("Overlay Blend", "content_glow_blend_mode", ["additive", "mix"], str(glow.get("blend_mode", "additive")))
	_add_content_color_picker("Glow Color", "content_glow_color", _color_from_value(glow.get("color", "#FFFFFF"), Color.WHITE))
	_add_float_spin_box("Aura Intensity", "content_glow_intensity", float(glow.get("intensity", 1.0)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Aura Alpha", "content_glow_alpha", float(glow.get("alpha", 0.75)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Aura Scale", "content_glow_scale", float(glow.get("scale", 1.0)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Stretch X", "content_glow_stretch_x", stretch.x, 0.01, 8.0, 0.01)
	_add_float_spin_box("Stretch Y", "content_glow_stretch_y", stretch.y, 0.01, 8.0, 0.01)
	_add_float_spin_box("Glow Offset X", "content_glow_offset_x", offset.x, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Glow Offset Y", "content_glow_offset_y", offset.y, -1024.0, 1024.0, 0.5)
	_add_check_box("Flicker Enabled", "content_glow_flicker_enabled", bool(glow.get("flicker_enabled", false)))
	_add_float_spin_box("Flicker Amount", "content_glow_flicker_amount", float(glow.get("flicker_amount", 0.08)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Flicker Speed", "content_glow_flicker_speed", float(glow.get("flicker_speed", 2.0)), 0.05, 12.0, 0.05)
	_add_spin_box("Overlay Z Index", "content_glow_overlay_z", int(glow.get("overlay_z", default_z)), -4096, 4096, 1)
	_add_check_box("Real Light Enabled", "content_glow_light_enabled", bool(glow.get("light_enabled", true)))
	_add_float_spin_box("Light Energy", "content_glow_light_energy", float(glow.get("light_energy", 0.8)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Radius Scale", "content_glow_light_scale", float(glow.get("light_scale", 1.5)), 0.05, 8.0, 0.05)
	_add_float_spin_box("Day Light Multiplier", "content_glow_day_multiplier", float(glow.get("day_multiplier", 0.18)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Night Light Multiplier", "content_glow_night_multiplier", float(glow.get("night_multiplier", 1.0)), 0.0, 4.0, 0.01)


func _get_content_glow_record() -> Dictionary:
	return {
		"enabled": _get_check_box_pressed("content_glow_enabled"),
		"visual_enabled": _get_check_box_pressed("content_glow_visual_enabled"),
		"visual_mode": _get_option_button_metadata("content_glow_visual_mode"),
		"blend_mode": _get_option_button_metadata("content_glow_blend_mode"),
		"color": _get_content_color_html("content_glow_color"),
		"intensity": _get_spin_box_value("content_glow_intensity"),
		"alpha": _get_spin_box_value("content_glow_alpha"),
		"scale": _get_spin_box_value("content_glow_scale"),
		"stretch": {
			"x": _get_spin_box_value("content_glow_stretch_x"),
			"y": _get_spin_box_value("content_glow_stretch_y"),
		},
		"offset": {
			"x": _get_spin_box_value("content_glow_offset_x"),
			"y": _get_spin_box_value("content_glow_offset_y"),
		},
		"flicker_enabled": _get_check_box_pressed("content_glow_flicker_enabled"),
		"flicker_amount": _get_spin_box_value("content_glow_flicker_amount"),
		"flicker_speed": _get_spin_box_value("content_glow_flicker_speed"),
		"overlay_z": _get_spin_box_int("content_glow_overlay_z"),
		"light_enabled": _get_check_box_pressed("content_glow_light_enabled"),
		"light_energy": _get_spin_box_value("content_glow_light_energy"),
		"light_scale": _get_spin_box_value("content_glow_light_scale"),
		"day_multiplier": _get_spin_box_value("content_glow_day_multiplier"),
		"night_multiplier": _get_spin_box_value("content_glow_night_multiplier"),
	}


func _add_content_color_picker(label_text: String, field_name: String, value: Color) -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.color = value
	picker.edit_alpha = true
	picker.custom_minimum_size = Vector2(120, 32)
	picker.color_changed.connect(func(_new_color: Color) -> void: _mark_dirty())
	_add_form_row(label_text, picker)
	field_controls[field_name] = picker
	return picker


func _get_content_color_html(field_name: String) -> String:
	if not field_controls.has(field_name) or not field_controls[field_name] is ColorPickerButton:
		return "#FFFFFFFF"
	return "#%s" % (field_controls[field_name] as ColorPickerButton).color.to_html(true)


func _record_dictionary(record: Dictionary, key: String) -> Dictionary:
	var value: Variant = record.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _dictionary_vector(record: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var value: Variant = record.get(key, {})
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)
