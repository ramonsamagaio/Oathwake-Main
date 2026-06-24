extends Control

const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")

var data_store = ContentEditorData.new()
var current_section: String = ContentEditorData.SECTION_ITEMS
var current_id := ""
var current_original_id := ""
var current_record := {}
var has_unsaved_changes := false
var is_refreshing_list := false
var is_building_form := false
var selected_drop_item_id := ""
var drop_item_filter := ""
var sidebar_buttons := {}
var field_controls := {}

var section_title_label: Label
var search_line_edit: LineEdit
var record_list: ItemList
var new_button: Button
var duplicate_button: Button
var delete_button: Button
var form_title_label: Label
var form_container: VBoxContainer
var save_button: Button
var revert_button: Button
var status_label: Label


func _ready() -> void:
	_build_ui()

	var error := data_store.load_all()
	if not error.is_empty():
		_set_status(error, true)
		return

	_select_section(ContentEditorData.SECTION_ITEMS, true)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin_container := MarginContainer.new()
	margin_container.name = "MarginContainer"
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 12)
	margin_container.add_theme_constant_override("margin_top", 12)
	margin_container.add_theme_constant_override("margin_right", 12)
	margin_container.add_theme_constant_override("margin_bottom", 12)
	add_child(margin_container)

	var main_layout := HBoxContainer.new()
	main_layout.name = "MainLayout"
	main_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_child(main_layout)

	_build_sidebar(main_layout)
	_build_record_panel(main_layout)
	_build_form_panel(main_layout)


func _build_sidebar(parent: Node) -> void:
	var sidebar := VBoxContainer.new()
	sidebar.name = "Sidebar"
	sidebar.custom_minimum_size = Vector2(160, 0)
	parent.add_child(sidebar)

	var title := Label.new()
	title.text = "Content"
	sidebar.add_child(title)

	for section in ContentEditorData.SECTIONS:
		var button := Button.new()
		button.text = data_store.get_section_label(section)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_section_button_pressed.bind(section))
		sidebar.add_child(button)
		sidebar_buttons[section] = button


