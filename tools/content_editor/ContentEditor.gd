extends Control

const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")
const SpriteSheetPreviewScript := preload("res://tools/content_editor/SpriteSheetPreview.gd")

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
var selected_workstation_id := ""
var workstation_filter := ""
var production_rows := []
var selected_sprite_id := ""
var sprite_filter := ""
var sprite_category_filter := "all"
var selected_sprite_sheet_id := ""
var sprite_sheet_filter := ""
var selected_animation_name := ""
var animation_preview_playing := false
var animation_preview_elapsed := 0.0
var animation_preview_frame_index := 0
var sidebar_buttons := {}
var field_controls := {}

var section_title_label: Label
var search_line_edit: LineEdit
var sprite_category_filter_button: OptionButton
var record_list: ItemList
var new_button: Button
var duplicate_button: Button
var delete_button: Button
var form_title_label: Label
var form_container: VBoxContainer
var production_rows_container: VBoxContainer
var sprite_preview_rect: TextureRect
var sprite_sheet_preview: Control
var animation_grid_preview: Control
var animation_preview_rect: TextureRect
var texture_file_dialog: FileDialog
var save_button: Button
var revert_button: Button
var reload_current_button: Button
var refresh_content_db_button: Button
var current_file_label: Label
var status_label: Label


func _ready() -> void:
	_build_ui()
	set_process(true)

	var error := data_store.load_all()
	if not error.is_empty():
		_set_status(error, true)
		return

	_select_section(ContentEditorData.SECTION_ITEMS, true)


func _process(delta: float) -> void:
	if not animation_preview_playing:
		return
	if current_section != ContentEditorData.SECTION_ANIMATION_SETS:
		return

	var frames: Array = _get_selected_animation_frames()
	if frames.is_empty():
		return

	var fps: float = max(float(_get_spin_box_value("animation_fps")), 0.01)
	animation_preview_elapsed += delta
	if animation_preview_elapsed < 1.0 / fps:
		return

	animation_preview_elapsed = 0.0
	animation_preview_frame_index += 1
	if animation_preview_frame_index >= frames.size():
		if _get_check_box_pressed("animation_loop"):
			animation_preview_frame_index = 0
		else:
			animation_preview_frame_index = frames.size() - 1
			animation_preview_playing = false

	_update_animation_preview_frame()


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
	search_line_edit.placeholder_text = "Search by id, display name, or role"
	search_line_edit.text_changed.connect(_on_search_text_changed)
	panel.add_child(search_line_edit)

	sprite_category_filter_button = OptionButton.new()
	sprite_category_filter_button.name = "SpriteCategoryFilter"
	sprite_category_filter_button.item_selected.connect(_on_sprite_category_filter_selected)
	panel.add_child(sprite_category_filter_button)
	_populate_sprite_category_filter()

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

	current_file_label = Label.new()
	current_file_label.name = "CurrentFileLabel"
	current_file_label.text = "File: -"
	panel.add_child(current_file_label)

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

	reload_current_button = Button.new()
	reload_current_button.name = "ReloadCurrentButton"
	reload_current_button.text = "Reload Current"
	reload_current_button.pressed.connect(_on_reload_current_pressed)
	form_action_row.add_child(reload_current_button)

	refresh_content_db_button = Button.new()
	refresh_content_db_button.name = "RefreshContentDBButton"
	refresh_content_db_button.text = "Refresh ContentDB"
	refresh_content_db_button.pressed.connect(_on_refresh_content_db_pressed)
	form_action_row.add_child(refresh_content_db_button)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Ready"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status_label)

	texture_file_dialog = FileDialog.new()
	texture_file_dialog.name = "TextureFileDialog"
	texture_file_dialog.access = FileDialog.ACCESS_RESOURCES
	texture_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	texture_file_dialog.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg, *.jpeg ; JPEG Images",
		"*.webp ; WebP Images",
		"*.svg ; SVG Images",
	])
	texture_file_dialog.file_selected.connect(_on_texture_file_selected)
	add_child(texture_file_dialog)


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
	selected_workstation_id = ""
	workstation_filter = ""
	production_rows.clear()
	selected_sprite_id = ""
	sprite_filter = ""
	selected_sprite_sheet_id = ""
	sprite_sheet_filter = ""
	selected_animation_name = ""
	animation_preview_playing = false
	if section != ContentEditorData.SECTION_SPRITES:
		sprite_category_filter = "all"

	is_refreshing_list = true
	search_line_edit.text = ""
	is_refreshing_list = false

	section_title_label.text = data_store.get_section_label(current_section)
	current_file_label.text = "File: %s" % data_store.get_section_path(current_section)
	_update_sprite_category_filter_visibility()
	_sync_sidebar_buttons()
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Selected %s" % data_store.get_section_label(current_section))


func _sync_sidebar_buttons() -> void:
	for section in sidebar_buttons.keys():
		var button: Button = sidebar_buttons[section]
		button.button_pressed = section == current_section


func _populate_sprite_category_filter() -> void:
	sprite_category_filter_button.clear()
	_add_sprite_category_filter_option("All", "all")
	for category in _get_sprite_categories():
		_add_sprite_category_filter_option(category.capitalize(), category)
	sprite_category_filter_button.select(0)
	sprite_category_filter_button.visible = false


func _add_sprite_category_filter_option(label: String, category: String) -> void:
	var index := sprite_category_filter_button.item_count
	sprite_category_filter_button.add_item(label)
	sprite_category_filter_button.set_item_metadata(index, category)


func _update_sprite_category_filter_visibility() -> void:
	if sprite_category_filter_button == null:
		return

	sprite_category_filter_button.visible = current_section == ContentEditorData.SECTION_SPRITES
	if sprite_category_filter_button.visible:
		for index in range(sprite_category_filter_button.item_count):
			if str(sprite_category_filter_button.get_item_metadata(index)) == sprite_category_filter:
				sprite_category_filter_button.select(index)
				return


func _on_search_text_changed(_new_text: String) -> void:
	if is_refreshing_list:
		return

	_refresh_record_list()


func _on_sprite_category_filter_selected(index: int) -> void:
	if sprite_category_filter_button == null:
		return

	sprite_category_filter = str(sprite_category_filter_button.get_item_metadata(index))
	_refresh_record_list()


func _refresh_record_list() -> void:
	is_refreshing_list = true
	record_list.clear()

	var query := search_line_edit.text.strip_edges().to_lower()
	for record in data_store.get_records(current_section):
		if current_section == ContentEditorData.SECTION_SPRITES and not _sprite_record_matches_category_filter(record):
			continue

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
	var role := str(record.get("role", "")).to_lower()
	var category := str(record.get("category", "")).to_lower()
	var sprite_sheet_id := str(record.get("sprite_sheet_id", "")).to_lower()
	var tags := _join_string_array(record.get("tags", []), " ").to_lower()
	return record_id.contains(query) or display_name.contains(query) or role.contains(query) or category.contains(query) or sprite_sheet_id.contains(query) or tags.contains(query)


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
	selected_workstation_id = str(current_record.get("preferred_workstation", ""))
	workstation_filter = ""
	selected_sprite_id = str(current_record.get("sprite_id", ""))
	sprite_filter = ""
	selected_sprite_sheet_id = str(current_record.get("sprite_sheet_id", ""))
	sprite_sheet_filter = ""
	selected_animation_name = _get_first_animation_name(current_record)
	animation_preview_playing = false
	var loaded_production = current_record.get("production", [])
	production_rows = loaded_production.duplicate(true) if loaded_production is Array else []

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
		ContentEditorData.SECTION_MONSTERS:
			_build_monster_form()
		ContentEditorData.SECTION_RECIPES:
			_build_recipe_form()
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_build_terrain_type_form()
		ContentEditorData.SECTION_NPCS:
			_build_npc_form()
		ContentEditorData.SECTION_SPRITES:
			_build_sprite_form()
		ContentEditorData.SECTION_ANIMATION_SETS:
			_build_animation_set_form()
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
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_spin_box("Stack Size", "stack_size", int(current_record.get("stack_size", 999)), 1, 999999, 1)
	_add_text_edit("Description", "description", str(current_record.get("description", "")), 100)


func _build_resource_form() -> void:
	form_title_label.text = "Resource: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_spin_box("Max Health", "max_health", int(current_record.get("max_health", 20)), 1, 999999, 1)
	_add_drop_item_picker(str(current_record.get("drop_item_id", "wood")))
	_add_spin_box("Drop Amount", "drop_amount", int(current_record.get("drop_amount", 1)), 1, 999999, 1)
	_add_spin_box("Respawn Time Seconds", "respawn_time_seconds", int(current_record.get("respawn_time_seconds", 60)), 0, 999999, 1)


func _build_monster_form() -> void:
	form_title_label.text = "Monster: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_spin_box("Max Health", "max_health", int(current_record.get("max_health", 20)), 1, 999999, 1)
	_add_spin_box("Move Speed", "move_speed", int(current_record.get("move_speed", 40)), 0, 999999, 1)
	_add_spin_box("Damage", "damage", int(current_record.get("damage", 5)), 0, 999999, 1)
	_add_spin_box("Attack Cooldown", "attack_cooldown", int(current_record.get("attack_cooldown", 1)), 0, 999999, 1)
	_add_spin_box("Spawn Time Seconds", "spawn_time_seconds", int(current_record.get("spawn_time_seconds", 20)), 0, 999999, 1)
	_add_line_edit("Spawn Tiles", "spawn_tiles", _join_string_array(current_record.get("spawn_tiles", []), ", "))
	_add_read_only_value("Loot Table", _stringify_value(current_record.get("loot_table", [])))


