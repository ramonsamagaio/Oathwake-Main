extends "res://tools/content_editor/ContentEditorLightingSuite.gd"


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Player Visual Calibration")
	var note := Label.new()
	note.text = "These values affect only the player artwork. Collision, movement speed and world position stay unchanged. Depth uses the player's ground line, while the shadow is generated procedurally toward southwest."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_float_spin_box("Visual Scale", "player_visual_scale", float(current_record.get("visual_scale", 1.0)), 0.10, 8.0, 0.05)
	_add_float_spin_box("Visual Offset X", "player_visual_offset_x", float(current_record.get("visual_offset_x", 0.0)), -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Visual Offset Y", "player_visual_offset_y", float(current_record.get("visual_offset_y", 0.0)), -1024.0, 1024.0, 0.5)
	_add_float_spin_box("Depth Sort Offset Y", "player_depth_sort_offset_y", float(current_record.get("depth_sort_offset_y", 0.0)), -512.0, 512.0, 0.5)

	var shadow := _record_dictionary(current_record, "shadow")
	_add_subsection_title("Player Directional Shadow")
	_add_check_box("Shadow Enabled", "player_shadow_enabled", bool(shadow.get("enabled", true)))
	_add_float_spin_box("Shadow Opacity", "player_shadow_opacity", float(shadow.get("opacity", 0.30)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Shadow Length", "player_shadow_length", float(shadow.get("length", 34.0)), 1.0, 256.0, 1.0)
	_add_float_spin_box("Shadow Width", "player_shadow_width", float(shadow.get("width", 22.0)), 1.0, 256.0, 1.0)
	_add_float_spin_box("Shadow Offset X", "player_shadow_offset_x", _dictionary_vector(shadow, "offset", Vector2.ZERO).x, -512.0, 512.0, 0.5)
	_add_float_spin_box("Shadow Offset Y", "player_shadow_offset_y", _dictionary_vector(shadow, "offset", Vector2.ZERO).y, -512.0, 512.0, 0.5)
	_add_float_spin_box("Shadow Fade Power", "player_shadow_fade_power", float(shadow.get("fade_power", 1.6)), 0.1, 8.0, 0.1)


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	record["visual_scale"] = _get_spin_box_value("player_visual_scale")
	record["visual_offset_x"] = _get_spin_box_value("player_visual_offset_x")
	record["visual_offset_y"] = _get_spin_box_value("player_visual_offset_y")
	record["depth_sort_offset_y"] = _get_spin_box_value("player_depth_sort_offset_y")
	record["shadow"] = {
		"enabled": _get_check_box_pressed("player_shadow_enabled"),
		"opacity": _get_spin_box_value("player_shadow_opacity"),
		"length": _get_spin_box_value("player_shadow_length"),
		"width": _get_spin_box_value("player_shadow_width"),
		"offset": {
			"x": _get_spin_box_value("player_shadow_offset_x"),
			"y": _get_spin_box_value("player_shadow_offset_y"),
		},
		"fade_power": _get_spin_box_value("player_shadow_fade_power"),
		"tail_width_ratio": 0.18,
		"z_index": -1,
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

	var shadow := _record_dictionary(current_record, "shadow")
	_add_subsection_title("Resource Directional Shadow")
	_add_check_box("Shadow Enabled", "resource_shadow_enabled", bool(shadow.get("enabled", true)))
	_add_float_spin_box("Shadow Opacity", "resource_shadow_opacity", float(shadow.get("opacity", 0.28)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Shadow Length", "resource_shadow_length", float(shadow.get("length", 30.0)), 1.0, 256.0, 1.0)
	_add_float_spin_box("Shadow Width", "resource_shadow_width", float(shadow.get("width", 20.0)), 1.0, 256.0, 1.0)
	_add_float_spin_box("Shadow Fade Power", "resource_shadow_fade_power", float(shadow.get("fade_power", 1.6)), 0.1, 8.0, 0.1)

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
	record["shadow"] = {
		"enabled": _get_check_box_pressed("resource_shadow_enabled"),
		"opacity": _get_spin_box_value("resource_shadow_opacity"),
		"length": _get_spin_box_value("resource_shadow_length"),
		"width": _get_spin_box_value("resource_shadow_width"),
		"fade_power": _get_spin_box_value("resource_shadow_fade_power"),
		"z_index": -1,
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


func _build_vfx_profile_form() -> void:
	super._build_vfx_profile_form()
	if str(current_record.get("id", "default")) != "default":
		return
	var shadow := _record_dictionary(current_record, "directional_shadow")
	var direction := _dictionary_vector(shadow, "direction", Vector2(-1.0, 0.55))
	_add_subsection_title("Global Directional Shadow")
	_add_float_spin_box("Direction X", "global_shadow_direction_x", direction.x, -4.0, 4.0, 0.05)
	_add_float_spin_box("Direction Y", "global_shadow_direction_y", direction.y, -4.0, 4.0, 0.05)
	_add_float_spin_box("Default Opacity", "global_shadow_opacity", float(shadow.get("opacity", 0.32)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Length Scale", "global_shadow_length_scale", float(shadow.get("length_scale", 1.0)), 0.1, 8.0, 0.05)
	_add_float_spin_box("Width Scale", "global_shadow_width_scale", float(shadow.get("width_scale", 1.0)), 0.1, 8.0, 0.05)
	_add_float_spin_box("Fade Power", "global_shadow_fade_power", float(shadow.get("fade_power", 1.6)), 0.1, 8.0, 0.1)
	_add_line_edit("Shadow Color", "global_shadow_color", str(shadow.get("color", "#040306FF")))


func _get_vfx_profile_form_record() -> Dictionary:
	var record := super._get_vfx_profile_form_record()
	if str(record.get("id", "default")) == "default" and field_controls.has("global_shadow_direction_x"):
		record["directional_shadow"] = {
			"direction": {
				"x": _get_spin_box_value("global_shadow_direction_x"),
				"y": _get_spin_box_value("global_shadow_direction_y"),
			},
			"opacity": _get_spin_box_value("global_shadow_opacity"),
			"length_scale": _get_spin_box_value("global_shadow_length_scale"),
			"width_scale": _get_spin_box_value("global_shadow_width_scale"),
			"fade_power": _get_spin_box_value("global_shadow_fade_power"),
			"tail_width_ratio": 0.18,
			"color": _get_line_edit_text("global_shadow_color"),
		}
	return record
