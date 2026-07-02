extends Control

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const SaveSlotSelectScene := preload("res://scenes/ui/SaveSlotSelect.tscn")

var _menu_panel: Panel
var _credits_panel: Panel
var _save_slot_select: Control


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.08, 0.10, 0.14, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_menu_panel = Panel.new()
	_menu_panel.custom_minimum_size = Vector2(520, 560)
	_menu_panel.anchor_left = 0.5
	_menu_panel.anchor_top = 0.5
	_menu_panel.anchor_right = 0.5
	_menu_panel.anchor_bottom = 0.5
	_menu_panel.offset_left = -260.0
	_menu_panel.offset_top = -280.0
	_menu_panel.offset_right = 260.0
	_menu_panel.offset_bottom = 280.0
	add_child(_menu_panel)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 28.0
	layout.offset_top = 28.0
	layout.offset_right = -28.0
	layout.offset_bottom = -28.0
	layout.add_theme_constant_override("separation", 16)
	_menu_panel.add_child(layout)

	var title := Label.new()
	title.text = "Oathwake"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	OathwakeTextStyle.apply_profile_to_label(title, "ui_title")

	var subtitle := Label.new()
	subtitle.text = "Godot Survival Prototype"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(subtitle)
	OathwakeTextStyle.apply_profile_to_label(subtitle, "base_ui")

	layout.add_child(_make_menu_button("New Game", _on_new_game_pressed))
	layout.add_child(_make_menu_button("Load Game", _on_load_game_pressed))

	var multiplayer_button := _make_menu_button("Multiplayer disabled", Callable())
	multiplayer_button.disabled = true
	layout.add_child(multiplayer_button)

	var settings_button := _make_menu_button("Settings placeholder", Callable())
	settings_button.disabled = true
	layout.add_child(settings_button)

	layout.add_child(_make_menu_button("Credits", _on_credits_pressed))
	layout.add_child(_make_menu_button("Quit", _on_quit_pressed))

	_credits_panel = _build_credits_panel()
	add_child(_credits_panel)
	_credits_panel.hide()

	_save_slot_select = SaveSlotSelectScene.instantiate()
	_save_slot_select.back_requested.connect(_on_slot_select_back_requested)
	add_child(_save_slot_select)


func _make_menu_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 56)
	button.focus_mode = Control.FOCUS_NONE
	if callback.is_valid():
		button.pressed.connect(callback)
	OathwakeTextStyle.apply_profile_to_control(button, "ui_button")
	return button


func _build_credits_panel() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(520, 300)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260.0
	panel.offset_top = -150.0
	panel.offset_right = 260.0
	panel.offset_bottom = 150.0

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 24.0
	layout.offset_top = 24.0
	layout.offset_right = -24.0
	layout.offset_bottom = -24.0
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)

	var title := Label.new()
	title.text = "Credits"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	OathwakeTextStyle.apply_profile_to_label(title, "ui_title")

	var body := Label.new()
	body.text = "Oathwake prototype\nBuilt in Godot 4.6\nMenu and slot flow placeholder"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	OathwakeTextStyle.apply_profile_to_label(body, "base_ui")

	var back_button := _make_menu_button("Back", _on_credits_back_pressed)
	layout.add_child(back_button)

	return panel


func _on_new_game_pressed() -> void:
	_menu_panel.hide()
	_credits_panel.hide()
	_save_slot_select.open_for("new")


func _on_load_game_pressed() -> void:
	_menu_panel.hide()
	_credits_panel.hide()
	_save_slot_select.open_for("load")


func _on_credits_pressed() -> void:
	_menu_panel.hide()
	_credits_panel.show()


func _on_credits_back_pressed() -> void:
	_credits_panel.hide()
	_menu_panel.show()


func _on_slot_select_back_requested() -> void:
	_menu_panel.show()


func _on_quit_pressed() -> void:
	get_tree().quit()
