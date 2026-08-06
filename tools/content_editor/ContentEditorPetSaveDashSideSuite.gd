extends "res://tools/content_editor/ContentEditorButterflyParticleDefaultsSuite.gd"

const PLAYER_STAMINA_REGEN_FIELD := "runtime_player_stamina_regeneration_per_second"
const FIXED_DASH_STAMINA_COST := 10.0
const DEFAULT_STAMINA_REGEN_PER_SECOND := 30.0


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
	_add_subsection_title("Stamina")
	var note := Label.new()
	note.text = "Every successful dash spends exactly 10 stamina. Regeneration starts automatically whenever the player is not currently dashing."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_read_only_value("Dash Stamina Cost", "10")
	var regen_control := _add_float_spin_box(
		"Stamina Regeneration / Second",
		PLAYER_STAMINA_REGEN_FIELD,
		float(current_record.get("stamina_regeneration_per_second", DEFAULT_STAMINA_REGEN_PER_SECOND)),
		0.0,
		500.0,
		0.5
	)
	regen_control.tooltip_text = "How many stamina points recover automatically per second. At 30, an empty 100-point bar refills in about 3.3 seconds."
	_add_read_only_value(
		"Dash Smoke Direction",
		"Derived from the lateral dash: left dash uses the left-facing sprite and right dash uses the right-facing sprite. Vertical dashes do not use this sheet."
	)


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	if field_controls.has(PLAYER_STAMINA_REGEN_FIELD):
		record["stamina_regeneration_per_second"] = maxf(
			_get_spin_box_value(PLAYER_STAMINA_REGEN_FIELD),
			0.0
		)
	record["max_stamina"] = maxf(float(record.get("max_stamina", 100.0)), 1.0)
	record["dash_stamina_cost"] = FIXED_DASH_STAMINA_COST
	record.erase("dash_smoke_facing")
	return record
