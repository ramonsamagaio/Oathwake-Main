extends Control

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const SaveSlotSelectScene := preload("res://scenes/ui/SaveSlotSelect.tscn")

const BASE_MENU_TEXTURE := preload("res://assets/ui/MM_UI/BASE _MENU.png")
const BUTTON_OFF_TEXTURE := preload("res://assets/ui/MM_UI/BUTTON_OFF.png")
const BUTTON_ON_TEXTURE := preload("res://assets/ui/MM_UI/BUTTON_ON.png")

@export var show_background := true

var _menu_root: Control
var _save_slot_select: Control
var _notice_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	if show_background:
		var background := ColorRect.new()
		background.color = Color(0.03, 0.04, 0.07, 0.78)
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(background)

	_menu_root = Control.new()
	_menu_root.name = "MainMenuVisual"
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_root)

	var panel := TextureRect.new()
	panel.name = "menu.options_panel"
	_set_control_rect(panel, Rect2(612, 238, 375, 472))
	panel.texture = BASE_MENU_TEXTURE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(panel)

	_menu_root.add_child(_make_mm_button("New Game", Rect2(644, 294, 313, 104), _on_new_game_pressed, true))
	_menu_root.add_child(_make_mm_button("Load Game", Rect2(643, 374, 313, 104), _on_load_game_pressed, true))
	_menu_root.add_child(_make_mm_button("Settings", Rect2(643, 453, 313, 104), _on_settings_pressed, true))
	_menu_root.add_child(_make_mm_button("Quit", Rect2(642, 532, 313, 104), _on_quit_pressed, true))

	_notice_label = Label.new()
	_notice_label.name = "NoticeLabel"
	_set_control_rect(_notice_label, Rect2(620, 672, 360, 30))
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.text = ""
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(_notice_label)
	OathwakeTextStyle.apply_profile_to_label(_notice_label, "base_ui")

	_save_slot_select = SaveSlotSelectScene.instantiate()
	_save_slot_select.back_requested.connect(_on_slot_select_back_requested)
	add_child(_save_slot_select)


func _make_mm_button(text_value: String, rect: Rect2, callback: Callable, enabled := true) -> TextureButton:
	var button := TextureButton.new()
	button.name = text_value.to_lower().replace(" ", "_")
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


func _show_notice(text_value: String) -> void:
	if _notice_label == null:
		return
	_notice_label.text = text_value
	var tween := create_tween()
	_notice_label.modulate.a = 1.0
	tween.tween_interval(1.4)
	tween.tween_property(_notice_label, "modulate:a", 0.0, 0.35)
	tween.finished.connect(func() -> void:
		_notice_label.text = ""
		_notice_label.modulate.a = 1.0
	)


func _on_new_game_pressed() -> void:
	_menu_root.hide()
	_save_slot_select.open_for("new")


func _on_load_game_pressed() -> void:
	_menu_root.hide()
	_save_slot_select.open_for("load")


func _on_settings_pressed() -> void:
	_show_notice("Settings coming soon.")


func _on_slot_select_back_requested() -> void:
	_menu_root.show()


func _on_quit_pressed() -> void:
	get_tree().quit()