func _build_recipe_form() -> void:
	form_title_label.text = "Recipe: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_recipe_type_option_button(str(current_record.get("type", "item")))
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_read_only_value("Cost", _stringify_value(current_record.get("cost", {})))


func _build_terrain_type_form() -> void:
	form_title_label.text = "Terrain Type: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_check_box("Walkable", "walkable", bool(current_record.get("walkable", true)))
	_add_check_box("Allows Monster Spawn", "allows_monster_spawn", bool(current_record.get("allows_monster_spawn", true)))
	_add_check_box("Allows Resource Spawn", "allows_resource_spawn", bool(current_record.get("allows_resource_spawn", true)))


func _build_npc_form() -> void:
	form_title_label.text = "NPC: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_spin_box("Max Health", "max_health", int(current_record.get("max_health", 50)), 1, 999999, 1)
	_add_spin_box("Move Speed", "move_speed", int(current_record.get("move_speed", 35)), 0, 999999, 1)
	_add_line_edit("Role", "role", str(current_record.get("role", "worker")))
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_workstation_picker(str(current_record.get("preferred_workstation", "workbench")))
	_add_check_box("Needs House", "needs_house", bool(current_record.get("needs_house", true)))
	_add_production_editor()


func _build_sprite_form() -> void:
	form_title_label.text = "Sprite: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_sprite_type_option_button(str(current_record.get("type", "single_sprite")))
	_add_texture_path_picker(str(current_record.get("texture_path", "")))
	_add_category_option_button(str(current_record.get("category", "item")))
	_add_line_edit("Tags", "tags", _join_string_array(current_record.get("tags", []), ", "))
	_add_check_box("Region Enabled", "region_enabled", bool(current_record.get("region_enabled", false)))

	var region = current_record.get("region", {})
	if not region is Dictionary:
		region = {}
	_add_spin_box("Region X", "region_x", int(region.get("x", 0)), 0, 999999, 1)
	_add_spin_box("Region Y", "region_y", int(region.get("y", 0)), 0, 999999, 1)
	_add_spin_box("Region W", "region_w", int(region.get("w", 32)), 1, 999999, 1)
	_add_spin_box("Region H", "region_h", int(region.get("h", 32)), 1, 999999, 1)

	var frame_size = current_record.get("frame_size", {})
	if not frame_size is Dictionary:
		frame_size = {}
	_add_spin_box("Frame Width", "frame_w", int(current_record.get("frame_width", frame_size.get("w", 32))), 1, 999999, 1)
	_add_spin_box("Frame Height", "frame_h", int(current_record.get("frame_height", frame_size.get("h", 32))), 1, 999999, 1)
	_add_spin_box("Columns", "columns", int(current_record.get("columns", 1)), 1, 999999, 1)
	_add_spin_box("Rows", "rows", int(current_record.get("rows", 1)), 1, 999999, 1)
	_add_spin_box("Total Frames", "total_frames", int(current_record.get("total_frames", 1)), 1, 999999, 1)
	_add_detect_grid_button()
	_add_sprite_preview_for_record(current_record)


func _build_animation_set_form() -> void:
	form_title_label.text = "Animation Set: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_sprite_sheet_picker(str(current_record.get("sprite_sheet_id", "")))

	var anchor = current_record.get("anchor", {})
	if not anchor is Dictionary:
		anchor = {}
	_add_spin_box("Anchor X", "anchor_x", int(anchor.get("x", 32)), 0, 999999, 1)
	_add_spin_box("Anchor Y", "anchor_y", int(anchor.get("y", 44)), 0, 999999, 1)

	_add_animation_list_editor()
	_add_animation_detail_editor()
	_add_animation_grid_editor()
	_add_mapping_helper()


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


