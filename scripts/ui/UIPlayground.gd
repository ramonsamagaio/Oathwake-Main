extends Control

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const OathwakeUISkin := preload("res://scripts/ui/OathwakeUISkin.gd")

const WINDOW_SIZE := Vector2(1600, 900)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.035, 0.045, 0.06, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 30)
	outer_margin.add_theme_constant_override("margin_top", 12)
	outer_margin.add_theme_constant_override("margin_right", 30)
	outer_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(outer_margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	outer_margin.add_child(content)

	var title := _make_label("Oathwake UI Playground", "ui_title", HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(title)

	var subtitle := _make_label("One-screen showcase for skins, slots, bars and texture validation.", "base_ui", HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(subtitle)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	content.add_child(columns)

	var col_a := _make_column()
	var col_b := _make_column()
	var col_c := _make_column()
	columns.add_child(col_a)
	columns.add_child(col_b)
	columns.add_child(col_c)

	_build_menu_section(col_a)
	_build_save_slots_section(col_a)

	_build_hud_section(col_b)
	_build_settings_section(col_b)

	_build_inventory_section(col_c)
	_build_misc_section(col_c)


func _make_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	return column


func _build_menu_section(parent: Container) -> void:
	var body := _make_section(parent, "Menu", Vector2(0, 220))

	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	body.add_child(buttons)

	buttons.add_child(_make_preview_button("Normal", "large"))
	var pressed := _make_preview_button("Pressed", "large")
	pressed.toggle_mode = true
	pressed.button_pressed = true
	buttons.add_child(pressed)

	var disabled := _make_preview_button("Disabled", "large")
	disabled.disabled = true
	buttons.add_child(disabled)
	buttons.add_child(_make_preview_button("Medium", "medium"))

	var menu_options := _make_static_skin_card("Menu options texture", "res://assets/ui/menu/panel_menu_options.png", Vector2(190, 92))
	body.add_child(menu_options)


func _build_save_slots_section(parent: Container) -> void:
	var body := _make_section(parent, "Save Slots", Vector2(0, 210))
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 5)
	body.add_child(row)

	row.add_child(_make_save_slot_button("Slot 1 | Empty", "save_empty"))
	row.add_child(_make_save_slot_button("Slot 2 | LV 3 | Day 5", "save_filled"))
	row.add_child(_make_save_slot_button("Slot 3 | Selected", "save_selected"))


func _build_hud_section(parent: Container) -> void:
	var body := _make_section(parent, "HUD", Vector2(0, 275))
	body.add_child(_make_label("Health", "base_ui"))
	body.add_child(_make_texture_bar("health_bar_frame", "health_bar_fill", 0.70, Vector2(320, 28)))
	body.add_child(_make_label("XP", "base_ui"))
	body.add_child(_make_texture_bar("xp_bar_frame", "xp_bar_fill", 0.40, Vector2(320, 24)))
	body.add_child(_make_label("Hotbar", "base_ui"))

	var hotbar_panel := PanelContainer.new()
	hotbar_panel.custom_minimum_size = Vector2(0, 76)
	hotbar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_hotbar_panel(hotbar_panel)
	body.add_child(hotbar_panel)

	var hotbar_margin := MarginContainer.new()
	hotbar_margin.add_theme_constant_override("margin_left", 8)
	hotbar_margin.add_theme_constant_override("margin_top", 8)
	hotbar_margin.add_theme_constant_override("margin_right", 8)
	hotbar_margin.add_theme_constant_override("margin_bottom", 8)
	hotbar_panel.add_child(hotbar_margin)

	var hotbar_row := HBoxContainer.new()
	hotbar_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hotbar_row.add_theme_constant_override("separation", 3)
	hotbar_margin.add_child(hotbar_row)

	for index in range(8):
		var slot := Button.new()
		slot.text = str(index + 1)
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size = Vector2(42, 42)
		OathwakeUISkin.apply_hotbar_slot_button(slot, "selected" if index == 0 else "empty")
		OathwakeTextStyle.apply_profile_to_control(slot, "base_ui")
		hotbar_row.add_child(slot)


func _build_settings_section(parent: Container) -> void:
	var body := _make_section(parent, "Settings", Vector2(0, 220))
	var checkbox_row := HBoxContainer.new()
	checkbox_row.add_theme_constant_override("separation", 12)
	body.add_child(checkbox_row)
	checkbox_row.add_child(_make_icon_sample("Off", "res://assets/ui/settings/checkbox_off.png"))
	checkbox_row.add_child(_make_icon_sample("On", "res://assets/ui/settings/checkbox_on.png"))

	body.add_child(_make_label("Slider", "base_ui"))
	var slider_wrap := Control.new()
	slider_wrap.custom_minimum_size = Vector2(0, 44)
	slider_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(slider_wrap)

	var slider_track := OathwakeUISkin.make_texture_rect("res://assets/ui/settings/slider_track.png", TextureRect.STRETCH_SCALE)
	slider_track.anchor_left = 0.0
	slider_track.anchor_top = 0.5
	slider_track.anchor_right = 1.0
	slider_track.anchor_bottom = 0.5
	slider_track.offset_top = -12.0
	slider_track.offset_bottom = 12.0
	slider_wrap.add_child(slider_track)

	var slider_knob := OathwakeUISkin.make_texture_rect("res://assets/ui/settings/slider_knob.png", TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	slider_knob.custom_minimum_size = Vector2(24, 24)
	slider_knob.anchor_left = 0.55
	slider_knob.anchor_top = 0.5
	slider_knob.anchor_right = 0.55
	slider_knob.anchor_bottom = 0.5
	slider_knob.offset_left = -12.0
	slider_knob.offset_top = -12.0
	slider_knob.offset_right = 12.0
	slider_knob.offset_bottom = 12.0
	slider_wrap.add_child(slider_knob)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	body.add_child(button_row)
	button_row.add_child(_make_preview_button("Apply", "medium"))
	var reset := _make_preview_button("Reset", "medium")
	reset.disabled = true
	button_row.add_child(reset)


func _build_inventory_section(parent: Container) -> void:
	var body := _make_section(parent, "Inventory", Vector2(0, 415))

	var static_inventory := _make_static_skin_card("Static inventory window texture", "res://assets/ui/inventory/inventory_window.png", Vector2(280, 165))
	body.add_child(static_inventory)

	var slot_grid := GridContainer.new()
	slot_grid.columns = 5
	slot_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot_grid.add_theme_constant_override("h_separation", 4)
	slot_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(slot_grid)

	for index in range(10):
		var variant := "empty"
		if index == 2:
			variant = "hover"
		elif index == 7:
			variant = "selected"
		var slot := Button.new()
		slot.text = str(index + 1)
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size = Vector2(40, 40)
		OathwakeUISkin.apply_slot_button(slot, variant)
		OathwakeTextStyle.apply_profile_to_control(slot, "base_ui")
		slot_grid.add_child(slot)

	var tooltip := PanelContainer.new()
	tooltip.custom_minimum_size = Vector2(0, 66)
	tooltip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_tooltip(tooltip)
	body.add_child(tooltip)

	var tooltip_margin := MarginContainer.new()
	tooltip_margin.add_theme_constant_override("margin_left", 10)
	tooltip_margin.add_theme_constant_override("margin_top", 6)
	tooltip_margin.add_theme_constant_override("margin_right", 10)
	tooltip_margin.add_theme_constant_override("margin_bottom", 6)
	tooltip.add_child(tooltip_margin)

	var tooltip_text := _make_label("Iron Pickaxe\nTier 2 Tool | + Gathering Power", "base_ui")
	tooltip_margin.add_child(tooltip_text)


func _build_misc_section(parent: Container) -> void:
	var body := _make_section(parent, "Misc", Vector2(0, 145))
	var row := GridContainer.new()
	row.columns = 2
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	body.add_child(row)

	row.add_child(_make_skin_preview_card("Toast", "toast", Vector2(170, 44), "Toast"))
	row.add_child(_make_skin_preview_card("Tutorial", "tutorial_panel", Vector2(170, 44), "Tutorial"))
	row.add_child(_make_skin_preview_card("Dialog", "dialog", Vector2(170, 44), "Dialog"))
	row.add_child(_make_skin_preview_card("Credits", "panel_credits", Vector2(170, 44), "Credits"))


func _make_section(parent: Container, title_text: String, min_size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_panel(panel, "panel")
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	margin.add_child(body)

	body.add_child(_make_label(title_text, "ui_title"))
	return body


func _make_label(text_value: String, profile := "base_ui", alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	OathwakeTextStyle.apply_profile_to_label(label, profile)
	return label


func _make_preview_button(text_value: String, size_key: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40) if size_key == "medium" else Vector2(0, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_button(button, size_key)
	OathwakeTextStyle.apply_profile_to_control(button, "ui_button")
	return button


func _make_save_slot_button(text_value: String, variant: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_slot_button(button, variant)
	OathwakeTextStyle.apply_profile_to_control(button, "base_ui")
	return button


func _make_icon_sample(label_text: String, texture_path: String) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.add_theme_constant_override("separation", 2)

	var icon := OathwakeUISkin.make_texture_rect(texture_path, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.add_child(icon)

	wrapper.add_child(_make_label(label_text, "base_ui", HORIZONTAL_ALIGNMENT_CENTER))
	return wrapper


func _make_texture_bar(frame_key: String, fill_key: String, ratio: float, min_size: Vector2) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = min_size
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var frame_path := _skin_path(frame_key)
	var fill_path := _skin_path(fill_key)
	var fill_width := maxf(8.0, min_size.x * clampf(ratio, 0.0, 1.0))

	var fill := OathwakeUISkin.make_texture_rect(fill_path, TextureRect.STRETCH_SCALE)
	fill.anchor_left = 0.0
	fill.anchor_top = 0.5
	fill.anchor_right = 0.0
	fill.anchor_bottom = 0.5
	fill.offset_left = 8.0
	fill.offset_top = -5.0
	fill.offset_right = fill_width
	fill.offset_bottom = 5.0
	wrapper.add_child(fill)

	var frame := OathwakeUISkin.make_texture_rect(frame_path, TextureRect.STRETCH_SCALE)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(frame)
	return wrapper


func _make_static_skin_card(label_text: String, texture_path: String, min_size: Vector2) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.add_theme_constant_override("separation", 4)

	var texture := OathwakeUISkin.make_texture_rect(texture_path, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	texture.custom_minimum_size = min_size
	texture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.add_child(texture)
	wrapper.add_child(_make_label(label_text, "base_ui", HORIZONTAL_ALIGNMENT_CENTER))
	return wrapper


func _make_skin_preview_card(title_text: String, skin_key: String, min_size: Vector2, body_text: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_panel(panel, skin_key)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var label := _make_label("%s\n%s" % [title_text, body_text], "base_ui", HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(label)
	return panel


func _skin_path(key: String) -> String:
	var skin_data := OathwakeUISkin.get_skin_data()
	var entry: Variant = skin_data.get(key, "")
	if entry is String:
		return str(entry)
	if entry is Dictionary:
		return str(entry.get("path", ""))
	return ""
