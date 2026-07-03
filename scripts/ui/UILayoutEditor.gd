extends Control

const UILayoutConfig = preload("res://scripts/ui/UILayoutConfig.gd")
const UILayoutApplier = preload("res://scripts/ui/UILayoutApplier.gd")

const CANVAS_SIZE := Vector2(1600, 900)
const SNAP_SIZE := 1

const ELEMENT_COLORS := {
	"hud": Color(0.22, 0.55, 0.95, 0.28),
	"window": Color(0.85, 0.68, 0.2, 0.28),
	"interaction": Color(0.9, 0.18, 0.62, 0.32),
	"hud_child": Color(0.24, 0.82, 0.42, 0.28),
	"default": Color(0.72, 0.72, 0.72, 0.24),
}

const DEFAULT_ELEMENT_ORDER := [
	"inventory.window",
	"inventory.drag_handle",
	"hotbar.panel",
	"hud.status_panel",
	"hud.health_bar",
	"hud.xp_bar",
	"hud.alignment_flame",
	"hud.minimap",
]


class PreviewCanvas:
	extends Control

	var editor_ref: Node = null

	func _draw() -> void:
		if editor_ref != null and editor_ref.has_method("_draw_preview_canvas"):
			editor_ref._draw_preview_canvas(self)

	func _gui_input(event: InputEvent) -> void:
		if editor_ref != null and editor_ref.has_method("_handle_preview_gui_input"):
			editor_ref._handle_preview_gui_input(self, event)


var layout: Dictionary = {}
var selected_element_id := ""
var show_interaction_zones := true
var show_hud_elements := true
var _updating_ui := false
var _drag_mode := ""
var _drag_element_id := ""
var _drag_start_mouse := Vector2.ZERO
var _drag_start_data: Dictionary = {}

var _elements_list: ItemList
var _preview_canvas: PreviewCanvas
var _element_id_label: Label
var _label_edit: LineEdit
var _type_label: Label
var _anchor_option: OptionButton
var _x_spin: SpinBox
var _y_spin: SpinBox
var _width_spin: SpinBox
var _height_spin: SpinBox
var _visible_check: CheckBox
var _locked_check: CheckBox
var _status_label: Label
var _toggle_interaction_button: Button
var _toggle_hud_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout = UILayoutConfig.load_layout()
	_build_ui()
	_refresh_everything()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.08, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 12)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_right", 12)
	outer.add_theme_constant_override("margin_bottom", 12)
	add_child(outer)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)

	_build_top_bar(root)

	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	root.add_child(content)

	_build_elements_panel(content)
	_build_preview_panel(content)
	_build_properties_panel(content)


func _build_top_bar(parent: Container) -> void:
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 8)
	parent.add_child(bar)

	var title := Label.new()
	title.text = "UILayout Editor"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	_toggle_interaction_button = _make_toggle_button("Toggle Interaction Zones", func() -> void:
		show_interaction_zones = not show_interaction_zones
		_update_toggle_buttons()
		_queue_preview_redraw()
	)
	bar.add_child(_toggle_interaction_button)

	_toggle_hud_button = _make_toggle_button("Toggle HUD Elements", func() -> void:
		show_hud_elements = not show_hud_elements
		_update_toggle_buttons()
		_queue_preview_redraw()
	)
	bar.add_child(_toggle_hud_button)

	bar.add_child(_make_action_button("Save Layout", _on_save_layout_pressed))
	bar.add_child(_make_action_button("Reload Layout", _on_reload_layout_pressed))
	bar.add_child(_make_action_button("Reset Defaults", _on_reset_defaults_pressed))


func _build_elements_panel(parent: Container) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)

	var label := Label.new()
	label.text = "Elements"
	body.add_child(label)

	_elements_list = ItemList.new()
	_elements_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_elements_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_elements_list.allow_reselect = true
	_elements_list.item_selected.connect(_on_elements_list_item_selected)
	body.add_child(_elements_list)


func _build_preview_panel(parent: Container) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)

	var label := Label.new()
	label.text = "Canvas Preview"
	body.add_child(label)

	var canvas_shell := PanelContainer.new()
	canvas_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(canvas_shell)

	_preview_canvas = PreviewCanvas.new()
	_preview_canvas.editor_ref = self
	_preview_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_shell.add_child(_preview_canvas)