func _add_texture_path_picker(value: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = "Texture Path"
	label.custom_minimum_size = Vector2(160, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var line_edit := LineEdit.new()
	line_edit.text = value
	line_edit.placeholder_text = "Choose a texture file..."
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text_changed.connect(func(_new_text: String) -> void: _mark_dirty())
	row.add_child(line_edit)
	field_controls["texture_path"] = line_edit

	var browse_button := Button.new()
	browse_button.text = "Browse..."
	browse_button.focus_mode = Control.FOCUS_NONE
	browse_button.pressed.connect(_on_browse_texture_pressed)
	row.add_child(browse_button)

	form_container.add_child(row)


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


func _add_workstation_picker(initial_recipe_id: String) -> void:
	selected_workstation_id = initial_recipe_id

	var search := LineEdit.new()
	search.placeholder_text = "Search building recipe by id or display name"
	search.text = workstation_filter
	search.text_changed.connect(_on_workstation_filter_changed)
	_add_form_row("Workstation Search", search)
	field_controls["workstation_search"] = search

	var option_button := OptionButton.new()
	option_button.item_selected.connect(_on_workstation_selected)
	_add_form_row("Preferred Workstation", option_button)
	field_controls["preferred_workstation"] = option_button
	_refresh_workstation_options()


func _add_sprite_picker(initial_sprite_id: String) -> void:
	selected_sprite_id = initial_sprite_id

	var search := LineEdit.new()
	search.placeholder_text = "Search sprite by id, display name, category, or tag"
	search.text = sprite_filter
	search.text_changed.connect(_on_sprite_filter_changed)
	_add_form_row("Sprite Search", search)
	field_controls["sprite_search"] = search

	var option_button := OptionButton.new()
	option_button.item_selected.connect(_on_sprite_selected)
	_add_form_row("Sprite", option_button)
	field_controls["sprite_id"] = option_button

	sprite_preview_rect = TextureRect.new()
	sprite_preview_rect.custom_minimum_size = Vector2(64, 64)
	sprite_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_add_form_row("Sprite Preview", sprite_preview_rect)
	_refresh_sprite_options()
	_update_selected_sprite_preview()


func _add_sprite_sheet_picker(initial_sprite_sheet_id: String) -> void:
	selected_sprite_sheet_id = initial_sprite_sheet_id

	var search := LineEdit.new()
	search.placeholder_text = "Search sprite sheet by id, display name, or tag"
	search.text = sprite_sheet_filter
	search.text_changed.connect(_on_sprite_sheet_filter_changed)
	_add_form_row("Sprite Sheet Search", search)
	field_controls["sprite_sheet_search"] = search

	var option_button := OptionButton.new()
	option_button.item_selected.connect(_on_sprite_sheet_selected)
	_add_form_row("Sprite Sheet", option_button)
	field_controls["sprite_sheet_id"] = option_button
	_refresh_sprite_sheet_options()


func _add_animation_list_editor() -> void:
	var title := Label.new()
	title.text = "Animations"
	form_container.add_child(title)

	var option_button := OptionButton.new()
	option_button.item_selected.connect(_on_animation_selected)
	_add_form_row("Selected Animation", option_button)
	field_controls["animation_select"] = option_button
	_refresh_animation_options()

	var row := HBoxContainer.new()
	form_container.add_child(row)

	var add_button := Button.new()
	add_button.text = "Add Animation"
	add_button.pressed.connect(_on_add_animation_pressed)
	row.add_child(add_button)

	var duplicate_button := Button.new()
	duplicate_button.text = "Duplicate Animation"
	duplicate_button.pressed.connect(_on_duplicate_animation_pressed)
	row.add_child(duplicate_button)

	var delete_button := Button.new()
	delete_button.text = "Delete Animation"
	delete_button.pressed.connect(_on_delete_animation_pressed)
	row.add_child(delete_button)

	var clear_button := Button.new()
	clear_button.text = "Clear Frames"
	clear_button.pressed.connect(_on_clear_animation_frames_pressed)
	row.add_child(clear_button)

	var standard_button := Button.new()
	standard_button.text = "Create Standard Character Animations"
	standard_button.pressed.connect(_on_create_standard_animations_pressed)
	form_container.add_child(standard_button)


func _add_animation_detail_editor() -> void:
	var animation_data := _get_selected_animation_data()
	_add_line_edit("Animation Name", "animation_name", selected_animation_name)
	_add_line_edit("Frames", "animation_frames", _join_string_array(animation_data.get("frames", []), ", "))
	_add_spin_box("FPS", "animation_fps", int(animation_data.get("fps", _get_default_animation_fps(selected_animation_name))), 1, 999999, 1)
	_add_check_box("Loop", "animation_loop", bool(animation_data.get("loop", true)))

	var row := HBoxContainer.new()
	form_container.add_child(row)

	var remove_button := Button.new()
	remove_button.text = "Remove Last Frame"
	remove_button.pressed.connect(_on_remove_last_animation_frame_pressed)
	row.add_child(remove_button)

	var up_button := Button.new()
	up_button.text = "Move Last Up"
	up_button.pressed.connect(_on_move_last_frame_up_pressed)
	row.add_child(up_button)

	var down_button := Button.new()
	down_button.text = "Move Last Down"
	down_button.pressed.connect(_on_move_last_frame_down_pressed)
	row.add_child(down_button)


func _add_animation_grid_editor() -> void:
	var sheet_record := _get_selected_sprite_sheet_record()
	_add_read_only_value("Selected Sheet", _get_sprite_sheet_summary(sheet_record))

	animation_grid_preview = SpriteSheetPreviewScript.new()
	animation_grid_preview.custom_minimum_size = Vector2(420, 420)
	animation_grid_preview.frame_clicked.connect(_on_animation_grid_frame_clicked)
	_add_form_row("Frame Grid", animation_grid_preview)
	_update_animation_grid_preview()

	animation_preview_rect = TextureRect.new()
	animation_preview_rect.custom_minimum_size = Vector2(128, 128)
	animation_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_add_form_row("Animation Preview", animation_preview_rect)
	_update_animation_preview_frame()

	var row := HBoxContainer.new()
	form_container.add_child(row)

	var play_button := Button.new()
	play_button.text = "Play Preview"
	play_button.pressed.connect(_on_play_animation_preview_pressed)
	row.add_child(play_button)

	var stop_button := Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_stop_animation_preview_pressed)
	row.add_child(stop_button)

	var previous_button := Button.new()
	previous_button.text = "Previous Frame"
	previous_button.pressed.connect(_on_previous_animation_frame_pressed)
	row.add_child(previous_button)

	var next_button := Button.new()
	next_button.text = "Next Frame"
	next_button.pressed.connect(_on_next_animation_frame_pressed)
	row.add_child(next_button)


func _add_mapping_helper() -> void:
	var title := Label.new()
	title.text = "Mapping Helper"
	form_container.add_child(title)

	_add_mapping_apply_mode_option()
	_add_line_edit("Helper Animation Name", "helper_animation_name", selected_animation_name)

	_add_spin_box("Row Index", "helper_row", 0, 0, 999999, 1)
	_add_spin_box("Start Column", "helper_start_column", 0, 0, 999999, 1)
	_add_spin_box("End Column", "helper_end_column", 3, 0, 999999, 1)
	var row_button := Button.new()
	row_button.text = "Add Row as Animation"
	row_button.pressed.connect(_on_helper_add_row_pressed)
	form_container.add_child(row_button)

	_add_spin_box("Column Index", "helper_column", 0, 0, 999999, 1)
	_add_spin_box("Start Row", "helper_start_row", 0, 0, 999999, 1)
	_add_spin_box("End Row", "helper_end_row", 3, 0, 999999, 1)
	var column_button := Button.new()
	column_button.text = "Add Column as Animation"
	column_button.pressed.connect(_on_helper_add_column_pressed)
	form_container.add_child(column_button)

	_add_spin_box("Start Frame", "helper_start_frame", 0, 0, 999999, 1)
	_add_spin_box("End Frame", "helper_end_frame", 3, 0, 999999, 1)
	_add_spin_box("Helper FPS", "helper_fps", 8, 1, 999999, 1)
	_add_check_box("Helper Loop", "helper_loop", true)
	var range_button := Button.new()
	range_button.text = "Add Range"
	range_button.pressed.connect(_on_helper_add_range_pressed)
	form_container.add_child(range_button)

	_add_copy_animation_picker()
	var copy_button := Button.new()
	copy_button.text = "Duplicate Direction"
	copy_button.pressed.connect(_on_helper_duplicate_direction_pressed)
	form_container.add_child(copy_button)


func _add_mapping_apply_mode_option() -> void:
	var option_button := OptionButton.new()
	for mode in ["append", "replace"]:
		var index := option_button.item_count
		option_button.add_item(mode)
		option_button.set_item_metadata(index, mode)
	option_button.select(0)
	option_button.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row("Apply Mode", option_button)
	field_controls["helper_apply_mode"] = option_button


func _add_copy_animation_picker() -> void:
	var option_button := OptionButton.new()
	for animation_name in _get_animation_names():
		var index := option_button.item_count
		option_button.add_item(animation_name)
		option_button.set_item_metadata(index, animation_name)
	option_button.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row("Copy Frames From", option_button)
	field_controls["copy_source_animation"] = option_button


func _add_category_option_button(initial_category: String) -> void:
	var option_button := OptionButton.new()
	var selected_index := 0

	for category in _get_sprite_categories():
		var index := option_button.item_count
		option_button.add_item(category)
		option_button.set_item_metadata(index, category)
		if category == initial_category:
			selected_index = index

	option_button.select(selected_index)
	option_button.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row("Category", option_button)
	field_controls["category"] = option_button


func _add_sprite_type_option_button(initial_type: String) -> void:
	var option_button := OptionButton.new()
	var types := [
		"single_sprite",
		"sprite_sheet",
	]
	var selected_index := 0

	for sprite_type in types:
		var index := option_button.item_count
		option_button.add_item(sprite_type)
		option_button.set_item_metadata(index, sprite_type)
		if sprite_type == initial_type:
			selected_index = index

	option_button.select(selected_index)
	option_button.item_selected.connect(_on_sprite_type_selected)
	_add_form_row("Type", option_button)
	field_controls["type"] = option_button


func _add_recipe_type_option_button(initial_type: String) -> void:
	var option_button := OptionButton.new()
	var types := [
		"building",
		"tool",
		"item",
		"material",
	]
	if not types.has(initial_type):
		types.append(initial_type)

	var selected_index := 0
	for recipe_type in types:
		var index := option_button.item_count
		option_button.add_item(recipe_type)
		option_button.set_item_metadata(index, recipe_type)
		if recipe_type == initial_type:
			selected_index = index

	option_button.select(selected_index)
	option_button.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row("Type", option_button)
	field_controls["type"] = option_button


func _add_detect_grid_button() -> void:
	var button := Button.new()
	button.text = "Detect Grid"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_detect_grid_pressed)
	_add_form_row("Sprite Sheet", button)


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


func _on_workstation_filter_changed(new_text: String) -> void:
	workstation_filter = new_text
	_refresh_workstation_options()


func _refresh_workstation_options() -> void:
	if not field_controls.has("preferred_workstation"):
		return

	var option_button: OptionButton = field_controls["preferred_workstation"]
	option_button.clear()

	var empty_index := option_button.item_count
	option_button.add_item("None")
	option_button.set_item_metadata(empty_index, "")

	var query := workstation_filter.strip_edges().to_lower()
	var selected_index := 0

	for recipe_record in _get_building_recipe_records():
		if not _record_matches_search(recipe_record, query):
			continue

		var recipe_id := str(recipe_record.get("id", ""))
		if recipe_id == selected_workstation_id:
			selected_index = option_button.item_count

		_add_recipe_option(option_button, recipe_record)

	option_button.select(selected_index)


func _add_recipe_option(option_button: OptionButton, recipe_record: Dictionary) -> void:
	var recipe_id := str(recipe_record.get("id", ""))
	var display_name := str(recipe_record.get("display_name", ""))
	var label := recipe_id
	if not display_name.is_empty():
		label = "%s - %s" % [recipe_id, display_name]

	var index := option_button.item_count
	option_button.add_item(label)
	option_button.set_item_metadata(index, recipe_id)


func _on_workstation_selected(index: int) -> void:
	if not field_controls.has("preferred_workstation"):
		return

	var option_button: OptionButton = field_controls["preferred_workstation"]
	selected_workstation_id = str(option_button.get_item_metadata(index))
	_mark_dirty()


func _on_sprite_filter_changed(new_text: String) -> void:
	sprite_filter = new_text
	_refresh_sprite_options()


func _refresh_sprite_options() -> void:
	if not field_controls.has("sprite_id"):
		return

	var option_button: OptionButton = field_controls["sprite_id"]
	option_button.clear()

	var empty_index := option_button.item_count
	option_button.add_item("None")
	option_button.set_item_metadata(empty_index, "")

	var query := sprite_filter.strip_edges().to_lower()
	var selected_index := 0

	for sprite_record in data_store.get_records(ContentEditorData.SECTION_SPRITES):
		if not _sprite_record_matches_search(sprite_record, query):
			continue

		var sprite_id := str(sprite_record.get("id", ""))
		if sprite_id == selected_sprite_id:
			selected_index = option_button.item_count

		_add_sprite_option(option_button, sprite_record)

	option_button.select(selected_index)


func _add_sprite_option(option_button: OptionButton, sprite_record: Dictionary) -> void:
	var sprite_id := str(sprite_record.get("id", ""))
	var display_name := str(sprite_record.get("display_name", ""))
	var category := str(sprite_record.get("category", ""))
	var label := sprite_id
	if not display_name.is_empty():
		label = "%s - %s" % [sprite_id, display_name]
	if not category.is_empty():
		label = "%s (%s)" % [label, category]

	var index := option_button.item_count
	option_button.add_item(label)
	option_button.set_item_metadata(index, sprite_id)


func _on_sprite_selected(index: int) -> void:
	if not field_controls.has("sprite_id"):
		return

	var option_button: OptionButton = field_controls["sprite_id"]
	selected_sprite_id = str(option_button.get_item_metadata(index))
	_update_selected_sprite_preview()
	_mark_dirty()


