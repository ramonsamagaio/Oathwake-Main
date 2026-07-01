extends Control

const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")
const SpriteSheetPreviewScript := preload("res://tools/content_editor/SpriteSheetPreview.gd")
const CombatCalculatorScript := preload("res://scripts/systems/CombatCalculator.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const MIN_WINDOW_SIZE := Vector2i(1280, 800)
const INITIAL_WINDOW_SIZE := Vector2i(1440, 900)
const BATCH_STATIC_SPRITE_IMPORT_DIR := "res://assets/sprites/static"

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
var item_resource_damage_rows := []
var resource_base_drop_rows := []
var resource_rare_drop_rows := []
var selected_workstation_id := ""
var workstation_filter := ""
var production_rows := []
var selected_sprite_id := ""
var sprite_filter := ""
var sprite_category_filter := "all"
var selected_sprite_sheet_id := ""
var sprite_sheet_filter := ""
var selected_animation_set_id := ""
var animation_set_filter := ""
var selected_animation_name := ""
var active_character_animation_name := ""
var animation_preview_playing := false
var animation_preview_elapsed := 0.0
var animation_preview_frame_index := 0
var sidebar_buttons := {}
var field_controls := {}
var combat_calculator := CombatCalculatorScript.new()

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
var character_preview_info_label: Label
var font_profile_preview_label: Label
var texture_file_dialog: FileDialog
var batch_static_sprite_button: Button
var batch_sprite_file_dialog: FileDialog
var batch_sprite_window: Window
var batch_sprite_rows := []
var batch_sprite_rows_container: VBoxContainer
var save_button: Button
var revert_button: Button
var reload_current_button: Button
var refresh_content_db_button: Button
var current_file_label: Label
var status_label: Label


func _ready() -> void:
	_configure_content_editor_window()
	_fit_root_to_viewport()
	var active_window := get_window()
	if active_window != null:
		active_window.size_changed.connect(_fit_root_to_viewport)
	_build_ui()
	set_process(true)

	var error := data_store.load_all()
	if not error.is_empty():
		_set_status(error, true)
		return

	_select_section(ContentEditorData.SECTION_ITEMS, true)


func _configure_content_editor_window() -> void:
	# Keep the editor resizable without forcing a minimum size that can clip
	# when Godot runs the scene inside a smaller debug viewport.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	var window := get_window()
	if window != null:
		window.min_size = MIN_WINDOW_SIZE
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		window.content_scale_size = Vector2i.ZERO

	var current_size := DisplayServer.window_get_size()
	if current_size.x < INITIAL_WINDOW_SIZE.x or current_size.y < INITIAL_WINDOW_SIZE.y:
		DisplayServer.window_set_size(INITIAL_WINDOW_SIZE)


func _fit_root_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT, false)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	position = Vector2.ZERO
	size = _get_editor_available_size()


func _get_editor_available_size() -> Vector2:
	var available_size := get_viewport_rect().size
	var window := get_window()
	if window != null:
		var window_size := Vector2(window.size)
		if window_size.x > available_size.x or window_size.y > available_size.y:
			available_size = window_size

	return available_size


func _process(delta: float) -> void:
	if not animation_preview_playing:
		return
	if current_section != ContentEditorData.SECTION_ANIMATION_SETS and current_section != ContentEditorData.SECTION_CHARACTERS:
		return

	var frames: Array = _get_current_preview_frames()
	if frames.is_empty():
		return

	var fps: float = max(_get_current_preview_fps(), 0.01)
	animation_preview_elapsed += delta
	if animation_preview_elapsed < 1.0 / fps:
		return

	animation_preview_elapsed = 0.0
	animation_preview_frame_index += 1
	if animation_preview_frame_index >= frames.size():
		if _get_current_preview_loop():
			animation_preview_frame_index = 0
		else:
			animation_preview_frame_index = frames.size() - 1
			animation_preview_playing = false

	_update_current_preview_frame()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var margin_container := MarginContainer.new()
	margin_container.name = "MarginContainer"
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 12)
	margin_container.add_theme_constant_override("margin_top", 12)
	margin_container.add_theme_constant_override("margin_right", 12)
	margin_container.add_theme_constant_override("margin_bottom", 12)
	add_child(margin_container)

	var main_layout := HSplitContainer.new()
	main_layout.name = "MainLayout"
	main_layout.split_offset = 160
	main_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_child(main_layout)

	_build_sidebar(main_layout)

	var content_split := HSplitContainer.new()
	content_split.name = "ContentSplit"
	content_split.split_offset = 460
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_layout.add_child(content_split)

	_build_record_panel(content_split)
	_build_form_panel(content_split)


func _build_sidebar(parent: Node) -> void:
	var sidebar := VBoxContainer.new()
	sidebar.name = "Sidebar"
	sidebar.custom_minimum_size = Vector2(140, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	panel.custom_minimum_size = Vector2(240, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	batch_static_sprite_button = Button.new()
	batch_static_sprite_button.name = "BatchStaticSpriteButton"
	batch_static_sprite_button.text = "Batch Static Sprites"
	batch_static_sprite_button.tooltip_text = "Import multiple static sprite PNGs/JPGs/WebPs/SVGs into the Sprites section."
	batch_static_sprite_button.pressed.connect(_on_batch_static_sprite_pressed)
	action_row.add_child(batch_static_sprite_button)


func _build_form_panel(parent: Node) -> void:
	var panel := VBoxContainer.new()
	panel.name = "FormPanel"
	panel.custom_minimum_size = Vector2(360, 0)
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
	form_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	batch_sprite_file_dialog = FileDialog.new()
	batch_sprite_file_dialog.name = "BatchStaticSpriteFileDialog"
	batch_sprite_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	batch_sprite_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	batch_sprite_file_dialog.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg, *.jpeg ; JPEG Images",
		"*.webp ; WebP Images",
		"*.svg ; SVG Images",
	])
	batch_sprite_file_dialog.files_selected.connect(_on_batch_static_sprite_files_selected)
	add_child(batch_sprite_file_dialog)


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
	item_resource_damage_rows.clear()
	selected_workstation_id = ""
	workstation_filter = ""
	production_rows.clear()
	selected_sprite_id = ""
	sprite_filter = ""
	selected_sprite_sheet_id = ""
	sprite_sheet_filter = ""
	selected_animation_set_id = ""
	animation_set_filter = ""
	selected_animation_name = ""
	active_character_animation_name = ""
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
	if current_section == ContentEditorData.SECTION_COMBAT_PREVIEW:
		_build_combat_preview_form()
	elif current_section == ContentEditorData.SECTION_PLAYER_TUNING and data_store.has_record(ContentEditorData.SECTION_PLAYER_TUNING, "default"):
		_load_record("default")
		return
	elif current_section == ContentEditorData.SECTION_VFX_PROFILES and data_store.has_record(ContentEditorData.SECTION_VFX_PROFILES, "default"):
		_load_record("default")
		return
	else:
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
	selected_animation_set_id = str(current_record.get("animation_set_id", ""))
	animation_set_filter = ""
	selected_animation_name = _get_first_animation_name(current_record)
	active_character_animation_name = ""
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
		ContentEditorData.SECTION_CHARACTERS:
			_build_character_form()
		ContentEditorData.SECTION_TIERS:
			_build_tier_form()
		ContentEditorData.SECTION_PLAYER_TUNING:
			_build_player_tuning_form()
		ContentEditorData.SECTION_FONT_PROFILES:
			_build_font_profile_form()
		ContentEditorData.SECTION_VFX_PROFILES:
			_build_vfx_profile_form()
		ContentEditorData.SECTION_COMBAT_PREVIEW:
			_build_combat_preview_form()
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
	_add_text_edit("Description", "description", str(current_record.get("description", "")), 100)
	_add_spin_box("Stack Size", "stack_size", int(current_record.get("stack_size", 999)), 1, 999999, 1)
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_item_type_option_button(str(current_record.get("item_type", "material")))
	_add_spin_box("Tier", "tier", int(current_record.get("tier", 1)), 1, 99, 1)
	_add_material_family_option_button(str(current_record.get("material_family", "misc")))
	_add_line_edit("Tags", "tags", _join_string_array(current_record.get("tags", []), ", "))

	var item_type: String = str(current_record.get("item_type", "material"))
	var is_equippable := item_type == "weapon" or item_type == "tool" or item_type == "armor" or item_type == "accessory"

	if is_equippable:
		_add_equipment_slot_option_button(str(current_record.get("equipment_slot", item_type)))
		_add_equipment_stats_bonus_editor()

	if item_type == "weapon" or item_type == "tool":
		_add_tool_progression_editor()
		_add_item_combat_editor(item_type)

	if item_type == "armor":
		_add_armor_editor()

	if item_type == "accessory":
		_add_accessory_editor()


func _build_resource_form() -> void:
	form_title_label.text = "Resource: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_spin_box("Max Health", "max_health", int(current_record.get("max_health", 20)), 1, 999999, 1)
	_add_drop_item_picker(str(current_record.get("drop_item_id", "wood")))
	_add_spin_box("Drop Amount", "drop_amount", int(current_record.get("drop_amount", 1)), 1, 999999, 1)
	_add_spin_box("Respawn Time Seconds", "respawn_time_seconds", int(current_record.get("respawn_time_seconds", 60)), 0, 999999, 1)
	_add_spin_box("Resource Tier", "resource_tier", int(current_record.get("resource_tier", 1)), 1, 7, 1)
	_add_spin_box("Resource HP", "resource_hp", int(current_record.get("resource_hp", current_record.get("max_health", 20))), 1, 999999, 1)
	_add_tool_type_option_button("Required Tool Type", "required_tool_type", str(current_record.get("required_tool_type", "axe")))
	_add_check_box("Allow Hands (harvest without tool)", "allow_hands", bool(current_record.get("allow_hands", true)))
	_add_skill_type_option_button(str(current_record.get("skill_type", "lumbering")))
	_add_spin_box("XP Reward", "xp_reward", int(current_record.get("xp_reward", 0)), 0, 999999, 1)
	_add_drop_table_editor("Base Drops", "base_drops", current_record.get("base_drops", []))
	_add_drop_table_editor("Rare Drops", "rare_drops", current_record.get("rare_drops", []))


func _build_tier_form() -> void:
	form_title_label.text = "Tier: %s" % str(current_record.get("id", ""))
	_add_spin_box("ID", "id", int(current_record.get("id", int(str(current_record.get("id", "1"))))), 1, 99, 1)
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_line_edit("Theme", "theme", str(current_record.get("theme", "")))
	_add_line_edit("Region", "region", str(current_record.get("region", "")))
	_add_line_edit("Boss", "boss", str(current_record.get("boss", "")))
	_add_line_edit("Primary Material", "primary_material", str(current_record.get("primary_material", "")))
	_add_line_edit("Metal Material", "metal_material", str(current_record.get("metal_material", "")))
	_add_line_edit("Secondary Material", "secondary_material", str(current_record.get("secondary_material", "")))
	_add_line_edit("Wood Material", "wood_material", str(current_record.get("wood_material", "")))
	_add_line_edit("Cloth Material", "cloth_material", str(current_record.get("cloth_material", "")))
	_add_line_edit("Tool Material", "tool_material", str(current_record.get("tool_material", "")))
	_add_line_edit("Weapon Material", "weapon_material", str(current_record.get("weapon_material", "")))
	_add_line_edit("Armor Material", "armor_material", str(current_record.get("armor_material", "")))

	var budget = current_record.get("power_budget", {})
	if not budget is Dictionary:
		budget = {}
	_add_read_only_value("Balance Note", "Power Budget controls default tier targets used to normalize tools, resources, monsters, repair and storage.")
	_add_spin_box("Budget Tool Damage", "budget_tool_damage", int(budget.get("tool_damage", 8)), 0, 999999, 1)
	_add_spin_box("Budget Tool Durability", "budget_tool_durability", int(budget.get("tool_durability", 90)), 0, 999999, 1)
	_add_spin_box("Budget Tree HP", "budget_resource_hp_tree", int(budget.get("resource_hp_tree", 22)), 0, 999999, 1)
	_add_spin_box("Budget Rock/Ore HP", "budget_resource_hp_ore_or_rock", int(budget.get("resource_hp_ore_or_rock", 28)), 0, 999999, 1)
	_add_spin_box("Budget XP Reward", "budget_xp_reward", int(budget.get("xp_reward", 10)), 0, 999999, 1)
	_add_float_spin_box("Budget Crit Chance", "budget_crit_chance", float(budget.get("crit_chance", 0.01)), 0.0, 1.0, 0.001)
	_add_float_spin_box("Budget Crit Power", "budget_crit_power", float(budget.get("crit_power", 1.5)), 1.0, 5.0, 0.01)
	_add_float_spin_box("Budget Attack Cooldown", "budget_attack_cooldown", float(budget.get("attack_cooldown", 1.0)), 0.1, 10.0, 0.01)
	_add_float_spin_box("Budget Repair Multiplier", "budget_repair_cost_multiplier", float(budget.get("repair_cost_multiplier", 0.45)), 0.0, 10.0, 0.01)
	_add_spin_box("Budget Storage Slots", "budget_storage_slots", int(budget.get("storage_slots", 20)), 1, 999, 1)
	_add_spin_box("Budget Monster HP", "budget_monster_hp_target", int(budget.get("monster_hp_target", 40)), 1, 999999, 1)
	_add_spin_box("Budget Monster Damage", "budget_monster_damage_target", int(budget.get("monster_damage_target", 4)), 0, 999999, 1)
	_add_spin_box("Budget Resource Respawn", "budget_resource_respawn_seconds", int(budget.get("resource_respawn_seconds", 45)), 0, 999999, 1)
	_add_line_edit("Progression Rule", "progression_rule", str(current_record.get("progression_rule", "")))
	_add_text_edit("Early Access Role", "early_access_role", str(current_record.get("early_access_role", "")), 80)