func _build_properties_panel(parent: Container) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 0)
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_END
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)

	body.add_child(_make_section_label("Properties"))
	_element_id_label = _make_value_label("")
	body.add_child(_make_labeled_row("Element", _element_id_label))

	_label_edit = LineEdit.new()
	_label_edit.text_changed.connect(_on_label_changed)
	body.add_child(_make_labeled_row("Label", _label_edit))

	_type_label = _make_value_label("")
	body.add_child(_make_labeled_row("Type", _type_label))

	_anchor_option = OptionButton.new()
	for anchor_name in ["top_left", "top_center", "top_right", "center", "bottom_center", "bottom_left", "bottom_right"]:
		_anchor_option.add_item(anchor_name)
	_anchor_option.item_selected.connect(_on_anchor_selected)
	body.add_child(_make_labeled_row("Anchor", _anchor_option))

	_x_spin = _make_spinbox(-5000, 5000, _on_position_changed)
	body.add_child(_make_labeled_row("X", _x_spin))
	_y_spin = _make_spinbox(-5000, 5000, _on_position_changed)
	body.add_child(_make_labeled_row("Y", _y_spin))
	_width_spin = _make_spinbox(1, 5000, _on_size_changed)
	body.add_child(_make_labeled_row("Width", _width_spin))
	_height_spin = _make_spinbox(1, 5000, _on_size_changed)
	body.add_child(_make_labeled_row("Height", _height_spin))

	_visible_check = CheckBox.new()
	_visible_check.text = "Visible"
	_visible_check.toggled.connect(_on_visible_toggled)
	body.add_child(_visible_check)

	_locked_check = CheckBox.new()
	_locked_check.text = "Locked"
	_locked_check.toggled.connect(_on_locked_toggled)
	body.add_child(_locked_check)

	_status_label = Label.new()
	_status_label.text = "Ready."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status_label)

	body.add_child(_make_section_label("Asset Preview"))
	_build_asset_preview(body)


func _build_asset_preview(parent: Container) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)

	var assets := [
		{"label": "health_bar_frame", "path": "res://assets/ui/hud/health_bar_frame.png"},
		{"label": "health_bar_fill", "path": "res://assets/ui/hud/health_bar_fill.png"},
		{"label": "xp_bar_frame", "path": "res://assets/ui/hud/xp_bar_frame.png"},
		{"label": "xp_bar_fill", "path": "res://assets/ui/hud/xp_bar_fill.png"},
		{"label": "inventory_window", "path": "res://assets/ui/inventory/inventory_window.png"},
		{"label": "hotbar_frame", "path": "res://assets/ui/hotbar/hotbar_frame.png"},
		{"label": "credits_panel", "path": "res://assets/ui/menu/credits_panel.png"},
	]

	for asset_info in assets:
		grid.add_child(_make_asset_card(str(asset_info.get("label", "")), str(asset_info.get("path", ""))))


func _make_asset_card(label_text: String, path: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(130, 94)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	margin.add_child(body)

	var preview: Control
	if FileAccess.file_exists(path):
		var texture := load(path)
		if texture is Texture2D:
			var texture_rect := TextureRect.new()
			texture_rect.texture = texture
			texture_rect.custom_minimum_size = Vector2(116, 56)
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			preview = texture_rect
		else:
			preview = _make_missing_asset_label("missing")
	else:
		preview = _make_missing_asset_label("missing")
	body.add_child(preview)

	var caption := Label.new()
	caption.text = label_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(caption)
	return card


func _make_missing_asset_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(116, 56)
	return label


func _make_section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label


func _make_value_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _make_labeled_row(title_text: String, value_control: Control) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = title_text
	title.custom_minimum_size = Vector2(72, 0)
	row.add_child(title)

	value_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_control)
	return row