func _on_sprite_sheet_filter_changed(new_text: String) -> void:
	sprite_sheet_filter = new_text
	_refresh_sprite_sheet_options()


func _refresh_sprite_sheet_options() -> void:
	if not field_controls.has("sprite_sheet_id"):
		return

	var option_button: OptionButton = field_controls["sprite_sheet_id"]
	option_button.clear()

	var query := sprite_sheet_filter.strip_edges().to_lower()
	var selected_index := -1

	for sprite_record in data_store.get_records(ContentEditorData.SECTION_SPRITES):
		if str(sprite_record.get("type", "single_sprite")) != "sprite_sheet":
			continue
		if not _sprite_record_matches_search(sprite_record, query):
			continue

		var sprite_id := str(sprite_record.get("id", ""))
		if sprite_id == selected_sprite_sheet_id:
			selected_index = option_button.item_count

		_add_sprite_option(option_button, sprite_record)

	if selected_index >= 0:
		option_button.select(selected_index)
	elif option_button.item_count > 0:
		option_button.select(0)
		selected_sprite_sheet_id = str(option_button.get_item_metadata(0))


func _on_sprite_sheet_selected(index: int) -> void:
	if not field_controls.has("sprite_sheet_id"):
		return

	_sync_animation_detail_to_record()
	var option_button: OptionButton = field_controls["sprite_sheet_id"]
	selected_sprite_sheet_id = str(option_button.get_item_metadata(index))
	_update_animation_grid_preview()
	_update_animation_preview_frame()
	_mark_dirty()


func _on_animation_selected(index: int) -> void:
	if not field_controls.has("animation_select"):
		return

	_sync_animation_detail_to_record()
	var option_button: OptionButton = field_controls["animation_select"]
	selected_animation_name = str(option_button.get_item_metadata(index))
	_build_form_for_current_record()
	_mark_dirty()


func _on_add_animation_pressed() -> void:
	_sync_animation_detail_to_record()
	var animations := _get_animation_set_animations()
	var animation_name := _create_unique_animation_name("new_animation")
	animations[animation_name] = _make_animation_data([], _get_default_animation_fps(animation_name), true)
	selected_animation_name = animation_name
	_build_form_for_current_record()
	_mark_dirty()


func _on_duplicate_animation_pressed() -> void:
	_sync_animation_detail_to_record()
	if selected_animation_name.is_empty():
		_set_status("Select an animation before duplicating.", true)
		return

	var animations := _get_animation_set_animations()
	var animation_name := _create_unique_animation_name("%s_copy" % selected_animation_name)
	animations[animation_name] = _get_selected_animation_data().duplicate(true)
	selected_animation_name = animation_name
	_build_form_for_current_record()
	_mark_dirty()


func _on_delete_animation_pressed() -> void:
	_sync_animation_detail_to_record()
	if selected_animation_name.is_empty():
		return

	var animations := _get_animation_set_animations()
	animations.erase(selected_animation_name)
	selected_animation_name = _get_first_animation_name(current_record)
	_build_form_for_current_record()
	_mark_dirty()


func _on_clear_animation_frames_pressed() -> void:
	_sync_animation_detail_to_record()
	var animation_data := _get_selected_animation_data()
	animation_data["frames"] = []
	_set_selected_animation_data(animation_data)
	_build_form_for_current_record()
	_mark_dirty()


func _on_create_standard_animations_pressed() -> void:
	_sync_animation_detail_to_record()
	var animations := _get_animation_set_animations()
	for animation_name in _get_standard_character_animation_names():
		if animations.has(animation_name):
			continue
		animations[animation_name] = _make_animation_data([], _get_default_animation_fps(animation_name), _get_default_animation_loop(animation_name))

	if selected_animation_name.is_empty() and not animations.is_empty():
		selected_animation_name = _get_first_animation_name(current_record)

	_build_form_for_current_record()
	_mark_dirty()


func _on_remove_last_animation_frame_pressed() -> void:
	_sync_animation_detail_to_record()
	var frames := _get_selected_animation_frames()
	if frames.is_empty():
		return

	frames.remove_at(frames.size() - 1)
	_set_selected_animation_frames(frames)
	_build_form_for_current_record()
	_mark_dirty()


func _on_move_last_frame_up_pressed() -> void:
	_sync_animation_detail_to_record()
	var frames := _get_selected_animation_frames()
	if frames.size() < 2:
		return

	var last_index := frames.size() - 1
	var value = frames[last_index]
	frames[last_index] = frames[last_index - 1]
	frames[last_index - 1] = value
	_set_selected_animation_frames(frames)
	_build_form_for_current_record()
	_mark_dirty()


func _on_move_last_frame_down_pressed() -> void:
	_set_status("Last frame is already at the end.")


func _on_animation_grid_frame_clicked(frame_index: int, mouse_button: int) -> void:
	_sync_animation_detail_to_record()
	if selected_animation_name.is_empty():
		_set_status("Create or select an animation before adding frames.", true)
		return

	var frames := _get_selected_animation_frames()
	if mouse_button == MOUSE_BUTTON_RIGHT:
		for index in range(frames.size() - 1, -1, -1):
			if int(frames[index]) == frame_index:
				frames.remove_at(index)
				break
	else:
		frames.append(frame_index)

	_set_selected_animation_frames(frames)
	_set_line_edit_text("animation_frames", _join_string_array(frames, ", "))
	_update_animation_grid_preview()
	_update_animation_preview_frame()
	_mark_dirty()


func _on_play_animation_preview_pressed() -> void:
	_sync_animation_detail_to_record()
	var frames := _get_selected_animation_frames()
	if frames.is_empty():
		_set_status("Add frames before playing preview.", true)
		return

	animation_preview_playing = true
	animation_preview_elapsed = 0.0
	animation_preview_frame_index = clamp(animation_preview_frame_index, 0, frames.size() - 1)
	_update_animation_preview_frame()


func _on_stop_animation_preview_pressed() -> void:
	animation_preview_playing = false
	animation_preview_elapsed = 0.0


func _on_previous_animation_frame_pressed() -> void:
	_sync_animation_detail_to_record()
	var frames := _get_selected_animation_frames()
	if frames.is_empty():
		return

	animation_preview_playing = false
	animation_preview_frame_index = max(animation_preview_frame_index - 1, 0)
	_update_animation_preview_frame()


func _on_next_animation_frame_pressed() -> void:
	_sync_animation_detail_to_record()
	var frames := _get_selected_animation_frames()
	if frames.is_empty():
		return

	animation_preview_playing = false
	animation_preview_frame_index = min(animation_preview_frame_index + 1, frames.size() - 1)
	_update_animation_preview_frame()


func _on_helper_add_row_pressed() -> void:
	_sync_animation_detail_to_record()
	var sheet_record := _get_selected_sprite_sheet_record()
	var columns := int(sheet_record.get("columns", 0))
	var rows := int(sheet_record.get("rows", 0))
	var row := _get_spin_box_int("helper_row")
	var start_column := _get_spin_box_int("helper_start_column")
	var end_column := _get_spin_box_int("helper_end_column")
	if row < 0 or row >= rows or start_column < 0 or end_column >= columns or start_column > end_column:
		_set_status("Row helper values are outside the selected sprite sheet grid.", true)
		return

	var frames := []
	for column in range(start_column, end_column + 1):
		frames.append((row * columns) + column)

	_apply_helper_frames(frames)


func _on_helper_add_column_pressed() -> void:
	_sync_animation_detail_to_record()
	var sheet_record := _get_selected_sprite_sheet_record()
	var columns := int(sheet_record.get("columns", 0))
	var rows := int(sheet_record.get("rows", 0))
	var column := _get_spin_box_int("helper_column")
	var start_row := _get_spin_box_int("helper_start_row")
	var end_row := _get_spin_box_int("helper_end_row")
	if column < 0 or column >= columns or start_row < 0 or end_row >= rows or start_row > end_row:
		_set_status("Column helper values are outside the selected sprite sheet grid.", true)
		return

	var frames := []
	for row in range(start_row, end_row + 1):
		frames.append((row * columns) + column)

	_apply_helper_frames(frames)


func _on_helper_add_range_pressed() -> void:
	_sync_animation_detail_to_record()
	var sheet_record := _get_selected_sprite_sheet_record()
	var total_frames := int(sheet_record.get("total_frames", 0))
	var start_frame := _get_spin_box_int("helper_start_frame")
	var end_frame := _get_spin_box_int("helper_end_frame")
	if start_frame < 0 or end_frame >= total_frames or start_frame > end_frame:
		_set_status("Range helper values are outside the selected sprite sheet frames.", true)
		return

	var frames := []
	for frame_index in range(start_frame, end_frame + 1):
		frames.append(frame_index)

	_apply_helper_frames(frames)


func _on_helper_duplicate_direction_pressed() -> void:
	_sync_animation_detail_to_record()
	var source_animation := _get_option_button_metadata("copy_source_animation")
	var destination_animation := _get_line_edit_text("helper_animation_name")
	if source_animation.is_empty() or destination_animation.is_empty():
		_set_status("Choose a source animation and destination name before duplicating.", true)
		return

	var animations := _get_animation_set_animations()
	if not animations.has(source_animation):
		_set_status("Source animation does not exist.", true)
		return

	var source_data: Dictionary = animations[source_animation]
	var frames := []
	var source_frames = source_data.get("frames", [])
	if source_frames is Array:
		frames = source_frames.duplicate()

	_apply_helper_frames(frames, destination_animation, int(source_data.get("fps", 8)), bool(source_data.get("loop", true)))


