@tool
extends Control

const OUTPUT_LAYOUT_PATH := "res://data/main_menu_layout.json"
const CANVAS_WIDTH := 1600
const CANVAS_HEIGHT := 900

# Toggle `export_layout_request` in the Inspector to export the current scene layout.
var _export_layout_request := false

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
	var z_counter: Array = [0]

	for child in get_children():
		_collect_node(child, "", false, "", z_counter, elements)

	var layout := {
		"version": 1,
		"canvas": {
			"width": CANVAS_WIDTH,
			"height": CANVAS_HEIGHT,
		},
		"elements": elements,
	}

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("MainMenuLayoutBaker: could not open %s for writing." % output_path)
		return false

	file.store_string(JSON.stringify(layout, "\t") + "\n")
	print("MainMenuLayoutBaker: exported layout to %s" % output_path)
	return true


func _collect_node(node: Node, parent_id: String, in_interaction_zones: bool, current_state: String, z_counter: Array, elements: Dictionary) -> void:
	var next_in_interaction_zones := in_interaction_zones or node.name == "InteractionZones"
	var next_state := _derive_state_for_node(node, parent_id, current_state, next_in_interaction_zones)
	var next_parent_id := parent_id

	if node is Control:
		var control := node as Control
		var element := _build_element_data(control, parent_id, next_state, next_in_interaction_zones, int(z_counter[0]))
		elements[control.name] = element
		z_counter[0] = int(z_counter[0]) + 1
		next_parent_id = str(control.name)

	for child in node.get_children():
		_collect_node(child, next_parent_id, next_in_interaction_zones, next_state, z_counter, elements)


func _build_element_data(control: Control, parent_id: String, state_name: String, in_interaction_zones: bool, z_index: int) -> Dictionary:
	var type_name := _get_element_type(control, in_interaction_zones)
	var rect := Rect2(control.position, control.size)
	var asset_path := ""

	if control is TextureRect:
		var texture := (control as TextureRect).texture
		if texture != null and texture.resource_path != "":
			asset_path = texture.resource_path

	return {
		"element_id": str(control.name),
		"label": str(control.name),
		"state": state_name,
		"type": type_name,
		"parent": parent_id,
		"x": int(roundf(rect.position.x)),
		"y": int(roundf(rect.position.y)),
		"width": max(1, int(roundf(rect.size.x))),
		"height": max(1, int(roundf(rect.size.y))),
		"visible": control.visible,
		"asset_path": asset_path,
		"z_index": z_index,
	}


func _get_element_type(control: Control, in_interaction_zones: bool) -> String:
	if in_interaction_zones:
		return "clickbox"
	if control is TextureRect:
		return "graphic"
	if control is ColorRect:
		return "guide"
	return "group"


func _derive_state_for_node(node: Node, parent_id: String, current_state: String, in_interaction_zones: bool) -> String:
	if node.name == "MainMenuState":
		return "main_menu"
	if node.name == "SaveSelectState":
		return "save_select"
	if node.name == "SharedGraphics":
		return "shared"
	if node.name == "InteractionZones":
		return current_state
	if current_state != "":
		return current_state
	if in_interaction_zones:
		if str(node.name).begins_with("menu."):
			return "main_menu"
		if str(node.name).begins_with("save."):
			return "save_select"
		return "shared"
	if parent_id.begins_with("menu."):
		return "main_menu"
	if parent_id.begins_with("save."):
		return "save_select"
	return "shared"