func _make_spinbox(min_value: float, max_value: float, callback: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1.0
	spin.allow_lesser = false
	spin.allow_greater = false
	spin.value_changed.connect(callback)
	return spin


func _make_action_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _make_toggle_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.pressed.connect(callback)
	return button


func _refresh_everything() -> void:
	_refresh_elements_list()
	_update_toggle_buttons()
	_select_default_element()
	_queue_preview_redraw()


func _refresh_elements_list() -> void:
	if _elements_list == null:
		return

	_elements_list.clear()
	for element_id in _get_sorted_element_ids():
		var element := UILayoutConfig.get_element(layout, element_id)
		if element.is_empty():
			continue
		var label_text := str(element.get("label", element_id))
		var type_text := str(element.get("type", ""))
		var display_text := "%s [%s]" % [label_text, type_text]
		_elements_list.add_item(display_text)
		_elements_list.set_item_metadata(_elements_list.item_count - 1, element_id)


func _select_default_element() -> void:
	if selected_element_id.is_empty():
		if _elements_list != null and _elements_list.item_count > 0:
			var first_id := str(_elements_list.get_item_metadata(0))
			_select_element(first_id)
		else:
			_refresh_property_panel()
		return

	_select_element(selected_element_id)


func _on_elements_list_item_selected(index: int) -> void:
	if _elements_list == null:
		return
	var element_id := str(_elements_list.get_item_metadata(index))
	_select_element(element_id)


func _select_element(element_id: String) -> void:
	if element_id.is_empty():
		selected_element_id = ""
		_refresh_property_panel()
		_queue_preview_redraw()
		return

	var element := UILayoutConfig.get_element(layout, element_id)
	if element.is_empty():
		selected_element_id = ""
		_refresh_property_panel()
		_queue_preview_redraw()
		return

	selected_element_id = element_id
	var item_index := _find_item_index_for_element(element_id)
	if item_index >= 0 and _elements_list != null:
		_updating_ui = true
		_elements_list.select(item_index)
		_updating_ui = false
	_refresh_property_panel()
	_queue_preview_redraw()


func _find_item_index_for_element(element_id: String) -> int:
	if _elements_list == null:
		return -1
	for index in range(_elements_list.item_count):
		if str(_elements_list.get_item_metadata(index)) == element_id:
			return index
	return -1


func _refresh_property_panel() -> void:
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	_updating_ui = true
	if element.is_empty():
		_element_id_label.text = "-"
		_label_edit.text = ""
		_type_label.text = ""
		_anchor_option.selected = 0
		_x_spin.value = 0
		_y_spin.value = 0
		_width_spin.value = 0
		_height_spin.value = 0
		_visible_check.button_pressed = false
		_locked_check.button_pressed = false
		_updating_ui = false
		return

	_element_id_label.text = selected_element_id
	_label_edit.text = str(element.get("label", ""))
	_type_label.text = str(element.get("type", ""))
	_anchor_option.select(_get_anchor_option_index(str(element.get("anchor", "top_left"))))
	_x_spin.value = float(element.get("x", 0.0))
	_y_spin.value = float(element.get("y", 0.0))
	_width_spin.value = float(element.get("width", 0.0))
	_height_spin.value = float(element.get("height", 0.0))
	_visible_check.button_pressed = bool(element.get("visible", true))
	_locked_check.button_pressed = bool(element.get("locked", false))
	_updating_ui = false


func _on_label_changed(new_text: String) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		return
	element["label"] = new_text
	UILayoutConfig.set_element(layout, selected_element_id, element)
	_refresh_elements_list()
	_select_element(selected_element_id)
	_queue_preview_redraw()


func _on_anchor_selected(index: int) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		return
	element["anchor"] = _get_anchor_name_from_index(index)
	UILayoutConfig.set_element(layout, selected_element_id, element)
	_queue_preview_redraw()


func _on_position_changed(_value: float) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		return
	element["x"] = int(roundf(_x_spin.value))
	element["y"] = int(roundf(_y_spin.value))
	UILayoutConfig.set_element(layout, selected_element_id, element)
	_queue_preview_redraw()


func _on_size_changed(_value: float) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		return
	element["width"] = max(1, int(roundf(_width_spin.value)))
	element["height"] = max(1, int(roundf(_height_spin.value)))
	UILayoutConfig.set_element(layout, selected_element_id, element)
	_queue_preview_redraw()


func _on_visible_toggled(pressed: bool) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		return
	element["visible"] = pressed
	UILayoutConfig.set_element(layout, selected_element_id, element)
	_queue_preview_redraw()


func _on_locked_toggled(pressed: bool) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		return
	element["locked"] = pressed
	UILayoutConfig.set_element(layout, selected_element_id, element)
	_queue_preview_redraw()


func _update_toggle_buttons() -> void:
	if _toggle_interaction_button != null:
		_toggle_interaction_button.button_pressed = show_interaction_zones
	if _toggle_hud_button != null:
		_toggle_hud_button.button_pressed = show_hud_elements


func _queue_preview_redraw() -> void:
	if _preview_canvas != null:
		_preview_canvas.queue_redraw()


func _draw_preview_canvas(canvas: Control) -> void:
	var view := _get_canvas_view(canvas)
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var scale := float(view.get("scale", 1.0))
	var canvas_rect := Rect2(origin, CANVAS_SIZE * scale)

	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.03, 0.04, 0.05, 1.0), true)
	canvas.draw_rect(canvas_rect, Color(0.12, 0.12, 0.14, 1.0), true)
	canvas.draw_rect(canvas_rect, Color(0.24, 0.24, 0.28, 1.0), false, 2.0)

	for element_id in _get_sorted_element_ids():
		var element := UILayoutConfig.get_element(layout, element_id)
		if element.is_empty():
			continue

		var rect := UILayoutApplier.get_element_rect(layout, element_id)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue

		var element_type := str(element.get("type", "default"))
		var visible := bool(element.get("visible", true))
		var draw_alpha := 1.0 if visible else 0.18
		if element_type == "interaction" and not show_interaction_zones:
			draw_alpha *= 0.2
		elif (element_type == "hud" or element_type == "hud_child") and not show_hud_elements:
			draw_alpha *= 0.2

		var color := _get_element_color(element_type)
		color.a *= draw_alpha
		var screen_rect := Rect2(origin + rect.position * scale, rect.size * scale)
		canvas.draw_rect(screen_rect, color, true)
		canvas.draw_rect(screen_rect, _selection_border_color(element_id), false, 2.0)

		var label_text := str(element.get("label", element_id))
		if not label_text.is_empty():
			var label_pos := screen_rect.position + Vector2(6, 14)
			var default_font := canvas.get_theme_default_font()
			if default_font != null:
				canvas.draw_string(
					default_font,
					label_pos,
					label_text,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					canvas.get_theme_default_font_size(),
					Color(1.0, 1.0, 1.0, 0.95)
				)

		if element_id == selected_element_id:
			canvas.draw_rect(screen_rect, Color(1.0, 1.0, 1.0, 1.0), false, 3.0)
			_draw_resize_handle(canvas, screen_rect)


