extends Control

signal back_requested

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const GAME_SCENE_PATH := "res://scenes/Main.tscn"
const SLOT_IDS := ["slot_1", "slot_2", "slot_3"]

var _mode := "load"
var _pending_slot_id := ""
var _title_label: Label
var _slot_buttons := {}
var _confirm_dialog: ConfirmationDialog


func _ready() -> void:
	_build_ui()
	hide()


func open_for(mode: String) -> void:
	_mode = mode if mode == "new" else "load"
	_pending_slot_id = ""
	_refresh_slot_buttons()
	_title_label.text = "Choose Slot" if _mode == "new" else "Load Slot"
	show()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.07, 0.10, 0.86)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(560, 420)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280.0
	panel.offset_top = -210.0
	panel.offset_right = 280.0
	panel.offset_bottom = 210.0
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 24.0
	layout.offset_top = 20.0
	layout.offset_right = -24.0
	layout.offset_bottom = -20.0
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.text = "Choose Slot"
	layout.add_child(_title_label)
	OathwakeTextStyle.apply_profile_to_label(_title_label, "ui_title")

	for slot_id in SLOT_IDS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 72)
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_on_slot_pressed.bind(slot_id))
		layout.add_child(button)
		_slot_buttons[slot_id] = button
		OathwakeTextStyle.apply_profile_to_control(button, "ui_button")

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(_on_back_pressed)
	layout.add_child(back_button)
	OathwakeTextStyle.apply_profile_to_control(back_button, "ui_button")

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Overwrite Save"
	_confirm_dialog.dialog_text = "This slot already has a save. Overwrite it?"
	_confirm_dialog.confirmed.connect(_confirm_new_game_overwrite)
	add_child(_confirm_dialog)


func _refresh_slot_buttons() -> void:
	var save_slot_manager := _get_save_slot_manager()
	for slot_id in SLOT_IDS:
		var button: Button = _slot_buttons[slot_id]
		var summary: Dictionary = save_slot_manager.get_slot_summary(slot_id)
		var slot_label: String = slot_id.replace("_", " ").capitalize()
		if not bool(summary.get("exists", false)):
			button.text = "%s  |  Empty" % slot_label
			button.disabled = _mode == "load"
			continue

		if not bool(summary.get("valid", true)):
			button.text = "%s  |  Invalid Save" % slot_label
			button.disabled = _mode == "load"
			continue

		button.text = "%s  |  LV %d  XP %d/%d" % [
			slot_label,
			int(summary.get("level", 1)),
			int(summary.get("current_xp", 0)),
			int(summary.get("xp_to_next_level", 30)),
		]
		button.disabled = false


func _on_slot_pressed(slot_id: String) -> void:
	var save_slot_manager := _get_save_slot_manager()
	if _mode == "new":
		if save_slot_manager.slot_exists(slot_id):
			_pending_slot_id = slot_id
			_confirm_dialog.popup_centered()
			return
		_start_game_in_slot(slot_id, false)
		return

	if not save_slot_manager.slot_exists(slot_id):
		return

	_start_game_in_slot(slot_id, true)


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