func _build_record_panel(parent: Node) -> void:
	var panel := VBoxContainer.new()
	panel.name = "RecordPanel"
	panel.custom_minimum_size = Vector2(320, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	section_title_label = Label.new()
	section_title_label.name = "SectionTitleLabel"
	panel.add_child(section_title_label)

	search_line_edit = LineEdit.new()
	search_line_edit.name = "SearchLineEdit"
	search_line_edit.placeholder_text = "Search by id or display name"
	search_line_edit.text_changed.connect(_on_search_text_changed)
	panel.add_child(search_line_edit)

	record_list = ItemList.new()
	record_list.name = "RecordList"
	record_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	record_list.item_selected.connect(_on_record_selected)
	panel.add_child(record_list)

	var action_row := HBoxContainer.new()
	action_row.name = "RecordActions"
	panel.add_child(action_row)

	new_button = Button.new()
	new_button.name = "NewButton"
	new_button.text = "New"
	new_button.pressed.connect(_on_new_pressed)
	action_row.add_child(new_button)

	duplicate_button = Button.new()
	duplicate_button.name = "DuplicateButton"
	duplicate_button.text = "Duplicate"
	duplicate_button.pressed.connect(_on_duplicate_pressed)
	action_row.add_child(duplicate_button)

	delete_button = Button.new()
	delete_button.name = "DeleteButton"
	delete_button.text = "Delete"
	delete_button.pressed.connect(_on_delete_pressed)
	action_row.add_child(delete_button)


func _build_form_panel(parent: Node) -> void:
	var panel := VBoxContainer.new()
	panel.name = "FormPanel"
	panel.custom_minimum_size = Vector2(430, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	form_title_label = Label.new()
	form_title_label.name = "FormTitleLabel"
	panel.add_child(form_title_label)

	var scroll_container := ScrollContainer.new()
	scroll_container.name = "FormScroll"
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll_container)

	form_container = VBoxContainer.new()
	form_container.name = "FormContainer"
	form_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(form_container)

	var form_action_row := HBoxContainer.new()
	form_action_row.name = "FormActions"
	panel.add_child(form_action_row)

	save_button = Button.new()
	save_button.name = "SaveButton"
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	form_action_row.add_child(save_button)

	revert_button = Button.new()
	revert_button.name = "RevertButton"
	revert_button.text = "Revert"
	revert_button.pressed.connect(_on_revert_pressed)
	form_action_row.add_child(revert_button)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Ready"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status_label)


func _on_section_button_pressed(section: String) -> void:
	_select_section(section)


func _select_section(section: String, force := false) -> void:
	if not force and has_unsaved_changes:
		_set_status("Save or Revert before changing section.", true)
		_sync_sidebar_buttons()
		return

	current_section = section
	current_id = ""
	current_original_id = ""
	current_record = {}
	has_unsaved_changes = false
	selected_drop_item_id = ""
	drop_item_filter = ""

	is_refreshing_list = true
	search_line_edit.text = ""
	is_refreshing_list = false

	section_title_label.text = data_store.get_section_label(current_section)
	_sync_sidebar_buttons()
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Selected %s" % data_store.get_section_label(current_section))


func _sync_sidebar_buttons() -> void:
	for section in sidebar_buttons.keys():
		var button: Button = sidebar_buttons[section]
		button.button_pressed = section == current_section


func _on_search_text_changed(_new_text: String) -> void:
	if is_refreshing_list:
		return

	_refresh_record_list()


func _refresh_record_list() -> void:
	is_refreshing_list = true
	record_list.clear()

	var query := search_line_edit.text.strip_edges().to_lower()
	for record in data_store.get_records(current_section):
		if _record_matches_search(record, query):
			_add_record_list_item(record)

	if current_original_id.is_empty() and not current_record.is_empty():
		_add_record_list_item(current_record, "[new] ")

	_select_current_record_in_list()
	is_refreshing_list = false


func _record_matches_search(record: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true

	var record_id := str(record.get("id", "")).to_lower()
	var display_name := str(record.get("display_name", "")).to_lower()
	return record_id.contains(query) or display_name.contains(query)


func _add_record_list_item(record: Dictionary, prefix := "") -> void:
	var record_id := str(record.get("id", ""))
	var display_name := str(record.get("display_name", ""))
	var label := record_id
	if not display_name.is_empty():
		label = "%s - %s" % [record_id, display_name]

	var index := record_list.item_count
	record_list.add_item(prefix + label)
	record_list.set_item_metadata(index, record_id)


func _select_current_record_in_list() -> void:
	record_list.deselect_all()
	if current_id.is_empty():
		return

	for index in range(record_list.item_count):
		if str(record_list.get_item_metadata(index)) == current_id:
			record_list.select(index)
			return


func _on_record_selected(index: int) -> void:
	if is_refreshing_list:
		return

	var selected_id := str(record_list.get_item_metadata(index))
	if has_unsaved_changes and selected_id != current_id:
		_set_status("Save or Revert before changing record.", true)
		_select_current_record_in_list()
		return

	_load_record(selected_id)


func _load_record(record_id: String) -> void:
	current_original_id = record_id
	current_id = record_id
	current_record = data_store.get_record(current_section, record_id)
	has_unsaved_changes = false
	selected_drop_item_id = str(current_record.get("drop_item_id", ""))
	drop_item_filter = ""

	_build_form_for_current_record()
	_update_action_buttons()
	_set_status("Loaded %s" % record_id)


func _show_empty_form() -> void:
	_clear_form()
	form_title_label.text = "Select a record"
	var note := Label.new()
	note.text = "Choose a record from the list or create a new one."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)


func _build_form_for_current_record() -> void:
	_clear_form()
	is_building_form = true

	match current_section:
		ContentEditorData.SECTION_ITEMS:
			_build_item_form()
		ContentEditorData.SECTION_RESOURCES:
			_build_resource_form()
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_build_terrain_type_form()
		_:
			_build_read_only_preview_form()

	is_building_form = false


func _clear_form() -> void:
	field_controls.clear()
	for child in form_container.get_children():
		child.queue_free()


func _build_item_form() -> void:
	form_title_label.text = "Item: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_spin_box("Stack Size", "stack_size", int(current_record.get("stack_size", 999)), 1, 999999, 1)
	_add_text_edit("Description", "description", str(current_record.get("description", "")), 100)


func _build_resource_form() -> void:
	form_title_label.text = "Resource: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_spin_box("Max Health", "max_health", int(current_record.get("max_health", 20)), 1, 999999, 1)
	_add_drop_item_picker(str(current_record.get("drop_item_id", "wood")))
	_add_spin_box("Drop Amount", "drop_amount", int(current_record.get("drop_amount", 1)), 1, 999999, 1)
	_add_spin_box("Respawn Time Seconds", "respawn_time_seconds", int(current_record.get("respawn_time_seconds", 60)), 0, 999999, 1)


func _build_terrain_type_form() -> void:
	form_title_label.text = "Terrain Type: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_check_box("Walkable", "walkable", bool(current_record.get("walkable", true)))
	_add_check_box("Allows Monster Spawn", "allows_monster_spawn", bool(current_record.get("allows_monster_spawn", true)))
	_add_check_box("Allows Resource Spawn", "allows_resource_spawn", bool(current_record.get("allows_resource_spawn", true)))


func _build_read_only_preview_form() -> void:
	var label := data_store.get_section_label(current_section)
	form_title_label.text = "%s: %s" % [label.trim_suffix("s"), str(current_record.get("id", ""))]

	var note := Label.new()
	note.text = "Visual editing for this section is prepared in the navigation, but the detailed form will come in a later step."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)

	for key in current_record.keys():
		_add_read_only_value(str(key).capitalize(), _stringify_value(current_record[key]))


