extends "res://tools/content_editor/ContentEditorLightingSuite.gd"


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Player Visual Calibration")
	var note := Label.new()
	note.text = "These values affect only the player artwork. Collision, movement speed and world position stay unchanged. Use Offset Y to keep the feet aligned with the ground shadow after scaling."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_float_spin_box(
		"Visual Scale",
		"player_visual_scale",
		float(current_record.get("visual_scale", 1.0)),
		0.10,
		8.0,
		0.05
	)
	_add_float_spin_box(
		"Visual Offset X",
		"player_visual_offset_x",
		float(current_record.get("visual_offset_x", 0.0)),
		-1024.0,
		1024.0,
		0.5
	)
	_add_float_spin_box(
		"Visual Offset Y",
		"player_visual_offset_y",
		float(current_record.get("visual_offset_y", 0.0)),
		-1024.0,
		1024.0,
		0.5
	)


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	record["visual_scale"] = _get_spin_box_value("player_visual_scale")
	record["visual_offset_x"] = _get_spin_box_value("player_visual_offset_x")
	record["visual_offset_y"] = _get_spin_box_value("player_visual_offset_y")
	return record
