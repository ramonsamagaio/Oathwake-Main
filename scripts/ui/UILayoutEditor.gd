extends Control

const UILayoutConfig = preload("res://scripts/ui/UILayoutConfig.gd")
const UILayoutApplier = preload("res://scripts/ui/UILayoutApplier.gd")

const CANVAS_SIZE := Vector2(1600, 900)
const SNAP_SIZE := 1
const HISTORY_LIMIT := 50

const DEFAULT_ASSET_PATHS := [
	"res://assets/ui/buttons/button_medium_normal.png",
	"res://assets/ui/inventory/item_slot_normal.png",
	"res://assets/ui/hud/hotbar_slot_empty.png",
	"res://assets/ui/hud/hotbar_frame.png",
	"res://assets/ui/hud/health_bar_frame.png",
	"res://assets/ui/hud/health_bar_fill.png",
	"res://assets/ui/hud/xp_bar_frame.png",
	"res://assets/ui/hud/xp_bar_fill.png",
	"res://assets/ui/inventory/tooltip_bg.png",
	"res://assets/ui/inventory/inventory_window.png",
]

const ELEMENT_COLORS := {
	"hud": Color(0.22, 0.55, 0.95, 0.28),
	"window": Color(0.85, 0.68, 0.2, 0.28),
	"guide": Color(0.42, 0.58, 0.78, 0.18),
	"interaction": Color(0.9, 0.18, 0.62, 0.32),
	"hud_child": Color(0.24, 0.82, 0.42, 0.28),
	"graphic": Color(0.65, 0.72, 0.95, 0.24),
	"default": Color(0.72, 0.72, 0.72, 0.24),
}


class PreviewCanvas:
	extends Control

	var editor_ref: Node = null

	func _draw() -> void:
		if editor_ref != null and editor_ref.has_method("_draw_preview_canvas"):
			editor_ref._draw_preview_canvas(self)

	func _gui_input(event: InputEvent) -> void:
		if editor_ref != null and editor_ref.has_method("_handle_preview_gui_input"):
			editor_ref._handle_preview_gui_input(self, event)


class AssetTile:
	extends Control

	var editor_ref: Node = null
	var asset_path := ""
	var title := ""
	var missing := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(124, 102)
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.08, 0.09, 0.12, 1.0), true)
		draw_rect(rect, Color(0.26, 0.28, 0.32, 1.0), false, 1.0)

		var thumb_rect := Rect2(Vector2(6, 6), Vector2(size.x - 12.0, 60.0))
		if editor_ref != null and editor_ref.has_method("_get_asset_preview_texture"):
			var texture: Texture2D = editor_ref._get_asset_preview_texture(asset_path)
			if texture != null:
				var fitted: Rect2 = editor_ref._get_fitted_rect(texture.get_size(), thumb_rect, "keep_aspect_centered")
				draw_texture_rect(texture, fitted, false, Color(1, 1, 1, 1))
			else:
				draw_rect(thumb_rect, Color(0.18, 0.18, 0.2, 1.0), true)
				draw_rect(thumb_rect, Color(0.6, 0.2, 0.2, 0.9), false, 1.0)
				var font := get_theme_default_font()
				if font != null:
					draw_string(font, Vector2(thumb_rect.position.x + 8.0, thumb_rect.position.y + 34.0), "missing", HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_default_font_size(), Color(1, 0.75, 0.75, 1))

		var label := title
		if label.is_empty():
			label = asset_path.get_file()
		var label_font := get_theme_default_font()
		if label_font != null:
			draw_string(label_font, Vector2(8, 84), label, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_default_font_size(), Color(0.95, 0.96, 0.98, 1.0))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
			if editor_ref != null and editor_ref.has_method("_on_asset_tile_double_clicked"):
				editor_ref._on_asset_tile_double_clicked(asset_path)


var layout: Dictionary = {}
var selected_element_id := ""

var show_assets := true
var show_rects := true
var show_labels := true
var visual_layer_enabled := true
var interaction_layer_enabled := true
var _is_dragging_preview := false

var _updating_ui := false
var _applying_history := false
var _drag_mode := ""
var _drag_element_id := ""
var _drag_start_mouse := Vector2.ZERO
var _drag_start_element: Dictionary = {}
var _undo_stack: Array = []
var _redo_stack: Array = []
var _texture_cache: Dictionary = {}

var _elements_list: ItemList
var _preview_canvas: PreviewCanvas
var _status_label: Label
var _file_dialog: FileDialog
var _asset_grid: GridContainer

var _label_edit: LineEdit
var _asset_path_edit: LineEdit
var _element_id_label: Label
var _type_label: Label
var _parent_label: Label
var _anchor_option: OptionButton
var _fit_mode_option: OptionButton
var _x_spin: SpinBox
var _y_spin: SpinBox
var _width_spin: SpinBox
var _height_spin: SpinBox
var _opacity_spin: SpinBox
var _z_index_spin: SpinBox
var _show_asset_check: CheckButton
var _show_rect_check: CheckButton
var _visible_check: CheckButton
var _locked_check: CheckButton

