extends Control

signal back_requested

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const GAME_SCENE_PATH := "res://scenes/Main.tscn"
const SLOT_IDS := ["slot_1", "slot_2", "slot_3"]

const BASE_MENU_TEXTURE := preload("res://assets/ui/MM_UI/BASE _MENU.png")
const BUTTON_OFF_TEXTURE := preload("res://assets/ui/MM_UI/BUTTON_OFF.png")
const BUTTON_ON_TEXTURE := preload("res://assets/ui/MM_UI/BUTTON_ON.png")
const SMALL_BUTTON_TEXTURE := preload("res://assets/ui/MM_UI/BUTTON_PEQUENO.png")

var _mode := "load"
var _selected_slot_id := ""
var _pending_slot_id := ""
var _root: Control
var _title_label: Label
var _slot_buttons := {}
var _slot_labels := {}
var _load_button: TextureButton
var _delete_button: TextureButton
var _confirm_dialog: ConfirmationDialog


func _ready() -> void:
	_build_ui()
	hide()


func open_for(mode: String) -> void:
	_mode = mode if mode == "new" else "load"
	_selected_slot_id = ""
	_pending_slot_id = ""
	_refresh_slot_buttons()
	_refresh_action_buttons()
	_title_label.text = "Choose Slot" if _mode == "new" else "Load Slot"
	show()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_root = Control.new()
	_root.name = "SaveSelectVisual"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var panel := TextureRect.new()
	panel.name = "save.panel"
	_set_control_rect(panel, Rect2(612, 238, 375, 472))
	panel.texture = BASE_MENU_TEXTURE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_set_control_rect(_title_label, Rect2(650, 250, 300, 30))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_label)
	OathwakeTextStyle.apply_profile_to_label(_title_label, "ui_title")

	for index in range(SLOT_IDS.size()):
		var slot_id := SLOT_IDS[index]
		var y := 277.0 + float(index) * 81.0
		var button := _make_large_button("", Rect2(643, y, 313, 104), _on_slot_pressed.bind(slot_id), true)
		button.name = "save_%s_button" % slot_id
		_root.add_child(button)
		_slot_buttons[slot_id] = button

		var label := Label.new()
		label.name = "%s_label" % slot_id
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
		_slot_labels[slot_id] = label
		OathwakeTextStyle.apply_profile_to_label(label, "ui_button")

	_load_button = _make_small_button("Start", Rect2(648, 540, 99, 56), _on_load_or_start_pressed)
	_root.add_child(_load_button)

	_delete_button = _make_small_button("Delete", Rect2(751, 540, 99, 56), _on_delete_pressed)
	_root.add_child(_delete_button)

	var back_button := _make_small_button("Back", Rect2(854, 540, 99, 56), _on_back_pressed)
	_root.add_child(back_button)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Overwrite Save"
	_confirm_dialog.dialog_text = "This slot already has a save. Overwrite it?"
	_confirm_dialog.confirmed.connect(_confirm_new_game_overwrite)
	add_child(_confirm_dialog)


func _make_large_button(_text_value: String, rect: Rect2, callback: Callable, enabled := true) -> TextureButton:
	var button := TextureButton.new()
	_set_control_rect(button, rect)
	button.texture_normal = BUTTON_OFF_TEXTURE
	button.texture_hover = BUTTON_ON_TEXTURE if enabled else BUTTON_OFF_TEXTURE
	button.texture_pressed = BUTTON_ON_TEXTURE if enabled else BUTTON_OFF_TEXTURE
	button.texture_disabled = BUTTON_OFF_TEXTURE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not enabled
	if enabled and callback.is_valid():
		button.pressed.connect(callback)
	return button


