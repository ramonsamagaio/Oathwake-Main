@tool
extends Control

const OUTPUT_LAYOUT_PATH := "res://data/ui_layout.json"
const CANVAS_WIDTH := 1600
const CANVAS_HEIGHT := 900

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
	for child in get_children():
		_collect_node(child, "", false, elements)

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
		push_error("UILayoutBaker: could not open %s for writing." % output_path)
		return false

	file.store_string(JSON.stringify(layout, "\t") + "\n")
	print("UILayoutBaker: exported layout to %s" % output_path)
	return true


func _collect_node(node: Node, parent_id: String, in_interaction_zones: bool, elements: Dictionary) -> void:
	var next_in_interaction_zones := in_interaction_zones or node.name == "InteractionZones"
	var next_parent_id := parent_id

	if node is Control:
		var control := node as Control
		var element := _build_element_data(control, parent_id, next_in_interaction_zones)
		elements[control.name] = element
		next_parent_id = str(control.name)

	for child in node.get_children():
		_collect_node(child, next_parent_id, next_in_interaction_zones, elements)


func _build_element_data(control: Control, parent_id: String, in_interaction_zones: bool) -> Dictionary:
	var type_name := _get_element_type(control, parent_id, in_interaction_zones)
	var rect := Rect2(control.position, control.size)
	var asset_path := ""
	var show_asset := false
	var show_rect := true
	var opacity := 0.12
	var z_index := control.z_index
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
	elif type_name == "interaction":
		show_asset = false
		show_rect = true
		opacity = 0.24
	elif type_name == "group":
		show_asset = false
		show_rect = true
		opacity = 0.08
		locked = true
	elif type_name == "guide":
		show_asset = false
		show_rect = true
		opacity = 0.12

	return {
		"label": str(control.name),
		"type": type_name,
		"parent": parent_id,
		"anchor": _get_anchor_name(control),
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
		"z_index": z_index,
		"fit_mode": fit_mode,
	}


func _get_element_type(control: Control, parent_id: String, in_interaction_zones: bool) -> String:
	if control is TextureRect:
		return "graphic"
	if in_interaction_zones:
		return "interaction"
	if control is ColorRect:
		return "guide"
	if control.name.ends_with("_hitbox"):
		return "interaction"
	return "guide"


func _get_anchor_name(control: Control) -> String:
	if _anchor_matches(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, 0.0, 0.0, 0.0, 0.0):
		return "top_left"
	if _anchor_matches(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, 0.5, 0.0, 0.5, 0.0):
		return "top_center"
	if _anchor_matches(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, 1.0, 0.0, 1.0, 0.0):
		return "top_right"
	if _anchor_matches(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, 0.5, 0.5, 0.5, 0.5):
		return "center"
	if _anchor_matches(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, 0.5, 1.0, 0.5, 1.0):
		return "bottom_center"
	if _anchor_matches(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, 0.0, 1.0, 0.0, 1.0):
		return "bottom_left"
	if _anchor_matches(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom, 1.0, 1.0, 1.0, 1.0):
		return "bottom_right"
	return "top_left"


func _anchor_matches(left: float, top: float, right: float, bottom: float, expected_left: float, expected_top: float, expected_right: float, expected_bottom: float) -> bool:
	return is_equal_approx(left, expected_left) and is_equal_approx(top, expected_top) and is_equal_approx(right, expected_right) and is_equal_approx(bottom, expected_bottom)


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
