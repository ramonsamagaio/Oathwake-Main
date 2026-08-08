extends "res://tools/content_editor/ContentEditorAlabasterPlayerSuite.gd"

# Single authoritative owner for Player Tuning -> character_id.
# Older editor suites still create legacy character OptionButtons. They are kept
# alive but hidden so ancestral getters never hold freed references. The exact
# selector synchronizes every legacy picker before any super save/getter runs.

const EXACT_PLAYER_TUNING_SECTION := "player_tuning"
const EXACT_CHARACTERS_SECTION := "characters"
const EXACT_SELECTOR_NAME := "ActivePlayerCharacterSelector"
const LEGACY_CHARACTER_FIELDS := ["active_character_id", "character_id"]

var _pending_player_character_id := ""
var _exact_player_character_option: OptionButton = null


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_pending_player_character_id = str(current_record.get("character_id", "juno_alabaster")).strip_edges()
	_hide_all_character_picker_candidates()
	_hide_legacy_character_picker_labels()
	_build_exact_player_character_picker()
	_sync_legacy_character_controls(_pending_player_character_id)


func _hide_all_character_picker_candidates() -> void:
	var valid_character_ids := {}
	for character_record in data_store.get_records(ContentEditorData.SECTION_CHARACTERS):
		var character_id := str(character_record.get("id", "")).strip_edges()
		if not character_id.is_empty():
			valid_character_ids[character_id] = true

	var rows_to_hide: Array[Node] = []
	_collect_character_picker_rows(form_container, valid_character_ids, rows_to_hide)
	for row in rows_to_hide:
		if row == null or not is_instance_valid(row):
			continue
		if row is CanvasItem:
			(row as CanvasItem).visible = false
		row.set_meta("legacy_character_picker_hidden", true)


func _hide_legacy_character_picker_labels() -> void:
	for child in form_container.get_children():
		if not child is Label:
			continue
		var label := child as Label
		var text := label.text.strip_edges()
		if (
			text == "Player Character"
			or text == "Active Player Character"
			or text.begins_with("Chooses which Characters record drives the player visual")
		):
			label.visible = false
			label.set_meta("legacy_character_picker_hidden", true)


func _collect_character_picker_rows(node: Node, valid_character_ids: Dictionary, rows: Array[Node]) -> void:
	for child in node.get_children():
		if child is OptionButton:
			var option := child as OptionButton
			var matching_ids := 0
			for item_index in range(option.item_count):
				var metadata_id := str(option.get_item_metadata(item_index)).strip_edges()
				if valid_character_ids.has(metadata_id):
					matching_ids += 1
			if matching_ids >= 2:
				var top_row := _top_level_form_row(option)
				if top_row != null and not rows.has(top_row):
					rows.append(top_row)
			continue
		_collect_character_picker_rows(child, valid_character_ids, rows)


func _top_level_form_row(control: Node) -> Node:
	var current := control
	while current != null and current.get_parent() != null and current.get_parent() != form_container:
		current = current.get_parent()
	if current != null and current.get_parent() == form_container:
		return current
	return null


func _build_exact_player_character_picker() -> void:
	var option := OptionButton.new()
	option.name = EXACT_SELECTOR_NAME
	option.tooltip_text = "Authoritative Player Tuning character_id selector."
	var selected_index := 0
	var index := 0
	for character_record in data_store.get_records(ContentEditorData.SECTION_CHARACTERS):
		var character_id := str(character_record.get("id", "")).strip_edges()
		if character_id.is_empty():
			continue
		var display_name := str(character_record.get("display_name", character_id)).strip_edges()
		var runtime_name := str(character_record.get("visual_runtime", "sprite_sheet"))
		var label := "%s  [%s]" % [display_name, character_id]
		if runtime_name == "alabaster":
			label += "  • Bone Rig"
		option.add_item(label)
		option.set_item_metadata(index, character_id)
		if character_id == _pending_player_character_id:
			selected_index = index
		index += 1

	if option.item_count == 0:
		option.add_item("No character records")
		option.set_item_metadata(0, "")
	option.select(clampi(selected_index, 0, option.item_count - 1))
	option.item_selected.connect(_on_exact_player_character_selected)
	_exact_player_character_option = option

	_add_subsection_title("Active Player Character")
	var note := Label.new()
	note.text = "Single authoritative selector. Saving writes this exact value to player_tuning.default.character_id."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_form_row("Character", option)

	print("PLAYER_CHARACTER_SELECTOR_READY node=%s selected=%s items=%d" % [
		option.name,
		_read_exact_player_character_option(),
		option.item_count,
	])