func _build_player_tuning_form() -> void:
	form_title_label.text = "Player Tuning: default"
	_add_read_only_value("ID", "default")
	_add_float_spin_box("Walk Speed", "walk_speed", float(current_record.get("walk_speed", 80.0)), 0.0, 999999.0, 1.0)
	_add_float_spin_box("Run Speed", "run_speed", float(current_record.get("run_speed", 130.0)), 0.0, 999999.0, 1.0)
	_add_float_spin_box("Acceleration", "acceleration", float(current_record.get("acceleration", 720.0)), 0.0, 999999.0, 1.0)
	_add_float_spin_box("Deceleration", "deceleration", float(current_record.get("deceleration", 980.0)), 0.0, 999999.0, 1.0)
	_add_float_spin_box("Run Stop Slide Time", "run_stop_slide_time", float(current_record.get("run_stop_slide_time", 0.18)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Run Stop Slide Strength", "run_stop_slide_strength", float(current_record.get("run_stop_slide_strength", 0.50)), 0.0, 1.0, 0.01)
	_add_check_box("Smoke Puff Enabled", "smoke_puff_enabled", bool(current_record.get("smoke_puff_enabled", true)))
	_add_float_spin_box("Smoke Puff Cooldown", "smoke_puff_cooldown", float(current_record.get("smoke_puff_cooldown", 0.28)), 0.0, 10.0, 0.01)


func _build_font_profile_form() -> void:
	form_title_label.text = "Font Profile: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_font_path_picker(str(current_record.get("font_path", "")))
	_add_spin_box("Font Size", "font_size", int(current_record.get("font_size", 14)), 1, 256, 1)
	_add_line_edit("Font Color", "font_color", str(current_record.get("font_color", "#FFFFFF")))
	_add_spin_box("Outline Size", "outline_size", int(current_record.get("outline_size", 0)), 0, 32, 1)
	_add_line_edit("Outline Color", "outline_color", str(current_record.get("outline_color", "#000000")))

	font_profile_preview_label = Label.new()
	font_profile_preview_label.text = "Oathwake 123 CRIT +XP"
	font_profile_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	font_profile_preview_label.custom_minimum_size = Vector2(0, 64)
	form_container.add_child(font_profile_preview_label)

	var update_preview_button := Button.new()
	update_preview_button.text = "Update Preview"
	update_preview_button.pressed.connect(_update_font_profile_preview)
	form_container.add_child(update_preview_button)

	for field_name in ["display_name", "font_color", "outline_color"]:
		if field_controls.has(field_name):
			var line_edit: LineEdit = field_controls[field_name]
			line_edit.text_changed.connect(func(_new_text: String) -> void: _update_font_profile_preview())
	for field_name in ["font_size", "outline_size"]:
		if field_controls.has(field_name):
			var spin_box: SpinBox = field_controls[field_name]
			spin_box.value_changed.connect(func(_new_value: float) -> void: _update_font_profile_preview())

	_update_font_profile_preview()


func _build_vfx_profile_form() -> void:
	form_title_label.text = "VFX Profile: %s" % str(current_record.get("id", "default"))
	_add_read_only_value("ID", "default")
	_add_float_spin_box("Critical Shake Strength", "critical_shake_strength", float(current_record.get("critical_shake_strength", 2.8)), 0.0, 999.0, 0.01)
	_add_float_spin_box("Critical Shake Duration", "critical_shake_duration", float(current_record.get("critical_shake_duration", 0.14)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Tree Wind Strength", "tree_wind_strength", float(current_record.get("tree_wind_strength", 1.5)), 0.0, 999.0, 0.01)
	_add_float_spin_box("Tree Wind Speed", "tree_wind_speed", float(current_record.get("tree_wind_speed", 1.2)), 0.0, 999.0, 0.01)
	_add_float_spin_box("Smoke Puff Lifetime", "smoke_puff_lifetime", float(current_record.get("smoke_puff_lifetime", 0.35)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Smoke Puff Scale", "smoke_puff_scale", float(current_record.get("smoke_puff_scale", 1.2)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Floating Text Duration", "floating_text_duration", float(current_record.get("floating_text_duration", 1.45)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Critical Text Duration", "critical_text_duration", float(current_record.get("critical_text_duration", 1.6)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Hit Flash Duration", "hit_flash_duration", float(current_record.get("hit_flash_duration", 0.10)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Critical Hit Flash Duration", "critical_hit_flash_duration", float(current_record.get("critical_hit_flash_duration", 0.14)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Hit Bump Scale", "hit_bump_scale", float(current_record.get("hit_bump_scale", 1.04)), 0.0, 10.0, 0.01)
	_add_float_spin_box("Critical Bump Scale", "critical_bump_scale", float(current_record.get("critical_bump_scale", 1.08)), 0.0, 10.0, 0.01)


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
	_add_string_option_button("Workstation", "workstation", ["basic", "workbench", "furnace", "anvil", "cooking_fire", "alchemy_table"], str(current_record.get("workstation", "workbench")))
	_add_spin_box("Tier", "tier", int(current_record.get("tier", 1)), 1, 7, 1)
	_add_output_item_picker(str(current_record.get("output_item_id", current_record.get("id", ""))))
	_add_spin_box("Output Amount", "output_amount", int(current_record.get("output_amount", 1)), 1, 999, 1)
	_add_sprite_picker(str(current_record.get("sprite_id", "")))
	_add_skill_type_option_button(str(current_record.get("skill_type", "lumbering")))
	_add_spin_box("XP Reward", "xp_reward", int(current_record.get("xp_reward", 0)), 0, 999999, 1)
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
	_add_preview_zoom_option("sheet_preview_zoom", _on_sheet_preview_zoom_selected)
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


func _build_character_form() -> void:
	form_title_label.text = "Character: %s" % str(current_record.get("id", ""))
	_add_line_edit("ID", "id", str(current_record.get("id", "")))
	_add_line_edit("Display Name", "display_name", str(current_record.get("display_name", "")))
	_add_sprite_sheet_picker(str(current_record.get("sprite_sheet_id", _get_default_sprite_sheet_id())))
	_add_animation_set_picker(str(current_record.get("animation_set_id", _get_default_character_animation_set_id())))

	var update_button := Button.new()
	update_button.text = "Create/Update Animation Set From Character"
	update_button.pressed.connect(_on_create_or_update_character_animation_set_pressed)
	form_container.add_child(update_button)

	var required_button := Button.new()
	required_button.text = "Create Required 4-Direction Animations"
	required_button.pressed.connect(_on_create_required_character_animations_pressed)
	form_container.add_child(required_button)

	_add_character_animation_setup()


func _build_combat_preview_form() -> void:
	_clear_form()
	form_title_label.text = "Combat Preview"
	current_file_label.text = "Uses CombatCalculator with content data."

	_add_combat_type_option("Attacker Type", "combat_attacker_type", "character", _on_combat_attacker_type_selected)
	_add_combat_actor_option("Attacker", "combat_attacker", "combat_attacker_type")
	_add_combat_type_option("Target Type", "combat_target_type", "monster", _on_combat_target_type_selected)
	_add_combat_actor_option("Target", "combat_target", "combat_target_type")
	_add_combat_weapon_option()

	var row := HBoxContainer.new()
	form_container.add_child(row)

	var calculate_button := Button.new()
	calculate_button.text = "Calculate Once"
	calculate_button.pressed.connect(_on_combat_calculate_once_pressed)
	row.add_child(calculate_button)

	var simulate_button := Button.new()
	simulate_button.text = "Simulate 100 Hits"
	simulate_button.pressed.connect(_on_combat_simulate_100_pressed)
	row.add_child(simulate_button)

	var results := Label.new()
	results.text = "Choose attacker, target, and weapon."
	results.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(results)
	field_controls["combat_results"] = results


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


func _add_font_path_picker(value: String) -> void:
	var options := _get_available_font_paths()
	if not value.is_empty() and not options.has(value):
		options.append(value)

	var option_button := OptionButton.new()
	option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option_button.add_item("Default / Fallback")
	option_button.set_item_metadata(0, "")
	var selected_index := 0
	for font_path in options:
		var index := option_button.item_count
		option_button.add_item(font_path)
		option_button.set_item_metadata(index, font_path)
		if font_path == value:
			selected_index = index
	option_button.select(selected_index)
	option_button.item_selected.connect(func(_index: int) -> void:
		_mark_dirty()
		_update_font_profile_preview()
	)
	_add_form_row("Select Font", option_button)
	field_controls["font_path"] = option_button


func _get_available_font_paths() -> Array:
	var font_paths := []
	var fonts_dir := DirAccess.open("res://assets/fonts")
	if fonts_dir == null:
		return font_paths

	fonts_dir.list_dir_begin()
	var file_name := fonts_dir.get_next()
	while not file_name.is_empty():
		if not fonts_dir.current_is_dir():
			var lower := file_name.to_lower()
			if lower.ends_with(".ttf") or lower.ends_with(".otf") or lower.ends_with(".fnt"):
				font_paths.append("res://assets/fonts/%s" % file_name)
		file_name = fonts_dir.get_next()
	fonts_dir.list_dir_end()
	font_paths.sort()
	return font_paths


func _add_check_box(label_text: String, field_name: String, value: bool) -> CheckBox:
	var check_box := CheckBox.new()
	check_box.button_pressed = value
	check_box.toggled.connect(func(_is_pressed: bool) -> void: _mark_dirty())
	_add_form_row(label_text, check_box)
	field_controls[field_name] = check_box
	return check_box


func _add_float_spin_box(label_text: String, field_name: String, value: float, minimum: float, maximum: float, step: float) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.min_value = minimum
	spin_box.max_value = maximum
	spin_box.step = step
	spin_box.value = value
	spin_box.value_changed.connect(func(_new_value: float) -> void: _mark_dirty())
	_add_form_row(label_text, spin_box)
	field_controls[field_name] = spin_box
	return spin_box


func _add_string_option_button(label_text: String, field_name: String, options: Array, initial_value: String, callback: Callable = Callable()) -> OptionButton:
	var option_button := OptionButton.new()
	var selected_index := 0
	if not options.has(initial_value):
		options.append(initial_value)

	for option_value in options:
		var index := option_button.item_count
		option_button.add_item(str(option_value))
		option_button.set_item_metadata(index, str(option_value))
		if str(option_value) == initial_value:
			selected_index = index

	option_button.select(selected_index)
	if callback.is_valid():
		option_button.item_selected.connect(callback)
	else:
		option_button.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row(label_text, option_button)
	field_controls[field_name] = option_button
	return option_button


func _add_material_family_option_button(initial_family: String) -> void:
	_add_string_option_button("Material Family", "material_family", ["wood", "ore", "ingot", "cloth", "fiber", "herb", "gem", "catalyst", "food", "monster_part", "misc"], initial_family)


func _add_tool_type_option_button(label_text: String, field_name: String, initial_type: String) -> void:
	_add_string_option_button(label_text, field_name, ["hands", "axe", "pickaxe", "hoe", "sickle", "hammer", "watering_can"], initial_type)


func _add_skill_type_option_button(initial_type: String) -> void:
	_add_string_option_button("Skill Type", "skill_type", ["mining", "lumbering", "farming", "smithing", "cooking", "alchemy"], initial_type)


func _add_tool_progression_editor() -> void:
	var title := Label.new()
	title.text = "Tool Progression"
	form_container.add_child(title)

	_add_tool_type_option_button("Tool Type", "tool_type", str(current_record.get("tool_type", "hands")))
	_add_spin_box("Tool Tier", "tool_tier", int(current_record.get("tool_tier", current_record.get("tier", 1))), 1, 7, 1)
	_add_spin_box("Tool Damage", "tool_damage", int(current_record.get("tool_damage", 0)), 0, 999999, 1)
	_add_float_spin_box("Tool Speed", "tool_speed", float(current_record.get("tool_speed", 1.0)), 0.01, 999999.0, 0.01)
	_add_spin_box("Durability", "durability", int(current_record.get("durability", 0)), 0, 999999, 1)
	_add_float_spin_box("Repair Cost Multiplier", "repair_cost_multiplier", float(current_record.get("repair_cost_multiplier", 0.5)), 0.0, 10.0, 0.05)
	_add_check_box("Can Repair", "can_repair", bool(current_record.get("can_repair", true)))
	_add_float_spin_box("Crit Chance", "crit_chance", float(current_record.get("crit_chance", 0.0)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Crit Power", "crit_power", float(current_record.get("crit_power", 1.5)), 1.0, 999999.0, 0.01)


func _add_item_combat_editor(item_type: String) -> void:
	var title := Label.new()
	title.text = "Combat"
	form_container.add_child(title)

	var combat: Dictionary = _get_record_dictionary(current_record, "combat")
	_add_spin_box("Attack Power", "combat_attack_power", int(combat.get("attack_power", 0)), 0, 999999, 1)
	_add_float_spin_box("Attack Variance", "combat_attack_variance", float(combat.get("attack_variance", 0.15)), 0.0, 1.0, 0.01)
	_add_damage_type_option_button(str(combat.get("damage_type", "physical")))
	_add_float_spin_box("Crit Chance Bonus", "combat_crit_chance_bonus", float(combat.get("crit_chance_bonus", 0.0)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Crit Damage Bonus", "combat_crit_damage_bonus", float(combat.get("crit_damage_bonus", 0.0)), 0.0, 999999.0, 0.01)
	_add_float_spin_box("Attack Cooldown Modifier", "combat_attack_cooldown_modifier", float(combat.get("attack_cooldown_modifier", 1.0)), 0.01, 999999.0, 0.01)
	_add_check_box("Can Hit Monsters", "combat_can_hit_monsters", bool(combat.get("can_hit_monsters", true)))
	_add_check_box("Can Hit Resources", "combat_can_hit_resources", bool(combat.get("can_hit_resources", item_type == "tool")))

	var scaling_title := Label.new()
	scaling_title.text = "Stat Scaling"
	form_container.add_child(scaling_title)

	var stat_scaling: Dictionary = _get_record_dictionary(combat, "stat_scaling")
	for stat_name in ["str", "dex", "agi", "vit", "wis", "int", "luk"]:
		_add_float_spin_box("%s Scaling" % stat_name.to_upper(), "scaling_%s" % stat_name, float(stat_scaling.get(stat_name, 0.0)), 0.0, 999999.0, 0.05)

	if item_type == "tool":
		_add_resource_damage_editor(_get_record_dictionary(combat, "resource_damage"))

	_add_item_combat_preview()


func _add_resource_damage_editor(resource_damage: Dictionary) -> void:
	var title := Label.new()
	title.text = "Resource Damage"
	form_container.add_child(title)

	item_resource_damage_rows.clear()
	for resource_type_id in resource_damage.keys():
		item_resource_damage_rows.append({
			"resource_type_id": str(resource_type_id),
			"damage": int(resource_damage[resource_type_id]),
		})

	_rebuild_resource_damage_rows()

	var add_button := Button.new()
	add_button.text = "Add Resource Damage"
	add_button.pressed.connect(_on_add_resource_damage_pressed)
	form_container.add_child(add_button)


func _rebuild_resource_damage_rows() -> void:
	for row_index in range(item_resource_damage_rows.size()):
		_add_resource_damage_row(row_index)


func _add_resource_damage_row(row_index: int) -> void:
	var row_data: Dictionary = item_resource_damage_rows[row_index]
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = "Resource Damage"
	label.custom_minimum_size = Vector2(160, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var option_button := OptionButton.new()
	option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_resource_type_option(option_button, str(row_data.get("resource_type_id", "")))
	option_button.item_selected.connect(func(selected_index: int) -> void: _on_resource_damage_resource_selected(selected_index, row_index, option_button))
	row.add_child(option_button)

	var spin_box := SpinBox.new()
	spin_box.min_value = 0
	spin_box.max_value = 999999
	spin_box.step = 1
	spin_box.value = int(row_data.get("damage", 0))
	spin_box.custom_minimum_size = Vector2(100, 0)
	spin_box.value_changed.connect(func(new_value: float) -> void: _on_resource_damage_value_changed(new_value, row_index))
	row.add_child(spin_box)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(func() -> void: _on_remove_resource_damage_pressed(row_index))
	row.add_child(remove_button)

	form_container.add_child(row)


func _populate_resource_type_option(option_button: OptionButton, selected_resource_id: String) -> void:
	var selected_index := 0
	for resource_record in data_store.get_records(ContentEditorData.SECTION_RESOURCES):
		var resource_id := str(resource_record.get("id", ""))
		var display_name := str(resource_record.get("display_name", resource_id))
		var index := option_button.item_count
		option_button.add_item("%s - %s" % [resource_id, display_name])
		option_button.set_item_metadata(index, resource_id)
		if resource_id == selected_resource_id:
			selected_index = index

	if option_button.item_count > 0:
		option_button.select(selected_index)


func _add_item_combat_preview() -> void:
	var preview := Label.new()
	preview.text = _make_item_combat_preview_text()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(preview)


func _add_drop_table_editor(label_text: String, field_name: String, drops_value: Variant) -> void:
	var title := Label.new()
	title.text = label_text
	form_container.add_child(title)

	var rows := _get_drop_rows(field_name)
	rows.clear()
	if drops_value is Array:
		for drop_entry in drops_value:
			if drop_entry is Dictionary:
				rows.append((drop_entry as Dictionary).duplicate(true))

	for row_index in range(rows.size()):
		_add_drop_table_row(field_name, row_index)

	var add_button := Button.new()
	add_button.text = "Add %s" % label_text.trim_suffix("s")
	add_button.pressed.connect(func() -> void: _on_add_drop_row_pressed(field_name))
	form_container.add_child(add_button)


func _add_drop_table_row(field_name: String, row_index: int) -> void:
	var rows := _get_drop_rows(field_name)
	var row_data: Dictionary = rows[row_index]
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = field_name.capitalize()
	label.custom_minimum_size = Vector2(160, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	var item_option := OptionButton.new()
	item_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_item_option(item_option, str(row_data.get("item_id", _get_default_item_id())))
	item_option.item_selected.connect(func(selected_index: int) -> void: _on_drop_row_item_selected(field_name, row_index, selected_index, item_option))
	row.add_child(item_option)

	var min_spin := _make_inline_spin_box(int(row_data.get("min_amount", 1)), 1, 999999, 1)
	min_spin.value_changed.connect(func(new_value: float) -> void: _on_drop_row_number_changed(field_name, row_index, "min_amount", new_value))
	row.add_child(min_spin)

	var max_spin := _make_inline_spin_box(int(row_data.get("max_amount", 1)), 1, 999999, 1)
	max_spin.value_changed.connect(func(new_value: float) -> void: _on_drop_row_number_changed(field_name, row_index, "max_amount", new_value))
	row.add_child(max_spin)

	var chance_spin := _make_inline_spin_box(float(row_data.get("chance", 1.0)), 0.0, 1.0, 0.01)
	chance_spin.value_changed.connect(func(new_value: float) -> void: _on_drop_row_number_changed(field_name, row_index, "chance", new_value))
	row.add_child(chance_spin)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(func() -> void: _on_remove_drop_row_pressed(field_name, row_index))
	row.add_child(remove_button)

	form_container.add_child(row)


func _make_inline_spin_box(value: float, minimum: float, maximum: float, step: float) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.min_value = minimum
	spin_box.max_value = maximum
	spin_box.step = step
	spin_box.value = value
	spin_box.custom_minimum_size = Vector2(82, 0)
	return spin_box


func _populate_item_option(option_button: OptionButton, selected_item_id: String) -> void:
	var selected_index := 0
	for item_record in data_store.get_records(ContentEditorData.SECTION_ITEMS):
		var item_id := str(item_record.get("id", ""))
		var display_name := str(item_record.get("display_name", item_id))
		var index := option_button.item_count
		option_button.add_item("%s - %s" % [item_id, display_name])
		option_button.set_item_metadata(index, item_id)
		if item_id == selected_item_id:
			selected_index = index

	if option_button.item_count > 0:
		option_button.select(selected_index)


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


func _add_output_item_picker(initial_item_id: String) -> void:
	var option_button := OptionButton.new()
	_populate_item_option(option_button, initial_item_id)
	_add_form_row("Output Item", option_button)
	field_controls["output_item_id"] = option_button


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


func _add_animation_set_picker(initial_animation_set_id: String) -> void:
	selected_animation_set_id = initial_animation_set_id

	var search := LineEdit.new()
	search.placeholder_text = "Search animation set by id or display name"
	search.text = animation_set_filter
	search.text_changed.connect(_on_animation_set_filter_changed)
	_add_form_row("Animation Set Search", search)
	field_controls["animation_set_search"] = search

	var option_button := OptionButton.new()
	option_button.item_selected.connect(_on_animation_set_selected)
	_add_form_row("Animation Set", option_button)
	field_controls["animation_set_id"] = option_button
	_refresh_animation_set_options()


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
	_add_preview_zoom_option("animation_grid_zoom", _on_animation_grid_zoom_selected)

	animation_grid_preview = SpriteSheetPreviewScript.new()
	animation_grid_preview.custom_minimum_size = Vector2(320, 320)
	animation_grid_preview.set_fit_minimum_size(Vector2(320, 320))
	animation_grid_preview.set_zoom_scale(_get_preview_zoom_scale("animation_grid_zoom"))
	animation_grid_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_grid_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	animation_grid_preview.frame_clicked.connect(_on_animation_grid_frame_clicked)
	_add_scrollable_preview_row("Frame Grid", animation_grid_preview)
	_update_animation_grid_preview()

	animation_preview_rect = TextureRect.new()
	animation_preview_rect.custom_minimum_size = Vector2(180, 180)
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


func _add_character_animation_setup() -> void:
	var title := Label.new()
	title.text = "Character Animation Setup"
	form_container.add_child(title)

	_add_character_direction_mode_option()

	var validate_button := Button.new()
	validate_button.text = "Validate Character Animations"
	validate_button.pressed.connect(_on_validate_character_animations_pressed)
	form_container.add_child(validate_button)

	_add_character_animation_tools()

	for animation_name in _get_character_animation_slot_names():
		_add_character_animation_slot(animation_name)

	_add_preview_zoom_option("character_grid_zoom", _on_character_grid_zoom_selected)
	animation_grid_preview = SpriteSheetPreviewScript.new()
	animation_grid_preview.custom_minimum_size = Vector2(320, 320)
	animation_grid_preview.set_fit_minimum_size(Vector2(320, 320))
	animation_grid_preview.set_zoom_scale(_get_preview_zoom_scale("character_grid_zoom"))
	animation_grid_preview.frame_clicked.connect(_on_character_grid_frame_clicked)
	_add_scrollable_preview_row("Character Frame Grid", animation_grid_preview)
	_update_character_grid_preview()

	animation_preview_rect = TextureRect.new()
	animation_preview_rect.custom_minimum_size = Vector2(180, 180)
	animation_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_add_form_row("Character Preview", animation_preview_rect)
	_update_character_preview_frame()
	_add_character_preview_controls()


func _add_character_animation_slot(animation_name: String) -> void:
	var animation_data := _get_character_animation_data(animation_name)
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_container.add_child(row)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(header)

	var title := Label.new()
	title.text = animation_name
	title.custom_minimum_size = Vector2(130, 0)
	header.add_child(title)

	var select_button := Button.new()
	select_button.text = "Select Frames"
	select_button.pressed.connect(_on_select_character_animation_pressed.bind(animation_name))
	header.add_child(select_button)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_character_animation_pressed.bind(animation_name))
	header.add_child(clear_button)

	var preview_button := Button.new()
	preview_button.text = "Preview"
	preview_button.pressed.connect(_on_preview_character_animation_pressed.bind(animation_name))
	header.add_child(preview_button)

	var values := HBoxContainer.new()
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(values)
	_add_character_slot_spin_box(values, animation_name, "frame_count", "Count", int(animation_data.get("frame_count", _get_default_character_frame_count(animation_name))), 1, 64)
	_add_character_slot_spin_box(values, animation_name, "fps", "FPS", int(animation_data.get("fps", _get_default_animation_fps(animation_name))), 1, 60)
	_add_character_slot_loop(values, animation_name, bool(animation_data.get("loop", true)))

	var frames_label := Label.new()
	frames_label.text = "Frames: [%s]" % _join_string_array(animation_data.get("frames", []), ", ")
	frames_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(frames_label)

	var status_label := Label.new()
	status_label.text = "Status: %s" % _get_character_animation_status(animation_name, animation_data)
	row.add_child(status_label)

	var warning := _get_character_animation_warning(animation_name, animation_data)
	if not warning.is_empty():
		var warning_label := Label.new()
		warning_label.text = warning
		warning_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
		row.add_child(warning_label)


func _add_character_slot_spin_box(parent: Node, animation_name: String, property_name: String, label_text: String, value: int, minimum: int, maximum: int) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var spin_box := SpinBox.new()
	spin_box.min_value = minimum
	spin_box.max_value = maximum
	spin_box.step = 1
	spin_box.value = value
	spin_box.value_changed.connect(_on_character_slot_spin_value_changed.bind(animation_name, property_name))
	parent.add_child(spin_box)


func _add_character_slot_loop(parent: Node, animation_name: String, value: bool) -> void:
	var check_box := CheckBox.new()
	check_box.text = "Loop"
	check_box.button_pressed = value
	check_box.toggled.connect(_on_character_slot_loop_changed.bind(animation_name))
	parent.add_child(check_box)


func _add_character_direction_mode_option() -> void:
	var option_button := OptionButton.new()
	var modes := {
		"4 Directions": "4dir",
		"8 Directions": "8dir",
	}
	var selected_mode := _get_character_direction_mode()
	var selected_index := 0
	for label in modes.keys():
		var index := option_button.item_count
		option_button.add_item(label)
		option_button.set_item_metadata(index, modes[label])
		if str(modes[label]) == selected_mode:
			selected_index = index
	option_button.select(selected_index)
	option_button.item_selected.connect(_on_character_direction_mode_selected)
	_add_form_row("Direction Mode", option_button)
	field_controls["character_direction_mode"] = option_button


func _add_character_animation_tools() -> void:
	var row := HBoxContainer.new()
	form_container.add_child(row)

	var clear_button := Button.new()
	clear_button.text = "Clear Current Animation"
	clear_button.pressed.connect(_on_clear_current_character_animation_pressed)
	row.add_child(clear_button)

	var reset_fps_button := Button.new()
	reset_fps_button.text = "Reset FPS Defaults"
	reset_fps_button.pressed.connect(_on_reset_character_fps_defaults_pressed)
	row.add_child(reset_fps_button)

	var reset_count_button := Button.new()
	reset_count_button.text = "Reset Frame Count Defaults"
	reset_count_button.pressed.connect(_on_reset_character_frame_count_defaults_pressed)
	row.add_child(reset_count_button)

	_add_character_copy_tool()
	_add_character_row_tool()
	_add_character_range_tool()


func _add_character_copy_tool() -> void:
	var row := HBoxContainer.new()
	form_container.add_child(row)

	var label := Label.new()
	label.text = "Copy Frames From"
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)

	var option_button := OptionButton.new()
	for animation_name in _get_character_available_animation_names():
		var index := option_button.item_count
		option_button.add_item(animation_name)
		option_button.set_item_metadata(index, animation_name)
	option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option_button)
	field_controls["character_copy_source"] = option_button

	var mode_button := OptionButton.new()
	for mode in ["replace", "append"]:
		var index := mode_button.item_count
		mode_button.add_item(mode.capitalize())
		mode_button.set_item_metadata(index, mode)
	row.add_child(mode_button)
	field_controls["character_apply_mode"] = mode_button

	var copy_button := Button.new()
	copy_button.text = "Copy"
	copy_button.pressed.connect(_on_copy_character_frames_pressed)
	row.add_child(copy_button)


func _add_character_row_tool() -> void:
	var row := HBoxContainer.new()
	form_container.add_child(row)
	_add_character_tool_spin(row, "character_row_index", "Row", 0)
	_add_character_tool_spin(row, "character_row_start_column", "Start Col", 0)
	_add_character_tool_spin(row, "character_row_end_column", "End Col", 3)

	var button := Button.new()
	button.text = "Add Row as Frames"
	button.pressed.connect(_on_add_character_row_frames_pressed)
	row.add_child(button)


func _add_character_range_tool() -> void:
	var row := HBoxContainer.new()
	form_container.add_child(row)
	_add_character_tool_spin(row, "character_range_start", "Start Frame", 0)
	_add_character_tool_spin(row, "character_range_end", "End Frame", 3)

	var button := Button.new()
	button.text = "Add Range as Frames"
	button.pressed.connect(_on_add_character_range_frames_pressed)
	row.add_child(button)


func _add_character_tool_spin(parent: Node, field_name: String, label_text: String, value: int) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var spin_box := SpinBox.new()
	spin_box.min_value = 0
	spin_box.max_value = 999999
	spin_box.step = 1
	spin_box.value = value
	parent.add_child(spin_box)
	field_controls[field_name] = spin_box


func _add_character_preview_controls() -> void:
	var row := HBoxContainer.new()
	form_container.add_child(row)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.pressed.connect(_on_play_character_preview_pressed)
	row.add_child(play_button)

	var stop_button := Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_stop_animation_preview_pressed)
	row.add_child(stop_button)

	var previous_button := Button.new()
	previous_button.text = "Previous Frame"
	previous_button.pressed.connect(_on_previous_character_frame_pressed)
	row.add_child(previous_button)

	var next_button := Button.new()
	next_button.text = "Next Frame"
	next_button.pressed.connect(_on_next_character_frame_pressed)
	row.add_child(next_button)

	_add_preview_zoom_option("character_preview_zoom", _on_character_preview_zoom_selected)

	character_preview_info_label = Label.new()
	character_preview_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(character_preview_info_label)
	_update_character_preview_info()


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


func _add_preview_zoom_option(field_name: String, callback: Callable) -> void:
	var option_button := OptionButton.new()
	var options := {
		"Fit": 0.0,
		"1x": 1.0,
		"2x": 2.0,
		"4x": 4.0,
		"8x": 8.0,
	}
	for label in options.keys():
		var index := option_button.item_count
		option_button.add_item(label)
		option_button.set_item_metadata(index, options[label])
	option_button.select(0)
	option_button.item_selected.connect(callback)
	_add_form_row("Preview Zoom", option_button)
	field_controls[field_name] = option_button


func _add_combat_type_option(label_text: String, field_name: String, selected_type: String, callback: Callable) -> void:
	var option_button := OptionButton.new()
	for type_name in ["character", "monster"]:
		var index := option_button.item_count
		option_button.add_item(type_name.capitalize())
		option_button.set_item_metadata(index, type_name)
		if type_name == selected_type:
			option_button.select(index)
	option_button.item_selected.connect(callback)
	_add_form_row(label_text, option_button)
	field_controls[field_name] = option_button


func _add_combat_actor_option(label_text: String, field_name: String, type_field_name: String) -> void:
	var option_button := OptionButton.new()
	_add_form_row(label_text, option_button)
	field_controls[field_name] = option_button
	_refresh_combat_actor_option(field_name, _get_option_button_metadata(type_field_name))


func _add_combat_weapon_option() -> void:
	var option_button := OptionButton.new()
	_add_form_row("Weapon/Tool", option_button)
	field_controls["combat_weapon"] = option_button
	_refresh_combat_weapon_option()


func _refresh_combat_actor_option(field_name: String, actor_type: String) -> void:
	if not field_controls.has(field_name):
		return

	var option_button: OptionButton = field_controls[field_name]
	option_button.clear()
	var records := data_store.get_records(ContentEditorData.SECTION_CHARACTERS if actor_type == "character" else ContentEditorData.SECTION_MONSTERS)
	for record in records:
		var record_id := str(record.get("id", ""))
		var display_name := str(record.get("display_name", record_id))
		var index := option_button.item_count
		option_button.add_item("%s - %s" % [record_id, display_name])
		option_button.set_item_metadata(index, record_id)
	if option_button.item_count > 0:
		option_button.select(0)


func _refresh_combat_weapon_option() -> void:
	var option_button: OptionButton = field_controls["combat_weapon"]
	option_button.clear()
	var hands_index := option_button.item_count
	option_button.add_item("Hands")
	option_button.set_item_metadata(hands_index, "")
	option_button.select(hands_index)

	for item_record in data_store.get_records(ContentEditorData.SECTION_ITEMS):
		var combat = item_record.get("combat", {})
		var item_type := str(item_record.get("item_type", ""))
		if not combat is Dictionary and item_type != "weapon" and item_type != "tool":
			continue
		var item_id := str(item_record.get("id", ""))
		var display_name := str(item_record.get("display_name", item_id))
		var index := option_button.item_count
		option_button.add_item("%s - %s" % [item_id, display_name])
		option_button.set_item_metadata(index, item_id)


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


func _add_item_type_option_button(initial_type: String) -> void:
	var option_button := OptionButton.new()
	var types := [
		"material",
		"consumable",
		"weapon",
		"tool",
		"armor",
		"accessory",
		"building",
		"quest",
		"misc",
	]
	if not types.has(initial_type):
		types.append(initial_type)

	var selected_index := 0
	for item_type in types:
		var index := option_button.item_count
		option_button.add_item(item_type)
		option_button.set_item_metadata(index, item_type)
		if item_type == initial_type:
			selected_index = index

	option_button.select(selected_index)
	option_button.item_selected.connect(_on_item_type_selected)
	_add_form_row("Item Type", option_button)
	field_controls["item_type"] = option_button


func _add_equipment_slot_option_button(initial_slot: String) -> void:
	_add_string_option_button("Equipment Slot", "equipment_slot", ["weapon", "tool", "armor", "accessory"], initial_slot)


func _add_equipment_stats_bonus_editor() -> void:
	var title := Label.new()
	title.text = "Stats Bonus"
	form_container.add_child(title)

	var stats_bonus: Dictionary = _get_record_dictionary(current_record, "stats_bonus")
	_add_spin_box("STR", "stats_bonus_str", int(stats_bonus.get("str", 0)), 0, 999, 1)
	_add_spin_box("DEX", "stats_bonus_dex", int(stats_bonus.get("dex", 0)), 0, 999, 1)
	_add_spin_box("AGI", "stats_bonus_agi", int(stats_bonus.get("agi", 0)), 0, 999, 1)
	_add_spin_box("VIT", "stats_bonus_vit", int(stats_bonus.get("vit", 0)), 0, 999, 1)
	_add_spin_box("WIS", "stats_bonus_wis", int(stats_bonus.get("wis", 0)), 0, 999, 1)
	_add_spin_box("INT", "stats_bonus_int", int(stats_bonus.get("int", 0)), 0, 999, 1)
	_add_spin_box("LUK", "stats_bonus_luk", int(stats_bonus.get("luk", 0)), 0, 999, 1)


func _add_armor_editor() -> void:
	var title := Label.new()
	title.text = "Armor"
	form_container.add_child(title)

	_add_spin_box("Defense", "defense", int(current_record.get("defense", 0)), 0, 999999, 1)
	_add_spin_box("Magic Defense", "magic_defense", int(current_record.get("magic_defense", 0)), 0, 999999, 1)
	_add_spin_box("Max HP Bonus", "max_hp_bonus", int(current_record.get("max_hp_bonus", 0)), 0, 99999, 1)
	_add_spin_box("Flee Bonus", "flee_bonus", int(current_record.get("flee_bonus", 0)), 0, 999, 1)
	_add_spin_box("Hit Bonus", "hit_bonus", int(current_record.get("hit_bonus", 0)), 0, 999, 1)
	_add_spin_box("Durability", "durability", int(current_record.get("durability", 0)), 0, 999999, 1)
	_add_float_spin_box("Repair Cost Multiplier", "armor_repair_cost_multiplier", float(current_record.get("repair_cost_multiplier", 0.5)), 0.0, 10.0, 0.05)
	_add_check_box("Can Repair", "armor_can_repair", bool(current_record.get("can_repair", true)))


func _add_accessory_editor() -> void:
	var title := Label.new()
	title.text = "Accessory"
	form_container.add_child(title)

	_add_float_spin_box("Crit Chance Bonus", "accessory_crit_chance", float(current_record.get("crit_chance_bonus", 0.0)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Crit Damage Bonus", "accessory_crit_damage", float(current_record.get("crit_damage_bonus", 0.0)), 0.0, 999999.0, 0.01)
	_add_spin_box("Hit Bonus", "acc_hit_bonus", int(current_record.get("hit_bonus", 0)), 0, 999, 1)
	_add_spin_box("Flee Bonus", "acc_flee_bonus", int(current_record.get("flee_bonus", 0)), 0, 999, 1)
	_add_spin_box("Max HP Bonus", "acc_max_hp_bonus", int(current_record.get("max_hp_bonus", 0)), 0, 99999, 1)
	_add_spin_box("Durability", "acc_durability", int(current_record.get("durability", 0)), 0, 999999, 1)
	_add_float_spin_box("Repair Cost Multiplier", "acc_repair_cost_multiplier", float(current_record.get("repair_cost_multiplier", 0.5)), 0.0, 10.0, 0.05)
	_add_check_box("Can Repair", "acc_can_repair", bool(current_record.get("can_repair", true)))


func _add_damage_type_option_button(initial_type: String) -> void:
	var option_button := OptionButton.new()
	var types := [
		"physical",
		"magical",
		"true",
	]
	if not types.has(initial_type):
		types.append(initial_type)

	var selected_index := 0
	for damage_type in types:
		var index := option_button.item_count
		option_button.add_item(damage_type)
		option_button.set_item_metadata(index, damage_type)
		if damage_type == initial_type:
			selected_index = index

	option_button.select(selected_index)
	option_button.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row("Damage Type", option_button)
	field_controls["combat_damage_type"] = option_button


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


func _add_scrollable_preview_row(label_text: String, preview_control: Control) -> void:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = label_text
	row.add_child(label)

	var scroll_container := ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(0, 420)
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(preview_control)

	preview_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(scroll_container)
	form_container.add_child(row)


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
	if current_section == ContentEditorData.SECTION_CHARACTERS:
		current_record["sprite_sheet_id"] = selected_sprite_sheet_id
		_update_character_grid_preview()
		_update_character_preview_frame()
		_mark_dirty()
		return

	_update_animation_grid_preview()
	_update_animation_preview_frame()
	_mark_dirty()


func _on_animation_set_filter_changed(new_text: String) -> void:
	animation_set_filter = new_text
	_refresh_animation_set_options()


func _refresh_animation_set_options() -> void:
	if not field_controls.has("animation_set_id"):
		return

	var option_button: OptionButton = field_controls["animation_set_id"]
	option_button.clear()
	var query := animation_set_filter.strip_edges().to_lower()
	var selected_index := -1

	for animation_set_record in data_store.get_records(ContentEditorData.SECTION_ANIMATION_SETS):
		if not _record_matches_search(animation_set_record, query):
			continue

		var animation_set_id := str(animation_set_record.get("id", ""))
		if animation_set_id == selected_animation_set_id:
			selected_index = option_button.item_count

		var label := animation_set_id
		var display_name := str(animation_set_record.get("display_name", ""))
		if not display_name.is_empty():
			label = "%s - %s" % [animation_set_id, display_name]

		var index := option_button.item_count
		option_button.add_item(label)
		option_button.set_item_metadata(index, animation_set_id)

	if selected_index >= 0:
		option_button.select(selected_index)
	elif option_button.item_count > 0:
		option_button.select(0)
		selected_animation_set_id = str(option_button.get_item_metadata(0))


func _on_animation_set_selected(index: int) -> void:
	if not field_controls.has("animation_set_id"):
		return

	var option_button: OptionButton = field_controls["animation_set_id"]
	selected_animation_set_id = str(option_button.get_item_metadata(index))
	current_record["animation_set_id"] = selected_animation_set_id
	_update_character_grid_preview()
	_update_character_preview_frame()
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


func _on_create_or_update_character_animation_set_pressed() -> void:
	_ensure_character_animation_set()
	_build_form_for_current_record()
	_mark_dirty()
	_set_status("Animation set ready for character.")


func _on_create_required_character_animations_pressed() -> void:
	_ensure_character_animation_set()
	var animations := _get_character_animation_set_animations()
	for animation_name in _get_character_animation_slot_names():
		if animations.has(animation_name):
			continue

		_set_character_animation_data(animation_name, _make_character_animation_data(animation_name, []))

	if active_character_animation_name.is_empty():
		active_character_animation_name = "idle_down"

	_build_form_for_current_record()
	_mark_dirty()
	_set_status("Created missing character animation slots.")


func _on_validate_character_animations_pressed() -> void:
	var results := _validate_character_animations()
	var has_errors := false
	var warning_count := 0
	for result in results:
		var line := str(result)
		if line.begins_with("ERROR"):
			has_errors = true
		elif line.begins_with("WARNING"):
			warning_count += 1

	print("\n".join(results))
	if has_errors:
		_set_status("Character validation found errors. Check console.", true)
	elif warning_count > 0:
		_set_status("Character validation found %d warning(s). Check console." % warning_count, false)
	else:
		_set_status("Character animations valid.")


func _on_character_direction_mode_selected(index: int) -> void:
	var option_button: OptionButton = field_controls["character_direction_mode"]
	_set_character_direction_mode(str(option_button.get_item_metadata(index)))
	_build_form_for_current_record()
	_mark_dirty()


func _on_clear_current_character_animation_pressed() -> void:
	if active_character_animation_name.is_empty():
		_set_status("Select an animation first.", true)
		return

	_on_clear_character_animation_pressed(active_character_animation_name)


func _on_reset_character_fps_defaults_pressed() -> void:
	_ensure_character_animation_set()
	for animation_name in _get_character_animation_slot_names():
		var animation_data := _get_character_animation_data(animation_name)
		animation_data["fps"] = _get_default_animation_fps(animation_name)
		_set_character_animation_data(animation_name, animation_data)

	_build_form_for_current_record()
	_mark_dirty()
	_set_status("Reset character FPS defaults.")


func _on_reset_character_frame_count_defaults_pressed() -> void:
	_ensure_character_animation_set()
	for animation_name in _get_character_animation_slot_names():
		var animation_data := _get_character_animation_data(animation_name)
		animation_data["frame_count"] = _get_default_character_frame_count(animation_name)
		_set_character_animation_data(animation_name, animation_data)

	_build_form_for_current_record()
	_mark_dirty()
	_set_status("Reset character frame count defaults.")


func _on_copy_character_frames_pressed() -> void:
	if active_character_animation_name.is_empty():
		_set_status("Select a target animation first.", true)
		return

	var source_animation := _get_option_button_metadata("character_copy_source")
	if source_animation.is_empty():
		_set_status("Choose a source animation.", true)
		return

	var source_frames := _get_character_animation_frames(source_animation)
	_apply_character_frames_to_active(source_frames)
	_set_status("Copied frames from %s to %s." % [source_animation, active_character_animation_name])


func _on_add_character_row_frames_pressed() -> void:
	if active_character_animation_name.is_empty():
		_set_status("Select a target animation first.", true)
		return

	var sheet_record := _get_selected_sprite_sheet_record()
	var columns := int(sheet_record.get("columns", 0))
	if columns < 1:
		_set_status("Sprite Sheet columns must be valid.", true)
		return

	var row_index := _get_spin_box_int("character_row_index")
	var start_column := _get_spin_box_int("character_row_start_column")
	var end_column := _get_spin_box_int("character_row_end_column")
	var frames := []
	for column in range(min(start_column, end_column), max(start_column, end_column) + 1):
		frames.append((row_index * columns) + column)

	_apply_character_frames_to_active(frames)
	_set_status("Added row frames to %s." % active_character_animation_name)


func _on_add_character_range_frames_pressed() -> void:
	if active_character_animation_name.is_empty():
		_set_status("Select a target animation first.", true)
		return

	var start_frame := _get_spin_box_int("character_range_start")
	var end_frame := _get_spin_box_int("character_range_end")
	var frames := []
	for frame_index in range(min(start_frame, end_frame), max(start_frame, end_frame) + 1):
		frames.append(frame_index)

	_apply_character_frames_to_active(frames)
	_set_status("Added range frames to %s." % active_character_animation_name)


func _on_select_character_animation_pressed(animation_name: String) -> void:
	active_character_animation_name = animation_name
	_update_character_grid_preview()
	_update_character_preview_frame()
	_set_status("Selected %s for frame picking." % animation_name)


func _on_clear_character_animation_pressed(animation_name: String) -> void:
	_ensure_character_animation_set()
	var animation_data := _get_character_animation_data(animation_name)
	animation_data["frames"] = []
	_set_character_animation_data(animation_name, animation_data)
	active_character_animation_name = animation_name
	_build_form_for_current_record()
	_mark_dirty()


func _on_preview_character_animation_pressed(animation_name: String) -> void:
	active_character_animation_name = animation_name
	animation_preview_frame_index = 0
	_update_character_grid_preview()
	_update_character_preview_frame()
	_set_status("Previewing %s." % animation_name)


func _on_character_slot_spin_value_changed(new_value: float, animation_name: String, property_name: String) -> void:
	_ensure_character_animation_set()
	var animation_data := _get_character_animation_data(animation_name)
	animation_data[property_name] = int(new_value)
	_set_character_animation_data(animation_name, animation_data)
	active_character_animation_name = animation_name
	_update_character_grid_preview()
	_update_character_preview_frame()
	_mark_dirty()


func _on_character_slot_loop_changed(is_pressed: bool, animation_name: String) -> void:
	_ensure_character_animation_set()
	var animation_data := _get_character_animation_data(animation_name)
	animation_data["loop"] = is_pressed
	_set_character_animation_data(animation_name, animation_data)
	active_character_animation_name = animation_name
	_mark_dirty()


func _on_character_grid_zoom_selected(_index: int) -> void:
	if animation_grid_preview == null:
		return

	animation_grid_preview.set_zoom_scale(_get_preview_zoom_scale("character_grid_zoom"))


func _on_character_preview_zoom_selected(_index: int) -> void:
	_update_character_preview_frame()


func _on_item_type_selected(_index: int) -> void:
	current_record = _get_item_form_record()
	_build_form_for_current_record()
	_mark_dirty()


func _on_add_resource_damage_pressed() -> void:
	var resource_id := _get_first_resource_id()
	if resource_id.is_empty():
		_set_status("Create a resource before adding Resource Damage.", true)
		return

	item_resource_damage_rows.append({
		"resource_type_id": resource_id,
		"damage": 0,
	})
	current_record = _get_item_form_record()
	_build_form_for_current_record()
	_mark_dirty()


func _on_remove_resource_damage_pressed(row_index: int) -> void:
	if row_index < 0 or row_index >= item_resource_damage_rows.size():
		return

	item_resource_damage_rows.remove_at(row_index)
	current_record = _get_item_form_record()
	_build_form_for_current_record()
	_mark_dirty()


func _on_resource_damage_resource_selected(selected_index: int, row_index: int, option_button: OptionButton) -> void:
	if row_index < 0 or row_index >= item_resource_damage_rows.size():
		return
	if selected_index < 0 or selected_index >= option_button.item_count:
		return

	item_resource_damage_rows[row_index]["resource_type_id"] = str(option_button.get_item_metadata(selected_index))
	_mark_dirty()


func _on_resource_damage_value_changed(new_value: float, row_index: int) -> void:
	if row_index < 0 or row_index >= item_resource_damage_rows.size():
		return

	item_resource_damage_rows[row_index]["damage"] = int(new_value)
	_mark_dirty()


func _on_add_drop_row_pressed(field_name: String) -> void:
	var rows := _get_drop_rows(field_name)
	rows.append({
		"item_id": _get_default_item_id(),
		"min_amount": 1,
		"max_amount": 1,
		"chance": 1.0,
	})
	current_record = _get_resource_form_record()
	_build_form_for_current_record()
	_mark_dirty()


func _on_remove_drop_row_pressed(field_name: String, row_index: int) -> void:
	var rows := _get_drop_rows(field_name)
	if row_index < 0 or row_index >= rows.size():
		return

	rows.remove_at(row_index)
	current_record = _get_resource_form_record()
	_build_form_for_current_record()
	_mark_dirty()


func _on_drop_row_item_selected(field_name: String, row_index: int, selected_index: int, option_button: OptionButton) -> void:
	var rows := _get_drop_rows(field_name)
	if row_index < 0 or row_index >= rows.size():
		return
	if selected_index < 0 or selected_index >= option_button.item_count:
		return

	rows[row_index]["item_id"] = str(option_button.get_item_metadata(selected_index))
	_mark_dirty()


func _on_drop_row_number_changed(field_name: String, row_index: int, key: String, new_value: float) -> void:
	var rows := _get_drop_rows(field_name)
	if row_index < 0 or row_index >= rows.size():
		return

	if key == "chance":
		rows[row_index][key] = new_value
	else:
		rows[row_index][key] = int(new_value)
	_mark_dirty()


func _on_combat_attacker_type_selected(_index: int) -> void:
	_refresh_combat_actor_option("combat_attacker", _get_option_button_metadata("combat_attacker_type"))


func _on_combat_target_type_selected(_index: int) -> void:
	_refresh_combat_actor_option("combat_target", _get_option_button_metadata("combat_target_type"))


func _on_combat_calculate_once_pressed() -> void:
	var setup: Dictionary = _get_combat_preview_setup()
	if not bool(setup.get("ok", false)):
		_set_combat_results(str(setup.get("error", "Invalid combat preview setup.")))
		return

	var result: Dictionary = combat_calculator.calculate_damage(setup["attacker"], setup["target"], setup["weapon"])
	_set_combat_results(_format_combat_once_result(setup, result))


func _on_combat_simulate_100_pressed() -> void:
	var setup: Dictionary = _get_combat_preview_setup()
	if not bool(setup.get("ok", false)):
		_set_combat_results(str(setup.get("error", "Invalid combat preview setup.")))
		return

	var total_damage: int = 0
	var hit_count: int = 0
	var miss_count: int = 0
	var crit_count: int = 0
	var min_damage: int = 999999
	var max_damage: int = 0
	for _index in range(100):
		var result: Dictionary = combat_calculator.calculate_damage(setup["attacker"], setup["target"], setup["weapon"])
		if bool(result.get("miss", false)):
			miss_count += 1
			continue

		var damage: int = int(result.get("damage", 0))
		hit_count += 1
		total_damage += damage
		min_damage = int(min(min_damage, damage))
		max_damage = int(max(max_damage, damage))
		if bool(result.get("is_critical", false)):
			crit_count += 1

	var average_damage: float = float(total_damage) / max(float(hit_count), 1.0)
	var attacker_derived: Dictionary = setup["attacker_derived"]
	var attack_cooldown: float = max(float(attacker_derived.get("attack_cooldown", 1.0)), 0.01)
	var estimated_dps: float = (float(total_damage) / 100.0) / attack_cooldown
	_set_combat_results(_format_combat_simulation_result(setup, average_damage, min_damage if hit_count > 0 else 0, max_damage, crit_count, miss_count, estimated_dps))


func _on_character_grid_frame_clicked(frame_index: int, mouse_button: int) -> void:
	if active_character_animation_name.is_empty():
		_set_status("Click Select Frames on an animation slot first.", true)
		return

	_ensure_character_animation_set()
	var animation_data := _get_character_animation_data(active_character_animation_name)
	var frames = animation_data.get("frames", [])
	if not frames is Array:
		frames = []

	if mouse_button == MOUSE_BUTTON_RIGHT:
		for index in range(frames.size() - 1, -1, -1):
			if int(frames[index]) == frame_index:
				frames.remove_at(index)
				break
	else:
		var frame_count := int(animation_data.get("frame_count", _get_default_character_frame_count(active_character_animation_name)))
		if frames.size() >= frame_count:
			_set_status("%s already has %d frames. Increase Frame Count or clear frames first." % [active_character_animation_name, frame_count], true)
			return

		frames.append(frame_index)

	animation_data["frames"] = frames
	_set_character_animation_data(active_character_animation_name, animation_data)
	_build_form_for_current_record()
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


func _on_play_character_preview_pressed() -> void:
	if active_character_animation_name.is_empty():
		active_character_animation_name = "idle_down"

	var frames := _get_character_animation_frames(active_character_animation_name)
	if frames.is_empty():
		_set_status("Animation has no frames.", true)
		_update_character_preview_info("Animation has no frames.")
		return

	animation_preview_playing = true
	animation_preview_elapsed = 0.0
	animation_preview_frame_index = clamp(animation_preview_frame_index, 0, frames.size() - 1)
	_update_character_preview_frame()


func _on_previous_character_frame_pressed() -> void:
	var frames := _get_character_animation_frames(active_character_animation_name)
	if frames.is_empty():
		_set_status("Animation has no frames.", true)
		_update_character_preview_info("Animation has no frames.")
		return

	animation_preview_playing = false
	animation_preview_frame_index = max(animation_preview_frame_index - 1, 0)
	_update_character_preview_frame()


func _on_next_character_frame_pressed() -> void:
	var frames := _get_character_animation_frames(active_character_animation_name)
	if frames.is_empty():
		_set_status("Animation has no frames.", true)
		_update_character_preview_info("Animation has no frames.")
		return

	animation_preview_playing = false
	animation_preview_frame_index = min(animation_preview_frame_index + 1, frames.size() - 1)
	_update_character_preview_frame()


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


func _on_sheet_preview_zoom_selected(_index: int) -> void:
	if sprite_sheet_preview == null:
		return

	sprite_sheet_preview.set_zoom_scale(_get_preview_zoom_scale("sheet_preview_zoom"))


func _on_animation_grid_zoom_selected(_index: int) -> void:
	if animation_grid_preview == null:
		return

	animation_grid_preview.set_zoom_scale(_get_preview_zoom_scale("animation_grid_zoom"))


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
		sprite_sheet_preview.custom_minimum_size = Vector2(320, 320)
		sprite_sheet_preview.set_fit_minimum_size(Vector2(320, 320))
		sprite_sheet_preview.set_zoom_scale(_get_preview_zoom_scale("sheet_preview_zoom"))
		sprite_sheet_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sprite_sheet_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_add_scrollable_preview_row("Sheet Preview", sprite_sheet_preview)
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



func _on_batch_static_sprite_pressed() -> void:
	if current_section != ContentEditorData.SECTION_SPRITES:
		_set_status("Batch Static Sprites is only available in the Sprites section.", true)
		return
	if has_unsaved_changes:
		_set_status("Save or Revert before importing static sprites.", true)
		return
	if batch_sprite_file_dialog == null:
		_set_status("Batch sprite file dialog is not ready.", true)
		return

	_ensure_static_sprite_import_dir()
	var suggested_dir := ProjectSettings.globalize_path(BATCH_STATIC_SPRITE_IMPORT_DIR)
	if not suggested_dir.is_empty():
		batch_sprite_file_dialog.current_dir = suggested_dir
	batch_sprite_file_dialog.popup_centered_ratio(0.8)


func _on_batch_static_sprite_files_selected(paths: PackedStringArray) -> void:
	if paths.is_empty():
		_set_status("No files selected for batch sprite import.", true)
		return
	_show_batch_static_sprite_review(paths)


func _show_batch_static_sprite_review(paths: PackedStringArray) -> void:
	if batch_sprite_window != null and is_instance_valid(batch_sprite_window):
		batch_sprite_window.queue_free()

	batch_sprite_rows.clear()
	batch_sprite_window = Window.new()
	batch_sprite_window.title = "Batch Static Sprites"
	batch_sprite_window.size = Vector2i(960, 640)
	batch_sprite_window.min_size = Vector2i(720, 420)
	batch_sprite_window.exclusive = true
	batch_sprite_window.close_requested.connect(func() -> void: batch_sprite_window.hide())
	add_child(batch_sprite_window)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	batch_sprite_window.add_child(root)

	var intro := Label.new()
	intro.text = "Review selected static sprites. Edit Display Name and ID, then click Create All. Files outside res:// will be copied to %s." % BATCH_STATIC_SPRITE_IMPORT_DIR
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)

	var header := HBoxContainer.new()
	root.add_child(header)
	for label_text in ["Preview", "Source File", "Display Name", "ID", "Category"]:
		var label := Label.new()
		label.text = label_text
		label.custom_minimum_size = Vector2(90, 0)
		if label_text == "Source File":
			label.custom_minimum_size = Vector2(260, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if label_text == "Source File" else Control.SIZE_SHRINK_CENTER
		header.add_child(label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	batch_sprite_rows_container = VBoxContainer.new()
	batch_sprite_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(batch_sprite_rows_container)

	for path in paths:
		_add_batch_static_sprite_row(str(path))

	var action_row := HBoxContainer.new()
	root.add_child(action_row)

	var create_button := Button.new()
	create_button.text = "Create All"
	create_button.pressed.connect(_on_create_batch_static_sprites_pressed)
	action_row.add_child(create_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func() -> void: batch_sprite_window.hide())
	action_row.add_child(cancel_button)

	batch_sprite_window.popup_centered()
	_set_status("Reviewing %d static sprite(s)." % paths.size())


func _add_batch_static_sprite_row(source_path: String) -> void:
	if batch_sprite_rows_container == null:
		return

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	batch_sprite_rows_container.add_child(row)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(72, 72)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = _load_any_image_texture(source_path)
	row.add_child(preview)

	var source_label := Label.new()
	source_label.text = source_path.get_file()
	source_label.tooltip_text = source_path
	source_label.custom_minimum_size = Vector2(260, 0)
	source_label.clip_text = true
	source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(source_label)

	var base_name := source_path.get_file().get_basename()
	var suggested_display_name := _humanize_id(base_name)
	var suggested_id := data_store.create_unique_id(ContentEditorData.SECTION_SPRITES, base_name)

	var name_edit := LineEdit.new()
	name_edit.text = suggested_display_name
	name_edit.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_edit)

	var id_edit := LineEdit.new()
	id_edit.text = suggested_id
	id_edit.custom_minimum_size = Vector2(170, 0)
	row.add_child(id_edit)

	name_edit.text_changed.connect(func(new_text: String) -> void:
		if id_edit.text.strip_edges().is_empty() or id_edit.text == suggested_id:
			id_edit.text = data_store.create_unique_id(ContentEditorData.SECTION_SPRITES, new_text)
	)

	var category_option := OptionButton.new()
	for category in ["item", "resource", "monster", "building", "terrain", "ui", "effect", "character", "misc"]:
		var index := category_option.item_count
		category_option.add_item(category.capitalize())
		category_option.set_item_metadata(index, category)
	category_option.select(0)
	category_option.custom_minimum_size = Vector2(120, 0)
	row.add_child(category_option)

	batch_sprite_rows.append({
		"source_path": source_path,
		"name_edit": name_edit,
		"id_edit": id_edit,
		"category_option": category_option,
	})


func _on_create_batch_static_sprites_pressed() -> void:
	if batch_sprite_rows.is_empty():
		_set_status("No batch sprite rows to create.", true)
		return
	if not _ensure_static_sprite_import_dir():
		_set_status("Could not create static sprite import directory: %s" % BATCH_STATIC_SPRITE_IMPORT_DIR, true)
		return

	var created_ids := []
	var used_ids := {}
	for row_data in batch_sprite_rows:
		if not row_data is Dictionary:
			continue

		var source_path := str(row_data.get("source_path", ""))
		var name_edit := row_data.get("name_edit") as LineEdit
		var id_edit := row_data.get("id_edit") as LineEdit
		var category_option := row_data.get("category_option") as OptionButton
		if source_path.is_empty() or name_edit == null or id_edit == null or category_option == null:
			continue

		var record_id := data_store.sanitize_id(id_edit.text)
		if record_id.is_empty():
			record_id = data_store.sanitize_id(name_edit.text)
		if record_id.is_empty():
			record_id = data_store.sanitize_id(source_path.get_file().get_basename())
		record_id = _make_batch_sprite_id_unique(record_id, used_ids)
		used_ids[record_id] = true

		var texture_path := _copy_static_sprite_to_project(source_path, record_id)
		if texture_path.is_empty():
			_set_status("Could not import sprite file: %s" % source_path, true)
			return

		var image_size := _get_image_file_size(source_path)
		var frame_w = max(int(image_size.x), 1)
		var frame_h = max(int(image_size.y), 1)
		var category := str(category_option.get_item_metadata(category_option.selected))
		var display_name := name_edit.text.strip_edges()
		if display_name.is_empty():
			display_name = _humanize_id(record_id)

		var record := {
			"display_name": display_name,
			"type": "single_sprite",
			"texture_path": texture_path,
			"region_enabled": false,
			"region": {"x": 0, "y": 0, "w": frame_w, "h": frame_h},
			"frame_size": {"w": frame_w, "h": frame_h},
			"frame_width": frame_w,
			"frame_height": frame_h,
			"columns": 1,
			"rows": 1,
			"total_frames": 1,
			"category": category,
			"tags": ["static", "batch_imported"],
		}

		data_store.set_record(ContentEditorData.SECTION_SPRITES, "", record_id, record)
		created_ids.append(record_id)

	var error := data_store.save_section(ContentEditorData.SECTION_SPRITES)
	if not error.is_empty():
		_set_status(error, true)
		return

	_reload_content_db()
	_populate_sprite_category_filter()
	_refresh_record_list()
	if not created_ids.is_empty():
		_load_record(str(created_ids[0]))
	if batch_sprite_window != null and is_instance_valid(batch_sprite_window):
		batch_sprite_window.hide()
	_set_status("Imported %d static sprite(s): %s" % [created_ids.size(), _join_strings(created_ids, ", ")])


func _make_batch_sprite_id_unique(base_id: String, used_ids: Dictionary) -> String:
	var clean_id := data_store.sanitize_id(base_id)
	if clean_id.is_empty():
		clean_id = "static_sprite"
	if not data_store.has_record(ContentEditorData.SECTION_SPRITES, clean_id) and not used_ids.has(clean_id):
		return clean_id

	var index := 2
	while data_store.has_record(ContentEditorData.SECTION_SPRITES, "%s_%d" % [clean_id, index]) or used_ids.has("%s_%d" % [clean_id, index]):
		index += 1
	return "%s_%d" % [clean_id, index]


func _ensure_static_sprite_import_dir() -> bool:
	var absolute_dir := ProjectSettings.globalize_path(BATCH_STATIC_SPRITE_IMPORT_DIR)
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	return error == OK or error == ERR_ALREADY_EXISTS


func _copy_static_sprite_to_project(source_path: String, record_id: String) -> String:
	var extension := source_path.get_extension().to_lower()
	if extension.is_empty():
		extension = "png"
	var target_res_path := "%s/%s.%s" % [BATCH_STATIC_SPRITE_IMPORT_DIR, record_id, extension]
	if source_path == target_res_path:
		return source_path

	var source_abs := source_path
	if source_path.begins_with("res://") or source_path.begins_with("user://"):
		source_abs = ProjectSettings.globalize_path(source_path)
	var target_abs := ProjectSettings.globalize_path(target_res_path)
	if source_abs == target_abs:
		return target_res_path

	var copy_error := DirAccess.copy_absolute(source_abs, target_abs)
	if copy_error != OK:
		return ""
	return target_res_path


func _load_any_image_texture(path: String) -> Texture2D:
	if path.begins_with("res://") or path.begins_with("user://"):
		var resource := load(path)
		if resource is Texture2D:
			return resource as Texture2D

	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)


func _get_image_file_size(path: String) -> Vector2i:
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		var texture := _load_any_image_texture(path)
		if texture != null:
			return Vector2i(texture.get_width(), texture.get_height())
		return Vector2i(32, 32)
	return Vector2i(image.get_width(), image.get_height())


func _humanize_id(raw_id: String) -> String:
	var clean_id := data_store.sanitize_id(raw_id)
	if clean_id.is_empty():
		return "New Sprite"
	var words := []
	for part in clean_id.split("_", false):
		words.append(str(part).capitalize())
	return _join_strings(words, " ")


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
		ContentEditorData.SECTION_CHARACTERS:
			_create_new_character()
		ContentEditorData.SECTION_TIERS:
			_create_new_tier()
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


func _create_new_character() -> void:
	var new_id := data_store.create_unique_id(ContentEditorData.SECTION_CHARACTERS, "new_character")
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": new_id,
		"display_name": "New Character",
		"sprite_sheet_id": _get_default_sprite_sheet_id(),
		"animation_set_id": "",
	}
	selected_sprite_sheet_id = str(current_record.get("sprite_sheet_id", ""))
	selected_animation_set_id = ""
	active_character_animation_name = ""
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved character.")


func _create_new_tier() -> void:
	var new_id := "8"
	for tier_id in range(1, 100):
		if not data_store.has_record(ContentEditorData.SECTION_TIERS, str(tier_id)):
			new_id = str(tier_id)
			break
	current_id = new_id
	current_original_id = ""
	current_record = {
		"id": int(new_id),
		"display_name": "New Tier",
		"theme": "",
		"region": "",
		"boss": "",
		"primary_material": "",
	}
	has_unsaved_changes = true
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_set_status("Created new unsaved tier.")


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
		ContentEditorData.SECTION_CHARACTERS:
			_duplicate_current_record("_copy")
		ContentEditorData.SECTION_TIERS:
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
	selected_animation_set_id = str(current_record.get("animation_set_id", ""))
	active_character_animation_name = ""
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
		ContentEditorData.SECTION_CHARACTERS:
			_delete_current_character()
		ContentEditorData.SECTION_TIERS:
			_set_status("Tier delete is blocked for now to preserve the Early Access progression.", true)
		ContentEditorData.SECTION_PLAYER_TUNING:
			_set_status("Player Tuning keeps a single default record.", true)
		ContentEditorData.SECTION_FONT_PROFILES:
			_set_status("Core font profiles should be edited, not deleted.", true)
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


func _delete_current_character() -> void:
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
	active_character_animation_name = ""
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Deleted character.")


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
		ContentEditorData.SECTION_CHARACTERS:
			_save_character()
		ContentEditorData.SECTION_TIERS:
			_save_tier()
		ContentEditorData.SECTION_PLAYER_TUNING:
			_save_player_tuning()
		ContentEditorData.SECTION_FONT_PROFILES:
			_save_font_profile()
		ContentEditorData.SECTION_VFX_PROFILES:
			_save_vfx_profile()
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


func _save_character() -> void:
	_ensure_character_animation_set()
	var record := _get_character_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_character(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	var animation_save_error := data_store.save_section(ContentEditorData.SECTION_ANIMATION_SETS)
	if not animation_save_error.is_empty():
		_set_status(animation_save_error, true)
		return

	_save_current_record(record_id, record)


func _save_tier() -> void:
	var record := _get_tier_form_record()
	var record_id := str(int(record.get("id", 0)))
	record["id"] = int(record_id)
	_set_spin_box_value("id", int(record_id))

	var error := data_store.validate_tier(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_player_tuning() -> void:
	var record := _get_player_tuning_form_record()
	var record_id := "default"
	record["id"] = record_id

	var error := data_store.validate_player_tuning(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_font_profile() -> void:
	var record := _get_font_profile_form_record()
	var record_id := data_store.sanitize_id(str(record.get("id", "")))
	record["id"] = record_id
	_set_line_edit_text("id", record_id)

	var error := data_store.validate_font_profile(record_id, current_original_id, record)
	if not error.is_empty():
		_set_status(error, true)
		return

	_save_current_record(record_id, record)


func _save_vfx_profile() -> void:
	var record := _get_vfx_profile_form_record()
	var record_id := "default"
	record["id"] = record_id

	var error := data_store.validate_vfx_profile(record_id, current_original_id, record)
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
	selected_animation_set_id = str(current_record.get("animation_set_id", ""))
	active_character_animation_name = ""
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
	selected_animation_set_id = str(current_record.get("animation_set_id", ""))
	animation_set_filter = ""
	active_character_animation_name = ""
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
	selected_animation_set_id = ""
	animation_set_filter = ""
	selected_animation_name = ""
	active_character_animation_name = ""
	animation_preview_playing = false
	production_rows.clear()
	_refresh_record_list()
	_show_empty_form()
	_update_action_buttons()
	_set_status("Discarded unsaved record.")


func _get_item_form_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = _get_line_edit_text("id")
	record["display_name"] = _get_line_edit_text("display_name")
	record["description"] = _get_text_edit_text("description")
	record["stack_size"] = _get_spin_box_int("stack_size")
	record["sprite_id"] = selected_sprite_id
	record["item_type"] = _get_option_button_metadata("item_type")
	record["tier"] = _get_spin_box_int("tier")
	record["material_family"] = _get_option_button_metadata("material_family")
	record["tags"] = _parse_tags(_get_line_edit_text("tags"))

	var item_type := str(record.get("item_type", "material"))
	var is_equippable := item_type == "weapon" or item_type == "tool" or item_type == "armor" or item_type == "accessory"

	if is_equippable:
		record["equipment_slot"] = _get_option_button_metadata("equipment_slot")
		record["stats_bonus"] = _get_equipment_stats_bonus_record()

	if item_type == "weapon" or item_type == "tool":
		record["tool_type"] = _get_option_button_metadata("tool_type")
		record["tool_tier"] = _get_spin_box_int("tool_tier")
		record["tool_damage"] = _get_spin_box_int("tool_damage")
		record["tool_speed"] = _get_spin_box_value("tool_speed")
		record["durability"] = _get_spin_box_int("durability")
		record["repair_cost_multiplier"] = _get_spin_box_value("repair_cost_multiplier")
		record["can_repair"] = _get_check_box_pressed("can_repair")
		record["crit_chance"] = _get_spin_box_value("crit_chance")
		record["crit_power"] = _get_spin_box_value("crit_power")
		var combat: Dictionary = _get_record_dictionary(record, "combat")
		combat["attack_power"] = _get_spin_box_int("combat_attack_power")
		combat["attack_variance"] = _get_spin_box_value("combat_attack_variance")
		combat["damage_type"] = _get_option_button_metadata("combat_damage_type")
		combat["crit_chance_bonus"] = _get_spin_box_value("combat_crit_chance_bonus")
		combat["crit_damage_bonus"] = _get_spin_box_value("combat_crit_damage_bonus")
		combat["attack_cooldown_modifier"] = _get_spin_box_value("combat_attack_cooldown_modifier")
		combat["can_hit_monsters"] = _get_check_box_pressed("combat_can_hit_monsters")
		combat["can_hit_resources"] = _get_check_box_pressed("combat_can_hit_resources")
		combat["stat_scaling"] = _get_item_stat_scaling_record()
		if item_type == "tool":
			combat["resource_damage"] = _get_resource_damage_record()
		record["combat"] = combat

	if item_type == "armor":
		record["defense"] = _get_spin_box_int("defense")
		record["magic_defense"] = _get_spin_box_int("magic_defense")
		record["max_hp_bonus"] = _get_spin_box_int("max_hp_bonus")
		record["flee_bonus"] = _get_spin_box_int("flee_bonus")
		record["hit_bonus"] = _get_spin_box_int("hit_bonus")
		record["durability"] = _get_spin_box_int("durability")
		record["repair_cost_multiplier"] = _get_spin_box_value("armor_repair_cost_multiplier")
		record["can_repair"] = _get_check_box_pressed("armor_can_repair")

	if item_type == "accessory":
		record["crit_chance_bonus"] = _get_spin_box_value("accessory_crit_chance")
		record["crit_damage_bonus"] = _get_spin_box_value("accessory_crit_damage")
		record["hit_bonus"] = _get_spin_box_int("acc_hit_bonus")
		record["flee_bonus"] = _get_spin_box_int("acc_flee_bonus")
		record["max_hp_bonus"] = _get_spin_box_int("acc_max_hp_bonus")
		record["durability"] = _get_spin_box_int("acc_durability")
		record["repair_cost_multiplier"] = _get_spin_box_value("acc_repair_cost_multiplier")
		record["can_repair"] = _get_check_box_pressed("acc_can_repair")

	return record


func _get_resource_form_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = _get_line_edit_text("id")
	record["display_name"] = _get_line_edit_text("display_name")
	record["sprite_id"] = selected_sprite_id
	record["max_health"] = _get_spin_box_int("max_health")
	record["drop_item_id"] = selected_drop_item_id
	record["drop_amount"] = _get_spin_box_int("drop_amount")
	record["respawn_time_seconds"] = _get_spin_box_int("respawn_time_seconds")
	record["resource_tier"] = _get_spin_box_int("resource_tier")
	record["resource_hp"] = _get_spin_box_int("resource_hp")
	record["required_tool_type"] = _get_option_button_metadata("required_tool_type")
	record["allow_hands"] = _get_check_box_pressed("allow_hands")
	record["skill_type"] = _get_option_button_metadata("skill_type")
	record["xp_reward"] = _get_spin_box_int("xp_reward")
	record["base_drops"] = _get_drop_rows_record("base_drops")
	record["rare_drops"] = _get_drop_rows_record("rare_drops")
	return record


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
	record["workstation"] = _get_option_button_metadata("workstation")
	record["tier"] = _get_spin_box_int("tier")
	record["output_item_id"] = _get_option_button_metadata("output_item_id")
	record["output_amount"] = _get_spin_box_int("output_amount")
	record["sprite_id"] = selected_sprite_id
	record["skill_type"] = _get_option_button_metadata("skill_type")
	record["xp_reward"] = _get_spin_box_int("xp_reward")
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
		"direction_mode": str(current_record.get("direction_mode", "4dir")),
		"animations": _get_animation_set_animations().duplicate(true),
	}


func _get_character_form_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = _get_line_edit_text("id")
	record["display_name"] = _get_line_edit_text("display_name")
	record["sprite_sheet_id"] = selected_sprite_sheet_id
	record["animation_set_id"] = selected_animation_set_id
	return record


func _get_tier_form_record() -> Dictionary:
	var record := current_record.duplicate(true)
	record["id"] = _get_spin_box_int("id")
	record["display_name"] = _get_line_edit_text("display_name")
	record["theme"] = _get_line_edit_text("theme")
	record["region"] = _get_line_edit_text("region")
	record["boss"] = _get_line_edit_text("boss")
	record["primary_material"] = _get_line_edit_text("primary_material")
	record["metal_material"] = _get_line_edit_text("metal_material")
	record["secondary_material"] = _get_line_edit_text("secondary_material")
	record["wood_material"] = _get_line_edit_text("wood_material")
	record["cloth_material"] = _get_line_edit_text("cloth_material")
	record["tool_material"] = _get_line_edit_text("tool_material")
	record["weapon_material"] = _get_line_edit_text("weapon_material")
	record["armor_material"] = _get_line_edit_text("armor_material")
	record["power_budget"] = {
		"tool_damage": _get_spin_box_int("budget_tool_damage"),
		"tool_durability": _get_spin_box_int("budget_tool_durability"),
		"resource_hp_tree": _get_spin_box_int("budget_resource_hp_tree"),
		"resource_hp_ore_or_rock": _get_spin_box_int("budget_resource_hp_ore_or_rock"),
		"xp_reward": _get_spin_box_int("budget_xp_reward"),
		"crit_chance": _get_spin_box_value("budget_crit_chance"),
		"crit_power": _get_spin_box_value("budget_crit_power"),
		"attack_cooldown": _get_spin_box_value("budget_attack_cooldown"),
		"repair_cost_multiplier": _get_spin_box_value("budget_repair_cost_multiplier"),
		"storage_slots": _get_spin_box_int("budget_storage_slots"),
		"monster_hp_target": _get_spin_box_int("budget_monster_hp_target"),
		"monster_damage_target": _get_spin_box_int("budget_monster_damage_target"),
		"resource_respawn_seconds": _get_spin_box_int("budget_resource_respawn_seconds"),
	}
	record["progression_rule"] = _get_line_edit_text("progression_rule")
	record["early_access_role"] = _get_text_edit_text("early_access_role")
	return record


func _get_player_tuning_form_record() -> Dictionary:
	return {
		"id": "default",
		"walk_speed": _get_spin_box_value("walk_speed"),
		"run_speed": _get_spin_box_value("run_speed"),
		"acceleration": _get_spin_box_value("acceleration"),
		"deceleration": _get_spin_box_value("deceleration"),
		"run_stop_slide_time": _get_spin_box_value("run_stop_slide_time"),
		"run_stop_slide_strength": _get_spin_box_value("run_stop_slide_strength"),
		"smoke_puff_enabled": _get_check_box_pressed("smoke_puff_enabled"),
		"smoke_puff_cooldown": _get_spin_box_value("smoke_puff_cooldown"),
	}


func _get_font_profile_form_record() -> Dictionary:
	return {
		"id": _get_line_edit_text("id"),
		"display_name": _get_line_edit_text("display_name"),
		"font_path": _get_option_button_metadata("font_path"),
		"font_size": _get_spin_box_int("font_size"),
		"font_color": _get_line_edit_text("font_color"),
		"outline_size": _get_spin_box_int("outline_size"),
		"outline_color": _get_line_edit_text("outline_color"),
	}


func _get_vfx_profile_form_record() -> Dictionary:
	return {
		"id": "default",
		"critical_shake_strength": _get_float_spin_box_value("critical_shake_strength"),
		"critical_shake_duration": _get_float_spin_box_value("critical_shake_duration"),
		"tree_wind_strength": _get_float_spin_box_value("tree_wind_strength"),
		"tree_wind_speed": _get_float_spin_box_value("tree_wind_speed"),
		"smoke_puff_lifetime": _get_float_spin_box_value("smoke_puff_lifetime"),
		"smoke_puff_scale": _get_float_spin_box_value("smoke_puff_scale"),
		"floating_text_duration": _get_float_spin_box_value("floating_text_duration"),
		"critical_text_duration": _get_float_spin_box_value("critical_text_duration"),
		"hit_flash_duration": _get_float_spin_box_value("hit_flash_duration"),
		"critical_hit_flash_duration": _get_float_spin_box_value("critical_hit_flash_duration"),
		"hit_bump_scale": _get_float_spin_box_value("hit_bump_scale"),
		"critical_bump_scale": _get_float_spin_box_value("critical_bump_scale"),
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


func _update_font_profile_preview() -> void:
	if font_profile_preview_label == null:
		return

	var settings := LabelSettings.new()
	var font := OathwakeTextStyle.load_font_from_path(_get_option_button_metadata("font_path"))
	if font != null:
		settings.font = font
	settings.font_size = max(_get_spin_box_int("font_size"), 1)
	settings.font_color = OathwakeTextStyle.parse_color(_get_line_edit_text("font_color"), Color.WHITE)
	settings.outline_size = max(_get_spin_box_int("outline_size"), 0)
	settings.outline_color = OathwakeTextStyle.parse_color(_get_line_edit_text("outline_color"), Color.BLACK)
	font_profile_preview_label.label_settings = settings


func _get_preview_zoom_scale(field_name: String) -> float:
	if not field_controls.has(field_name):
		return 0.0

	var option_button: OptionButton = field_controls[field_name]
	if option_button.item_count <= 0 or option_button.selected < 0:
		return 0.0

	return float(option_button.get_item_metadata(option_button.selected))


func _get_item_stat_scaling_record() -> Dictionary:
	var stat_scaling := {}
	for stat_name in ["str", "dex", "agi", "vit", "wis", "int", "luk"]:
		stat_scaling[stat_name] = _get_spin_box_value("scaling_%s" % stat_name)
	return stat_scaling


func _get_equipment_stats_bonus_record() -> Dictionary:
	var stats_bonus := {}
	for stat_name in ["str", "dex", "agi", "vit", "wis", "int", "luk"]:
		stats_bonus[stat_name] = _get_spin_box_int("stats_bonus_%s" % stat_name)
	return stats_bonus


func _get_resource_damage_record() -> Dictionary:
	var resource_damage := {}
	for row_data in item_resource_damage_rows:
		if not row_data is Dictionary:
			continue

		var resource_type_id := str(row_data.get("resource_type_id", ""))
		var damage := int(row_data.get("damage", 0))
		if not resource_type_id.is_empty():
			resource_damage[resource_type_id] = max(damage, 0)
	return resource_damage


func _get_drop_rows(field_name: String) -> Array:
	if field_name == "rare_drops":
		return resource_rare_drop_rows
	return resource_base_drop_rows


func _get_drop_rows_record(field_name: String) -> Array:
	var clean_rows := []
	for row_data in _get_drop_rows(field_name):
		if not row_data is Dictionary:
			continue

		var item_id := str(row_data.get("item_id", ""))
		if item_id.is_empty():
			continue

		var min_amount: int = max(int(row_data.get("min_amount", 1)), 1)
		var max_amount: int = max(int(row_data.get("max_amount", min_amount)), min_amount)
		var drop_chance: float = clamp(float(row_data.get("chance", 1.0)), 0.0, 1.0)
		clean_rows.append({
			"item_id": item_id,
			"min_amount": min_amount,
			"max_amount": max_amount,
			"chance": drop_chance,
		})
	return clean_rows


func _get_record_dictionary(data: Dictionary, key: String) -> Dictionary:
	var value = data.get(key, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _get_first_resource_id() -> String:
	for resource_record in data_store.get_records(ContentEditorData.SECTION_RESOURCES):
		return str(resource_record.get("id", ""))
	return ""


func _make_item_combat_preview_text() -> String:
	var player_data := data_store.get_record(ContentEditorData.SECTION_CHARACTERS, "player")
	var slime_data := data_store.get_record(ContentEditorData.SECTION_MONSTERS, "slime")
	if player_data.is_empty() or slime_data.is_empty():
		return "Estimated vs Slime: N/A"

	var item_data := _get_item_form_record()
	var preview: Dictionary = combat_calculator.get_damage_preview(player_data, item_data)
	var result: Dictionary = combat_calculator.calculate_damage(player_data, slime_data, item_data)
	return "Estimated vs Slime: %d-%d damage | Sample hit: %d%s" % [
		int(preview.get("min_damage", 0)),
		int(preview.get("max_damage", 0)),
		int(result.get("damage", 0)),
		" CRIT" if bool(result.get("is_critical", false)) else "",
	]


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
	var supports_visual_editing := current_section == ContentEditorData.SECTION_ITEMS or current_section == ContentEditorData.SECTION_RESOURCES or current_section == ContentEditorData.SECTION_MONSTERS or current_section == ContentEditorData.SECTION_RECIPES or current_section == ContentEditorData.SECTION_TERRAIN_TYPES or current_section == ContentEditorData.SECTION_NPCS or current_section == ContentEditorData.SECTION_SPRITES or current_section == ContentEditorData.SECTION_ANIMATION_SETS or current_section == ContentEditorData.SECTION_CHARACTERS or current_section == ContentEditorData.SECTION_TIERS or current_section == ContentEditorData.SECTION_PLAYER_TUNING or current_section == ContentEditorData.SECTION_FONT_PROFILES or current_section == ContentEditorData.SECTION_VFX_PROFILES
	var is_singleton_section := current_section == ContentEditorData.SECTION_PLAYER_TUNING or current_section == ContentEditorData.SECTION_FONT_PROFILES or current_section == ContentEditorData.SECTION_VFX_PROFILES
	var has_record := not current_record.is_empty()

	new_button.disabled = not supports_visual_editing or has_unsaved_changes or is_singleton_section
	duplicate_button.disabled = not supports_visual_editing or has_unsaved_changes or current_original_id.is_empty() or is_singleton_section
	delete_button.disabled = not supports_visual_editing or current_id.is_empty() or is_singleton_section
	save_button.disabled = not supports_visual_editing or not has_record
	revert_button.disabled = not supports_visual_editing or not has_record
	reload_current_button.disabled = current_section.is_empty()
	refresh_content_db_button.disabled = false

	if batch_static_sprite_button != null:
		batch_static_sprite_button.visible = current_section == ContentEditorData.SECTION_SPRITES
		batch_static_sprite_button.disabled = current_section != ContentEditorData.SECTION_SPRITES or has_unsaved_changes


func _reload_content_db() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("load_all"):
		content_db.load_all()


func _get_animation_set_animations() -> Dictionary:
	if not current_record.has("animations") or not current_record["animations"] is Dictionary:
		current_record["animations"] = {}

	return current_record["animations"] as Dictionary


func _ensure_character_animation_set() -> void:
	if selected_animation_set_id.is_empty():
		selected_animation_set_id = _get_default_character_animation_set_id()
	if selected_animation_set_id.is_empty():
		selected_animation_set_id = data_store.create_unique_id(ContentEditorData.SECTION_ANIMATION_SETS, "%s_animations" % _get_line_edit_text("id"))

	current_record["animation_set_id"] = selected_animation_set_id
	current_record["sprite_sheet_id"] = selected_sprite_sheet_id

	if not data_store.has_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id):
		var animation_set_record := {
			"id": selected_animation_set_id,
			"display_name": "%s Animations" % _get_line_edit_text("display_name"),
			"sprite_sheet_id": selected_sprite_sheet_id,
			"anchor": {
				"x": 32,
				"y": 44,
			},
			"direction_mode": "4dir",
			"animations": {},
		}
		data_store.set_record(ContentEditorData.SECTION_ANIMATION_SETS, "", selected_animation_set_id, animation_set_record)
	else:
		var animation_set_record := data_store.get_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id)
		animation_set_record["sprite_sheet_id"] = selected_sprite_sheet_id
		data_store.set_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id, selected_animation_set_id, animation_set_record)


func _get_character_animation_set_record() -> Dictionary:
	if selected_animation_set_id.is_empty() or not data_store.has_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id):
		return {}

	return data_store.get_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id)


func _get_character_animation_set_animations() -> Dictionary:
	var animation_set_record := _get_character_animation_set_record()
	if animation_set_record.is_empty():
		return {}

	var animations = animation_set_record.get("animations", {})
	if not animations is Dictionary:
		animations = {}

	return animations


func _get_character_animation_data(animation_name: String) -> Dictionary:
	var animations := _get_character_animation_set_animations()
	if animations.has(animation_name) and animations[animation_name] is Dictionary:
		var animation_data: Dictionary = animations[animation_name]
		var copied_data := animation_data.duplicate(true)
		if not copied_data.has("frame_count"):
			var frames = copied_data.get("frames", [])
			var frame_count_from_frames: int = 1
			if frames is Array:
				frame_count_from_frames = frames.size()
			copied_data["frame_count"] = max(_get_default_character_frame_count(animation_name), int(frame_count_from_frames))
		return copied_data

	return _make_character_animation_data(animation_name, [])


func _set_character_animation_data(animation_name: String, animation_data: Dictionary) -> void:
	_ensure_character_animation_set()
	var animation_set_record := _get_character_animation_set_record()
	if animation_set_record.is_empty():
		return

	var animations = animation_set_record.get("animations", {})
	if not animations is Dictionary:
		animations = {}

	animations[animation_name] = animation_data
	animation_set_record["animations"] = animations
	data_store.set_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id, selected_animation_set_id, animation_set_record)


func _get_character_direction_mode() -> String:
	var animation_set_record := _get_character_animation_set_record()
	return str(animation_set_record.get("direction_mode", "4dir")) if not animation_set_record.is_empty() else "4dir"


func _set_character_direction_mode(direction_mode: String) -> void:
	_ensure_character_animation_set()
	var animation_set_record := _get_character_animation_set_record()
	if animation_set_record.is_empty():
		return

	animation_set_record["direction_mode"] = direction_mode if direction_mode == "8dir" else "4dir"
	data_store.set_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id, selected_animation_set_id, animation_set_record)


func _apply_character_frames_to_active(frames: Array) -> void:
	_ensure_character_animation_set()
	var animation_data := _get_character_animation_data(active_character_animation_name)
	var mode := _get_option_button_metadata("character_apply_mode")
	if mode == "append":
		var existing_frames = animation_data.get("frames", [])
		if not existing_frames is Array:
			existing_frames = []
		for frame in frames:
			existing_frames.append(int(frame))
		animation_data["frames"] = existing_frames
	else:
		var clean_frames := []
		for frame in frames:
			clean_frames.append(int(frame))
		animation_data["frames"] = clean_frames

	_set_character_animation_data(active_character_animation_name, animation_data)
	_build_form_for_current_record()
	_mark_dirty()


func _make_character_animation_data(animation_name: String, frames: Array) -> Dictionary:
	return {
		"frames": frames,
		"frame_count": _get_default_character_frame_count(animation_name),
		"fps": _get_default_animation_fps(animation_name),
		"loop": true,
	}


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


func _update_character_grid_preview() -> void:
	if animation_grid_preview == null:
		return

	var sheet_record := _get_selected_sprite_sheet_record()
	var texture := _load_texture(str(sheet_record.get("texture_path", "")))
	if texture == null:
		animation_grid_preview.clear_preview()
		return

	animation_grid_preview.set_preview_data(texture, int(sheet_record.get("columns", 0)), int(sheet_record.get("rows", 0)))
	if active_character_animation_name.is_empty():
		animation_grid_preview.set_selected_frames([])
	else:
		animation_grid_preview.set_selected_frames(_get_character_animation_frames(active_character_animation_name))


func _update_character_preview_frame() -> void:
	if animation_preview_rect == null:
		return

	if active_character_animation_name.is_empty():
		_update_character_preview_info("Choose an animation to preview.")
		return

	var frames := _get_character_animation_frames(active_character_animation_name)
	if frames.is_empty():
		_update_character_preview_info("Animation has no frames.")
		return

	animation_preview_frame_index = clamp(animation_preview_frame_index, 0, frames.size() - 1)
	animation_preview_rect.texture = _make_frame_texture(frames[animation_preview_frame_index])
	var zoom_scale := _get_preview_zoom_scale("character_preview_zoom")
	if zoom_scale > 0.0 and animation_preview_rect.texture != null:
		animation_preview_rect.custom_minimum_size = animation_preview_rect.texture.get_size() * zoom_scale
	else:
		animation_preview_rect.custom_minimum_size = Vector2(180, 180)
	_update_character_preview_info()


func _update_current_preview_frame() -> void:
	if current_section == ContentEditorData.SECTION_CHARACTERS:
		_update_character_preview_frame()
	else:
		_update_animation_preview_frame()


func _get_current_preview_frames() -> Array:
	if current_section == ContentEditorData.SECTION_CHARACTERS:
		return _get_character_animation_frames(active_character_animation_name)

	return _get_selected_animation_frames()


func _get_current_preview_fps() -> float:
	if current_section != ContentEditorData.SECTION_CHARACTERS:
		return float(_get_spin_box_value("animation_fps"))

	var animation_data := _get_character_animation_data(active_character_animation_name)
	return float(animation_data.get("fps", _get_default_animation_fps(active_character_animation_name)))


func _get_current_preview_loop() -> bool:
	if current_section != ContentEditorData.SECTION_CHARACTERS:
		return _get_check_box_pressed("animation_loop")

	var animation_data := _get_character_animation_data(active_character_animation_name)
	return bool(animation_data.get("loop", true))


func _update_character_preview_info(extra_message := "") -> void:
	if character_preview_info_label == null:
		return

	var animation_data := _get_character_animation_data(active_character_animation_name)
	var lines := [
		"animation_set_id: %s" % selected_animation_set_id,
		"sprite_sheet_id: %s" % selected_sprite_sheet_id,
		"current_animation: %s" % active_character_animation_name,
		"current_frame_index: %d" % animation_preview_frame_index,
		"fps: %s" % str(animation_data.get("fps", "-")),
		"loop: %s" % str(animation_data.get("loop", "-")),
	]
	if not extra_message.is_empty():
		lines.append(extra_message)

	character_preview_info_label.text = "\n".join(lines)


func _get_character_animation_frames(animation_name: String) -> Array:
	var animation_data := _get_character_animation_data(animation_name)
	var frames = animation_data.get("frames", [])
	if not frames is Array:
		return []

	var clean_frames := []
	for frame in frames:
		clean_frames.append(int(frame))

	return clean_frames


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


func _get_required_character_animation_names() -> Array:
	return [
		"idle_down",
		"idle_up",
		"idle_left",
		"idle_right",
		"walk_down",
		"walk_up",
		"walk_left",
		"walk_right",
	]


func _get_diagonal_character_animation_names() -> Array:
	return [
		"idle_down_left",
		"idle_down_right",
		"idle_up_left",
		"idle_up_right",
		"walk_down_left",
		"walk_down_right",
		"walk_up_left",
		"walk_up_right",
	]


func _get_character_animation_slot_names() -> Array:
	var names := _get_required_character_animation_names()
	if _get_character_direction_mode() == "8dir":
		names.append_array(_get_diagonal_character_animation_names())

	return names


func _get_character_available_animation_names() -> Array:
	var names := _get_character_animation_slot_names()
	var animations := _get_character_animation_set_animations()
	for animation_name in animations.keys():
		var clean_name := str(animation_name)
		if not names.has(clean_name):
			names.append(clean_name)
	names.sort()
	return names


func _get_default_character_frame_count(animation_name: String) -> int:
	if animation_name.begins_with("walk"):
		return 6

	return 1


func _get_character_animation_warning(animation_name: String, animation_data: Dictionary) -> String:
	var frames = animation_data.get("frames", [])
	if not frames is Array:
		return "Warning: frames is not a list."

	if frames.is_empty():
		return "Warning: animation has no frames."

	if _has_invalid_character_frame(frames):
		return "Error: animation has frame outside Sprite Sheet range."

	var frame_count := int(animation_data.get("frame_count", _get_default_character_frame_count(animation_name)))
	if frames.size() < frame_count:
		return "Warning: %d/%d frames selected." % [frames.size(), frame_count]

	if animation_name.begins_with("walk") and frames.size() == 1:
		return "Warning: walk animation has only 1 frame."

	return ""


func _get_character_animation_status(animation_name: String, animation_data: Dictionary) -> String:
	var frames = animation_data.get("frames", [])
	if not frames is Array:
		return "Invalid frame"
	if frames.is_empty():
		return "Empty"
	if _has_invalid_character_frame(frames):
		return "Invalid frame"

	var frame_count := int(animation_data.get("frame_count", _get_default_character_frame_count(animation_name)))
	if frames.size() < frame_count:
		return "Missing frames"

	return "Complete"


func _has_invalid_character_frame(frames: Array) -> bool:
	var total_frames := _get_selected_sprite_sheet_total_frames()
	if total_frames < 1:
		return false

	for frame in frames:
		var frame_index := int(frame)
		if frame_index < 0 or frame_index >= total_frames:
			return true

	return false


func _get_selected_sprite_sheet_total_frames() -> int:
	var sheet_record := _get_selected_sprite_sheet_record()
	var total_frames := int(sheet_record.get("total_frames", 0))
	if total_frames > 0:
		return total_frames

	return int(sheet_record.get("columns", 0)) * int(sheet_record.get("rows", 0))


func _validate_character_animations() -> Array:
	var results := []
	var character_id := _get_line_edit_text("id")
	if character_id.is_empty():
		results.append("ERROR: Character id is empty.")

	if selected_sprite_sheet_id.is_empty():
		results.append("ERROR: Character has no sprite_sheet_id.")
	elif not data_store.has_record(ContentEditorData.SECTION_SPRITES, selected_sprite_sheet_id):
		results.append("ERROR: Sprite Sheet does not exist: %s" % selected_sprite_sheet_id)

	if selected_animation_set_id.is_empty():
		results.append("ERROR: Character has no animation_set_id.")
	elif not data_store.has_record(ContentEditorData.SECTION_ANIMATION_SETS, selected_animation_set_id):
		results.append("ERROR: Animation Set does not exist: %s" % selected_animation_set_id)

	var sheet_record := _get_selected_sprite_sheet_record()
	if not sheet_record.is_empty():
		if int(sheet_record.get("frame_width", 0)) < 1:
			results.append("ERROR: Sprite Sheet frame_width must be valid.")
		if int(sheet_record.get("frame_height", 0)) < 1:
			results.append("ERROR: Sprite Sheet frame_height must be valid.")
		if int(sheet_record.get("columns", 0)) < 1:
			results.append("ERROR: Sprite Sheet columns must be valid.")
		if int(sheet_record.get("rows", 0)) < 1:
			results.append("ERROR: Sprite Sheet rows must be valid.")

	var animations := _get_character_animation_set_animations()
	var total_frames := _get_selected_sprite_sheet_total_frames()
	for animation_name in _get_character_animation_slot_names():
		if not animations.has(animation_name):
			results.append("ERROR: Missing required animation: %s" % animation_name)
			continue

		var animation_data = animations[animation_name]
		if not animation_data is Dictionary:
			results.append("ERROR: Animation %s data is invalid." % animation_name)
			continue

		var frame_count := int(animation_data.get("frame_count", 0))
		if frame_count < 1:
			results.append("ERROR: %s frame_count must be >= 1." % animation_name)
		if float(animation_data.get("fps", 0.0)) <= 0.0:
			results.append("ERROR: %s fps must be > 0." % animation_name)
		if not animation_data.has("loop"):
			results.append("WARNING: %s loop is not defined." % animation_name)

		var frames = animation_data.get("frames", [])
		if not frames is Array:
			results.append("ERROR: %s frames must be a list." % animation_name)
			continue

		if frames.is_empty():
			results.append("WARNING: %s has no frames." % animation_name)
		elif frames.size() < frame_count:
			results.append("WARNING: %s has %d/%d frames." % [animation_name, frames.size(), frame_count])

		if animation_name.begins_with("walk") and frames.size() == 1:
			results.append("WARNING: %s has only 1 frame." % animation_name)

		for frame in frames:
			var frame_index := int(frame)
			if frame_index < 0 or (total_frames > 0 and frame_index >= total_frames):
				results.append("ERROR: %s has frame outside range: %d." % [animation_name, frame_index])

	if results.is_empty():
		results.append("OK: Character animations are valid.")

	return results


func _get_combat_preview_setup() -> Dictionary:
	var attacker_type: String = _get_option_button_metadata("combat_attacker_type")
	var target_type: String = _get_option_button_metadata("combat_target_type")
	var attacker_id: String = _get_option_button_metadata("combat_attacker")
	var target_id: String = _get_option_button_metadata("combat_target")
	if attacker_id.is_empty():
		return {"ok": false, "error": "Choose a valid attacker."}
	if target_id.is_empty():
		return {"ok": false, "error": "Choose a valid target."}

	var attacker: Dictionary = _get_combat_actor_data(attacker_type, attacker_id)
	var target: Dictionary = _get_combat_actor_data(target_type, target_id)
	if attacker.is_empty():
		return {"ok": false, "error": "Attacker data is invalid."}
	if target.is_empty():
		return {"ok": false, "error": "Target data is invalid."}

	var weapon: Dictionary = _get_combat_weapon_data()
	var attacker_derived: Dictionary = combat_calculator.calculate_derived_stats(attacker, weapon)
	var target_derived: Dictionary = combat_calculator.calculate_derived_stats(target)
	var damage_preview: Dictionary = combat_calculator.get_damage_preview(attacker, weapon)
	return {
		"ok": true,
		"attacker": attacker,
		"target": target,
		"weapon": weapon,
		"attacker_derived": attacker_derived,
		"target_derived": target_derived,
		"damage_preview": damage_preview,
	}


func _get_combat_actor_data(actor_type: String, actor_id: String) -> Dictionary:
	var section := ContentEditorData.SECTION_CHARACTERS if actor_type == "character" else ContentEditorData.SECTION_MONSTERS
	if actor_id.is_empty() or not data_store.has_record(section, actor_id):
		return {}

	var record := data_store.get_record(section, actor_id)
	if actor_type == "monster":
		record["damage"] = int(record.get("damage", 5))
	record["id"] = actor_id
	return record


func _get_combat_weapon_data() -> Dictionary:
	var item_id := _get_option_button_metadata("combat_weapon")
	if item_id.is_empty() or not data_store.has_record(ContentEditorData.SECTION_ITEMS, item_id):
		return {
			"id": "hands",
			"display_name": "Hands",
			"combat": {
				"attack_power": 0,
				"attack_variance": 0.15,
			},
		}

	return data_store.get_record(ContentEditorData.SECTION_ITEMS, item_id)


func _set_combat_results(text: String) -> void:
	if not field_controls.has("combat_results"):
		return

	var results: Label = field_controls["combat_results"]
	results.text = text


func _format_combat_once_result(setup: Dictionary, result: Dictionary) -> String:
	var lines := _format_combat_setup_summary(setup)
	lines.append("")
	lines.append("Calculate Once")
	lines.append("Hit: %s" % str(result.get("hit", false)))
	lines.append("Miss: %s" % str(result.get("miss", false)))
	lines.append("Damage: %d" % int(result.get("damage", 0)))
	lines.append("Critical: %s" % str(result.get("is_critical", false)))
	lines.append("Damage Type: %s" % str(result.get("damage_type", "physical")))
	return "\n".join(lines)


func _format_combat_simulation_result(setup: Dictionary, average_damage: float, min_damage: int, max_damage: int, crit_count: int, miss_count: int, estimated_dps: float) -> String:
	var lines := _format_combat_setup_summary(setup)
	lines.append("")
	lines.append("Simulate 100 Hits")
	lines.append("Average Damage: %.2f" % average_damage)
	lines.append("Min Damage: %d" % min_damage)
	lines.append("Max Damage: %d" % max_damage)
	lines.append("Crit Count: %d" % crit_count)
	lines.append("Crit Rate: %.1f%%" % float(crit_count))
	lines.append("Miss Count: %d" % miss_count)
	lines.append("Miss Rate: %.1f%%" % float(miss_count))
	lines.append("Estimated DPS: %.2f" % estimated_dps)
	return "\n".join(lines)


func _format_combat_setup_summary(setup: Dictionary) -> Array:
	var attacker_derived: Dictionary = setup["attacker_derived"]
	var target_derived: Dictionary = setup["target_derived"]
	var damage_preview: Dictionary = setup["damage_preview"]
	var hit_chance: float = clamp(0.75 + (float(attacker_derived.get("hit", 0.0)) - float(target_derived.get("flee", 0.0))) * 0.005, 0.15, 0.97)
	return [
		"Attacker Derived",
		"  Physical Attack: %.2f" % float(attacker_derived.get("physical_attack", 0.0)),
		"  Hit: %.2f" % float(attacker_derived.get("hit", 0.0)),
		"  Crit Chance: %.1f%%" % (float(attacker_derived.get("crit_chance", 0.0)) * 100.0),
		"  Crit Damage: %.2fx" % float(attacker_derived.get("crit_damage", 1.0)),
		"  Attack Cooldown: %.2fs" % float(attacker_derived.get("attack_cooldown", 0.0)),
		"",
		"Target Derived",
		"  Defense: %.2f" % float(target_derived.get("defense", 0.0)),
		"  Flee: %.2f" % float(target_derived.get("flee", 0.0)),
		"",
		"Estimated",
		"  Hit Chance: %.1f%%" % (hit_chance * 100.0),
		"  Damage Range: %d - %d" % [int(damage_preview.get("min_damage", 0)), int(damage_preview.get("max_damage", 0))],
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


func _get_default_character_animation_set_id() -> String:
	if data_store.has_record(ContentEditorData.SECTION_ANIMATION_SETS, "player_base_body"):
		return "player_base_body"

	var records := data_store.get_records(ContentEditorData.SECTION_ANIMATION_SETS)
	if records.is_empty():
		return ""

	return str(records[0].get("id", ""))


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
