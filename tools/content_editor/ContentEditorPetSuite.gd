extends "res://tools/content_editor/ContentEditorSupplementalMonsterSuite.gd"

const SECTION_PETS := "pets"
const PETS_PATH := "res://data/pet_items.json"
const PET_FUNCTION_ITEM_GATHER := "item_gather"


func _ready() -> void:
	super._ready()
	_merge_pet_records_into_editor()
	_install_pets_sidebar_button()


func _install_pets_sidebar_button() -> void:
	if sidebar_buttons.has(SECTION_PETS):
		return
	var sidebar := get_node_or_null("MarginContainer/MainLayout/Sidebar") as VBoxContainer
	if sidebar == null:
		return
	var button := Button.new()
	button.name = "PetsSectionButton"
	button.text = "Pets"
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_section_button_pressed.bind(SECTION_PETS))
	sidebar.add_child(button)
	sidebar_buttons[SECTION_PETS] = button
	var monster_button := sidebar_buttons.get(ContentEditorData.SECTION_MONSTERS) as Button
	if monster_button != null:
		sidebar.move_child(button, monster_button.get_index() + 1)


func _select_section(section: String, force := false) -> void:
	if section == SECTION_PETS:
		_merge_pet_records_into_editor()
	super._select_section(section, force)
	if section == SECTION_PETS and current_file_label != null:
		current_file_label.text = "File: %s" % PETS_PATH


func _refresh_record_list() -> void:
	if current_section == SECTION_PETS:
		_merge_pet_records_into_editor()
	super._refresh_record_list()


func _load_record(record_id: String) -> void:
	if current_section == SECTION_PETS:
		_merge_pet_records_into_editor()
	super._load_record(record_id)
	if current_section == SECTION_PETS and current_file_label != null:
		current_file_label.text = "File: %s" % PETS_PATH


func _build_form_for_current_record() -> void:
	if current_section != SECTION_PETS:
		super._build_form_for_current_record()
		return
	_clear_form()
	is_building_form = true
	_build_pet_form()
	is_building_form = false


func _build_pet_form() -> void:
	form_title_label.text = "Pet: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "pet_record_id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "pet_display_name", str(current_record.get("display_name", "")))
	_add_text_edit("Description", "pet_description", str(current_record.get("description", "")), 88)
	_add_string_option_button(
		"Function",
		"pet_function",
		[PET_FUNCTION_ITEM_GATHER],
		str(current_record.get("pet_function", PET_FUNCTION_ITEM_GATHER))
	)
	_add_read_only_value("Function Note", "Item Gather follows the player and collects nearby world drops. More pet functions can be added here later.")
	_add_line_edit("Pet Runtime ID", "pet_runtime_id", str(current_record.get("pet_id", "")))
	_add_line_edit("Family", "pet_family", str(current_record.get("pet_family", "butterfly")))
	_add_line_edit("Color / Variant", "pet_color", str(current_record.get("pet_color", "")))
	_add_float_spin_box("Sprite Scale Multiplier", "pet_visual_scale", float(current_record.get("visual_scale", 2.0)), 0.05, 16.0, 0.05)
	_add_float_spin_box("Item Gather Radius", "pet_pickup_radius", float(current_record.get("pet_pickup_radius", 190.0)), 0.0, 2000.0, 1.0)
	_add_line_edit("Sprite Sheet Path", "pet_sprite_path", str(current_record.get("sprite_path", "")))
	_add_spin_box("Frame Width", "pet_frame_width", int(current_record.get("frame_width", 16)), 1, 4096, 1)
	_add_spin_box("Frame Height", "pet_frame_height", int(current_record.get("frame_height", 16)), 1, 4096, 1)
	_add_spin_box("Frame Count", "pet_frame_count", int(current_record.get("frames", 5)), 1, 512, 1)
	_add_float_spin_box("Animation FPS", "pet_fps", float(current_record.get("fps", 10.0)), 0.1, 120.0, 0.1)
	_add_spin_box("Item Stack Size", "pet_stack_size", int(current_record.get("stack_size", 1)), 1, 999999, 1)
	_add_spin_box("Tier", "pet_tier", int(current_record.get("tier", 1)), 1, 99, 1)
	_add_line_edit("Tags", "pet_tags", _join_string_array(current_record.get("tags", []), ", "))


func _on_save_pressed() -> void:
	if current_section != SECTION_PETS:
		super._on_save_pressed()
		return
	_save_current_pet()


