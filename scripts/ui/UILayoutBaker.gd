@tool
extends Control

const OUTPUT_LAYOUT_PATH := "res://data/ui_layout.json"
const CANVAS_WIDTH := 1600
const CANVAS_HEIGHT := 900

var _export_layout_request := false
var _export_z_index := 0

@export_file("*.json") var output_path: String = OUTPUT_LAYOUT_PATH

@export var export_layout_request: bool:
	get:
		return _export_layout_request
	set(value):
		_export_layout_request = value
		if value:
			call_deferred("_run_export_request")


func _run_export_request() -> void:
	export_layout()
	_export_layout_request = false
	notify_property_list_changed()


func export_layout() -> bool:
	var elements: Dictionary = {}
	var controls: Array[Control] = []
	var inventory_slot_clickboxes: Array[Control] = []
	_export_z_index = 0

	for child in get_children():
		_collect_controls(child, controls)

	for control in controls:
		if not _should_export_control(control):
			continue
		if _is_inventory_slot_clickbox_candidate(control):
			inventory_slot_clickboxes.append(control)
			continue
		_export_control(control, elements)

	inventory_slot_clickboxes.sort_custom(_sort_controls_by_grid_position)
	for index in range(inventory_slot_clickboxes.size()):
		var slot_control: Control = inventory_slot_clickboxes[index]
		var slot_id := "inventory.slot_%02d_clickbox" % (index + 1)
		_export_control(slot_control, elements, slot_id, "inventory.window")

	var layout := {
		"version": 2,
		"coordinate_space": "global",
		"canvas": {
			"width": CANVAS_WIDTH,
			"height": CANVAS_HEIGHT,
		},
		"elements": elements,
	}

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("UILayoutBaker: could not open %s for writing." % output_path)
		return false

	file.store_string(JSON.stringify(layout, "\t") + "\n")
	print("UILayoutBaker: exported %d elements to %s" % [elements.size(), output_path])
	return true


func _collect_controls(node: Node, controls: Array[Control]) -> void:
	if node is Control and node != self:
		controls.append(node as Control)

	for child in node.get_children():
		_collect_controls(child, controls)


func _should_export_control(control: Control) -> bool:
	return not control.name.is_empty()


func _export_control(control: Control, elements: Dictionary, forced_id := "", forced_parent := "") -> void:
	var element_id := forced_id if not forced_id.is_empty() else _get_normalized_element_id(control)
	if element_id.is_empty():
		return

	var parent_id := forced_parent
	if parent_id.is_empty():
		parent_id = _get_normalized_parent_id(control)

	elements[element_id] = _build_element_data(control, element_id, parent_id)
	_export_z_index += 1


func _build_element_data(control: Control, element_id: String, parent_id: String) -> Dictionary:
	var type_name := _get_element_type(control)
	var rect := _get_root_relative_rect(control)
	var asset_path := ""
	var show_asset := false
	var show_rect := true
	var opacity := 0.12
	var fit_mode := "stretch"
	var locked := false

	if control is TextureRect:
		var texture := (control as TextureRect).texture
		if texture != null and texture.resource_path != "":
			asset_path = texture.resource_path
		show_asset = true
		show_rect = false
		opacity = 1.0
		fit_mode = _get_fit_mode_name(control as TextureRect)
	elif type_name == "clickbox":
		show_asset = false
		show_rect = true
		opacity = 0.22
	elif type_name == "guide":
		show_asset = false
		show_rect = true
		opacity = 0.08
	elif type_name == "group":
		show_asset = false
		show_rect = false
		opacity = 0.0
		locked = true

	return {
		"element_id": element_id,
		"label": element_id,
		"type": type_name,
		"parent": parent_id,
		"coordinate_space": "global",
		"anchor": "top_left",
		"x": int(roundf(rect.position.x)),
		"y": int(roundf(rect.position.y)),
		"width": max(1, int(roundf(rect.size.x))),
		"height": max(1, int(roundf(rect.size.y))),
		"visible": control.visible,
		"locked": locked,
		"asset_path": asset_path,
		"show_asset": show_asset,
		"show_rect": show_rect,
		"opacity": opacity,
		"z_index": _export_z_index,
		"fit_mode": fit_mode,
		"source_group": _get_source_group(control),
	}


func _get_root_relative_rect(control: Control) -> Rect2:
	var root_rect := get_global_rect()
	var rect := control.get_global_rect()
	return Rect2(rect.position - root_rect.position, rect.size)


func _get_element_type(control: Control) -> String:
	if _is_inside_group(control, "InteractionZones"):
		return "clickbox"
	if control is TextureRect:
		return "graphic"
	if control is ColorRect:
		return "guide"
	return "guide"


