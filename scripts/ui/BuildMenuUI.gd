extends Control

var build_system: Node
var panel: PanelContainer
var title_label: Label
var selected_label: Label
var catalog_container: VBoxContainer
var hint_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	visible = false


func setup(system: Node) -> void:
	build_system = system
	refresh_catalog()


func set_build_mode_visible(is_visible: bool) -> void:
	visible = is_visible
	if is_visible:
		refresh_catalog()


func refresh_catalog() -> void:
	if catalog_container == null:
		return
	for child in catalog_container.get_children():
		child.queue_free()
	if build_system == null or not build_system.has_method("get_build_catalog"):
		return
	var selected_id := ""
	if build_system.has_method("get_selected_building_id"):
		selected_id = str(build_system.call("get_selected_building_id"))
	for entry_value in build_system.call("get_build_catalog"):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var building_id := str(entry.get("id", ""))
		var button := Button.new()
		button.name = "Build_%s" % building_id
		button.toggle_mode = true
		button.button_pressed = building_id == selected_id
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s  %s\n%s" % [
			str(entry.get("key", "")),
			str(entry.get("display_name", building_id)),
			str(entry.get("cost", "Free")),
		]
		button.tooltip_text = "Select %s" % str(entry.get("display_name", building_id))
		button.pressed.connect(_on_building_selected.bind(building_id))
		catalog_container.add_child(button)
	_update_selected_label(selected_id)


func _build_interface() -> void:
	panel = PanelContainer.new()
	panel.name = "BuildMenuPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1.0
	panel.anchor_top = 0.5
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.5
	panel.offset_left = -344.0
	panel.offset_top = -330.0
	panel.offset_right = -24.0
	panel.offset_bottom = 330.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	title_label = Label.new()
	title_label.text = "BUILDING MODE"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	selected_label = Label.new()
	selected_label.text = "Selected: -"
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(selected_label)

	var separator := HSeparator.new()
	column.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	catalog_container = VBoxContainer.new()
	catalog_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_container.add_theme_constant_override("separation", 6)
	scroll.add_child(catalog_container)

	hint_label = Label.new()
	hint_label.text = "Left click: build   Right click: remove\nB: close mode   Number keys: quick select"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint_label)


func _on_building_selected(building_id: String) -> void:
	if build_system != null and build_system.has_method("select_building"):
		build_system.call("select_building", building_id)
	refresh_catalog()


func _on_close_pressed() -> void:
	if build_system != null and build_system.has_method("set_build_mode_enabled"):
		build_system.call("set_build_mode_enabled", false)


func _update_selected_label(selected_id: String) -> void:
	if selected_label == null:
		return
	var display_name := selected_id.capitalize()
	if build_system != null and build_system.has_method("get_selected_building_display_name"):
		display_name = str(build_system.call("get_selected_building_display_name"))
	selected_label.text = "Selected: %s" % display_name
