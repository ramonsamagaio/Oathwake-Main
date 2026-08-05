extends CanvasLayer

const RecipeBookScript := preload("res://scripts/systems/RecipeBook.gd")
const CAMPFIRE_ID := "campfire"

var _build_system: Node
var _floor_manager: Node
var _panel: PanelContainer
var _title_label: Label
var _floor_label: Label
var _cost_label: Label
var _button_list: VBoxContainer
var _buttons: Dictionary = {}
var _recipe_book := RecipeBookScript.new()
var _last_build_mode := false
var _last_selected_type := ""
var _last_floor := -1
var _affordability_timer := 0.0
var _legacy_build_label: CanvasItem
var _feedback_panel: PanelContainer
var _feedback_label: Label
var _feedback_tween: Tween


func _ready() -> void:
	layer = 35
	process_priority = 850
	add_to_group("build_feedback_ui")
	_build_interface()
	call_deferred("_resolve_context")


func _process(delta: float) -> void:
	if _build_system == null or not is_instance_valid(_build_system):
		_resolve_context()
		return

	# The old BuildLabel duplicates the entire menu on the right side. The clickable
	# overlay is now the single source of truth for building selection and hints.
	if _legacy_build_label != null and is_instance_valid(_legacy_build_label):
		_legacy_build_label.visible = false

	var build_mode := bool(_build_system.get("build_mode_enabled"))
	if _panel != null:
		_panel.visible = build_mode
	if not build_mode:
		_last_build_mode = false
		return

	var selected_type := str(_build_system.get("selected_build_type"))
	var floor_index := int(_floor_manager.call("get_current_floor")) if _floor_manager != null and _floor_manager.has_method("get_current_floor") else 0
	if not _last_build_mode or selected_type != _last_selected_type or floor_index != _last_floor:
		_refresh_state(selected_type, floor_index)
	_last_build_mode = true
	_last_selected_type = selected_type
	_last_floor = floor_index

	_affordability_timer -= delta
	if _affordability_timer <= 0.0:
		_affordability_timer = 0.2
		_refresh_affordability()


func _build_interface() -> void:
	var root := Control.new()
	root.name = "BuildMenuRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "BuildMenuPanel"
	_panel.offset_left = 16.0
	_panel.offset_top = 228.0
	_panel.offset_right = 364.0
	_panel.offset_bottom = 844.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	_title_label = Label.new()
	_title_label.text = "BUILDING"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.custom_minimum_size.y = 30.0
	layout.add_child(_title_label)

	_floor_label = Label.new()
	_floor_label.text = "Floor 0"
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_floor_label)

	var floor_controls := HBoxContainer.new()
	floor_controls.add_theme_constant_override("separation", 8)
	layout.add_child(floor_controls)

	var floor_down := Button.new()
	floor_down.text = "Floor -"
	floor_down.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_down.pressed.connect(_change_floor.bind(-1))
	floor_controls.add_child(floor_down)

	var floor_up := Button.new()
	floor_up.text = "Floor +"
	floor_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_up.pressed.connect(_change_floor.bind(1))
	floor_controls.add_child(floor_up)

	layout.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.name = "BuildButtonsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	layout.add_child(scroll)

	_button_list = VBoxContainer.new()
	_button_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_button_list)

	_cost_label = Label.new()
	_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cost_label.custom_minimum_size.y = 52.0
	layout.add_child(_cost_label)

	var hint := Label.new()
	hint.text = "Left click: build\nRight click: retrieve/remove\nR or E: use stairs"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)

	_create_feedback_toast(root)


