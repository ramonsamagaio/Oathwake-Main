extends Node

const MIN_BUTTON_HEIGHT := 42.0
const MIN_FIELD_HEIGHT := 38.0
const MIN_BUTTON_WIDTH := 92.0
const CLOSE_BUTTON_SIZE := 42.0

var _queued_nodes: Dictionary = {}


func _ready() -> void:
	process_priority = -900
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_polish_existing_tree")


func _on_node_added(node: Node) -> void:
	if not node is Control:
		return
	var instance_id := node.get_instance_id()
	if _queued_nodes.has(instance_id):
		return
	_queued_nodes[instance_id] = true
	call_deferred("_polish_deferred", node, instance_id)


func _polish_existing_tree() -> void:
	_polish_branch(get_tree().root)


func _polish_deferred(node: Node, instance_id: int) -> void:
	_queued_nodes.erase(instance_id)
	if is_instance_valid(node):
		_polish_branch(node)


func _polish_branch(node: Node) -> void:
	if node is Control:
		_polish_control(node as Control)
	for child in node.get_children():
		_polish_branch(child)


func _polish_control(control: Control) -> void:
	if control.has_meta("ui_interaction_polished"):
		return
	control.set_meta("ui_interaction_polished", true)

	if control is BaseButton:
		_polish_button(control as BaseButton)
	elif control is LineEdit:
		_polish_line_edit(control as LineEdit)
	elif control is SpinBox:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, MIN_FIELD_HEIGHT)
	elif control is ItemList:
		_polish_item_list(control as ItemList)
	elif control is PanelContainer:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.05, 0.045, 0.985), Color(0.49, 0.35, 0.22, 1.0), 3))
	elif control is Panel:
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		control.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.05, 0.045, 0.985), Color(0.49, 0.35, 0.22, 1.0), 3))
	elif control is ScrollContainer:
		control.mouse_filter = Control.MOUSE_FILTER_STOP


func _polish_button(button: BaseButton) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	var is_close_button := button.name.to_lower().contains("close") or button.text.strip_edges() == "X"
	var minimum_width := CLOSE_BUTTON_SIZE if is_close_button else MIN_BUTTON_WIDTH
	button.custom_minimum_size = Vector2(
		maxf(button.custom_minimum_size.x, minimum_width),
		maxf(button.custom_minimum_size.y, MIN_BUTTON_HEIGHT)
	)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.20, 0.15, 0.11, 0.98), Color(0.55, 0.39, 0.23, 1.0), 2))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.30, 0.21, 0.14, 1.0), Color(0.88, 0.64, 0.31, 1.0), 3))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.12, 0.10, 0.085, 1.0), Color(0.96, 0.72, 0.34, 1.0), 3))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.27, 0.20, 0.13, 1.0), Color(1.0, 0.78, 0.38, 1.0), 3))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.12, 0.11, 0.10, 0.94), Color(0.28, 0.25, 0.22, 1.0), 1))
	button.add_theme_color_override("font_color", Color(0.96, 0.91, 0.80, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.76, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.82, 0.46, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.52, 0.49, 0.44, 1.0))


func _polish_line_edit(line_edit: LineEdit) -> void:
	line_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	line_edit.custom_minimum_size.y = maxf(line_edit.custom_minimum_size.y, MIN_FIELD_HEIGHT)
	line_edit.add_theme_stylebox_override("normal", _panel_style(Color(0.07, 0.065, 0.06, 0.98), Color(0.42, 0.34, 0.25, 1.0), 2))
	line_edit.add_theme_stylebox_override("focus", _panel_style(Color(0.09, 0.075, 0.06, 1.0), Color(0.88, 0.64, 0.31, 1.0), 3))


func _polish_item_list(item_list: ItemList) -> void:
	item_list.mouse_filter = Control.MOUSE_FILTER_STOP
	item_list.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item_list.focus_mode = Control.FOCUS_ALL
	item_list.custom_minimum_size = Vector2(maxf(item_list.custom_minimum_size.x, 220.0), maxf(item_list.custom_minimum_size.y, 220.0))
	item_list.fixed_icon_size = Vector2i(36, 36)
	item_list.add_theme_constant_override("v_separation", 8)
	item_list.add_theme_constant_override("h_separation", 8)
	item_list.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.052, 0.048, 0.99), Color(0.36, 0.29, 0.21, 1.0), 2))
	item_list.add_theme_stylebox_override("focus", _panel_style(Color(0.075, 0.064, 0.052, 1.0), Color(0.88, 0.64, 0.31, 1.0), 3))
	item_list.add_theme_stylebox_override("selected", _panel_style(Color(0.34, 0.24, 0.14, 1.0), Color(0.94, 0.68, 0.31, 1.0), 2))
	item_list.add_theme_stylebox_override("selected_focus", _panel_style(Color(0.40, 0.28, 0.15, 1.0), Color(1.0, 0.78, 0.38, 1.0), 3))


func _button_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _panel_style(background, border, width)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _panel_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