func _make_small_button(text_value: String, rect: Rect2, callback: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.name = text_value.to_lower().replace(" ", "_")
	_set_control_rect(button, rect)
	button.texture_normal = SMALL_BUTTON_TEXTURE
	button.texture_hover = SMALL_BUTTON_TEXTURE
	button.texture_pressed = SMALL_BUTTON_TEXTURE
	button.texture_disabled = SMALL_BUTTON_TEXTURE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.focus_mode = Control.FOCUS_NONE
	if callback.is_valid():
		button.pressed.connect(callback)

	var label := Label.new()
	label.text = text_value
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	OathwakeTextStyle.apply_profile_to_label(label, "ui_button")
	return button


func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


func _refresh_slot_buttons() -> void:
	var save_slot_manager := _get_save_slot_manager()
	for slot_id in SLOT_IDS:
		var button: TextureButton = _slot_buttons[slot_id]
		var label: Label = _slot_labels[slot_id]
		var summary: Dictionary = save_slot_manager.get_slot_summary(slot_id)
		var slot_label: String = slot_id.replace("_", " ").capitalize()
		var enabled := true
		if not bool(summary.get("exists", false)):
			label.text = "%s\nEmpty" % slot_label
			enabled = _mode == "new"
		elif not bool(summary.get("valid", true)):
			label.text = "%s\nInvalid Save" % slot_label
			enabled = _mode == "new"
		else:
			label.text = "%s\nLV %d  XP %d/%d" % [
				slot_label,
				int(summary.get("level", 1)),
				int(summary.get("current_xp", 0)),
				int(summary.get("xp_to_next_level", 30)),
			]
			enabled = true
		button.disabled = not enabled
		_update_slot_texture_state(slot_id)


func _update_slot_texture_state(slot_id: String) -> void:
	if not _slot_buttons.has(slot_id):
		return
	var button: TextureButton = _slot_buttons[slot_id]
	var selected := slot_id == _selected_slot_id
	button.texture_normal = BUTTON_ON_TEXTURE if selected else BUTTON_OFF_TEXTURE
	button.texture_hover = BUTTON_ON_TEXTURE
	button.texture_pressed = BUTTON_ON_TEXTURE


func _refresh_all_slot_texture_states() -> void:
	for slot_id in SLOT_IDS:
		_update_slot_texture_state(slot_id)


func _refresh_action_buttons() -> void:
	if _load_button == null or _delete_button == null:
		return
	var has_selection := not _selected_slot_id.is_empty()
	_load_button.disabled = not has_selection
	_delete_button.disabled = not has_selection or not _get_save_slot_manager().slot_exists(_selected_slot_id)
	var load_label := _load_button.get_child(0) as Label
	if load_label != null:
		load_label.text = "Start" if _mode == "new" else "Load"


func _on_slot_pressed(slot_id: String) -> void:
	_selected_slot_id = slot_id
	_refresh_all_slot_texture_states()
	_refresh_action_buttons()


func _on_load_or_start_pressed() -> void:
	if _selected_slot_id.is_empty():
		return
	var save_slot_manager := _get_save_slot_manager()
	if _mode == "new":
		if save_slot_manager.slot_exists(_selected_slot_id):
			_pending_slot_id = _selected_slot_id
			_confirm_dialog.popup_centered()
			return
		_start_game_in_slot(_selected_slot_id, false)
		return

	if not save_slot_manager.slot_exists(_selected_slot_id):
		return
	_start_game_in_slot(_selected_slot_id, true)


func _on_delete_pressed() -> void:
	if _selected_slot_id.is_empty():
		return
	var save_slot_manager := _get_save_slot_manager()
	if save_slot_manager.delete_slot(_selected_slot_id):
		_selected_slot_id = ""
		_refresh_slot_buttons()
		_refresh_action_buttons()


func _confirm_new_game_overwrite() -> void:
	if _pending_slot_id.is_empty():
		return
	_start_game_in_slot(_pending_slot_id, false)


func _start_game_in_slot(slot_id: String, preserve_existing_save: bool) -> void:
	var save_slot_manager := _get_save_slot_manager()
	save_slot_manager.set_active_slot(slot_id)
	if not preserve_existing_save and save_slot_manager.slot_exists(slot_id):
		save_slot_manager.delete_slot(slot_id)
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_back_pressed() -> void:
	hide()
	back_requested.emit()


func _get_save_slot_manager() -> Node:
	var manager := get_node_or_null("/root/SaveSlotManager")
	if manager != null:
		return manager
	return preload("res://scripts/systems/SaveSlotManager.gd").new()
