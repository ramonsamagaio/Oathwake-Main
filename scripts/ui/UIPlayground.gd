extends Control

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const OathwakeUISkin := preload("res://scripts/ui/OathwakeUISkin.gd")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.07, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 44)
	outer_margin.add_theme_constant_override("margin_top", 40)
	outer_margin.add_theme_constant_override("margin_right", 44)
	outer_margin.add_theme_constant_override("margin_bottom", 44)
	scroll.add_child(outer_margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	outer_margin.add_child(content)

	var title := Label.new()
	title.text = "Oathwake UI Playground"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	OathwakeTextStyle.apply_profile_to_label(title, "ui_title")

	var subtitle := Label.new()
	subtitle.text = "Static showcase for UI skins, fallback styles, and texture validation."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	OathwakeTextStyle.apply_profile_to_label(subtitle, "base_ui")

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	content.add_child(columns)

	var left_column := VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 24)
	columns.add_child(left_column)

	var right_column := VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 24)
	columns.add_child(right_column)

	_build_menu_section(left_column)
	_build_save_slots_section(left_column)
	_build_settings_section(left_column)

	_build_hud_section(right_column)
	_build_inventory_section(right_column)
	_build_misc_section(right_column)


func _build_menu_section(parent: Container) -> void:
	var body := _make_section(parent, "Menu Block", "panel_menu", Vector2(680, 400))

	var panel_preview := PanelContainer.new()
	panel_preview.custom_minimum_size = Vector2(0, 210)
	panel_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_panel(panel_preview, "panel_menu")
	body.add_child(panel_preview)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 18)
	panel_margin.add_theme_constant_override("margin_top", 18)
	panel_margin.add_theme_constant_override("margin_right", 18)
	panel_margin.add_theme_constant_override("margin_bottom", 18)
	panel_preview.add_child(panel_margin)

	var button_row := GridContainer.new()
	button_row.columns = 2
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_theme_constant_override("h_separation", 12)
	button_row.add_theme_constant_override("v_separation", 12)
	panel_margin.add_child(button_row)

	button_row.add_child(_make_preview_button("Normal style", "large"))

	var pressed_button := _make_preview_button("Pressed style test", "large")
	pressed_button.toggle_mode = true
	pressed_button.button_pressed = true
	button_row.add_child(pressed_button)

	var disabled_button := _make_preview_button("Disabled", "large")
	disabled_button.disabled = true
	button_row.add_child(disabled_button)

	var medium_button := _make_preview_button("Medium", "medium")
	button_row.add_child(medium_button)

	var credits_preview := PanelContainer.new()
	credits_preview.custom_minimum_size = Vector2(0, 92)
	credits_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_panel(credits_preview, "panel_credits")
	body.add_child(credits_preview)

	var credits_margin := MarginContainer.new()
	credits_margin.add_theme_constant_override("margin_left", 18)
	credits_margin.add_theme_constant_override("margin_top", 18)
	credits_margin.add_theme_constant_override("margin_right", 18)
	credits_margin.add_theme_constant_override("margin_bottom", 18)
	credits_preview.add_child(credits_margin)

	var credits_label := Label.new()
	credits_label.text = "Credits panel preview"
	credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	credits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	credits_margin.add_child(credits_label)
	OathwakeTextStyle.apply_profile_to_label(credits_label, "base_ui")


func _build_save_slots_section(parent: Container) -> void:
	var body := _make_section(parent, "Save Slots", "panel", Vector2(680, 340))

	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)

	row.add_child(_make_save_slot_button("Slot 1\nEmpty", "save_empty"))
	row.add_child(_make_save_slot_button("Slot 2\nLV 3 | Day 5", "save_filled"))
	row.add_child(_make_save_slot_button("Slot 3\nSelected", "save_selected"))