func _on_browse_texture_pressed() -> void:
	if texture_file_dialog == null:
		return

	texture_file_dialog.popup_centered_ratio(0.75)


func _on_texture_file_selected(path: String) -> void:
	_set_line_edit_text("texture_path", path)
	if current_section == ContentEditorData.SECTION_SPRITES:
		var preview_record := current_record.duplicate(true)
		preview_record["texture_path"] = path
		preview_record["type"] = _get_option_button_metadata("type")
		preview_record["frame_width"] = _get_spin_box_int("frame_w")
		preview_record["frame_height"] = _get_spin_box_int("frame_h")
		preview_record["columns"] = _get_spin_box_int("columns")
		preview_record["rows"] = _get_spin_box_int("rows")
		if str(preview_record.get("type", "single_sprite")) == "sprite_sheet":
			_set_sprite_sheet_preview(preview_record)
		else:
			_set_texture_preview(sprite_preview_rect, preview_record)
	_mark_dirty()


func _on_sprite_type_selected(_index: int) -> void:
	if current_section != ContentEditorData.SECTION_SPRITES:
		_mark_dirty()
		return

	current_record = _get_sprite_form_record()
	_build_form_for_current_record()
	_mark_dirty()


func _on_detect_grid_pressed() -> void:
	var texture_path := _get_line_edit_text("texture_path")
	if texture_path.is_empty():
		_set_status("Choose a Texture Path before detecting a sprite sheet grid.", true)
		return

	var texture := _load_texture(texture_path)
	if texture == null:
		_set_status("Texture Path must point to a valid Texture2D.", true)
		return

	var frame_width := _get_spin_box_int("frame_w")
	var frame_height := _get_spin_box_int("frame_h")
	if frame_width < 1 or frame_height < 1:
		_set_status("Frame Width and Frame Height must be greater than zero.", true)
		return

	var texture_size := texture.get_size()
	var texture_width := int(texture_size.x)
	var texture_height := int(texture_size.y)
	if texture_width % frame_width != 0:
		_set_status("Texture width %d is not divisible by Frame Width %d." % [texture_width, frame_width], true)
		return
	if texture_height % frame_height != 0:
		_set_status("Texture height %d is not divisible by Frame Height %d." % [texture_height, frame_height], true)
		return

	var columns := int(texture_width / frame_width)
	var rows := int(texture_height / frame_height)
	var total_frames := columns * rows
	_set_spin_box_value("columns", columns)
	_set_spin_box_value("rows", rows)
	_set_spin_box_value("total_frames", total_frames)
	_set_option_button_by_metadata("type", "sprite_sheet")

	var preview_record := _get_sprite_form_record()
	if sprite_sheet_preview == null:
		current_record = preview_record
		_build_form_for_current_record()
		preview_record = _get_sprite_form_record()
	_set_sprite_sheet_preview(preview_record)
	_mark_dirty()
	_set_status("Detected grid: %d columns, %d rows, %d frames." % [columns, rows, total_frames])


func _sprite_record_matches_search(sprite_record: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true

	var haystack := "%s %s %s %s" % [
		str(sprite_record.get("id", "")),
		str(sprite_record.get("display_name", "")),
		str(sprite_record.get("category", "")),
		_join_string_array(sprite_record.get("tags", []), " "),
	]
	return haystack.to_lower().contains(query)


func _sprite_record_matches_category_filter(sprite_record: Dictionary) -> bool:
	if sprite_category_filter == "all":
		return true

	return str(sprite_record.get("category", "")) == sprite_category_filter


func _add_sprite_preview_for_record(sprite_record: Dictionary) -> void:
	var sprite_type := str(sprite_record.get("type", "single_sprite"))
	if sprite_type == "sprite_sheet":
		sprite_preview_rect = null
		sprite_sheet_preview = SpriteSheetPreviewScript.new()
		sprite_sheet_preview.custom_minimum_size = Vector2(420, 420)
		_add_form_row("Sheet Preview", sprite_sheet_preview)
		_set_sprite_sheet_preview(sprite_record)
		return

	sprite_sheet_preview = null
	sprite_preview_rect = TextureRect.new()
	sprite_preview_rect.custom_minimum_size = Vector2(96, 96)
	sprite_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_add_form_row("Preview", sprite_preview_rect)
	_set_texture_preview(sprite_preview_rect, sprite_record)


func _update_selected_sprite_preview() -> void:
	if sprite_preview_rect == null:
		return

	if selected_sprite_id.is_empty() or not data_store.has_record(ContentEditorData.SECTION_SPRITES, selected_sprite_id):
		sprite_preview_rect.texture = null
		return

	_set_texture_preview(sprite_preview_rect, data_store.get_record(ContentEditorData.SECTION_SPRITES, selected_sprite_id))


func _set_texture_preview(texture_rect: TextureRect, sprite_record: Dictionary) -> void:
	if texture_rect == null:
		return

	var texture_path := str(sprite_record.get("texture_path", ""))
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		texture_rect.texture = null
		return

	var texture := _load_texture(texture_path)
	if texture != null:
		texture_rect.texture = texture
	else:
		texture_rect.texture = null
	# TODO: crop TextureRect preview to sprite region when region_enabled is true.


func _set_sprite_sheet_preview(sprite_record: Dictionary) -> void:
	if sprite_sheet_preview == null:
		return

	var texture_path := str(sprite_record.get("texture_path", ""))
	var texture := _load_texture(texture_path)
	if texture == null:
		sprite_sheet_preview.clear_preview()
		return

	var columns := int(sprite_record.get("columns", 0))
	var rows := int(sprite_record.get("rows", 0))
	if columns < 1 or rows < 1:
		var frame_width := int(sprite_record.get("frame_width", 0))
		var frame_height := int(sprite_record.get("frame_height", 0))
		if frame_width < 1 or frame_height < 1:
			var frame_size = sprite_record.get("frame_size", {})
			if frame_size is Dictionary:
				frame_width = int(frame_size.get("w", 0))
				frame_height = int(frame_size.get("h", 0))

		var texture_size := texture.get_size()
		if frame_width > 0 and frame_height > 0:
			columns = int(int(texture_size.x) / frame_width)
			rows = int(int(texture_size.y) / frame_height)

	sprite_sheet_preview.set_preview_data(texture, columns, rows)


func _load_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		return null

	var resource := load(texture_path)
	if resource is Texture2D:
		return resource

	return null


func _add_production_editor() -> void:
	var title := Label.new()
	title.text = "Production Table"
	form_container.add_child(title)

	production_rows_container = VBoxContainer.new()
	production_rows_container.name = "ProductionRows"
	production_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_container.add_child(production_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Production"
	add_button.pressed.connect(_on_add_production_pressed)
	form_container.add_child(add_button)

	_rebuild_production_rows()


func _rebuild_production_rows() -> void:
	if production_rows_container == null:
		return

	for child in production_rows_container.get_children():
		child.queue_free()

	for row_index in range(production_rows.size()):
		_add_production_row(row_index)


func _add_production_row(row_index: int) -> void:
	var row_data: Dictionary = production_rows[row_index]
	if not row_data.has("item_filter"):
		row_data["item_filter"] = ""

	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	production_rows_container.add_child(row)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(header)

	var title := Label.new()
	title.text = "Production %d" % (row_index + 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(_on_remove_production_pressed.bind(row_index))
	header.add_child(remove_button)

	var search := LineEdit.new()
	search.placeholder_text = "Search item by id or display name"
	search.text = str(row_data.get("item_filter", ""))
	row.add_child(search)

	var option_button := OptionButton.new()
	row.add_child(option_button)
	_populate_production_item_options(option_button, row_index)

	search.text_changed.connect(_on_production_item_filter_changed.bind(row_index, option_button))
	option_button.item_selected.connect(_on_production_item_selected.bind(row_index, option_button))

	var values := HBoxContainer.new()
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(values)

	var amount_label := Label.new()
	amount_label.text = "Amount"
	values.add_child(amount_label)

	var amount_spin := SpinBox.new()
	amount_spin.min_value = 1
	amount_spin.max_value = 999999
	amount_spin.step = 1
	amount_spin.value = int(row_data.get("amount", 1))
	amount_spin.value_changed.connect(_on_production_amount_changed.bind(row_index))
	values.add_child(amount_spin)

	var interval_label := Label.new()
	interval_label.text = "Interval Seconds"
	values.add_child(interval_label)

	var interval_spin := SpinBox.new()
	interval_spin.min_value = 1
	interval_spin.max_value = 999999
	interval_spin.step = 1
	interval_spin.value = int(row_data.get("interval_seconds", 30))
	interval_spin.value_changed.connect(_on_production_interval_changed.bind(row_index))
	values.add_child(interval_spin)


func _populate_production_item_options(option_button: OptionButton, row_index: int) -> void:
	option_button.clear()
	var row_data: Dictionary = production_rows[row_index]
	var selected_item_id := str(row_data.get("item_id", _get_default_item_id()))
	var query := str(row_data.get("item_filter", "")).strip_edges().to_lower()
	var selected_index := -1
	var selected_record := {}

	for item_record in data_store.get_records(ContentEditorData.SECTION_ITEMS):
		if str(item_record.get("id", "")) == selected_item_id:
			selected_record = item_record
			break

	if not selected_record.is_empty() and not _record_matches_search(selected_record, query):
		_add_drop_item_option(option_button, selected_record)
		selected_index = 0

	for item_record in data_store.get_records(ContentEditorData.SECTION_ITEMS):
		if not _record_matches_search(item_record, query):
			continue

		if str(item_record.get("id", "")) == selected_item_id and selected_index == -1:
			selected_index = option_button.item_count

		_add_drop_item_option(option_button, item_record)

	if selected_index >= 0:
		option_button.select(selected_index)


func _on_production_item_filter_changed(new_text: String, row_index: int, option_button: OptionButton) -> void:
	if not _is_valid_production_row_index(row_index):
		return

	production_rows[row_index]["item_filter"] = new_text
	_populate_production_item_options(option_button, row_index)
	_mark_dirty()


func _on_production_item_selected(selected_index: int, row_index: int, option_button: OptionButton) -> void:
	if not _is_valid_production_row_index(row_index):
		return

	production_rows[row_index]["item_id"] = str(option_button.get_item_metadata(selected_index))
	_mark_dirty()


func _on_production_amount_changed(new_value: float, row_index: int) -> void:
	if not _is_valid_production_row_index(row_index):
		return

	production_rows[row_index]["amount"] = int(new_value)
	_mark_dirty()


func _on_production_interval_changed(new_value: float, row_index: int) -> void:
	if not _is_valid_production_row_index(row_index):
		return

	production_rows[row_index]["interval_seconds"] = int(new_value)
	_mark_dirty()


func _on_add_production_pressed() -> void:
	production_rows.append({
		"item_id": _get_default_item_id(),
		"amount": 1,
		"interval_seconds": 30,
		"item_filter": "",
	})
	_rebuild_production_rows()
	_mark_dirty()


func _on_remove_production_pressed(row_index: int) -> void:
	if not _is_valid_production_row_index(row_index):
		return

	production_rows.remove_at(row_index)
	_rebuild_production_rows()
	_mark_dirty()


func _is_valid_production_row_index(row_index: int) -> bool:
	return row_index >= 0 and row_index < production_rows.size()


func _on_new_pressed() -> void:
	if has_unsaved_changes:
		_set_status("Save or Revert before creating a new record.", true)
		return

	match current_section:
		ContentEditorData.SECTION_ITEMS:
			_create_new_item()
		ContentEditorData.SECTION_RESOURCES:
			_create_new_resource()
		ContentEditorData.SECTION_MONSTERS:
			_create_new_monster()
		ContentEditorData.SECTION_RECIPES:
			_create_new_recipe()
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_create_new_terrain_type()
		ContentEditorData.SECTION_NPCS:
			_create_new_npc()
		ContentEditorData.SECTION_SPRITES:
			_create_new_sprite()
		ContentEditorData.SECTION_ANIMATION_SETS:
			_create_new_animation_set()
		_:
			_set_status("New is available for visual content sections.", true)


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


func _create_new_monster() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_MONSTERS, "new_monster")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Monster",
		"max_health": 20,
		"move_speed": 40,
		"damage": 5,
		"attack_cooldown": 1,
		"spawn_time_seconds": 20,
		"spawn_tiles": ["grass"],
		"loot_table": [],
	}
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved monster.")


func _create_new_recipe() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_RECIPES, "new_recipe")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Recipe",
		"type": "item",
		"cost": {},
	}
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved recipe.")


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