func _add_line_edit(label_text: String, field_name: String, value: String) -> LineEdit:
	var line_edit := LineEdit.new()
	line_edit.text = value
	line_edit.text_changed.connect(func(_new_text: String) -> void: _mark_dirty())
	_add_form_row(label_text, line_edit)
	field_controls[field_name] = line_edit
	return line_edit


func _add_spin_box(label_text: String, field_name: String, value: int, minimum: int, maximum: int, step: int) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.min_value = minimum
	spin_box.max_value = maximum
	spin_box.step = step
	spin_box.value = value
	spin_box.value_changed.connect(func(_new_value: float) -> void: _mark_dirty())
	_add_form_row(label_text, spin_box)
	field_controls[field_name] = spin_box
	return spin_box


func _add_text_edit(label_text: String, field_name: String, value: String, height: int) -> TextEdit:
	var text_edit := TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, height)
	text_edit.text = value
	text_edit.text_changed.connect(_mark_dirty)
	_add_form_row(label_text, text_edit)
	field_controls[field_name] = text_edit
	return text_edit


func _add_check_box(label_text: String, field_name: String, value: bool) -> CheckBox:
	var check_box := CheckBox.new()
	check_box.button_pressed = value
	check_box.toggled.connect(func(_is_pressed: bool) -> void: _mark_dirty())
	_add_form_row(label_text, check_box)
	field_controls[field_name] = check_box
	return check_box


func _add_drop_item_picker(initial_item_id: String) -> void:
	selected_drop_item_id = initial_item_id

	var search := LineEdit.new()
	search.placeholder_text = "Search item by id or display name"
	search.text = drop_item_filter
	search.text_changed.connect(_on_drop_item_filter_changed)
	_add_form_row("Drop Item Search", search)
	field_controls["drop_item_search"] = search

	var option_button := OptionButton.new()
	option_button.item_selected.connect(_on_drop_item_selected)
	_add_form_row("Drop Item", option_button)
	field_controls["drop_item_id"] = option_button
	_refresh_drop_item_options()


func _add_form_row(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	form_container.add_child(row)


func _add_read_only_value(label_text: String, value: String) -> void:
	var label := Label.new()
	label.text = "%s: %s" % [label_text, value]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(label)


func _on_drop_item_filter_changed(new_text: String) -> void:
	drop_item_filter = new_text
	_refresh_drop_item_options()


func _refresh_drop_item_options() -> void:
	if not field_controls.has("drop_item_id"):
		return

	var option_button: OptionButton = field_controls["drop_item_id"]
	option_button.clear()

	var query := drop_item_filter.strip_edges().to_lower()
	var selected_index := -1
	var selected_record := {}

	for item_record in data_store.get_records(ContentEditorData.SECTION_ITEMS):
		var item_id := str(item_record.get("id", ""))
		if item_id == selected_drop_item_id:
			selected_record = item_record
			break

	if not selected_record.is_empty() and not _record_matches_search(selected_record, query):
		_add_drop_item_option(option_button, selected_record)
		selected_index = 0

	for item_record in data_store.get_records(ContentEditorData.SECTION_ITEMS):
		if not _record_matches_search(item_record, query):
			continue

		var item_id := str(item_record.get("id", ""))
		if item_id == selected_drop_item_id and selected_index == -1:
			selected_index = option_button.item_count

		_add_drop_item_option(option_button, item_record)

	if selected_index >= 0:
		option_button.select(selected_index)


func _add_drop_item_option(option_button: OptionButton, item_record: Dictionary) -> void:
	var item_id := str(item_record.get("id", ""))
	var display_name := str(item_record.get("display_name", ""))
	var label := item_id
	if not display_name.is_empty():
		label = "%s - %s" % [item_id, display_name]

	var index := option_button.item_count
	option_button.add_item(label)
	option_button.set_item_metadata(index, item_id)


func _on_drop_item_selected(index: int) -> void:
	if not field_controls.has("drop_item_id"):
		return

	var option_button: OptionButton = field_controls["drop_item_id"]
	selected_drop_item_id = str(option_button.get_item_metadata(index))
	_mark_dirty()


func _on_new_pressed() -> void:
	if has_unsaved_changes:
		_set_status("Save or Revert before creating a new record.", true)
		return

	match current_section:
		ContentEditorData.SECTION_ITEMS:
			_create_new_item()
		ContentEditorData.SECTION_RESOURCES:
			_create_new_resource()
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_create_new_terrain_type()
		_:
			_set_status("New is available for Items, Resources, and Terrain Types in this step.", true)


func _create_new_item() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_ITEMS, "new_item")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Item",
		"stack_size": 999,
		"description": "",
	}
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved item.")