var _show_assets_button: CheckButton
var _show_rects_button: CheckButton
var _show_labels_button: CheckButton
var _visual_layer_button: CheckButton
var _interaction_layer_button: CheckButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout = UILayoutConfig.load_layout()
	_build_ui()
	_refresh_all(false)


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
	root.add_theme_constant_override("separation", 8)
	outer.add_child(root)

	_build_actions_bar(root)
	_build_view_bar(root)

	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	root.add_child(content)

	_build_elements_panel(content)
	_build_preview_panel(content)
	_build_properties_panel(content)
	_build_file_dialog()


func _build_actions_bar(parent: Container) -> void:
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 6)
	parent.add_child(bar)

	var title := Label.new()
	title.text = "UILayout Editor"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	bar.add_child(_make_button("Undo", _on_undo_pressed))
	bar.add_child(_make_button("Redo", _on_redo_pressed))
	bar.add_child(_make_button("Add Graphic", _on_add_graphic_pressed))
	bar.add_child(_make_button("Duplicate", _on_duplicate_pressed))
	bar.add_child(_make_button("Delete", _on_delete_pressed))
	bar.add_child(_make_button("Save Layout", _on_save_layout_pressed))
	bar.add_child(_make_button("Reload Layout", _on_reload_layout_pressed))
	bar.add_child(_make_button("Reset Defaults", _on_reset_defaults_pressed))


func _build_view_bar(parent: Container) -> void:
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 6)
	parent.add_child(bar)

	_show_assets_button = _make_check_button("Show Assets", func(pressed: bool) -> void:
		show_assets = pressed
		_queue_redraw()
	)
	_show_assets_button.button_pressed = true
	bar.add_child(_show_assets_button)

	_show_rects_button = _make_check_button("Show Rects", func(pressed: bool) -> void:
		show_rects = pressed
		_queue_redraw()
	)
	_show_rects_button.button_pressed = true
	bar.add_child(_show_rects_button)

	_show_labels_button = _make_check_button("Show Labels", func(pressed: bool) -> void:
		show_labels = pressed
		_queue_redraw()
	)
	_show_labels_button.button_pressed = true
	bar.add_child(_show_labels_button)

	_visual_layer_button = _make_check_button("Visual Layer", func(pressed: bool) -> void:
		visual_layer_enabled = pressed
		_queue_redraw()
	)
	_visual_layer_button.button_pressed = true
	bar.add_child(_visual_layer_button)

	_interaction_layer_button = _make_check_button("Interaction Layer", func(pressed: bool) -> void:
		interaction_layer_enabled = pressed
		_queue_redraw()
	)
	_interaction_layer_button.button_pressed = true
	bar.add_child(_interaction_layer_button)


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
	_element_id_label = _make_value_label("-")
	body.add_child(_make_labeled_row("Element", _element_id_label))

	_label_edit = _make_line_edit(func() -> void:
		_commit_property_text("label", _label_edit.text)
	)
	body.add_child(_make_labeled_row("Label", _label_edit))

	_type_label = _make_value_label("")
	body.add_child(_make_labeled_row("Type", _type_label))

	_parent_label = _make_value_label("")
	body.add_child(_make_labeled_row("Parent", _parent_label))

	_asset_path_edit = _make_line_edit(func() -> void:
		_commit_property_text("asset_path", _asset_path_edit.text)
	)
	body.add_child(_make_labeled_row("Asset Path", _asset_path_edit))

	_show_asset_check = _make_check_button("Show Asset", func(pressed: bool) -> void:
		_commit_property_bool("show_asset", pressed)
	)
	body.add_child(_show_asset_check)

	_show_rect_check = _make_check_button("Show Rect", func(pressed: bool) -> void:
		_commit_property_bool("show_rect", pressed)
	)
	body.add_child(_show_rect_check)

	_anchor_option = _make_option_button(["top_left", "top_center", "top_right", "center", "bottom_center", "bottom_left", "bottom_right"], func(index: int) -> void:
		_commit_property_text("anchor", _anchor_option.get_item_text(index))
	)
	body.add_child(_make_labeled_row("Anchor", _anchor_option))

	_fit_mode_option = _make_option_button(["stretch", "keep_aspect", "keep_aspect_centered", "tile"], func(index: int) -> void:
		_commit_property_text("fit_mode", _fit_mode_option.get_item_text(index))
	)
	body.add_child(_make_labeled_row("Fit Mode", _fit_mode_option))

	_x_spin = _make_spinbox(-5000, 5000, 1.0, func(_value: float) -> void:
		_commit_property_number("x", int(roundf(_x_spin.value)))
	)
	body.add_child(_make_labeled_row("X", _x_spin))

	_y_spin = _make_spinbox(-5000, 5000, 1.0, func(_value: float) -> void:
		_commit_property_number("y", int(roundf(_y_spin.value)))
	)
	body.add_child(_make_labeled_row("Y", _y_spin))

	_width_spin = _make_spinbox(1, 5000, 1.0, func(_value: float) -> void:
		_commit_property_number("width", max(1, int(roundf(_width_spin.value))))
	)
	body.add_child(_make_labeled_row("Width", _width_spin))

	_height_spin = _make_spinbox(1, 5000, 1.0, func(_value: float) -> void:
		_commit_property_number("height", max(1, int(roundf(_height_spin.value))))
	)
	body.add_child(_make_labeled_row("Height", _height_spin))

	_opacity_spin = _make_spinbox(0, 1, 0.01, func(_value: float) -> void:
		_commit_property_float("opacity", _opacity_spin.value)
	)
	body.add_child(_make_labeled_row("Opacity", _opacity_spin))

	_z_index_spin = _make_spinbox(-999, 999, 1.0, func(_value: float) -> void:
		_commit_property_number("z_index", int(roundf(_z_index_spin.value)))
	)
	body.add_child(_make_labeled_row("Z Index", _z_index_spin))

	_visible_check = _make_check_button("Visible", func(pressed: bool) -> void:
		_commit_property_bool("visible", pressed)
	)
	body.add_child(_visible_check)

	_locked_check = _make_check_button("Locked", func(pressed: bool) -> void:
		_commit_property_bool("locked", pressed)
	)
	body.add_child(_locked_check)

	_status_label = Label.new()
	_status_label.text = "Ready."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status_label)

	body.add_child(_make_section_label("Asset Preview"))
	_build_asset_preview(body)