func _create_new_npc() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_NPCS, "new_npc")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New NPC",
		"max_health": 50,
		"move_speed": 35,
		"role": "worker",
		"preferred_workstation": _get_default_workstation_id(),
		"production": [],
		"needs_house": true,
	}
	selected_workstation_id = str(current_record.get("preferred_workstation", ""))
	production_rows = []
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved NPC.")


func _create_new_sprite() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_SPRITES, "new_sprite")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Sprite",
		"type": "single_sprite",
		"texture_path": "",
		"region_enabled": false,
		"region": {
			"x": 0,
			"y": 0,
			"w": 32,
			"h": 32,
		},
		"frame_size": {
			"w": 32,
			"h": 32,
		},
		"frame_width": 32,
		"frame_height": 32,
		"columns": 1,
		"rows": 1,
		"total_frames": 1,
		"category": "item",
		"tags": [],
	}
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved sprite.")


func _create_new_animation_set() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_ANIMATION_SETS, "new_animation_set")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Animation Set",
		"sprite_sheet_id": _get_default_sprite_sheet_id(),
		"anchor": {
			"x": 32,
			"y": 44,
		},
		"animations": {},
	}
	selected_sprite_sheet_id = str(current_record.get("sprite_sheet_id", ""))
	selected_animation_name = ""
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved animation set.")


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
		ContentEditorData.SECTION_MONSTERS:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_RECIPES:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_NPCS:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_SPRITES:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_ANIMATION_SETS:
			_duplicate_current_record("_copy")
		_:
			_set_status("Duplicate is available for visual content sections.", true)


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
	selected_workstation_id = str(current_record.get("preferred_workstation", ""))
	selected_sprite_id = str(current_record.get("sprite_id", ""))
	selected_sprite_sheet_id = str(current_record.get("sprite_sheet_id", ""))
	selected_animation_name = _get_first_animation_name(current_record)
	var loaded_production = current_record.get("production", [])
	production_rows = loaded_production.duplicate(true) if loaded_production is Array else []
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
		ContentEditorData.SECTION_MONSTERS:
			_delete_current_monster()
		ContentEditorData.SECTION_RECIPES:
			_delete_current_recipe()
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_delete_current_terrain_type()
		ContentEditorData.SECTION_NPCS:
			_delete_current_npc()
		ContentEditorData.SECTION_SPRITES:
			_delete_current_sprite()
		ContentEditorData.SECTION_ANIMATION_SETS:
			_delete_current_animation_set()
		_:
			_set_status("Delete is available for visual content sections.", true)


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


func _delete_current_monster() -> void:
	var usages := data_store.find_monster_usages(current_original_id)
	if not usages.is_empty():
		_set_status("Cannot delete monster. It is used by: %s" % _join_strings(usages, ", "), true)
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
	_set_status("Deleted monster.")


func _delete_current_recipe() -> void:
	var usages := data_store.find_recipe_usages(current_original_id)
	if not usages.is_empty():
		_set_status("Cannot delete recipe. It is used by: %s" % _join_strings(usages, ", "), true)
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
	_set_status("Deleted recipe.")


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


func _delete_current_npc() -> void:
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
	production_rows.clear()
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Deleted NPC.")


func _delete_current_sprite() -> void:
	var usages := data_store.find_sprite_usage(current_original_id)
	if not usages.is_empty():
		_set_status("Cannot delete sprite. It is used by: %s" % _join_strings(usages, ", "), true)
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
	_set_status("Deleted sprite.")


func _delete_current_animation_set() -> void:
	var usages := data_store.find_animation_set_usages(current_original_id)
	if not usages.is_empty():
		_set_status("Cannot delete animation set. It is used by: %s" % _join_strings(usages, ", "), true)
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
	selected_animation_name = ""
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Deleted animation set.")


func _on_save_pressed() -> void:
	if current_record.is_empty():
		_set_status("Select or create a record before saving.", true)
		return

	match current_section:
		ContentEditorData.SECTION_ITEMS:
			_save_item()
		ContentEditorData.SECTION_RESOURCES:
			_save_resource()
		ContentEditorData.SECTION_MONSTERS:
			_save_monster()
		ContentEditorData.SECTION_RECIPES:
			_save_recipe()
		ContentEditorData.SECTION_TERRAIN_TYPES:
			_save_terrain_type()
		ContentEditorData.SECTION_NPCS:
			_save_npc()
		ContentEditorData.SECTION_SPRITES:
			_save_sprite()
		ContentEditorData.SECTION_ANIMATION_SETS:
			_save_animation_set()
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