func _create_feedback_toast(root: Control) -> void:
	_feedback_panel = PanelContainer.new()
	_feedback_panel.name = "BuildFeedbackToast"
	_feedback_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_feedback_panel.offset_left = -280.0
	_feedback_panel.offset_top = 96.0
	_feedback_panel.offset_right = 280.0
	_feedback_panel.offset_bottom = 154.0
	_feedback_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_panel.visible = false
	_feedback_panel.z_index = 500
	_feedback_panel.set_meta("ui_interaction_polished", true)
	root.add_child(_feedback_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.035, 0.025, 0.97)
	style.border_color = Color(0.95, 0.36, 0.18, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 11.0
	style.content_margin_bottom = 11.0
	_feedback_panel.add_theme_stylebox_override("panel", style)

	_feedback_label = Label.new()
	_feedback_label.name = "BuildFeedbackLabel"
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.76, 1.0))
	_feedback_panel.add_child(_feedback_label)


func show_feedback(message: String, is_error := true, duration := 2.4) -> void:
	if _feedback_panel == null or _feedback_label == null or message.strip_edges().is_empty():
		return
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()

	_feedback_label.text = message
	var style := _feedback_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.bg_color = Color(0.11, 0.035, 0.025, 0.97) if is_error else Color(0.035, 0.10, 0.055, 0.97)
		style.border_color = Color(0.95, 0.36, 0.18, 1.0) if is_error else Color(0.42, 0.82, 0.42, 1.0)
	_feedback_panel.modulate = Color.WHITE
	_feedback_panel.visible = true
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(maxf(duration, 0.8))
	_feedback_tween.tween_property(_feedback_panel, "modulate:a", 0.0, 0.35)
	_feedback_tween.tween_callback(_hide_feedback)


func _hide_feedback() -> void:
	if _feedback_panel != null:
		_feedback_panel.visible = false
		_feedback_panel.modulate = Color.WHITE


func _resolve_context() -> void:
	_build_system = get_tree().get_first_node_in_group("build_system")
	_floor_manager = get_node_or_null("/root/MultiFloorBuildManager")
	if _build_system == null:
		return
	_legacy_build_label = _build_system.get("build_label") as CanvasItem
	if _legacy_build_label != null:
		_legacy_build_label.visible = false
	_rebuild_buttons()
	_refresh_state(str(_build_system.get("selected_build_type")), 0)


