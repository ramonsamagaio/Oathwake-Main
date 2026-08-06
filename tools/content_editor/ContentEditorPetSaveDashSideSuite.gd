extends "res://tools/content_editor/ContentEditorButterflyParticleDefaultsSuite.gd"

const PLAYER_DASH_SMOKE_FACING_FIELD := "runtime_player_dash_smoke_facing"
const DASH_SMOKE_FACING_OPTIONS := ["left", "right"]


func _update_action_buttons() -> void:
	super._update_action_buttons()
	if current_section != SECTION_PETS:
		return

	# Pets are stored in the supplemental pet_items.json file and therefore are
	# not part of ContentEditorData.SECTIONS. Explicitly grant the same editing
	# controls as the regular data-backed sections.
	var has_record := not current_record.is_empty()
	new_button.disabled = has_unsaved_changes
	duplicate_button.disabled = has_unsaved_changes or current_original_id.is_empty()
	delete_button.disabled = true
	save_button.disabled = not has_record
	revert_button.disabled = not has_record
	reload_current_button.disabled = not has_record


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_string_option_button(
		"Dash Smoke Facing",
		PLAYER_DASH_SMOKE_FACING_FIELD,
		DASH_SMOKE_FACING_OPTIONS,
		_normalize_dash_smoke_facing(str(current_record.get("dash_smoke_facing", "right")))
	)
	_add_read_only_value(
		"Dash Smoke Facing Note",
		"Choose the fixed horizontal orientation of the authored dash-smoke sprite. It no longer alternates randomly between left and right."
	)


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	if field_controls.has(PLAYER_DASH_SMOKE_FACING_FIELD):
		record["dash_smoke_facing"] = _normalize_dash_smoke_facing(
			str(_get_option_button_metadata(PLAYER_DASH_SMOKE_FACING_FIELD))
		)
	return record


func _normalize_dash_smoke_facing(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	return normalized if normalized in DASH_SMOKE_FACING_OPTIONS else "right"