func _save_monster() -> void:
	var record := _get_monster_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_monster(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_recipe() -> void:
	var record := _get_recipe_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_recipe(record_id, current_original_id, record)
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


func _save_npc() -> void:
	var record := _get_npc_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_npc(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_sprite() -> void:
	var record := _get_sprite_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_sprite(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_animation_set() -> void:
	_sync_animation_detail_to_record()
	var record := _get_animation_set_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_animation_set(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_current_record(record_id: String, record: Dictionary) -> void:
	_cleanup_optional_fields(record)
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
	selected_workstation_id = str(current_record.get("preferred_workstation", ""))
	selected_sprite_id = str(current_record.get("sprite_id", ""))
	selected_sprite_sheet_id = str(current_record.get("sprite_sheet_id", ""))
	selected_animation_name = _get_first_animation_name(current_record)
	var loaded_production = current_record.get("production", [])
	production_rows = loaded_production.duplicate(true) if loaded_production is Array else []
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Saved %s. ContentDB refreshed." % record_id)


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
	drop_item_filter = ""
	selected_workstation_id = str(current_record.get("preferred_workstation", ""))
	workstation_filter = ""
	selected_sprite_id = str(current_record.get("sprite_id", ""))
	sprite_filter = ""
	selected_sprite_sheet_id = str(current_record.get("sprite_sheet_id", ""))
	sprite_sheet_filter = ""
	selected_animation_name = _get_first_animation_name(current_record)
	animation_preview_playing = false
	var loaded_production = current_record.get("production", [])
	production_rows = loaded_production.duplicate(true) if loaded_production is Array else []
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Reverted %s." % current_id)


func _on_reload_current_pressed() -> void:
	if current_section.is_empty():
		return

	var error := data_store.load_section(current_section)
	if not error.is_empty():
		_set_status(error, true)
		return

	if not current_original_id.is_empty():
		_load_record(current_original_id)
	else:
		_refresh_record_list()
		_show_empty_form()

	has_unsaved_changes = false
	_update_action_buttons()
	_set_status("Reloaded %s." % data_store.get_section_label(current_section))


func _on_refresh_content_db_pressed() -> void:
	_reload_content_db()
	_set_status("ContentDB refreshed.")


func _discard_unsaved_new_record() -> void:
	current_id = ""
	current_original_id = ""
	current_record = {}
	has_unsaved_changes = false
	selected_drop_item_id = ""
	drop_item_filter = ""
	selected_workstation_id = ""
	workstation_filter = ""
	selected_sprite_id = ""
	sprite_filter = ""
	selected_sprite_sheet_id = ""
	sprite_sheet_filter = ""
	selected_animation_name = ""
	animation_preview_playing = false
	production_rows.clear()
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Discarded unsaved record.")


func _get_item_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"sprite_id": selected_sprite_id,
		"stack_size": _get_spin_box_int("stack_size"),
		"description": _get_text_edit_text("description"),
	}


func _get_resource_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"sprite_id": selected_sprite_id,
		"max_health": _get_spin_box_int("max_health"),
		"drop_item_id": selected_drop_item_id,
		"drop_amount": _get_spin_box_int("drop_amount"),
		"respawn_time_seconds": _get_spin_box_int("respawn_time_seconds"),
	}


func _get_monster_form_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = _get_line_edit_text("id")
	record["display_name"] = _get_line_edit_text("display_name")
	record["sprite_id"] = selected_sprite_id
	record["max_health"] = _get_spin_box_int("max_health")
	record["move_speed"] = _get_spin_box_int("move_speed")
	record["damage"] = _get_spin_box_int("damage")
	record["attack_cooldown"] = _get_spin_box_int("attack_cooldown")
	record["spawn_time_seconds"] = _get_spin_box_int("spawn_time_seconds")
	record["spawn_tiles"] = _parse_tags(_get_line_edit_text("spawn_tiles"))
	if not record.has("loot_table"):
		record["loot_table"] = []
	return record


func _get_recipe_form_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = _get_line_edit_text("id")
	record["display_name"] = _get_line_edit_text("display_name")
	record["type"] = _get_option_button_metadata("type")
	record["sprite_id"] = selected_sprite_id
	if not record.has("cost"):
		record["cost"] = {}
	return record


func _get_terrain_type_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"sprite_id": selected_sprite_id,
		"walkable": _get_check_box_pressed("walkable"),
		"allows_monster_spawn": _get_check_box_pressed("allows_monster_spawn"),
		"allows_resource_spawn": _get_check_box_pressed("allows_resource_spawn"),
	}


func _get_npc_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"max_health": _get_spin_box_int("max_health"),
		"move_speed": _get_spin_box_int("move_speed"),
		"role": _get_line_edit_text("role"),
		"sprite_id": selected_sprite_id,
		"preferred_workstation": selected_workstation_id,
		"production": _get_clean_production_rows(),
		"needs_house": _get_check_box_pressed("needs_house"),
	}


func _get_sprite_form_record() -> Dictionary:
	var frame_width := _get_spin_box_int("frame_w")
	var frame_height := _get_spin_box_int("frame_h")
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"type": _get_option_button_metadata("type"),
		"texture_path": _get_line_edit_text("texture_path"),
		"region_enabled": _get_check_box_pressed("region_enabled"),
		"region": {
			"x": _get_spin_box_int("region_x"),
			"y": _get_spin_box_int("region_y"),
			"w": _get_spin_box_int("region_w"),
			"h": _get_spin_box_int("region_h"),
		},
		"frame_size": {
			"w": frame_width,
			"h": frame_height,
		},
		"frame_width": frame_width,
		"frame_height": frame_height,
		"columns": _get_spin_box_int("columns"),
		"rows": _get_spin_box_int("rows"),
		"total_frames": _get_spin_box_int("total_frames"),
		"category": _get_option_button_metadata("category"),
		"tags": _parse_tags(_get_line_edit_text("tags")),
	}


func _get_animation_set_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"sprite_sheet_id": selected_sprite_sheet_id,
		"anchor": {
			"x": _get_spin_box_int("anchor_x"),
			"y": _get_spin_box_int("anchor_y"),
		},
		"animations": _get_animation_set_animations().duplicate(true),
	}


func _get_clean_production_rows() -> Array:
	var clean_rows := []

	for production_row in production_rows:
		if not production_row is Dictionary:
			continue

		clean_rows.append({
			"item_id": str(production_row.get("item_id", _get_default_item_id())),
			"amount": int(production_row.get("amount", 1)),
			"interval_seconds": int(production_row.get("interval_seconds", 30)),
		})

	return clean_rows


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


func _get_spin_box_value(field_name: String) -> float:
	if not field_controls.has(field_name):
		return 0.0

	var spin_box: SpinBox = field_controls[field_name]
	return spin_box.value


func _set_spin_box_value(field_name: String, value: int) -> void:
	if not field_controls.has(field_name):
		return

	var spin_box: SpinBox = field_controls[field_name]
	spin_box.value = value


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


func _get_option_button_metadata(field_name: String) -> String:
	if not field_controls.has(field_name):
		return ""

	var option_button: OptionButton = field_controls[field_name]
	if option_button.item_count <= 0 or option_button.selected < 0:
		return ""

	return str(option_button.get_item_metadata(option_button.selected))


func _set_option_button_by_metadata(field_name: String, metadata: String) -> void:
	if not field_controls.has(field_name):
		return

	var option_button: OptionButton = field_controls[field_name]
	for index in range(option_button.item_count):
		if str(option_button.get_item_metadata(index)) == metadata:
			option_button.select(index)
			return


func _mark_dirty() -> void:
	if is_building_form:
		return

	has_unsaved_changes = true
	_update_action_buttons()
	_set_status("Unsaved changes.")


func _update_action_buttons() -> void:
	var supports_visual_editing := current_section == ContentEditorData.SECTION_ITEMS or current_section == ContentEditorData.SECTION_RESOURCES or current_section == ContentEditorData.SECTION_MONSTERS or current_section == ContentEditorData.SECTION_RECIPES or current_section == ContentEditorData.SECTION_TERRAIN_TYPES or current_section == ContentEditorData.SECTION_NPCS or current_section == ContentEditorData.SECTION_SPRITES or current_section == ContentEditorData.SECTION_ANIMATION_SETS
	var has_record := not current_record.is_empty()

	new_button.disabled = not supports_visual_editing or has_unsaved_changes
	duplicate_button.disabled = not supports_visual_editing or has_unsaved_changes or current_original_id.is_empty()
	delete_button.disabled = not supports_visual_editing or current_id.is_empty()
	save_button.disabled = not supports_visual_editing or not has_record
	revert_button.disabled = not supports_visual_editing or not has_record
	reload_current_button.disabled = current_section.is_empty()
	refresh_content_db_button.disabled = false


func _reload_content_db() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("load_all"):
		content_db.load_all()


func _get_animation_set_animations() -> Dictionary:
	if not current_record.has("animations") or not current_record["animations"] is Dictionary:
		current_record["animations"] = {}

	return current_record["animations"] as Dictionary


func _get_animation_names() -> Array:
	var names := _get_animation_set_animations().keys()
	names.sort()
	return names


func _refresh_animation_options() -> void:
	if not field_controls.has("animation_select"):
		return

	var option_button: OptionButton = field_controls["animation_select"]
	option_button.clear()

	var selected_index := 0
	for animation_name in _get_animation_names():
		var index := option_button.item_count
		option_button.add_item(str(animation_name))
		option_button.set_item_metadata(index, str(animation_name))
		if str(animation_name) == selected_animation_name:
			selected_index = index

	if option_button.item_count > 0:
		option_button.select(selected_index)


func _get_selected_animation_data() -> Dictionary:
	var animations := _get_animation_set_animations()
	if selected_animation_name.is_empty() or not animations.has(selected_animation_name):
		return _make_animation_data([], _get_default_animation_fps(selected_animation_name), true)

	var animation_data = animations[selected_animation_name]
	if not animation_data is Dictionary:
		return _make_animation_data([], _get_default_animation_fps(selected_animation_name), true)

	return (animation_data as Dictionary).duplicate(true)


func _set_selected_animation_data(animation_data: Dictionary) -> void:
	if selected_animation_name.is_empty():
		return

	var animations := _get_animation_set_animations()
	animations[selected_animation_name] = animation_data