func _create_new_resource() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_RESOURCES, "new_resource")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Resource",
		"max_health": 20,
		"drop_item_id": _get_default_item_id(),
		"drop_amount": 1,
		"respawn_time_seconds": 60,
	}
	selected_drop_item_id = str(current_record.get("drop_item_id", ""))
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved resource.")


func _create_new_terrain_type() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_TERRAIN_TYPES, "new_terrain")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Terrain",
		"walkable": true,
		"allows_monster_spawn": true,
		"allows_resource_spawn": true,
	}
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved terrain type.")


func _on_duplicate_pressed() -> void:
	if has_unsaved_changes:
		_set_status("Save or Revert before duplicating a record.", true)
		return

	if current_original_id.is_empty():
		_set_status("Select a record to duplicate.", true)
		return

	match current_section:
		ContentEditorData.SECTION_ITEMS:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_RESOURCES:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_duplicate_current_record("_copy")
		_:
			_set_status("Duplicate is available for Items, Resources, and Terrain Types in this step.", true)


func _duplicate_current_record(suffix: String) -> void:
	var source_record := data_store.get_record(current_section, current_original_id)
	if source_record.is_empty():
		_set_status("Could not duplicate missing record.", true)
		return

	var new_id := data_store.create_unique_id(current_section, "%s%s" % [current_original_id, suffix])
	source_record["id"] = new_id
	source_record["display_name"] = "%s Copy" % str(source_record.get("display_name", current_original_id))

	current_id = new_id
	current_original_id = ""
	current_record = source_record
	has_unsaved_changes = true
	selected_drop_item_id = str(current_record.get("drop_item_id", ""))
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Duplicated record. Click Save to write it.")


func _on_delete_pressed() -> void:
	if current_id.is_empty():
		_set_status("Select a record to delete.", true)
		return

	if has_unsaved_changes:
		if current_original_id.is_empty():
			_discard_unsaved_new_record()
			return

		_set_status("Save or Revert before deleting this record.", true)
		return

	match current_section:
		ContentEditorData.SECTION_ITEMS:
			_delete_current_item()
		ContentEditorData.SECTION_RESOURCES:
			_set_status("Resource delete is blocked for now to avoid breaking scene references.", true)
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_delete_current_terrain_type()
		_:
			_set_status("Delete is available for Items and Terrain Types in this step.", true)


func _delete_current_item() -> void:
	var usages := data_store.find_item_usage(current_original_id)
	if not usages.is_empty():
		_set_status("Cannot delete item. It is used by: %s" % _join_strings(usages, ", "), true)
		return

	data_store.delete_record(current_section, current_original_id)
	var error := data_store.save_section(current_section)
	if not error.is_empty():
		_set_status(error, true)
		return

	_reload_content_db()
	current_id = ""
	current_original_id = ""
	current_record = {}
	has_unsaved_changes = false
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Deleted item.")


func _delete_current_terrain_type() -> void:
	var usages := data_store.find_terrain_type_usage(current_original_id)
	if not usages.is_empty():
		_set_status("Cannot delete terrain type. It is used by: %s" % _join_strings(usages, ", "), true)
		return

	data_store.delete_record(current_section, current_original_id)
	var error := data_store.save_section(current_section)
	if not error.is_empty():
		_set_status(error, true)
		return

	_reload_content_db()
	current_id = ""
	current_original_id = ""
	current_record = {}
	has_unsaved_changes = false
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Deleted terrain type.")


func _on_save_pressed() -> void:
	if current_record.is_empty():
		_set_status("Select or create a record before saving.", true)
		return

	match current_section:
		ContentEditorData.SECTION_ITEMS:
			_save_item()
		ContentEditorData.SECTION_RESOURCES:
			_save_resource()
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_save_terrain_type()
		_:
			_set_status("Visual saving for this section will come in a later step.", true)


