extends "res://tools/content_editor/ContentEditorShadowOcclusionSuite.gd"

const PLAYER_LIGHT_PERSPECTIVE_FIELD := "player_light_perspective_angle"


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	var light := _record_dictionary(current_record, "light")
	_add_float_spin_box(
		"Light Perspective Angle",
		PLAYER_LIGHT_PERSPECTIVE_FIELD,
		float(light.get("perspective_angle_degrees", 50.0)),
		15.0,
		90.0,
		1.0
	)
	var control: Variant = field_controls.get(PLAYER_LIGHT_PERSPECTIVE_FIELD)
	if control is Control:
		(control as Control).tooltip_text = "Camera elevation used to project the player light onto the ground. 90° is zenith and circular; lower angles make the light elliptical for the game's top-down perspective."


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	var light := _record_dictionary(record, "light")
	light["perspective_angle_degrees"] = (
		_get_spin_box_value(PLAYER_LIGHT_PERSPECTIVE_FIELD)
		if field_controls.has(PLAYER_LIGHT_PERSPECTIVE_FIELD)
		else 50.0
	)
	record["light"] = light
	return record