func _rebuild_buttons() -> void:
	if _button_list == null:
		return
	for child in _button_list.get_children():
		child.queue_free()
	_buttons.clear()
	var entries := _get_building_entries()
	entries.sort_custom(_compare_buildings)
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var building_id := str(entry.get("id", ""))
		if building_id.is_empty() or building_id == "stairs_down":
			continue
		var button := Button.new()
		button.name = "Build_%s" % building_id
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(300.0, 54.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _get_button_text(building_id, entry)
		button.tooltip_text = "Select %s" % str(entry.get("display_name", building_id.capitalize()))
		button.pressed.connect(_select_building.bind(building_id))
		_button_list.add_child(button)
		_buttons[building_id] = button


func _get_building_entries() -> Array:
	var entries: Array = []
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("get_all_buildings"):
		var buildings: Variant = content_db.call("get_all_buildings")
		if buildings is Dictionary:
			for building_id_variant in buildings.keys():
				var data: Variant = buildings[building_id_variant]
				if data is Dictionary:
					var entry: Dictionary = data.duplicate(true)
					entry["id"] = str(building_id_variant)
					entries.append(entry)
	if not entries.is_empty():
		return entries
	for recipe_variant in _recipe_book.get_recipes_by_type("building"):
		if recipe_variant is Dictionary:
			entries.append((recipe_variant as Dictionary).duplicate(true))
	return entries


func _compare_buildings(a: Variant, b: Variant) -> bool:
	var left: Dictionary = a
	var right: Dictionary = b
	var left_key := int(left.get("build_key", 999))
	var right_key := int(right.get("build_key", 999))
	if left_key != right_key:
		return left_key < right_key
	return str(left.get("display_name", left.get("id", ""))) < str(right.get("display_name", right.get("id", "")))


func _get_button_text(building_id: String, entry: Dictionary) -> String:
	var display_name := str(entry.get("display_name", building_id.capitalize()))
	var key_text := _key_text(entry.get("build_key", ""))
	var prefix := "%s  " % key_text if not key_text.is_empty() else ""
	return "%s%s\n     %s" % [prefix, display_name, _get_cost_text(building_id)]


func _key_text(raw_key: Variant) -> String:
	var literal := str(raw_key).strip_edges()
	if literal.length() == 1 and literal in "0123456789":
		return "[%s]" % literal
	var keycode := int(raw_key)
	if keycode == 0:
		return ""
	var key_name := OS.get_keycode_string(keycode)
	return "[%s]" % key_name if not key_name.is_empty() else ""


func _get_cost_text(building_id: String) -> String:
	if building_id == CAMPFIRE_ID and _has_retrieved_campfire():
		return "1 Campfire item (or raw resources)"
	if _build_system == null or not _build_system.has_method("_get_building_cost"):
		return ""
	var costs: Variant = _build_system.call("_get_building_cost", building_id)
	if not costs is Array or costs.is_empty():
		return "Free"
	var parts: PackedStringArray = []
	for cost_variant in costs:
		if cost_variant is Dictionary:
			var cost: Dictionary = cost_variant
			parts.append("%d %s" % [int(cost.get("amount", 0)), str(cost.get("resource", "")).capitalize()])
	return ", ".join(parts)


func _select_building(building_id: String) -> void:
	if _build_system == null:
		return
	_build_system.set("selected_build_type", building_id)
	if _build_system.has_method("_update_preview"):
		_build_system.call("_update_preview")
	if _build_system.has_method("_update_build_label"):
		_build_system.call("_update_build_label")
	_refresh_state(building_id, _last_floor)


func _change_floor(direction: int) -> void:
	if _floor_manager == null or not _floor_manager.has_method("try_change_floor"):
		return
	var current := int(_floor_manager.call("get_current_floor"))
	if not bool(_floor_manager.call("try_change_floor", current + direction)):
		show_feedback("That floor is not available yet. Build stairs to reach it.")


func _refresh_state(selected_type: String, floor_index: int) -> void:
	if _floor_label != null:
		_floor_label.text = "CURRENT FLOOR: %d" % floor_index
	for building_id_variant in _buttons.keys():
		var building_id := str(building_id_variant)
		var button := _buttons[building_id] as Button
		if button != null:
			button.set_pressed_no_signal(building_id == selected_type)
	_refresh_affordability()
	if _cost_label != null:
		_cost_label.text = "Selected: %s\nCost: %s" % [selected_type.capitalize(), _get_cost_text(selected_type)]
		_cost_label.modulate = Color(0.94, 0.88, 0.72, 1.0) if _can_afford(selected_type) else Color(1.0, 0.52, 0.38, 1.0)


func _refresh_affordability() -> void:
	if _build_system == null:
		return
	for building_id_variant in _buttons.keys():
		var building_id := str(building_id_variant)
		var button := _buttons[building_id] as Button
		if button == null:
			continue
		var can_afford := _can_afford(building_id)
		button.disabled = false
		button.modulate = Color.WHITE if can_afford else Color(0.68, 0.65, 0.60, 1.0)
		button.tooltip_text = "%s\n%s" % ["Can build" if can_afford else "Missing resources", _get_cost_text(building_id)]
	if _cost_label != null and _build_system != null:
		var selected := str(_build_system.get("selected_build_type"))
		_cost_label.modulate = Color(0.94, 0.88, 0.72, 1.0) if _can_afford(selected) else Color(1.0, 0.52, 0.38, 1.0)


func _can_afford(building_id: String) -> bool:
	if building_id == CAMPFIRE_ID and _has_retrieved_campfire():
		return true
	return _build_system != null and _build_system.has_method("_can_spend_building_cost") and bool(_build_system.call("_can_spend_building_cost", building_id))


func _has_retrieved_campfire() -> bool:
	if _build_system == null:
		return false
	var main := _build_system.get("main") as Node
	return main != null and main.has_method("can_spend_resource") and bool(main.call("can_spend_resource", CAMPFIRE_ID, 1))