func _build_asset_preview(parent: Container) -> void:
	_asset_grid = GridContainer.new()
	_asset_grid.columns = 2
	_asset_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_grid.add_theme_constant_override("h_separation", 6)
	_asset_grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(_asset_grid)

	_refresh_asset_preview()


func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.title = "Choose Graphic"
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.current_dir = "res://assets/ui"
	_file_dialog.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg ; JPEG Images",
		"*.jpeg ; JPEG Images",
		"*.webp ; WebP Images",
	])
	_file_dialog.file_selected.connect(_on_file_dialog_file_selected)
	add_child(_file_dialog)


func _refresh_all(keep_selection := false) -> void:
	_refresh_elements_list()
	_refresh_property_panel()
	_refresh_asset_preview()
	_queue_redraw()
	if not keep_selection:
		_select_default_element()


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
		var z_index := int(element.get("z_index", 0))
		var display_text := "%s [%s] z:%d" % [label_text, type_text, z_index]
		_elements_list.add_item(display_text)
		_elements_list.set_item_metadata(_elements_list.item_count - 1, element_id)


func _refresh_property_panel() -> void:
	if _updating_ui:
		return

	_updating_ui = true
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		_element_id_label.text = "-"
		_label_edit.text = ""
		_type_label.text = ""
		_parent_label.text = ""
		_asset_path_edit.text = ""
		_anchor_option.select(0)
		_fit_mode_option.select(0)
		_x_spin.value = 0
		_y_spin.value = 0
		_width_spin.value = 0
		_height_spin.value = 0
		_opacity_spin.value = 1.0
		_z_index_spin.value = 0
		_show_asset_check.button_pressed = false
		_show_rect_check.button_pressed = false
		_visible_check.button_pressed = false
		_locked_check.button_pressed = false
		_updating_ui = false
		return

	_element_id_label.text = selected_element_id
	_label_edit.text = str(element.get("label", ""))
	_type_label.text = str(element.get("type", ""))
	_parent_label.text = str(element.get("parent", ""))
	_asset_path_edit.text = UILayoutConfig.normalize_asset_path(str(element.get("asset_path", "")))
	_asset_path_edit.tooltip_text = _asset_path_edit.text
	_anchor_option.select(_get_anchor_option_index(str(element.get("anchor", "top_left"))))
	_fit_mode_option.select(_get_fit_mode_option_index(str(element.get("fit_mode", "stretch"))))
	_x_spin.value = float(element.get("x", 0.0))
	_y_spin.value = float(element.get("y", 0.0))
	_width_spin.value = float(element.get("width", 0.0))
	_height_spin.value = float(element.get("height", 0.0))
	_opacity_spin.value = clampf(float(element.get("opacity", 1.0)), 0.0, 1.0)
	_z_index_spin.value = float(element.get("z_index", 0))
	_show_asset_check.button_pressed = bool(element.get("show_asset", false))
	_show_rect_check.button_pressed = bool(element.get("show_rect", true))
	_visible_check.button_pressed = bool(element.get("visible", true))
	_locked_check.button_pressed = bool(element.get("locked", false))
	_updating_ui = false


func _refresh_asset_preview() -> void:
	if _asset_grid == null:
		return

	for child in _asset_grid.get_children():
		child.queue_free()

	var asset_paths := {}
	for asset_path in DEFAULT_ASSET_PATHS:
		asset_paths[asset_path] = true

	var elements := UILayoutConfig.get_element_ids(layout)
	for element_id in elements:
		var element := UILayoutConfig.get_element(layout, element_id)
		var asset_path := str(element.get("asset_path", ""))
		if asset_path.is_empty():
			continue
		asset_paths[asset_path] = true

	var sorted_paths: Array[String] = []
	for key in asset_paths.keys():
		sorted_paths.append(str(key))
	sorted_paths.sort()

	for asset_path in sorted_paths:
		var tile := AssetTile.new()
		tile.editor_ref = self
		tile.asset_path = asset_path
		tile.title = asset_path.get_file()
		tile.missing = not _asset_exists(asset_path)
		_asset_grid.add_child(tile)


func _select_default_element() -> void:
	if selected_element_id.is_empty():
		var ids := _get_sorted_element_ids()
		if not ids.is_empty():
			_select_element(ids[0])
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
		_queue_redraw()
		return

	var element := UILayoutConfig.get_element(layout, element_id)
	if element.is_empty():
		selected_element_id = ""
		_refresh_property_panel()
		_queue_redraw()
		return

	selected_element_id = element_id
	var item_index := _find_item_index_for_element(element_id)
	if item_index >= 0 and _elements_list != null:
		_updating_ui = true
		_elements_list.select(item_index)
		_updating_ui = false
	_refresh_property_panel()
	_queue_redraw()


