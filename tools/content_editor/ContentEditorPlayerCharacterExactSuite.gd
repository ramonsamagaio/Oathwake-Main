extends "res://tools/content_editor/ContentEditorAlabasterPlayerSuite.gd"

# Final ownership layer for Player Tuning -> character_id.
# The selected ID delivered by OptionButton.item_selected(index) is authoritative.
# Never re-read OptionButton.selected during Save: in the runtime editor that
# property can still report the previously selected row while the selection
# event has already fired, which caused every Dummy/Male save to be overwritten
# back to Juno.

const EXACT_PLAYER_CHARACTER_FIELD := "character_id"
const EXACT_PLAYER_TUNING_SECTION := "player_tuning"
const EXACT_CHARACTERS_SECTION := "characters"

var _pending_player_character_id := ""


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_pending_player_character_id = str(current_record.get("character_id", "")).strip_edges()
	var option := field_controls.get(EXACT_PLAYER_CHARACTER_FIELD) as OptionButton
	if option == null:
		return
	option.item_selected.connect(_capture_exact_player_character_selection.bind(option))


func _capture_exact_player_character_selection(index: int, option: OptionButton) -> void:
	if option == null or index < 0 or index >= option.item_count:
		return
	var selected_character_id := str(option.get_item_metadata(index)).strip_edges()
	if selected_character_id.is_empty():
		return
	_pending_player_character_id = selected_character_id
	current_record["character_id"] = selected_character_id
	_mark_dirty()
	_set_status("Selected player character: %s (press Save to persist)" % selected_character_id)
	print("PLAYER_CHARACTER_PICK index=%d id=%s option_property_selected=%d" % [index, selected_character_id, option.selected])


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	var selected_character_id := _pending_player_character_id.strip_edges()
	if selected_character_id.is_empty():
		selected_character_id = str(current_record.get("character_id", "")).strip_edges()
	if not selected_character_id.is_empty():
		record["character_id"] = selected_character_id
	return record


func _save_player_tuning_exact() -> void:
	# IMPORTANT: use only the ID captured from item_selected(index), with the
	# current record as startup fallback. Do not consult OptionButton.selected.
	var selected_character_id := _pending_player_character_id.strip_edges()
	if selected_character_id.is_empty():
		selected_character_id = str(current_record.get("character_id", "")).strip_edges()

	print("PLAYER_CHARACTER_SAVE_INPUT pending=%s record=%s" % [
		_pending_player_character_id,
		str(current_record.get("character_id", "")),
	])

	if selected_character_id.is_empty():
		_set_status("Active Player Character cannot be empty.", true)
		return
	if not data_store.has_record(EXACT_CHARACTERS_SECTION, selected_character_id):
		_set_status("Active Player Character does not exist: %s" % selected_character_id, true)
		return

	# Preserve the complete singleton record and every field edited by lower
	# suites, then overwrite character_id with the event-captured value last.
	var record := current_record.duplicate(true)
	var edited := super._get_player_tuning_form_record()
	for key in edited.keys():
		record[key] = edited[key]
	record["id"] = "default"
	record["character_id"] = selected_character_id

	var validation_error := data_store.validate_player_tuning("default", current_original_id, record)
	if not validation_error.is_empty():
		_set_status(validation_error, true)
		return

	data_store.set_record(EXACT_PLAYER_TUNING_SECTION, "default", "default", record)
	var save_error := data_store.save_section(EXACT_PLAYER_TUNING_SECTION)
	if not save_error.is_empty():
		_set_status(save_error, true)
		return

	var reload_error := data_store.load_section(EXACT_PLAYER_TUNING_SECTION)
	if not reload_error.is_empty():
		_set_status(reload_error, true)
		return

	var persisted := data_store.get_record(EXACT_PLAYER_TUNING_SECTION, "default")
	var persisted_character := str(persisted.get("character_id", "")).strip_edges()
	if persisted_character != selected_character_id:
		_set_status(
			"PLAYER CHARACTER SAVE FAILED: selected=%s persisted=%s" % [selected_character_id, persisted_character],
			true
		)
		push_error("PLAYER_CHARACTER_SAVE_MISMATCH selected=%s persisted=%s" % [selected_character_id, persisted_character])
		return

	_reload_content_db()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("get_player_tuning"):
		var runtime_tuning: Dictionary = content_db.call("get_player_tuning", "default")
		var runtime_character := str(runtime_tuning.get("character_id", "")).strip_edges()
		if runtime_character != selected_character_id:
			_set_status(
				"PLAYER CHARACTER RUNTIME RELOAD FAILED: persisted=%s ContentDB=%s" % [selected_character_id, runtime_character],
				true
			)
			push_error("PLAYER_CHARACTER_CONTENTDB_MISMATCH persisted=%s runtime=%s" % [selected_character_id, runtime_character])
			return

	current_id = "default"
	current_original_id = "default"
	current_record = persisted
	_pending_player_character_id = persisted_character
	has_unsaved_changes = false
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_refresh_live_players()
	_set_status("Saved Player Tuning. Active character: %s" % selected_character_id)
	print("PLAYER_CHARACTER_SAVE_OK selected=%s persisted=%s" % [selected_character_id, persisted_character])