func _draw_resize_handle(canvas: Control, rect: Rect2) -> void:
	var handle_size := 10.0
	var handle_rect := Rect2(rect.position + rect.size - Vector2(handle_size, handle_size), Vector2(handle_size, handle_size))
	canvas.draw_rect(handle_rect, Color(1.0, 1.0, 1.0, 0.9), true)
	canvas.draw_rect(handle_rect, Color(0.0, 0.0, 0.0, 0.8), false, 1.0)


func _handle_preview_gui_input(canvas: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed:
			var canvas_pos := _screen_to_canvas_pos(canvas, mouse_event.position)
			var hit_id := _pick_element_at_canvas_position(canvas_pos)
			if not hit_id.is_empty():
				_select_element(hit_id)
				var selected_rect := UILayoutApplier.get_element_rect(layout, hit_id)
				if _is_locked(hit_id):
					return
				if _is_in_resize_handle(canvas, mouse_event.position, selected_rect):
					_begin_drag("resize", hit_id, canvas_pos)
				elif selected_rect.has_point(canvas_pos):
					_begin_drag("move", hit_id, canvas_pos)
				return
		else:
			_end_drag()
			return

	if event is InputEventMouseMotion and _drag_mode != "":
		var motion := event as InputEventMouseMotion
		var canvas_pos := _screen_to_canvas_pos(canvas, motion.position)
		_update_drag(canvas_pos)


func _begin_drag(mode: String, element_id: String, mouse_canvas_pos: Vector2) -> void:
	var element := UILayoutConfig.get_element(layout, element_id)
	if element.is_empty() or bool(element.get("locked", false)):
		return
	_drag_mode = mode
	_drag_element_id = element_id
	_drag_start_mouse = mouse_canvas_pos
	_drag_start_data = element.duplicate(true)


func _end_drag() -> void:
	_drag_mode = ""
	_drag_element_id = ""
	_drag_start_data = {}


func _update_drag(current_mouse_canvas_pos: Vector2) -> void:
	if _drag_mode.is_empty() or _drag_element_id.is_empty():
		return

	var element := UILayoutConfig.get_element(layout, _drag_element_id)
	if element.is_empty() or bool(element.get("locked", false)):
		return

	var delta := current_mouse_canvas_pos - _drag_start_mouse
	var updated := _drag_start_data.duplicate(true)
	if _drag_mode == "move":
		updated["x"] = _snap_value(float(_drag_start_data.get("x", 0.0)) + delta.x)
		updated["y"] = _snap_value(float(_drag_start_data.get("y", 0.0)) + delta.y)
	elif _drag_mode == "resize":
		updated["width"] = max(1, _snap_value(float(_drag_start_data.get("width", 0.0)) + delta.x))
		updated["height"] = max(1, _snap_value(float(_drag_start_data.get("height", 0.0)) + delta.y))

	UILayoutConfig.set_element(layout, _drag_element_id, updated)
	_select_element(_drag_element_id)
	_queue_preview_redraw()


func _snap_value(value: float) -> int:
	return int(roundf(value / float(SNAP_SIZE)) * float(SNAP_SIZE))


func _screen_to_canvas_pos(canvas: Control, screen_pos: Vector2) -> Vector2:
	var view := _get_canvas_view(canvas)
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var scale := float(view.get("scale", 1.0))
	return (screen_pos - origin) / scale


func _get_canvas_view(canvas: Control) -> Dictionary:
	var available := canvas.size
	var scale := minf(available.x / CANVAS_SIZE.x, available.y / CANVAS_SIZE.y)
	if scale <= 0.0:
		scale = 1.0
	var canvas_draw_size := CANVAS_SIZE * scale
	var origin := (available - canvas_draw_size) * 0.5
	return {
		"origin": origin,
		"scale": scale,
	}


func _pick_element_at_canvas_position(canvas_pos: Vector2) -> String:
	var hit_id := ""
	for element_id in _get_sorted_element_ids():
		var element := UILayoutConfig.get_element(layout, element_id)
		if element.is_empty():
			continue
		if not bool(element.get("visible", true)):
			continue
		var rect := UILayoutApplier.get_element_rect(layout, element_id)
		if rect.has_point(canvas_pos):
			hit_id = element_id
	return hit_id


func _is_in_resize_handle(canvas: Control, screen_pos: Vector2, rect: Rect2) -> bool:
	var view := _get_canvas_view(canvas)
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var scale := float(view.get("scale", 1.0))
	var screen_rect := Rect2(origin + rect.position * scale, rect.size * scale)
	var handle_size := 12.0
	var handle_rect := Rect2(screen_rect.position + screen_rect.size - Vector2(handle_size, handle_size), Vector2(handle_size, handle_size))
	return handle_rect.has_point(screen_pos)


func _get_element_color(element_type: String) -> Color:
	if ELEMENT_COLORS.has(element_type):
		return ELEMENT_COLORS[element_type]
	return ELEMENT_COLORS["default"]


func _selection_border_color(element_id: String) -> Color:
	if element_id == selected_element_id:
		return Color(1.0, 1.0, 1.0, 0.9)
	return Color(0.0, 0.0, 0.0, 0.5)


func _is_locked(element_id: String) -> bool:
	var element := UILayoutConfig.get_element(layout, element_id)
	return not element.is_empty() and bool(element.get("locked", false))


func _get_sorted_element_ids() -> Array[String]:
	var ordered: Array[String] = []
	var seen := {}
	var elements: Variant = layout.get("elements", {})
	if not elements is Dictionary:
		return ordered

	for element_id in DEFAULT_ELEMENT_ORDER:
		if (elements as Dictionary).has(element_id):
			ordered.append(element_id)
			seen[element_id] = true

	var extras: Array[String] = []
	for key in (elements as Dictionary).keys():
		var element_id := str(key)
		if seen.has(element_id):
			continue
		extras.append(element_id)
	extras.sort()
	for element_id in extras:
		ordered.append(element_id)
	return ordered


func _get_anchor_option_index(anchor_name: String) -> int:
	match anchor_name:
		"top_left":
			return 0
		"top_center":
			return 1
		"top_right":
			return 2
		"center":
			return 3
		"bottom_center":
			return 4
		"bottom_left":
			return 5
		"bottom_right":
			return 6
		_:
			return 0


func _get_anchor_name_from_index(index: int) -> String:
	match index:
		0:
			return "top_left"
		1:
			return "top_center"
		2:
			return "top_right"
		3:
			return "center"
		4:
			return "bottom_center"
		5:
			return "bottom_left"
		6:
			return "bottom_right"
		_:
			return "top_left"


func _on_save_layout_pressed() -> void:
	if UILayoutConfig.save_layout(layout):
		_status_label.text = "Layout saved to %s" % UILayoutConfig.LAYOUT_PATH
	else:
		_status_label.text = "Save failed."


func _on_reload_layout_pressed() -> void:
	layout = UILayoutConfig.load_layout()
	_status_label.text = "Layout reloaded."
	_refresh_everything()


func _on_reset_defaults_pressed() -> void:
	layout = UILayoutConfig.get_default_layout()
	_status_label.text = "Reset to defaults."
	_refresh_everything()