func _find_item_index_for_element(element_id: String) -> int:
	if _elements_list == null:
		return -1
	for index in range(_elements_list.item_count):
		if str(_elements_list.get_item_metadata(index)) == element_id:
			return index
	return -1


func _commit_property_text(property_name: String, value: String) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return

	var current := UILayoutConfig.get_element(layout, selected_element_id)
	if current.is_empty() or bool(current.get("locked", false)):
		return
	if str(current.get(property_name, "")) == value:
		return

	_push_undo_state()
	current[property_name] = value
	var refresh_assets := property_name == "asset_path"
	_set_element_and_refresh(selected_element_id, current, refresh_assets)


func _commit_property_bool(property_name: String, value: bool) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return

	var current := UILayoutConfig.get_element(layout, selected_element_id)
	if current.is_empty() or bool(current.get("locked", false)):
		return
	if bool(current.get(property_name, false)) == value:
		return

	_push_undo_state()
	current[property_name] = value
	_set_element_and_refresh(selected_element_id, current, false)


func _commit_property_number(property_name: String, value: int) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return

	var current := UILayoutConfig.get_element(layout, selected_element_id)
	if current.is_empty() or bool(current.get("locked", false)):
		return
	if int(current.get(property_name, 0)) == value:
		return

	_push_undo_state()
	current[property_name] = value
	_set_element_and_refresh(selected_element_id, current, false)


func _commit_property_float(property_name: String, value: float) -> void:
	if _updating_ui or selected_element_id.is_empty():
		return

	var current := UILayoutConfig.get_element(layout, selected_element_id)
	if current.is_empty() or bool(current.get("locked", false)):
		return
	if is_equal_approx(float(current.get(property_name, 0.0)), value):
		return

	_push_undo_state()
	current[property_name] = value
	_set_element_and_refresh(selected_element_id, current, false)


func _set_element_and_refresh(element_id: String, element_data: Dictionary, refresh_asset_panel := false) -> void:
	UILayoutConfig.set_element(layout, element_id, element_data)
	_refresh_elements_list()
	_refresh_property_panel()
	if refresh_asset_panel:
		_refresh_asset_preview()
	_queue_redraw()


func _on_anchor_selected(index: int) -> void:
	_commit_property_text("anchor", _anchor_option.get_item_text(index))


func _on_fit_mode_selected(index: int) -> void:
	_commit_property_text("fit_mode", _fit_mode_option.get_item_text(index))


func _on_asset_path_finished() -> void:
	_commit_property_text("asset_path", _asset_path_edit.text)


func _make_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _make_check_button(text_value: String, callback: Callable) -> CheckButton:
	var button := CheckButton.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(callback)
	return button


func _make_line_edit(on_finished: Callable) -> LineEdit:
	var line_edit := LineEdit.new()
	line_edit.text_submitted.connect(func(_text: String) -> void:
		on_finished.call()
	)
	line_edit.focus_exited.connect(func() -> void:
		on_finished.call()
	)
	return line_edit


func _make_option_button(items: Array[String], callback: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item_text in items:
		option.add_item(item_text)
	option.item_selected.connect(callback)
	return option


func _make_spinbox(min_value: float, max_value: float, step_value: float, callback: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step_value
	spin.allow_lesser = false
	spin.allow_greater = false
	spin.value_changed.connect(callback)
	return spin


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
	title.custom_minimum_size = Vector2(92, 0)
	row.add_child(title)

	value_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_control)
	return row


func _draw_preview_canvas(canvas: Control) -> void:
	var view := _get_canvas_view(canvas)
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var scale := float(view.get("scale", 1.0))
	var preview_rect := Rect2(origin, CANVAS_SIZE * scale)

	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.03, 0.04, 0.05, 1.0), true)
	canvas.draw_rect(preview_rect, Color(0.12, 0.12, 0.14, 1.0), true)
	canvas.draw_rect(preview_rect, Color(0.24, 0.24, 0.28, 1.0), false, 2.0)

	var sorted_ids := _get_sorted_element_ids()
	for pass_name in ["visual", "guide", "interaction"]:
		for element_id in sorted_ids:
			var element := UILayoutConfig.get_element(layout, element_id)
			if element.is_empty():
				continue

			var element_type := str(element.get("type", "hud"))
			var visible := bool(element.get("visible", true))
			var opacity := clampf(float(element.get("opacity", 1.0)), 0.0, 1.0)
			var is_interaction := element_type == "interaction"
			var is_guide := element_type == "guide"
			var is_visual := not is_interaction and not is_guide

			if pass_name == "visual" and not is_visual:
				continue
			if pass_name == "guide" and not is_guide:
				continue
			if pass_name == "interaction" and not is_interaction:
				continue

			if is_interaction and not interaction_layer_enabled:
				continue
			if not is_interaction and not visual_layer_enabled:
				continue

			var rect := _get_element_rect(element_id)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue

			var screen_rect := Rect2(origin + rect.position * scale, rect.size * scale)
			var alpha := opacity
			if not visible:
				alpha *= 0.18

			var show_asset := show_assets and bool(element.get("show_asset", false)) and is_visual
			var show_rect := show_rects and bool(element.get("show_rect", true))

			if show_asset:
				_draw_element_asset(canvas, screen_rect, element, alpha, element_id)

			if show_rect:
				_draw_element_rect(canvas, screen_rect, element, alpha, element_id, is_interaction, show_asset)

	if show_labels and not _is_dragging_preview:
		for element_id in sorted_ids:
			var element := UILayoutConfig.get_element(layout, element_id)
			if element.is_empty():
				continue
			var element_type := str(element.get("type", "hud"))
			var is_interaction := element_type == "interaction"
			if is_interaction and not interaction_layer_enabled:
				continue
			if not is_interaction and not visual_layer_enabled:
				continue
			var rect := _get_element_rect(element_id)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			var screen_rect := Rect2(origin + rect.position * scale, rect.size * scale)
			var visible := bool(element.get("visible", true))
			var alpha := clampf(float(element.get("opacity", 1.0)), 0.0, 1.0)
			if not visible:
				alpha *= 0.18
			_draw_element_label(canvas, screen_rect, element, alpha, element_id)

	if not selected_element_id.is_empty():
		var selected_rect := _get_element_rect(selected_element_id)
		if selected_rect.size.x > 0.0 and selected_rect.size.y > 0.0:
			var selected_screen_rect := Rect2(origin + selected_rect.position * scale, selected_rect.size * scale)
			var selected_data := UILayoutConfig.get_element(layout, selected_element_id)
			var selected_border := 3.0
			var selected_asset_visible := show_assets and bool(selected_data.get("show_asset", false)) and str(selected_data.get("type", "")) not in ["interaction", "guide"]
			if selected_asset_visible and not show_rects:
				selected_border = 1.0
			canvas.draw_rect(selected_screen_rect, Color(1.0, 1.0, 1.0, 1.0), false, selected_border)
			_draw_resize_handle(canvas, selected_screen_rect)