func _save_item() -> void:
	var record := _get_item_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_item(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_resource() -> void:
	var record := _get_resource_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_resource(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_terrain_type() -> void:
	var record := _get_terrain_type_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_terrain_type(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_current_record(record_id: String, record: Dictionary) -> void:
	data_store.set_record(current_section, current_original_id, record_id, record)

	var error := data_store.save_section(current_section)
	if not error.is_empty():
		_set_status(error, true)
		return

	_reload_content_db()
	current_id = record_id
	current_original_id = record_id
	current_record = data_store.get_record(current_section, record_id)
	has_unsaved_changes = false
	selected_drop_item_id = str(current_record.get("drop_item_id", ""))
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Saved %s." % record_id)


func _on_revert_pressed() -> void:
	if current_record.is_empty():
		return

	if current_original_id.is_empty():
		_discard_unsaved_new_record()
		return

	var error := data_store.load_all()
	if not error.is_empty():
		_set_status(error, true)
		return

	current_id = current_original_id
	current_record = data_store.get_record(current_section, current_original_id)
	has_unsaved_changes = false
	selected_drop_item_id = str(current_record.get("drop_item_id", ""))
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Reverted %s." % current_id)


func _discard_unsaved_new_record() -> void:
	current_id = ""
	current_original_id = ""
	current_record = {}
	has_unsaved_changes = false
	selected_drop_item_id = ""
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Discarded unsaved record.")


func _get_item_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"stack_size": _get_spin_box_int("stack_size"),
		"description": _get_text_edit_text("description"),
	}


func _get_resource_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"max_health": _get_spin_box_int("max_health"),
		"drop_item_id": selected_drop_item_id,
		"drop_amount": _get_spin_box_int("drop_amount"),
		"respawn_time_seconds": _get_spin_box_int("respawn_time_seconds"),
	}


func _get_terrain_type_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"walkable": _get_check_box_pressed("walkable"),
		"allows_monster_spawn": _get_check_box_pressed("allows_monster_spawn"),
		"allows_resource_spawn": _get_check_box_pressed("allows_resource_spawn"),
	}


func _get_line_edit_text(field_name: String) -> String:
	if not field_controls.has(field_name):
		return ""

	var line_edit: LineEdit = field_controls[field_name]
	return line_edit.text


func _set_line_edit_text(field_name: String, value: String) -> void:
	if not field_controls.has(field_name):
		return

	var line_edit: LineEdit = field_controls[field_name]
	line_edit.text = value


func _get_spin_box_int(field_name: String) -> int:
	if not field_controls.has(field_name):
		return 0

	var spin_box: SpinBox = field_controls[field_name]
	return int(spin_box.value)


func _get_text_edit_text(field_name: String) -> String:
	if not field_controls.has(field_name):
		return ""

	var text_edit: TextEdit = field_controls[field_name]
	return text_edit.text


func _get_check_box_pressed(field_name: String) -> bool:
	if not field_controls.has(field_name):
		return false

	var check_box: CheckBox = field_controls[field_name]
	return check_box.button_pressed


func _mark_dirty() -> void:
	if is_building_form:
		return

	has_unsaved_changes = true
	_update_action_buttons()
	_set_status("Unsaved changes.")


func _update_action_buttons() -> void:
	var supports_visual_editing := current_section == ContentEditorData.SECTION_ITEMS or current_section == ContentEditorData.SECTION_RESOURCES or current_section == ContentEditorData.SECTION_TERRAIN_TYPES
	var has_record := not current_record.is_empty()

	new_button.disabled = not supports_visual_editing or has_unsaved_changes
	duplicate_button.disabled = not supports_visual_editing or has_unsaved_changes or current_original_id.is_empty()
	delete_button.disabled = not supports_visual_editing or current_id.is_empty()
	save_button.disabled = not supports_visual_editing or not has_record
	revert_button.disabled = not supports_visual_editing or not has_record


func _reload_content_db() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("load_all"):
		content_db.load_all()


func _get_default_item_id() -> String:
	if data_store.has_record(ContentEditorData.SECTION_ITEMS, "wood"):
		return "wood"

	var records := data_store.get_records(ContentEditorData.SECTION_ITEMS)
	if records.is_empty():
		return ""

	return str(records[0].get("id", ""))


func _stringify_value(value) -> String:
	if value is Dictionary or value is Array:
		return JSON.stringify(value)

	return str(value)


func _join_strings(values: Array, separator: String) -> String:
	var text := ""
	for value in values:
		if not text.is_empty():
			text += separator
		text += str(value)

	return text


func _set_status(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.15) if is_error else Color(0.25, 0.7, 0.25))
	print(message)