func _save_current_pet() -> void:
	if current_record.is_empty():
		_set_status("Select or create a pet before saving.", true)
		return
	var record := current_record.duplicate(true)
	var record_id := data_store.sanitize_id(_get_line_edit_text("pet_record_id"))
	if record_id.is_empty():
		_set_status("Pet ID cannot be empty.", true)
		return
	var display_name := _get_line_edit_text("pet_display_name").strip_edges()
	if display_name.is_empty():
		_set_status("Pet Display Name cannot be empty.", true)
		return
	var sprite_path := _get_line_edit_text("pet_sprite_path").strip_edges()
	if sprite_path.is_empty() or not sprite_path.to_lower().ends_with(".png"):
		_set_status("Pet Sprite Sheet Path must point to a PNG file.", true)
		return

	record["id"] = record_id
	record["display_name"] = display_name
	record["description"] = _get_text_edit_text("pet_description")
	record["pet_function"] = str(_get_option_button_metadata("pet_function"))
	record["pet_behavior"] = "pickup_items"
	record["pet_id"] = _get_line_edit_text("pet_runtime_id").strip_edges()
	record["pet_family"] = _get_line_edit_text("pet_family").strip_edges()
	record["pet_color"] = _get_line_edit_text("pet_color").strip_edges()
	record["visual_scale"] = maxf(_get_spin_box_value("pet_visual_scale"), 0.05)
	record["pet_pickup_radius"] = maxf(_get_spin_box_value("pet_pickup_radius"), 0.0)
	record["sprite_path"] = sprite_path
	record["frame_width"] = maxi(_get_spin_box_int("pet_frame_width"), 1)
	record["frame_height"] = maxi(_get_spin_box_int("pet_frame_height"), 1)
	record["frames"] = maxi(_get_spin_box_int("pet_frame_count"), 1)
	record["fps"] = maxf(_get_spin_box_value("pet_fps"), 0.1)
	record["stack_size"] = maxi(_get_spin_box_int("pet_stack_size"), 1)
	record["tier"] = maxi(_get_spin_box_int("pet_tier"), 1)
	record["item_type"] = "accessory"
	record["equipment_slot"] = "trinket"
	record["sprite_region"] = {
		"x": 0,
		"y": 0,
		"w": int(record["frame_width"]),
		"h": int(record["frame_height"]),
	}
	record["tags"] = _parse_csv(_get_line_edit_text("pet_tags"))

	var records := _load_pet_dictionary()
	if not current_original_id.is_empty() and current_original_id != record_id:
		records.erase(current_original_id)
	var stored := record.duplicate(true)
	stored.erase("id")
	records[record_id] = stored
	var error := _write_pet_dictionary(records)
	if not error.is_empty():
		_set_status(error, true)
		return

	data_store.set_record(SECTION_PETS, current_original_id, record_id, record)
	current_original_id = record_id
	current_id = record_id
	current_record = record.duplicate(true)
	has_unsaved_changes = false
	_reload_content_db()
	_refresh_record_list()
	_load_record(record_id)
	_set_status("Saved %s to %s" % [record_id, PETS_PATH])


func _on_new_pressed() -> void:
	if current_section != SECTION_PETS:
		super._on_new_pressed()
		return
	if has_unsaved_changes:
		_set_status("Save or Revert before creating another pet.", true)
		return
	var record_id := data_store.create_unique_id(SECTION_PETS, "new_pet")
	current_original_id = ""
	current_id = record_id
	current_record = {
		"id": record_id,
		"display_name": "New Pet",
		"description": "",
		"item_type": "accessory",
		"equipment_slot": "trinket",
		"pet_id": record_id,
		"pet_family": "butterfly",
		"pet_color": "",
		"pet_function": PET_FUNCTION_ITEM_GATHER,
		"pet_behavior": "pickup_items",
		"pet_pickup_radius": 190.0,
		"visual_scale": 2.0,
		"sprite_path": "",
		"frame_width": 16,
		"frame_height": 16,
		"frames": 5,
		"fps": 10.0,
		"stack_size": 1,
		"tier": 1,
		"tags": ["pet", "trinket"],
	}
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created an unsaved pet record.")


func _on_delete_pressed() -> void:
	if current_section == SECTION_PETS:
		_set_status("Pet records are equipment-backed definitions and cannot be deleted from this editor yet.", true)
		return
	super._on_delete_pressed()


func _merge_pet_records_into_editor() -> void:
	for raw_id in _load_pet_dictionary().keys():
		var value: Variant = _load_pet_dictionary().get(raw_id)
		if not value is Dictionary:
			continue
		var record := (value as Dictionary).duplicate(true)
		if not record.has("pet_function"):
			record["pet_function"] = PET_FUNCTION_ITEM_GATHER
		if not record.has("visual_scale"):
			record["visual_scale"] = 2.0
		data_store.set_record(SECTION_PETS, "", str(raw_id), record)


func _load_pet_dictionary() -> Dictionary:
	if not FileAccess.file_exists(PETS_PATH):
		return {}
	var file := FileAccess.open(PETS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_pet_dictionary(records: Dictionary) -> String:
	var file := FileAccess.open(PETS_PATH, FileAccess.WRITE)
	if file == null:
		return "Could not write file: %s" % PETS_PATH
	file.store_string(JSON.stringify(records, "\t") + "\n")
	return ""


func _parse_csv(value: String) -> Array:
	var result := []
	for part in value.split(",", false):
		var clean := str(part).strip_edges()
		if not clean.is_empty() and clean not in result:
			result.append(clean)
	return result