func _draw_element_asset(canvas: Control, screen_rect: Rect2, element: Dictionary, alpha: float, element_id: String) -> void:
	var asset_path := UILayoutConfig.normalize_asset_path(str(element.get("asset_path", "")))
	var texture := _get_cached_texture(asset_path)
	if texture == null:
		var missing_color := Color(0.18, 0.18, 0.2, maxf(0.24, alpha))
		canvas.draw_rect(screen_rect, missing_color, true)
		canvas.draw_rect(screen_rect, Color(0.65, 0.2, 0.2, maxf(0.45, alpha)), false, 1.0)
		var font := canvas.get_theme_default_font()
		if font != null:
			canvas.draw_string(font, screen_rect.position + Vector2(6, 16), "missing asset", HORIZONTAL_ALIGNMENT_LEFT, -1, canvas.get_theme_default_font_size(), Color(1.0, 0.8, 0.8, alpha))
		return

	var fit_mode := str(element.get("fit_mode", "stretch"))
	var texture_rect := screen_rect
	if fit_mode != "stretch" and fit_mode != "tile":
		texture_rect = _get_fitted_rect(texture.get_size(), screen_rect, fit_mode)

	var modulate := Color(1, 1, 1, alpha)
	if fit_mode == "tile":
		canvas.draw_texture_rect(texture, screen_rect, true, modulate)
	else:
		canvas.draw_texture_rect(texture, texture_rect, false, modulate)


func _draw_element_rect(canvas: Control, screen_rect: Rect2, element: Dictionary, alpha: float, element_id: String, is_interaction: bool, asset_visible: bool) -> void:
	var color := _get_element_color(str(element.get("type", "default")))
	var fill_enabled := is_interaction or str(element.get("type", "")) == "guide" or not asset_visible
	if fill_enabled:
		if is_interaction:
			color.a = clampf(maxf(alpha * 0.35, 0.2), 0.2, 0.38)
		else:
			color.a = clampf(alpha * 0.16, 0.12, 0.24)
		canvas.draw_rect(screen_rect, color, true)
	var border := Color(0.0, 0.0, 0.0, 0.5)
	if element_id == selected_element_id:
		border = Color(1.0, 1.0, 1.0, 0.85)
	else:
		var border_alpha := 0.38
		if is_interaction:
			border_alpha = 0.5
		border = Color(0.0, 0.0, 0.0, border_alpha)
	canvas.draw_rect(screen_rect, border, false, 2.0)


func _draw_element_label(canvas: Control, screen_rect: Rect2, element: Dictionary, alpha: float, element_id: String) -> void:
	if _should_suppress_label(element_id):
		return
	var label_text := str(element.get("label", ""))
	if label_text.is_empty():
		label_text = str(element.get("type", ""))
	if label_text.is_empty():
		return
	var font := canvas.get_theme_default_font()
	if font == null:
		return
	canvas.draw_string(font, screen_rect.position + Vector2(6, 14), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, canvas.get_theme_default_font_size(), Color(1.0, 1.0, 1.0, alpha))


func _should_suppress_label(element_id: String) -> bool:
	if element_id.begins_with("inventory.slot_"):
		return true
	if element_id.begins_with("hotbar.slot_"):
		return true
	if element_id.ends_with("_hitbox"):
		return true
	return false


