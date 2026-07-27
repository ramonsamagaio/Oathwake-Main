extends "res://tools/content_editor/ContentEditorLightingSuite.gd"

# World Occlusion, Shared World Wind and Biome Ambient Particles are now
# exposed in the independent Post Effects sidebar tab.


func _build_monster_form() -> void:
	super._build_monster_form()
	# Keep legacy per-monster shadow data compatible, but hide its scattered
	# controls. Projection shape and intensity now live in World Shadows.
	for field_name in [
		"content_shadow_enabled",
		"content_shadow_opacity",
		"content_shadow_offset_x",
		"content_shadow_offset_y",
		"content_shadow_scale_x",
		"content_shadow_scale_y",
		"content_shadow_z",
	]:
		var control: Variant = field_controls.get(field_name)
		if control is Control and (control as Control).get_parent() is Control:
			((control as Control).get_parent() as Control).visible = false
	for child in form_container.get_children():
		if child is Label and (child as Label).text == "Ground Shadow":
			(child as Label).visible = false


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Player Visual Calibration")
	var note := Label.new()
	note.text = "These values affect only the player artwork. Collision, movement speed and world position stay unchanged. Depth uses the player's ground line. Global projected shadows now live in the separate World Shadows tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_float_spin_box("Visual Scale", "player_visual_scale", float(current_record.get("visual_scale", 1.0)), 0.10, 8.0, 0.05)
	_add_float_spin_box("Visual Offset X", "player_visual_offset_x", float(current_record.get("visual_offset_x", 0.0)), -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Visual Offset Y", "player_visual_offset_y", float(current_record.get("visual_offset_y", 0.0)), -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Depth Sort Offset Y", "player_depth_sort_offset_y", float(current_record.get("depth_sort_offset_y", 0.0)), -512.0, 512.0, 0.5)

	var light := _record_dictionary(current_record, "light")
	var light_offset := _dictionary_vector(light, "offset", Vector2(0.0, 6.0))
	_add_subsection_title("Player Light")
	var light_note := Label.new()
	light_note.text = "Small light around the active player. Aura controls the visible circle; Emission and Radius control the real PointLight2D."
	light_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(light_note)
	_add_check_box("Player Light Enabled", "player_light_enabled", bool(light.get("enabled", true)))
	_add_check_box("Visible Aura Enabled", "player_light_visual_aura", bool(light.get("visual_aura_enabled", true)))
	_add_content_color_picker("Light Color", "player_light_color", _color_from_value(light.get("color", "#AFCBFFFF"), Color(0.69, 0.80, 1.0, 1.0)))
	_add_float_spin_box("Aura Intensity", "player_light_aura_intensity", float(light.get("aura_intensity", 0.75)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Aura Alpha", "player_light_aura_alpha", float(light.get("aura_alpha", 0.30)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Aura Size", "player_light_aura_scale", float(light.get("aura_scale", 0.44)), 0.01, 8.0, 0.01)
	_add_float_spin_box("Aura Blur / Softness", "player_light_blur", float(light.get("blur", 1.25)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Emission", "player_light_emission", float(light.get("emission", 0.85)), 0.0, 8.0, 0.05)
	_add_float_spin_box("Light Radius", "player_light_radius", float(light.get("radius_scale", 1.20)), 0.05, 8.0, 0.05)
	_add_float_spin_box("Day Multiplier", "player_light_day", float(light.get("day_multiplier", 0.0)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Night Multiplier", "player_light_night", float(light.get("night_multiplier", 1.0)), 0.0, 4.0, 0.01)
	_add_float_spin_box("Light Offset X", "player_light_offset_x", light_offset.x, -512.0, 512.0, 0.5)
	_add_float_spin_box("Light Offset Y", "player_light_offset_y", light_offset.y, -512.0, 512.0, 0.5)


func _get_player_tuning_form_record() -> Dictionary:
	if current_section == "camera_display":
		return _get_camera_display_form_record()
	var record := current_record.duplicate(true)
	var base_record := super._get_player_tuning_form_record()
	for key in base_record.keys():
		record[key] = base_record[key]
	record["visual_scale"] = _get_spin_box_value("player_visual_scale")
	record["visual_offset_x"] = _get_spin_box_value("player_visual_offset_x")
	record["visual_offset_y"] = _get_spin_box_value("player_visual_offset_y")
	record["depth_sort_offset_y"] = _get_spin_box_value("player_depth_sort_offset_y")
	record["light"] = {
		"enabled": _get_check_box_pressed("player_light_enabled"),
		"visual_aura_enabled": _get_check_box_pressed("player_light_visual_aura"),
		"color": _get_content_color_html("player_light_color"),
		"aura_intensity": _get_spin_box_value("player_light_aura_intensity"),
		"aura_alpha": _get_spin_box_value("player_light_aura_alpha"),
		"aura_scale": _get_spin_box_value("player_light_aura_scale"),
		"blur": _get_spin_box_value("player_light_blur"),
		"emission": _get_spin_box_value("player_light_emission"),
		"radius_scale": _get_spin_box_value("player_light_radius"),
		"day_multiplier": _get_spin_box_value("player_light_day"),
		"night_multiplier": _get_spin_box_value("player_light_night"),
		"offset": {
			"x": _get_spin_box_value("player_light_offset_x"),
			"y": _get_spin_box_value("player_light_offset_y"),
		},
	}
	return record


func _build_character_form() -> void:
	super._build_character_form()
	_add_subsection_title("Attack Animation Variation")
	var note := Label.new()
	note.text = "Comma-separated animation names. Use {direction} to resolve the current facing direction, for example attack_{direction}. A shuffle bag cycles compatible animations without immediate repetition."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_line_edit("Attack Animation Variants", "character_attack_variants", _join_string_array(current_record.get("attack_animation_variants", []), ", "))
	_add_check_box("Avoid Immediate Repeat", "character_avoid_attack_repeat", bool(current_record.get("avoid_immediate_attack_repeat", true)))


func _get_character_form_record() -> Dictionary:
	var record := super._get_character_form_record()
	record["attack_animation_variants"] = _split_string_list(_get_line_edit_text("character_attack_variants"))
	record["avoid_immediate_attack_repeat"] = _get_check_box_pressed("character_avoid_attack_repeat")
	return record


func _build_resource_form() -> void:
	super._build_resource_form()
	var depth := _record_dictionary(current_record, "depth_sort")
	_add_subsection_title("World Depth Line")
	var depth_note := Label.new()
	depth_note.text = "The player changes from behind to in front when the player's feet cross this vertical ratio inside the resource sprite. 0.50 is the exact middle; 0.58 is slightly below it."
	depth_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(depth_note)
	_add_float_spin_box("Depth Line Ratio", "resource_depth_line_ratio", float(depth.get("line_ratio", 0.58)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Depth Offset Y", "resource_depth_offset_y", float(depth.get("offset_y", 0.0)), -512.0, 512.0, 0.5)

	var layered := _record_dictionary(current_record, "layered_visual")
	_add_subsection_title("Layered Tree Backend")
	var layered_note := Label.new()
	layered_note.text = "Prepared backend only. Nothing changes in the current map until Layered Visual Enabled is saved for a resource. Trunk stays rigid; canopy can receive wind independently."
	layered_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(layered_note)
	_add_check_box("Layered Visual Enabled", "resource_layered_enabled", bool(layered.get("enabled", false)))
	_add_line_edit("Trunk Sprite ID", "resource_layered_trunk_sprite_id", str(layered.get("trunk_sprite_id", "")))
	_add_line_edit("Canopy Sprite ID", "resource_layered_canopy_sprite_id", str(layered.get("canopy_sprite_id", "")))
	var trunk_offset := _dictionary_vector(layered, "trunk_offset", Vector2.ZERO)
	var canopy_offset := _dictionary_vector(layered, "canopy_offset", Vector2.ZERO)
	_add_float_spin_box("Trunk Offset X", "resource_layered_trunk_offset_x", trunk_offset.x, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Trunk Offset Y", "resource_layered_trunk_offset_y", trunk_offset.y, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Canopy Offset X", "resource_layered_canopy_offset_x", canopy_offset.x, -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Canopy Offset Y", "resource_layered_canopy_offset_y", canopy_offset.y, -1024.0, 1024.0, 0.5)
	_add_spin_box("Canopy Z Offset", "resource_layered_canopy_z", int(layered.get("canopy_z_offset", 2)), -64, 64, 1)
	_add_check_box("Canopy Wind Enabled", "resource_layered_canopy_wind", bool(layered.get("canopy_wind_enabled", true)))


func _get_resource_form_record() -> Dictionary:
	var record := super._get_resource_form_record()
	record["depth_sort"] = {
		"line_ratio": _get_spin_box_value("resource_depth_line_ratio"),
		"offset_y": _get_spin_box_value("resource_depth_offset_y"),
	}
	record["layered_visual"] = {
		"enabled": _get_check_box_pressed("resource_layered_enabled"),
		"trunk_sprite_id": _get_line_edit_text("resource_layered_trunk_sprite_id"),
		"canopy_sprite_id": _get_line_edit_text("resource_layered_canopy_sprite_id"),
		"trunk_offset": {
			"x": _get_spin_box_value("resource_layered_trunk_offset_x"),
			"y": _get_spin_box_value("resource_layered_trunk_offset_y"),
		},
		"canopy_offset": {
			"x": _get_spin_box_value("resource_layered_canopy_offset_x"),
			"y": _get_spin_box_value("resource_layered_canopy_offset_y"),
		},
		"canopy_z_offset": _get_spin_box_int("resource_layered_canopy_z"),
		"canopy_wind_enabled": _get_check_box_pressed("resource_layered_canopy_wind"),
	}
	return record