func _get_selected_animation_frames() -> Array:
	var animation_data := _get_selected_animation_data()
	var frames = animation_data.get("frames", [])
	if not frames is Array:
		return []

	var clean_frames := []
	for frame in frames:
		clean_frames.append(int(frame))

	return clean_frames


func _set_selected_animation_frames(frames: Array) -> void:
	var animation_data := _get_selected_animation_data()
	animation_data["frames"] = frames
	_set_selected_animation_data(animation_data)


func _sync_animation_detail_to_record() -> void:
	if current_section != ContentEditorData.SECTION_ANIMATION_SETS:
		return
	if selected_animation_name.is_empty() or not field_controls.has("animation_name"):
		return

	var old_name := selected_animation_name
	var new_name := data_store.sanitize_id(_get_line_edit_text("animation_name"))
	if new_name.is_empty():
		new_name = old_name

	var animations := _get_animation_set_animations()
	var animation_data := _make_animation_data(
		_parse_frame_list(_get_line_edit_text("animation_frames")),
		int(_get_spin_box_value("animation_fps")),
		_get_check_box_pressed("animation_loop")
	)

	if new_name != old_name:
		animations.erase(old_name)

	animations[new_name] = animation_data
	selected_animation_name = new_name


func _update_animation_grid_preview() -> void:
	if animation_grid_preview == null:
		return

	var sheet_record := _get_selected_sprite_sheet_record()
	var texture := _load_texture(str(sheet_record.get("texture_path", "")))
	if texture == null:
		animation_grid_preview.clear_preview()
		return

	animation_grid_preview.set_preview_data(texture, int(sheet_record.get("columns", 0)), int(sheet_record.get("rows", 0)))
	animation_grid_preview.set_selected_frames(_get_selected_animation_frames())


func _update_animation_preview_frame() -> void:
	if animation_preview_rect == null:
		return

	var frames := _get_selected_animation_frames()
	if frames.is_empty():
		animation_preview_rect.texture = null
		return

	animation_preview_frame_index = clamp(animation_preview_frame_index, 0, frames.size() - 1)
	animation_preview_rect.texture = _make_frame_texture(frames[animation_preview_frame_index])


func _make_frame_texture(frame_index: int) -> Texture2D:
	var sheet_record := _get_selected_sprite_sheet_record()
	var texture := _load_texture(str(sheet_record.get("texture_path", "")))
	if texture == null:
		return null

	var columns := int(sheet_record.get("columns", 0))
	var frame_width := int(sheet_record.get("frame_width", 0))
	var frame_height := int(sheet_record.get("frame_height", 0))
	if columns < 1 or frame_width < 1 or frame_height < 1:
		return null

	var column := frame_index % columns
	var row := int(frame_index / columns)
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = Rect2(column * frame_width, row * frame_height, frame_width, frame_height)
	return atlas_texture


func _get_selected_sprite_sheet_record() -> Dictionary:
	if selected_sprite_sheet_id.is_empty():
		return {}
	if not data_store.has_record(ContentEditorData.SECTION_SPRITES, selected_sprite_sheet_id):
		return {}

	return data_store.get_record(ContentEditorData.SECTION_SPRITES, selected_sprite_sheet_id)


func _get_sprite_sheet_summary(sprite_record: Dictionary) -> String:
	if sprite_record.is_empty():
		return "None"

	return "%s | columns %d | rows %d | total %d" % [
		str(sprite_record.get("id", "")),
		int(sprite_record.get("columns", 0)),
		int(sprite_record.get("rows", 0)),
		int(sprite_record.get("total_frames", 0)),
	]


func _apply_helper_frames(frames: Array, animation_name := "", fps := -1, loop := true) -> void:
	var target_name := data_store.sanitize_id(animation_name if not animation_name.is_empty() else _get_line_edit_text("helper_animation_name"))
	if target_name.is_empty():
		_set_status("Helper Animation Name cannot be empty.", true)
		return

	var animations := _get_animation_set_animations()
	var mode := _get_option_button_metadata("helper_apply_mode")
	var animation_data := _make_animation_data([], fps if fps > 0 else _get_spin_box_int("helper_fps"), loop if fps > 0 else _get_check_box_pressed("helper_loop"))
	if animations.has(target_name) and mode == "append":
		animation_data = animations[target_name].duplicate(true)
		var existing_frames = animation_data.get("frames", [])
		if not existing_frames is Array:
			existing_frames = []
		for frame in frames:
			existing_frames.append(int(frame))
		animation_data["frames"] = existing_frames
	else:
		animation_data["frames"] = frames

	animations[target_name] = animation_data
	selected_animation_name = target_name
	_build_form_for_current_record()
	_mark_dirty()
	_set_status("Applied helper frames to %s." % target_name)


func _make_animation_data(frames: Array, fps: int, loop: bool) -> Dictionary:
	return {
		"frames": frames,
		"fps": max(fps, 1),
		"loop": loop,
	}


func _parse_frame_list(text: String) -> Array:
	var frames := []
	for raw_frame in text.split(",", false):
		var clean_frame := raw_frame.strip_edges()
		if clean_frame.is_empty():
			continue
		frames.append(int(clean_frame))

	return frames


func _get_default_animation_fps(animation_name: String) -> int:
	if animation_name.begins_with("idle"):
		return 1
	if animation_name.begins_with("attack") or animation_name.begins_with("interact"):
		return 10
	return 8


func _get_default_animation_loop(animation_name: String) -> bool:
	return not animation_name.begins_with("attack") and not animation_name.begins_with("interact")


func _get_first_animation_name(record: Dictionary) -> String:
	var animations = record.get("animations", {})
	if not animations is Dictionary:
		return ""

	var animation_dictionary: Dictionary = animations
	var names: Array = animation_dictionary.keys()
	names.sort()
	if names.is_empty():
		return ""

	return str(names[0])


func _create_unique_animation_name(base_name: String) -> String:
	var animations := _get_animation_set_animations()
	var clean_base := data_store.sanitize_id(base_name)
	if clean_base.is_empty():
		clean_base = "animation"
	if not animations.has(clean_base):
		return clean_base

	var index := 2
	while animations.has("%s_%d" % [clean_base, index]):
		index += 1

	return "%s_%d" % [clean_base, index]


func _get_standard_character_animation_names() -> Array:
	return [
		"idle_down",
		"walk_down",
		"idle_up",
		"walk_up",
		"idle_left",
		"walk_left",
		"idle_right",
		"walk_right",
		"idle_down_left",
		"walk_down_left",
		"idle_down_right",
		"walk_down_right",
		"idle_up_left",
		"walk_up_left",
		"idle_up_right",
		"walk_up_right",
		"attack_down",
		"attack_up",
		"attack_left",
		"attack_right",
		"interact_down",
		"interact_up",
		"interact_left",
		"interact_right",
	]


func _get_default_item_id() -> String:
	if data_store.has_record(ContentEditorData.SECTION_ITEMS, "wood"):
		return "wood"

	var records := data_store.get_records(ContentEditorData.SECTION_ITEMS)
	if records.is_empty():
		return ""

	return str(records[0].get("id", ""))


func _get_default_workstation_id() -> String:
	if data_store.has_record(ContentEditorData.SECTION_RECIPES, "workbench"):
		return "workbench"

	var records := _get_building_recipe_records()
	if records.is_empty():
		return ""

	return str(records[0].get("id", ""))


func _get_default_sprite_sheet_id() -> String:
	for sprite_record in data_store.get_records(ContentEditorData.SECTION_SPRITES):
		if str(sprite_record.get("type", "single_sprite")) == "sprite_sheet":
			return str(sprite_record.get("id", ""))

	return ""


func _get_building_recipe_records() -> Array:
	var building_recipes := []

	for recipe_record in data_store.get_records(ContentEditorData.SECTION_RECIPES):
		if str(recipe_record.get("type", "")) == "building":
			building_recipes.append(recipe_record)

	return building_recipes


func _get_sprite_categories() -> Array:
	return [
		"item",
		"monster",
		"tileset",
		"resource",
		"building",
		"terrain",
		"ui",
		"character",
		"effect",
	]


func _cleanup_optional_fields(record: Dictionary) -> void:
	for optional_field in [
		"sprite_id",
		"output_item_id",
		"building_id",
		"tool_id",
	]:
		if record.has(optional_field) and str(record.get(optional_field, "")).is_empty():
			record.erase(optional_field)


func _parse_tags(text: String) -> Array:
	var tags := []

	for raw_tag in text.split(",", false):
		var tag := raw_tag.strip_edges().to_lower()
		if tag.is_empty() or tags.has(tag):
			continue

		tags.append(tag)

	return tags


func _join_string_array(value, separator: String) -> String:
	if not value is Array:
		return ""

	var parts := []
	for entry in value:
		parts.append(str(entry))

	return _join_lines_with_separator(parts, separator)


func _stringify_value(value) -> String:
	if value is Dictionary or value is Array:
		return JSON.stringify(value)

	return str(value)


func _join_strings(values: Array, separator: String) -> String:
	return _join_lines_with_separator(values, separator)


func _join_lines_with_separator(values: Array, separator: String) -> String:
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