func _draw_resize_handle(canvas: Control, rect: Rect2) -> void:
	var handle_size := 10.0
	var handle_rect := Rect2(rect.position + rect.size - Vector2(handle_size, handle_size), Vector2(handle_size, handle_size))
	canvas.draw_rect(handle_rect, Color(1.0, 1.0, 1.0, 0.9), true)
	canvas.draw_rect(handle_rect, Color(0.0, 0.0, 0.0, 0.85), false, 1.0)


func _handle_preview_gui_input(canvas: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed:
			var canvas_pos := _screen_to_canvas_pos(canvas, mouse_event.position)
			var hit_id := _pick_element_at_canvas_position(canvas_pos)
			if not hit_id.is_empty():
				_select_element(hit_id)
				var element := UILayoutConfig.get_element(layout, hit_id)
				if bool(element.get("locked", false)):
					return
				if _is_in_resize_handle(canvas, mouse_event.position, _get_element_screen_rect(hit_id)):
					_begin_drag("resize", hit_id, canvas_pos)
				else:
					_begin_drag("move", hit_id, canvas_pos)
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
	_push_undo_state()
	_drag_mode = mode
	_drag_element_id = element_id
	_drag_start_mouse = mouse_canvas_pos
	_drag_start_element = element.duplicate(true)
	_is_dragging_preview = true


func _end_drag() -> void:
	var had_drag := not _drag_mode.is_empty()
	_drag_mode = ""
	_drag_element_id = ""
	_drag_start_element = {}
	_is_dragging_preview = false
	if had_drag:
		_refresh_property_panel()
	_queue_redraw()


func _update_drag(current_mouse_canvas_pos: Vector2) -> void:
	if _drag_mode.is_empty() or _drag_element_id.is_empty():
		return

	var element := UILayoutConfig.get_element(layout, _drag_element_id)
	if element.is_empty() or bool(element.get("locked", false)):
		return

	var delta := current_mouse_canvas_pos - _drag_start_mouse
	var updated := _drag_start_element.duplicate(true)
	if _drag_mode == "move":
		updated["x"] = _snap_value(float(_drag_start_element.get("x", 0.0)) + delta.x)
		updated["y"] = _snap_value(float(_drag_start_element.get("y", 0.0)) + delta.y)
	elif _drag_mode == "resize":
		updated["width"] = max(1, _snap_value(float(_drag_start_element.get("width", 0.0)) + delta.x))
		updated["height"] = max(1, _snap_value(float(_drag_start_element.get("height", 0.0)) + delta.y))

	UILayoutConfig.set_element(layout, _drag_element_id, updated)
	_updating_ui = true
	if _x_spin != null:
		_x_spin.value = float(updated.get("x", 0))
	if _y_spin != null:
		_y_spin.value = float(updated.get("y", 0))
	if _width_spin != null:
		_width_spin.value = float(updated.get("width", 0))
	if _height_spin != null:
		_height_spin.value = float(updated.get("height", 0))
	_updating_ui = false
	_queue_redraw()


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
	var preview_size := CANVAS_SIZE * scale
	var origin := (available - preview_size) * 0.5
	return {
		"origin": origin,
		"scale": scale,
	}


func _pick_element_at_canvas_position(canvas_pos: Vector2) -> String:
	var ids := _get_sorted_element_ids()
	for index in range(ids.size() - 1, -1, -1):
		var element_id := ids[index]
		var element := UILayoutConfig.get_element(layout, element_id)
		if element.is_empty():
			continue
		var is_interaction := str(element.get("type", "")) == "interaction"
		if is_interaction and not interaction_layer_enabled:
			continue
		if not is_interaction and not visual_layer_enabled:
			continue
		var rect := _get_element_rect(element_id)
		if rect.has_point(canvas_pos):
			return element_id
	return ""


func _is_in_resize_handle(canvas: Control, screen_pos: Vector2, rect: Rect2) -> bool:
	var view := _get_canvas_view(canvas)
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var scale := float(view.get("scale", 1.0))
	var screen_rect := Rect2(origin + rect.position * scale, rect.size * scale)
	var handle_size := 12.0
	var handle_rect := Rect2(screen_rect.position + screen_rect.size - Vector2(handle_size, handle_size), Vector2(handle_size, handle_size))
	return handle_rect.has_point(screen_pos)


func _get_element_screen_rect(element_id: String) -> Rect2:
	var rect := _get_element_rect(element_id)
	var view := _get_canvas_view(_preview_canvas)
	var origin: Vector2 = view.get("origin", Vector2.ZERO)
	var scale := float(view.get("scale", 1.0))
	return Rect2(origin + rect.position * scale, rect.size * scale)


func _get_element_rect(element_id: String) -> Rect2:
	return UILayoutApplier.get_element_rect(layout, element_id)


func _get_element_color(element_type: String) -> Color:
	if ELEMENT_COLORS.has(element_type):
		return ELEMENT_COLORS[element_type]
	return ELEMENT_COLORS["default"]


func _get_sorted_element_ids() -> Array[String]:
	var ids := UILayoutConfig.get_element_ids(layout)
	ids.sort_custom(Callable(self, "_compare_element_ids"))
	return ids


func _compare_element_ids(a: String, b: String) -> bool:
	var element_a := UILayoutConfig.get_element(layout, a)
	var element_b := UILayoutConfig.get_element(layout, b)

	var z_a := int(element_a.get("z_index", 0))
	var z_b := int(element_b.get("z_index", 0))
	if z_a != z_b:
		return z_a < z_b

	var order_a := _get_default_order_index(a)
	var order_b := _get_default_order_index(b)
	if order_a != order_b:
		return order_a < order_b

	return a < b


func _get_default_order_index(element_id: String) -> int:
	var default_ids := UILayoutConfig.get_default_element_ids()
	var index := default_ids.find(element_id)
	if index >= 0:
		return index
	return 1000


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


func _get_fit_mode_option_index(fit_mode: String) -> int:
	match fit_mode:
		"stretch":
			return 0
		"keep_aspect":
			return 1
		"keep_aspect_centered":
			return 2
		"tile":
			return 3
		_:
			return 0


func _get_fit_mode_from_index(index: int) -> String:
	match index:
		0:
			return "stretch"
		1:
			return "keep_aspect"
		2:
			return "keep_aspect_centered"
		3:
			return "tile"
		_:
			return "stretch"


func _asset_exists(asset_path: String) -> bool:
	return _get_cached_texture(asset_path) != null


func _get_asset_preview_texture(asset_path: String) -> Texture2D:
	return _get_cached_texture(asset_path)


func _get_cached_texture(asset_path: String) -> Texture2D:
	var normalized := UILayoutConfig.normalize_asset_path(asset_path)
	if normalized.is_empty():
		return null
	if _texture_cache.has(normalized):
		return _texture_cache[normalized]
	if not ResourceLoader.exists(normalized):
		_texture_cache[normalized] = null
		return null
	var resource := ResourceLoader.load(normalized)
	var texture := resource if resource is Texture2D else null
	_texture_cache[normalized] = texture
	return texture


func _get_fitted_rect(texture_size: Vector2, target_rect: Rect2, fit_mode: String) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return target_rect
	if fit_mode == "stretch":
		return target_rect
	if fit_mode == "tile":
		return target_rect

	var scale_x := target_rect.size.x / texture_size.x
	var scale_y := target_rect.size.y / texture_size.y
	var scale := minf(scale_x, scale_y)
	var fitted_size := texture_size * scale
	var fitted_pos := target_rect.position + (target_rect.size - fitted_size) * 0.5
	return Rect2(fitted_pos, fitted_size)


func _on_asset_tile_double_clicked(asset_path: String) -> void:
	if asset_path.is_empty() or not _asset_exists(asset_path):
		_status_label.text = "Asset missing."
		return
	_create_graphic_from_asset(asset_path)


func _on_add_graphic_pressed() -> void:
	if _file_dialog != null:
		_file_dialog.popup_centered_ratio(0.7)


func _on_file_dialog_file_selected(path: String) -> void:
	_create_graphic_from_asset(_normalize_project_path(path))


func _create_graphic_from_asset(asset_path: String) -> void:
	if asset_path.is_empty() or not _asset_exists(asset_path):
		_status_label.text = "Missing asset."
		return

	var texture := _get_asset_preview_texture(asset_path)
	var texture_size := texture.get_size() if texture != null else Vector2(128, 128)
	var new_id := UILayoutConfig.get_next_custom_graphic_id(layout)
	var label_text := "Graphic %s" % new_id.get_slice("_", 2)
	var width := int(maxf(64.0, texture_size.x))
	var height := int(maxf(64.0, texture_size.y))
	var x := int((CANVAS_SIZE.x - width) * 0.5)
	var y := int((CANVAS_SIZE.y - height) * 0.5)

	_push_undo_state()
	var element := {
		"label": label_text,
		"type": "graphic",
		"parent": "",
		"anchor": "top_left",
		"x": x,
		"y": y,
		"width": width,
		"height": height,
		"visible": true,
		"locked": false,
		"asset_path": asset_path,
		"show_asset": true,
		"show_rect": true,
		"opacity": 1.0,
		"z_index": 50,
		"fit_mode": "keep_aspect_centered",
	}
	UILayoutConfig.set_element(layout, new_id, element)
	_select_element(new_id)
	_refresh_all(true)
	_status_label.text = "Added %s." % new_id


func _on_duplicate_pressed() -> void:
	_duplicate_selected_element()


func _duplicate_selected_element() -> void:
	if selected_element_id.is_empty():
		return
	var source := UILayoutConfig.get_element(layout, selected_element_id)
	if source.is_empty():
		return

	_push_undo_state()
	var new_id := _get_unique_duplicate_id(selected_element_id)
	var duplicate := source.duplicate(true)
	var offset := 20
	duplicate["x"] = int(source.get("x", 0)) + offset
	duplicate["y"] = int(source.get("y", 0)) + offset
	duplicate["label"] = "%s Copy" % str(source.get("label", selected_element_id))
	duplicate["locked"] = bool(source.get("locked", false))
	UILayoutConfig.set_element(layout, new_id, duplicate)
	_select_element(new_id)
	_refresh_all(true)
	_status_label.text = "Duplicated to %s." % new_id


func _get_unique_duplicate_id(source_id: String) -> String:
	var base := "%s_copy" % source_id
	var candidate := base
	var suffix := 2
	while not _element_id_exists(candidate):
		return candidate
	return candidate


func _element_id_exists(element_id: String) -> bool:
	var ids := UILayoutConfig.get_element_ids(layout)
	return ids.has(element_id)


func _on_delete_pressed() -> void:
	_delete_selected_element()


func _delete_selected_element() -> void:
	if selected_element_id.is_empty():
		return
	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty():
		return
	if bool(element.get("locked", false)):
		_status_label.text = "Locked element cannot be deleted."
		return

	_push_undo_state()
	var removed_id := selected_element_id
	UILayoutConfig.remove_element(layout, removed_id)
	selected_element_id = ""
	_refresh_all(true)
	_status_label.text = "Deleted %s." % removed_id


func _on_undo_pressed() -> void:
	_undo()


func _on_redo_pressed() -> void:
	_redo()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(layout.duplicate(true))
	if _redo_stack.size() > HISTORY_LIMIT:
		_redo_stack.remove_at(0)
	layout = _undo_stack.pop_back()
	_applying_history = true
	_refresh_all(true)
	_applying_history = false
	_status_label.text = "Undo."


func _redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(layout.duplicate(true))
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.remove_at(0)
	layout = _redo_stack.pop_back()
	_applying_history = true
	_refresh_all(true)
	_applying_history = false
	_status_label.text = "Redo."


func _push_undo_state() -> void:
	if _applying_history:
		return
	_undo_stack.append(layout.duplicate(true))
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.remove_at(0)
	_redo_stack.clear()


func _on_save_layout_pressed() -> void:
	if UILayoutConfig.save_layout(layout):
		_status_label.text = "Layout saved."
	else:
		_status_label.text = "Save failed."


func _on_reload_layout_pressed() -> void:
	layout = UILayoutConfig.load_layout()
	_undo_stack.clear()
	_redo_stack.clear()
	_select_default_element()
	_refresh_all(true)
	_status_label.text = "Layout reloaded."


func _on_reset_defaults_pressed() -> void:
	_push_undo_state()
	layout = UILayoutConfig.get_default_layout()
	_select_default_element()
	_refresh_all(true)
	_status_label.text = "Defaults restored."


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not is_drag_successful():
		_end_drag()


func _unhandled_input(event: InputEvent) -> void:
	if _is_text_input_focused():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.ctrl_pressed and key_event.keycode == KEY_Z:
			_undo()
			get_viewport().set_input_as_handled()
			return
		if key_event.ctrl_pressed and key_event.keycode == KEY_Y:
			_redo()
			get_viewport().set_input_as_handled()
			return
		if key_event.ctrl_pressed and key_event.keycode == KEY_D:
			_duplicate_selected_element()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_DELETE:
			_delete_selected_element()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			_handle_nudge(key_event)
			get_viewport().set_input_as_handled()
			return


func _handle_nudge(event: InputEventKey) -> void:
	if selected_element_id.is_empty():
		return

	var element := UILayoutConfig.get_element(layout, selected_element_id)
	if element.is_empty() or bool(element.get("locked", false)):
		return

	var step := 1
	if event.shift_pressed:
		step = 10

	var is_resize := event.alt_pressed
	_push_undo_state()
	if not is_resize:
		match event.keycode:
			KEY_UP:
				element["y"] = int(element.get("y", 0)) - step
			KEY_DOWN:
				element["y"] = int(element.get("y", 0)) + step
			KEY_LEFT:
				element["x"] = int(element.get("x", 0)) - step
			KEY_RIGHT:
				element["x"] = int(element.get("x", 0)) + step
	else:
		match event.keycode:
			KEY_UP:
				element["height"] = max(1, int(element.get("height", 0)) - step)
			KEY_DOWN:
				element["height"] = max(1, int(element.get("height", 0)) + step)
			KEY_LEFT:
				element["width"] = max(1, int(element.get("width", 0)) - step)
			KEY_RIGHT:
				element["width"] = max(1, int(element.get("width", 0)) + step)

	UILayoutConfig.set_element(layout, selected_element_id, element)
	_refresh_property_panel()
	_queue_redraw()


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is SpinBox


func _queue_redraw() -> void:
	if _preview_canvas != null:
		_preview_canvas.queue_redraw()


func _normalize_project_path(path: String) -> String:
	return UILayoutConfig.normalize_asset_path(path)


func _get_anchor_position(anchor_name: String, canvas_size: Vector2) -> Vector2:
	match anchor_name:
		"top_left":
			return Vector2.ZERO
		"top_right":
			return Vector2(canvas_size.x, 0.0)
		"bottom_left":
			return Vector2(0.0, canvas_size.y)
		"bottom_right":
			return canvas_size
		"bottom_center":
			return Vector2(canvas_size.x * 0.5, canvas_size.y)
		"top_center":
			return Vector2(canvas_size.x * 0.5, 0.0)
		"center":
			return canvas_size * 0.5
		_:
			return Vector2.ZERO


func _get_asset_paths_for_preview() -> Array[String]:
	var paths: Array[String] = DEFAULT_ASSET_PATHS.duplicate(true)
	var existing := {}
	for asset_path in paths:
		existing[UILayoutConfig.normalize_asset_path(asset_path)] = true
	for element_id in UILayoutConfig.get_element_ids(layout):
		var element := UILayoutConfig.get_element(layout, element_id)
		var asset_path := UILayoutConfig.normalize_asset_path(str(element.get("asset_path", "")))
		if asset_path.is_empty() or existing.has(asset_path):
			continue
		paths.append(asset_path)
		existing[asset_path] = true
	paths.sort()
	return paths