func _get_normalized_element_id(control: Control) -> String:
	var raw_name := str(control.name)
	var raw_upper := raw_name.to_upper()

	match raw_name:
		"Inventory_Hover":
			return "inventory.hover_frame"
		"Inventory_Select":
			return "inventory.select_frame"
		"inventory_drag_handle":
			return "inventory.drag_handle"
		"inventory_close_hitbox":
			return "inventory.close_hitbox"
		"inventory_split_button_clickbox":
			return "inventory.split_button_clickbox"
		"inventory_use_button_clickbox":
			return "inventory.use_button_clickbox"
		"inventory_drop_button_clickbox":
			return "inventory.drop_button_clickbox"
		"EXP_BAR":
			return "hud.xp_bar_fill"
		"EXP_BORDER":
			return "hud.xp_bar_frame"
		"BAR_LIFE":
			return "hud.life_bar"
		"LIFE_BAR":
			return "hud.life_bar"
		"BAR_MANA":
			return "hud.mana_bar"
		"MANA_BAR":
			return "hud.mana_bar"
		"BAR_STAMINA":
			return "hud.stamina_bar"
		"STAMINA_BAR":
			return "hud.stamina_bar"
		"ALIG_FLAME":
			return "hud.alignment_flame_frame"
		"FLAME_FRAME":
			return "hud.alignment_flame_frame"
		"PURPLE_FLAME PLACEHOLDER":
			return "hud.alignment_flame"
		"PORTRAIT":
			return "hud.portrait"

	if raw_name.begins_with("hotbar_"):
		var suffix := raw_name.substr("hotbar_".length())
		var slot_number := 10 if suffix == "0" else int(suffix)
		if slot_number >= 1 and slot_number <= 10:
			return "hotbar.slot_%02d" % slot_number

	match raw_upper:
		"XP_BAR_FILL":
			return "hud.xp_bar_fill"
		"XP_BAR_FRAME":
			return "hud.xp_bar_frame"
		"ALIGNMENT_FLAME_FRAME":
			return "hud.alignment_flame_frame"
		"ALIGNMENT_FLAME":
			return "hud.alignment_flame"
		"HELM":
			return "equipment.helm"
		"ARMOR":
			return "equipment.armor"
		"LEGS":
			return "equipment.legs"
		"BOOTS":
			return "equipment.boots"
		"NECK":
			return "equipment.neck"
		"HAND_LEFT":
			return "equipment.hand_left"
		"HAND_RIGHT":
			return "equipment.hand_right"
		"RING1":
			return "equipment.ring_left"
		"RING2":
			return "equipment.ring_right"
		"BACK":
			return "equipment.back"

	return raw_name


func _get_normalized_parent_id(control: Control) -> String:
	var parent := control.get_parent()
	if parent == null or parent == self:
		return ""
	if parent is Control:
		var parent_control := parent as Control
		var parent_id := _get_normalized_element_id(parent_control)
		if not parent_id.is_empty():
			return parent_id
	return ""


func _get_source_group(control: Control) -> String:
	var current := control.get_parent()
	while current != null and current != self:
		if current.get_parent() == self:
			return str(current.name)
		current = current.get_parent()
	return ""


func _is_inside_group(control: Control, group_name: String) -> bool:
	var current: Node = control
	while current != null and current != self:
		if current.name == group_name:
			return true
		current = current.get_parent()
	return false


func _is_inventory_slot_clickbox_candidate(control: Control) -> bool:
	if not _is_inside_group(control, "InteractionZones"):
		return false

	var element_id := _get_normalized_element_id(control)
	if element_id.begins_with("equipment.") or (element_id.begins_with("inventory.") and element_id != str(control.name)):
		return false

	var raw_name := str(control.name)
	var raw_lower := raw_name.to_lower()
	if not (raw_lower.begins_with("i") or raw_lower.begins_with("colorrect")):
		return false

	var rect := _get_root_relative_rect(control)
	return rect.position.x >= 520.0 and rect.position.x <= 1080.0 and rect.position.y >= 230.0 and rect.position.y <= 730.0


func _sort_controls_by_grid_position(a: Control, b: Control) -> bool:
	var rect_a := _get_root_relative_rect(a)
	var rect_b := _get_root_relative_rect(b)
	if absf(rect_a.position.y - rect_b.position.y) > 8.0:
		return rect_a.position.y < rect_b.position.y
	return rect_a.position.x < rect_b.position.x


func _get_fit_mode_name(texture_rect: TextureRect) -> String:
	match texture_rect.stretch_mode:
		TextureRect.STRETCH_KEEP:
			return "keep_aspect"
		TextureRect.STRETCH_KEEP_CENTERED:
			return "keep_aspect_centered"
		TextureRect.STRETCH_TILE:
			return "tile"
		_:
			return "stretch"
