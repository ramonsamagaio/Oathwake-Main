extends "res://tools/content_editor/ContentEditorUsabilitySuite.gd"

const SUPPLEMENTAL_BUTTERFLY_PATH := "res://data/butterfly_monsters.json"
const BUTTERFLY_GROUP_ID := "butterflies"


func _ready() -> void:
	super._ready()
	_merge_supplemental_butterflies_into_editor()


func _refresh_record_list() -> void:
	if current_section == ContentEditorData.SECTION_MONSTERS:
		_merge_supplemental_butterflies_into_editor()
	super._refresh_record_list()


func _load_record(record_id: String) -> void:
	if current_section == ContentEditorData.SECTION_MONSTERS:
		_merge_supplemental_butterflies_into_editor()
	super._load_record(record_id)
	if _is_supplemental_butterfly_id(record_id) and current_file_label != null:
		current_file_label.text = "File: %s" % SUPPLEMENTAL_BUTTERFLY_PATH


func _on_save_pressed() -> void:
	if current_section == ContentEditorData.SECTION_MONSTERS and _is_current_supplemental_butterfly():
		_save_current_supplemental_butterfly()
		return

	var supplemental_records := _load_json_dictionary(SUPPLEMENTAL_BUTTERFLY_PATH)
	_remove_supplemental_butterflies_from_editor(supplemental_records)
	super._on_save_pressed()
	_merge_supplemental_butterflies_into_editor(supplemental_records)
	if current_section == ContentEditorData.SECTION_MONSTERS:
		_refresh_record_list()


func _on_delete_pressed() -> void:
	if current_section == ContentEditorData.SECTION_MONSTERS and _is_current_supplemental_butterfly():
		_set_status("Butterfly fauna records are stored in butterfly_monsters.json and cannot be deleted from the shared monster list.", true)
		return

	var supplemental_records := _load_json_dictionary(SUPPLEMENTAL_BUTTERFLY_PATH)
	_remove_supplemental_butterflies_from_editor(supplemental_records)
	super._on_delete_pressed()
	_merge_supplemental_butterflies_into_editor(supplemental_records)
	if current_section == ContentEditorData.SECTION_MONSTERS:
		_refresh_record_list()


func _on_reload_current_pressed() -> void:
	if current_section == ContentEditorData.SECTION_MONSTERS and _is_current_supplemental_butterfly():
		var reload_id := current_id
		_merge_supplemental_butterflies_into_editor()
		if data_store.has_record(ContentEditorData.SECTION_MONSTERS, reload_id):
			_load_record(reload_id)
			_set_status("Reloaded %s from %s" % [reload_id, SUPPLEMENTAL_BUTTERFLY_PATH])
		return
	super._on_reload_current_pressed()


func _save_current_supplemental_butterfly() -> void:
	var form_record := _get_monster_form_record()
	var record := current_record.duplicate(true)
	for key in form_record.keys():
		record[key] = form_record[key]

	var new_id := data_store.sanitize_id(str(record.get("id", current_id)))
	if new_id.is_empty():
		_set_status("Butterfly monster ID cannot be empty.", true)
		return
	record["id"] = new_id
	record["content_group"] = BUTTERFLY_GROUP_ID

	var validation_record := record.duplicate(true)
	if str(validation_record.get("behavior", "")) == "passive_wanderer":
		validation_record["behavior"] = "passive"
	var validation_error := data_store.validate_monster(new_id, current_original_id, validation_record)
	if not validation_error.is_empty():
		_set_status(validation_error, true)
		return

	var supplemental_records := _load_json_dictionary(SUPPLEMENTAL_BUTTERFLY_PATH)
	if supplemental_records.is_empty() and not FileAccess.file_exists(SUPPLEMENTAL_BUTTERFLY_PATH):
		_set_status("Could not find %s" % SUPPLEMENTAL_BUTTERFLY_PATH, true)
		return

	if not current_original_id.is_empty() and current_original_id != new_id:
		supplemental_records.erase(current_original_id)
	var stored_record := record.duplicate(true)
	stored_record.erase("id")
	supplemental_records[new_id] = stored_record

	var write_error := _write_json_dictionary(SUPPLEMENTAL_BUTTERFLY_PATH, supplemental_records)
	if not write_error.is_empty():
		_set_status(write_error, true)
		return

	data_store.set_record(ContentEditorData.SECTION_MONSTERS, current_original_id, new_id, record)
	current_original_id = new_id
	current_id = new_id
	current_record = record.duplicate(true)
	has_unsaved_changes = false
	_reload_content_db()
	_refresh_record_list()
	_load_record(new_id)
	_set_status("Saved %s to %s" % [new_id, SUPPLEMENTAL_BUTTERFLY_PATH])


func _is_current_supplemental_butterfly() -> bool:
	if _is_supplemental_butterfly_id(current_original_id) or _is_supplemental_butterfly_id(current_id):
		return true
	return str(current_record.get("content_group", "")) == BUTTERFLY_GROUP_ID


func _is_supplemental_butterfly_id(record_id: String) -> bool:
	if record_id.is_empty():
		return false
	return _load_json_dictionary(SUPPLEMENTAL_BUTTERFLY_PATH).has(record_id)


func _merge_supplemental_butterflies_into_editor(records: Dictionary = {}) -> void:
	var supplemental_records := records
	if supplemental_records.is_empty():
		supplemental_records = _load_json_dictionary(SUPPLEMENTAL_BUTTERFLY_PATH)
	for raw_id in supplemental_records.keys():
		var record_id := str(raw_id)
		var value: Variant = supplemental_records[raw_id]
		if not value is Dictionary:
			continue
		var record := (value as Dictionary).duplicate(true)
		record["content_group"] = BUTTERFLY_GROUP_ID
		data_store.set_record(ContentEditorData.SECTION_MONSTERS, "", record_id, record)


func _remove_supplemental_butterflies_from_editor(records: Dictionary) -> void:
	for raw_id in records.keys():
		data_store.delete_record(ContentEditorData.SECTION_MONSTERS, str(raw_id))


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json_dictionary(path: String, data: Dictionary) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write file: %s" % path
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return ""