func _build_settings_section(parent: Container) -> void:
	var body := _make_section(parent, "Settings", "panel", Vector2(680, 280))

	var checkbox_row := HBoxContainer.new()
	checkbox_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checkbox_row.add_theme_constant_override("separation", 18)
	body.add_child(checkbox_row)

	checkbox_row.add_child(_make_icon_sample("Checkbox Off", "res://assets/ui/settings/checkbox_off.png"))
	checkbox_row.add_child(_make_icon_sample("Checkbox On", "res://assets/ui/settings/checkbox_on.png"))

	var slider_title := Label.new()
	slider_title.text = "Slider track + knob"
	body.add_child(slider_title)
	OathwakeTextStyle.apply_profile_to_label(slider_title, "base_ui")

	var slider_wrap := Control.new()
	slider_wrap.custom_minimum_size = Vector2(0, 48)
	slider_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(slider_wrap)

	var slider_track := OathwakeUISkin.make_texture_rect("res://assets/ui/settings/slider_track.png", TextureRect.STRETCH_SCALE)
	slider_track.anchor_left = 0.0
	slider_track.anchor_top = 0.5
	slider_track.anchor_right = 1.0
	slider_track.anchor_bottom = 0.5
	slider_track.offset_left = 0.0
	slider_track.offset_top = -12.0
	slider_track.offset_right = 0.0
	slider_track.offset_bottom = 12.0
	slider_wrap.add_child(slider_track)

	var slider_knob := OathwakeUISkin.make_texture_rect("res://assets/ui/settings/slider_knob.png", TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	slider_knob.custom_minimum_size = Vector2(24, 24)
	slider_knob.anchor_left = 0.5
	slider_knob.anchor_top = 0.5
	slider_knob.anchor_right = 0.5
	slider_knob.anchor_bottom = 0.5
	slider_knob.offset_left = -12.0
	slider_knob.offset_top = -12.0
	slider_knob.offset_right = 12.0
	slider_knob.offset_bottom = 12.0
	slider_wrap.add_child(slider_knob)

	var medium_row := HBoxContainer.new()
	medium_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	medium_row.add_theme_constant_override("separation", 12)
	body.add_child(medium_row)

	var apply_button := _make_preview_button("Apply", "medium")
	medium_row.add_child(apply_button)

	var reset_button := _make_preview_button("Reset", "medium")
	reset_button.disabled = true
	medium_row.add_child(reset_button)


func _build_hud_section(parent: Container) -> void:
	var body := _make_section(parent, "HUD", "panel", Vector2(680, 280))

	var health_label := Label.new()
	health_label.text = "Health bar example"
	body.add_child(health_label)
	OathwakeTextStyle.apply_profile_to_label(health_label, "base_ui")

	var health_bar := TextureProgressBar.new()
	health_bar.custom_minimum_size = Vector2(320, 28)
	health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_bar.max_value = 100.0
	health_bar.value = 70.0
	health_bar.texture_under = _skin_texture("health_bar_frame")
	health_bar.texture_progress = _skin_texture("health_bar_fill")
	body.add_child(health_bar)

	var xp_label := Label.new()
	xp_label.text = "XP bar example"
	body.add_child(xp_label)
	OathwakeTextStyle.apply_profile_to_label(xp_label, "base_ui")

	var xp_bar := TextureProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(320, 24)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.max_value = 100.0
	xp_bar.value = 40.0
	xp_bar.texture_under = _skin_texture("xp_bar_frame")
	xp_bar.texture_progress = _skin_texture("xp_bar_fill")
	body.add_child(xp_bar)

	var hotbar_label := Label.new()
	hotbar_label.text = "Hotbar frame + 8 slots"
	body.add_child(hotbar_label)
	OathwakeTextStyle.apply_profile_to_label(hotbar_label, "base_ui")

	var hotbar_panel := PanelContainer.new()
	hotbar_panel.custom_minimum_size = Vector2(0, 94)
	hotbar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_hotbar_panel(hotbar_panel)
	body.add_child(hotbar_panel)

	var hotbar_margin := MarginContainer.new()
	hotbar_margin.add_theme_constant_override("margin_left", 10)
	hotbar_margin.add_theme_constant_override("margin_top", 10)
	hotbar_margin.add_theme_constant_override("margin_right", 10)
	hotbar_margin.add_theme_constant_override("margin_bottom", 10)
	hotbar_panel.add_child(hotbar_margin)

	var hotbar_row := HBoxContainer.new()
	hotbar_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hotbar_row.add_theme_constant_override("separation", 6)
	hotbar_margin.add_child(hotbar_row)

	for index in range(8):
		var variant := "selected" if index == 0 else "empty"
		var slot := _make_hotbar_slot_button(str(index + 1), variant)
		hotbar_row.add_child(slot)


func _build_inventory_section(parent: Container) -> void:
	var body := _make_section(parent, "Inventory", "inventory_window", Vector2(680, 390))

	var inventory_preview := PanelContainer.new()
	inventory_preview.custom_minimum_size = Vector2(0, 0)
	inventory_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_inventory_panel(inventory_preview)
	body.add_child(inventory_preview)

	var inventory_margin := MarginContainer.new()
	inventory_margin.add_theme_constant_override("margin_left", 18)
	inventory_margin.add_theme_constant_override("margin_top", 18)
	inventory_margin.add_theme_constant_override("margin_right", 18)
	inventory_margin.add_theme_constant_override("margin_bottom", 18)
	inventory_preview.add_child(inventory_margin)

	var inventory_layout := VBoxContainer.new()
	inventory_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_layout.add_theme_constant_override("separation", 14)
	inventory_margin.add_child(inventory_layout)

	var inventory_grid := GridContainer.new()
	inventory_grid.columns = 5
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.add_theme_constant_override("h_separation", 10)
	inventory_grid.add_theme_constant_override("v_separation", 10)
	inventory_layout.add_child(inventory_grid)

	for index in range(20):
		var variant := "empty"
		if index == 2:
			variant = "hover"
		elif index == 7:
			variant = "selected"
		elif index == 19:
			variant = "blocked"
		var slot := _make_inventory_slot_button(str(index + 1), variant)
		inventory_grid.add_child(slot)

	var tooltip_preview := PanelContainer.new()
	tooltip_preview.custom_minimum_size = Vector2(0, 104)
	tooltip_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_tooltip(tooltip_preview)
	inventory_layout.add_child(tooltip_preview)

	var tooltip_margin := MarginContainer.new()
	tooltip_margin.add_theme_constant_override("margin_left", 12)
	tooltip_margin.add_theme_constant_override("margin_top", 12)
	tooltip_margin.add_theme_constant_override("margin_right", 12)
	tooltip_margin.add_theme_constant_override("margin_bottom", 12)
	tooltip_preview.add_child(tooltip_margin)

	var tooltip_box := VBoxContainer.new()
	tooltip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tooltip_box.add_theme_constant_override("separation", 2)
	tooltip_margin.add_child(tooltip_box)

	var tooltip_title := Label.new()
	tooltip_title.text = "Iron Pickaxe"
	tooltip_box.add_child(tooltip_title)
	OathwakeTextStyle.apply_profile_to_label(tooltip_title, "ui_title")

	var tooltip_tier := Label.new()
	tooltip_tier.text = "Tier 2 Tool"
	tooltip_box.add_child(tooltip_tier)
	OathwakeTextStyle.apply_profile_to_label(tooltip_tier, "base_ui")

	var tooltip_bonus := Label.new()
	tooltip_bonus.text = "+ Gathering Power"
	tooltip_box.add_child(tooltip_bonus)
	OathwakeTextStyle.apply_profile_to_label(tooltip_bonus, "base_ui")


func _build_misc_section(parent: Container) -> void:
	var body := _make_section(parent, "Misc", "panel", Vector2(680, 320))

	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_theme_constant_override("separation", 12)
	body.add_child(top_row)

	top_row.add_child(_make_skin_preview_card("Toast", "toast", Vector2(198, 72), "Toast background"))
	top_row.add_child(_make_skin_preview_card("Tutorial", "tutorial_panel", Vector2(224, 112), "Tutorial panel"))

	var middle_row := HBoxContainer.new()
	middle_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_row.add_theme_constant_override("separation", 12)
	body.add_child(middle_row)

	middle_row.add_child(_make_skin_preview_card("Dialog", "dialog", Vector2(320, 132), "Dialog box"))
	middle_row.add_child(_make_skin_preview_card("Credits", "panel_credits", Vector2(320, 132), "Credits panel"))

	var divider_row := VBoxContainer.new()
	divider_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	divider_row.add_theme_constant_override("separation", 10)
	body.add_child(divider_row)

	var divider_label := Label.new()
	divider_label.text = "Divider ornament"
	divider_row.add_child(divider_label)
	OathwakeTextStyle.apply_profile_to_label(divider_label, "base_ui")

	var divider := OathwakeUISkin.make_texture_rect("res://assets/ui/misc/divider_ornament.png", TextureRect.STRETCH_SCALE)
	divider.custom_minimum_size = Vector2(280, 18)
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	divider_row.add_child(divider)


func _make_section(parent: Container, title_text: String, skin_key: String, min_size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_panel(panel, skin_key)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)

	var header := Label.new()
	header.text = title_text
	body.add_child(header)
	OathwakeTextStyle.apply_profile_to_label(header, "ui_title")
	return body


func _make_preview_button(text: String, size_key: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 56) if size_key == "large" else Vector2(0, 44)
	OathwakeUISkin.apply_button(button, size_key)
	OathwakeTextStyle.apply_profile_to_control(button, "ui_button")
	return button


func _make_save_slot_button(text: String, variant: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 84)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	OathwakeUISkin.apply_slot_button(button, variant)
	OathwakeTextStyle.apply_profile_to_control(button, "base_ui")
	return button


func _make_hotbar_slot_button(text: String, variant: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(60, 56)
	OathwakeUISkin.apply_slot_button(button, variant)
	OathwakeTextStyle.apply_profile_to_control(button, "base_ui")
	return button


func _make_inventory_slot_button(text: String, variant: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 64)
	OathwakeUISkin.apply_slot_button(button, variant)
	OathwakeTextStyle.apply_profile_to_control(button, "base_ui")
	return button


func _make_icon_sample(label_text: String, texture_path: String) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.add_theme_constant_override("separation", 6)

	var icon := OathwakeUISkin.make_texture_rect(texture_path, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.add_child(icon)

	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrapper.add_child(label)
	OathwakeTextStyle.apply_profile_to_label(label, "base_ui")
	return wrapper


func _make_skin_preview_card(title_text: String, skin_key: String, min_size: Vector2, body_text: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	OathwakeUISkin.apply_panel(panel, skin_key)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	OathwakeTextStyle.apply_profile_to_label(title, "ui_title")

	var description := Label.new()
	description.text = body_text
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(description)
	OathwakeTextStyle.apply_profile_to_label(description, "base_ui")
	return panel


func _skin_texture(key: String) -> Texture2D:
	var skin_data := OathwakeUISkin.get_skin_data()
	var entry: Variant = skin_data.get(key, {})
	if entry is String:
		var loaded := load(str(entry))
		return loaded as Texture2D
	if entry is Dictionary:
		var path := str(entry.get("path", ""))
		if path.is_empty():
			return null
		var loaded_path := load(path)
		return loaded_path as Texture2D
	return null