func _on_exact_player_character_selected(index: int) -> void:
	if _exact_player_character_option == null:
		return
	if index < 0 or index >= _exact_player_character_option.item_count:
		return
	var selected_character_id := str(_exact_player_character_option.get_item_metadata(index)).strip_edges()
	if selected_character_id.is_empty():
		return
	_pending_player_character_id = selected_character_id
	current_record["character_id"] = selected_character_id
	_sync_legacy_character_controls(selected_character_id)
	_mark_dirty()
	_set_status("Selected player character: %s (press Save to persist)" % selected_character_id)
	print("PLAYER_CHARACTER_PICK node=%s index=%d id=%s selected_property=%d" % [
		_exact_player_character_option.name,
		index,
		selected_character_id,
		_exact_player_character_option.selected,
	])


func _sync_legacy_character_controls(selected_character_id: String) -> void:
	var clean_id := selected_character_id.strip_edges()
	if clean_id.is_empty():
		return
	for field_name in LEGACY_CHARACTER_FIELDS:
		var control_value: Variant = field_controls.get(field_name)
		if not (control_value is OptionButton):
			continue
		var option := control_value as OptionButton
		if not is_instance_valid(option):
			continue
		for item_index in range(option.item_count):
			if str(option.get_item_metadata(item_index)).strip_edges() == clean_id:
				option.select(item_index)
				break


func _read_exact_player_character_option() -> String:
	if _exact_player_character_option == null or not is_instance_valid(_exact_player_character_option):
		return ""
	var index := _exact_player_character_option.selected
	if index < 0 or index >= _exact_player_character_option.item_count:
		return ""
	return str(_exact_player_character_option.get_item_metadata(index)).strip_edges()


func _get_player_tuning_form_record() -> Dictionary:
	var selected_character_id := _read_exact_player_character_option()
	if selected_character_id.is_empty():
		selected_character_id = _pending_player_character_id.strip_edges()
	if selected_character_id.is_empty():
		selected_character_id = str(current_record.get("character_id", "")).strip_edges()

	_sync_legacy_character_controls(selected_character_id)
	var record := super._get_player_tuning_form_record()
	if not selected_character_id.is_empty():
		record["character_id"] = selected_character_id
	return record


func _save_player_tuning_exact() -> void:
	var selected_character_id := _read_exact_player_character_option()
	if selected_character_id.is_empty():
		selected_character_id = _pending_player_character_id.strip_edges()
	if selected_character_id.is_empty():
		selected_character_id = str(current_record.get("character_id", "")).strip_edges()

	_sync_legacy_character_controls(selected_character_id)

	print("PLAYER_CHARACTER_SAVE_INPUT selector=%s pending=%s record=%s legacy_active=%s legacy_character=%s" % [
		_read_exact_player_character_option(),
		_pending_player_character_id,
		str(current_record.get("character_id", "")),
		_read_legacy_character_control("active_character_id"),
		_read_legacy_character_control("character_id"),
	])

	if selected_character_id.is_empty():
		_set_status("Active Player Character cannot be empty.", true)
		return
	if not data_store.has_record(EXACT_CHARACTERS_SECTION, selected_character_id):
		_set_status("Active Player Character does not exist: %s" % selected_character_id, true)
		return

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


func _read_legacy_character_control(field_name: String) -> String:
	var control_value: Variant = field_controls.get(field_name)
	if not (control_value is OptionButton):
		return "<none>"
	var option := control_value as OptionButton
	if not is_instance_valid(option):
		return "<invalid>"
	if option.selected < 0 or option.selected >= option.item_count:
		return "<unselected>"
	return str(option.get_item_metadata(option.selected)).strip_edges()
