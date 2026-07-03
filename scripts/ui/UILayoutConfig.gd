extends RefCounted

const LAYOUT_PATH := "res://data/ui_layout.json"
const DEFAULT_CANVAS_WIDTH := 1600
const DEFAULT_CANVAS_HEIGHT := 900


static func load_layout() -> Dictionary:
	var layout := get_default_layout()
	if not FileAccess.file_exists(LAYOUT_PATH):
		return layout

	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		return layout

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return layout

	return _merge_layout(layout, parsed)


static func save_layout(layout: Dictionary) -> bool:
	var normalized := _merge_layout(get_default_layout(), layout)
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if file == null:
		return false

	var json_text := JSON.stringify(normalized, "\t")
	file.store_string(json_text + "\n")
	return true


static func get_default_layout() -> Dictionary:
	return {
		"version": 1,
		"canvas": {
			"width": DEFAULT_CANVAS_WIDTH,
			"height": DEFAULT_CANVAS_HEIGHT,
		},
		"elements": {
			"inventory.window": {
				"label": "Inventory Window",
				"type": "window",
				"anchor": "center",
				"x": -340,
				"y": -310,
				"width": 680,
				"height": 560,
				"visible": true,
				"locked": false,
			},
			"inventory.drag_handle": {
				"label": "Inventory Drag Handle",
				"type": "interaction",
				"parent": "inventory.window",
				"x": 34,
				"y": 18,
				"width": 612,
				"height": 44,
				"visible": true,
				"locked": false,
			},
			"hotbar.panel": {
				"label": "Hotbar",
				"type": "hud",
				"anchor": "bottom_center",
				"x": -350,
				"y": -120,
				"width": 700,
				"height": 68,
				"visible": true,
				"locked": false,
			},
			"hud.status_panel": {
				"label": "HUD Status Panel",
				"type": "hud",
				"anchor": "top_left",
				"x": 20,
				"y": 20,
				"width": 380,
				"height": 170,
				"visible": true,
				"locked": false,
			},
			"hud.health_bar": {
				"label": "Health Bar",
				"type": "hud_child",
				"parent": "hud.status_panel",
				"x": 18,
				"y": 54,
				"width": 240,
				"height": 22,
				"visible": true,
				"locked": false,
			},
			"hud.xp_bar": {
				"label": "XP Bar",
				"type": "hud_child",
				"parent": "hud.status_panel",
				"x": 18,
				"y": 86,
				"width": 240,
				"height": 18,
				"visible": true,
				"locked": false,
			},
			"hud.alignment_flame": {
				"label": "Alignment Flame",
				"type": "hud_child",
				"parent": "hud.status_panel",
				"x": 300,
				"y": 42,
				"width": 48,
				"height": 64,
				"visible": true,
				"locked": false,
			},
			"hud.minimap": {
				"label": "Minimap Placeholder",
				"type": "hud",
				"anchor": "top_right",
				"x": -260,
				"y": 20,
				"width": 240,
				"height": 180,
				"visible": true,
				"locked": false,
			},
		},
	}


static func get_element(layout: Dictionary, element_id: String) -> Dictionary:
	var elements: Variant = layout.get("elements", {})
	if not elements is Dictionary:
		return {}
	var element_dict: Dictionary = elements
	if not element_dict.has(element_id):
		return {}
	var element_data: Variant = element_dict.get(element_id, {})
	if not element_data is Dictionary:
		return {}
	return element_data.duplicate(true)


static func set_element(layout: Dictionary, element_id: String, element_data: Dictionary) -> void:
	if not layout.has("elements") or not (layout["elements"] is Dictionary):
		layout["elements"] = {}
	var elements: Dictionary = layout["elements"]
	elements[element_id] = element_data.duplicate(true)
	layout["elements"] = elements


static func get_canvas_size(layout: Dictionary) -> Vector2:
	var canvas: Variant = layout.get("canvas", {})
	if not canvas is Dictionary:
		return Vector2(DEFAULT_CANVAS_WIDTH, DEFAULT_CANVAS_HEIGHT)

	var canvas_dict: Dictionary = canvas
	var width := int(canvas_dict.get("width", DEFAULT_CANVAS_WIDTH))
	var height := int(canvas_dict.get("height", DEFAULT_CANVAS_HEIGHT))
	if width <= 0:
		width = DEFAULT_CANVAS_WIDTH
	if height <= 0:
		height = DEFAULT_CANVAS_HEIGHT
	return Vector2(width, height)


static func _merge_layout(base_layout: Dictionary, incoming_layout: Variant) -> Dictionary:
	if not incoming_layout is Dictionary:
		return base_layout.duplicate(true)
	return _merge_dictionary(base_layout, incoming_layout)


static func _merge_dictionary(base_dict: Dictionary, incoming_dict: Dictionary) -> Dictionary:
	var result := base_dict.duplicate(true)
	for key in incoming_dict.keys():
		var incoming_value: Variant = incoming_dict[key]
		if result.has(key) and result[key] is Dictionary and incoming_value is Dictionary:
			result[key] = _merge_dictionary(result[key], incoming_value)
		else:
			result[key] = incoming_value
	return result
