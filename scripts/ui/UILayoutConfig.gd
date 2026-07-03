extends RefCounted

const LAYOUT_PATH := "res://data/ui_layout.json"
const DEFAULT_CANVAS_WIDTH := 1600
const DEFAULT_CANVAS_HEIGHT := 900

const DEFAULT_ELEMENT_IDS := [
	"inventory.window",
	"inventory.drag_handle",
	"inventory.sort_button",
	"inventory.split_button",
	"inventory.drop_button",
	"inventory.grid_area",
	"inventory.trash_area",
	"inventory.tooltip_area",
	"inventory.equipment_panel",
	"inventory.weapon_slot",
	"inventory.tool_slot",
	"inventory.armor_slot",
	"inventory.accessory_slot",
	"inventory.close_hitbox",
	"hotbar.panel",
	"hotbar.slot_1",
	"hotbar.slot_2",
	"hotbar.slot_3",
	"hotbar.slot_4",
	"hotbar.slot_5",
	"hotbar.slot_6",
	"hotbar.slot_7",
	"hotbar.slot_8",
	"hotbar.slot_9",
	"hotbar.slot_10",
	"hotbar.slot_1_hitbox",
	"hotbar.slot_2_hitbox",
	"hotbar.slot_3_hitbox",
	"hotbar.slot_4_hitbox",
	"hotbar.slot_5_hitbox",
	"hotbar.slot_6_hitbox",
	"hotbar.slot_7_hitbox",
	"hotbar.slot_8_hitbox",
	"hotbar.slot_9_hitbox",
	"hotbar.slot_10_hitbox",
	"hud.status_panel",
	"hud.health_bar",
	"hud.xp_bar",
	"hud.alignment_flame",
	"hud.minimap",
]


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

	return normalize_layout(_merge_dictionary(layout, parsed))


static func save_layout(layout: Dictionary) -> bool:
	var normalized := normalize_layout(layout)
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(normalized, "\t") + "\n")
	return true


static func normalize_layout(layout: Dictionary) -> Dictionary:
	var normalized := get_default_layout()
	normalized = _merge_dictionary(normalized, layout)

	var elements_variant: Variant = normalized.get("elements", {})
	if not elements_variant is Dictionary:
		return normalized

	var elements: Dictionary = elements_variant
	var default_layout := get_default_layout()
	var default_elements: Dictionary = default_layout.get("elements", {})
	for element_id in elements.keys():
		var element_value: Variant = elements[element_id]
		if not element_value is Dictionary:
			elements[element_id] = _make_element_defaults("hud")
			continue

		var element_data: Dictionary = element_value
		if element_data.has("asset_path"):
			element_data["asset_path"] = normalize_asset_path(str(element_data.get("asset_path", "")))
		var type_name := str(element_data.get("type", "hud"))
		var base := _make_element_defaults(type_name)
		if default_elements.has(element_id) and default_elements[element_id] is Dictionary:
			base = _merge_dictionary(base, default_elements[element_id])
		elements[element_id] = _merge_dictionary(base, element_data)

	normalized["elements"] = elements
	return normalized


static func get_default_layout() -> Dictionary:
	return {
		"version": 1,
		"canvas": {
			"width": DEFAULT_CANVAS_WIDTH,
			"height": DEFAULT_CANVAS_HEIGHT,
		},
		"elements": {
			"inventory.window": _make_element("Inventory Window", "window", -340, -310, 680, 560, "center", "", "res://assets/ui/inventory/inventory_window.png", true, true, 1.0, 0, "stretch", true, false),
			"inventory.drag_handle": _make_element("Inventory Drag Handle", "interaction", 34, 18, 612, 44, "top_left", "inventory.window", "", false, true, 0.35, 12, "stretch", true, false),
			"inventory.sort_button": _make_element("Sort", "graphic", 34, 64, 132, 42, "top_left", "inventory.window", "res://assets/ui/buttons/button_medium_normal.png", true, true, 1.0, 8, "stretch", true, false),
			"inventory.split_button": _make_element("Split", "graphic", 174, 64, 132, 42, "top_left", "inventory.window", "res://assets/ui/buttons/button_medium_normal.png", true, true, 1.0, 8, "stretch", true, false),
			"inventory.drop_button": _make_element("Drop", "graphic", 314, 64, 132, 42, "top_left", "inventory.window", "res://assets/ui/buttons/button_medium_normal.png", true, true, 1.0, 8, "stretch", true, false),
			"inventory.grid_area": _make_element("Inventory Grid Area", "graphic", 34, 120, 430, 320, "top_left", "inventory.window", "res://assets/ui/inventory/item_slot_normal.png", true, true, 1.0, 3, "stretch", true, false),
			"inventory.trash_area": _make_element("Trash Area", "graphic", 34, 458, 92, 92, "top_left", "inventory.window", "res://assets/ui/inventory/tooltip_bg.png", true, true, 0.9, 3, "stretch", true, false),
			"inventory.tooltip_area": _make_element("Tooltip Area", "graphic", 138, 458, 276, 92, "top_left", "inventory.window", "res://assets/ui/inventory/tooltip_bg.png", true, true, 0.95, 3, "stretch", true, false),
			"inventory.equipment_panel": _make_element("Equipment Panel", "graphic", 480, 64, 166, 410, "top_left", "inventory.window", "res://assets/ui/inventory/tooltip_bg.png", true, true, 0.9, 3, "stretch", true, false),
			"inventory.weapon_slot": _make_element("Weapon Slot", "interaction", 20, 44, 138, 52, "top_left", "inventory.equipment_panel", "res://assets/ui/inventory/item_slot_normal.png", true, true, 0.42, 13, "stretch", true, false),
			"inventory.tool_slot": _make_element("Tool Slot", "interaction", 20, 102, 138, 52, "top_left", "inventory.equipment_panel", "res://assets/ui/inventory/item_slot_normal.png", true, true, 0.42, 13, "stretch", true, false),
			"inventory.armor_slot": _make_element("Armor Slot", "interaction", 20, 160, 138, 52, "top_left", "inventory.equipment_panel", "res://assets/ui/inventory/item_slot_normal.png", true, true, 0.42, 13, "stretch", true, false),
			"inventory.accessory_slot": _make_element("Accessory Slot", "interaction", 20, 218, 138, 52, "top_left", "inventory.equipment_panel", "res://assets/ui/inventory/item_slot_normal.png", true, true, 0.42, 13, "stretch", true, false),
			"inventory.close_hitbox": _make_element("Close Hitbox", "interaction", 620, 20, 28, 28, "top_left", "inventory.window", "", false, true, 0.35, 20, "stretch", true, false),
			"hotbar.panel": _make_element("Hotbar", "hud", -350, -120, 700, 68, "bottom_center", "", "res://assets/ui/hud/hotbar_frame.png", true, true, 1.0, 0, "stretch", true, false),
			"hotbar.slot_1": _make_element("Hotbar Slot 1", "graphic", 14, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_2": _make_element("Hotbar Slot 2", "graphic", 80, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_3": _make_element("Hotbar Slot 3", "graphic", 146, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_4": _make_element("Hotbar Slot 4", "graphic", 212, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_5": _make_element("Hotbar Slot 5", "graphic", 278, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_6": _make_element("Hotbar Slot 6", "graphic", 344, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_7": _make_element("Hotbar Slot 7", "graphic", 410, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_8": _make_element("Hotbar Slot 8", "graphic", 476, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_9": _make_element("Hotbar Slot 9", "graphic", 542, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_10": _make_element("Hotbar Slot 10", "graphic", 608, 8, 58, 52, "top_left", "hotbar.panel", "res://assets/ui/hud/hotbar_slot_empty.png", true, true, 1.0, 5, "stretch", true, false),
			"hotbar.slot_1_hitbox": _make_element("Hotbar Slot 1 Hitbox", "interaction", 14, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_2_hitbox": _make_element("Hotbar Slot 2 Hitbox", "interaction", 80, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_3_hitbox": _make_element("Hotbar Slot 3 Hitbox", "interaction", 146, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_4_hitbox": _make_element("Hotbar Slot 4 Hitbox", "interaction", 212, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_5_hitbox": _make_element("Hotbar Slot 5 Hitbox", "interaction", 278, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_6_hitbox": _make_element("Hotbar Slot 6 Hitbox", "interaction", 344, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_7_hitbox": _make_element("Hotbar Slot 7 Hitbox", "interaction", 410, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_8_hitbox": _make_element("Hotbar Slot 8 Hitbox", "interaction", 476, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_9_hitbox": _make_element("Hotbar Slot 9 Hitbox", "interaction", 542, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hotbar.slot_10_hitbox": _make_element("Hotbar Slot 10 Hitbox", "interaction", 608, 8, 58, 52, "top_left", "hotbar.panel", "", false, true, 0.35, 15, "stretch", true, false),
			"hud.status_panel": _make_element("HUD Status Panel", "hud", 20, 20, 380, 170, "top_left", "", "res://assets/ui/inventory/tooltip_bg.png", true, true, 0.95, 0, "stretch", true, false),
			"hud.health_bar": _make_element("Health Bar", "hud_child", 18, 54, 240, 22, "top_left", "hud.status_panel", "res://assets/ui/hud/health_bar_frame.png", true, true, 1.0, 2, "stretch", true, false),
			"hud.xp_bar": _make_element("XP Bar", "hud_child", 18, 86, 240, 18, "top_left", "hud.status_panel", "res://assets/ui/hud/xp_bar_frame.png", true, true, 1.0, 2, "stretch", true, false),
			"hud.alignment_flame": _make_element("Alignment Flame", "hud_child", 300, 42, 48, 64, "top_left", "hud.status_panel", "", false, true, 1.0, 2, "stretch", true, false),
			"hud.minimap": _make_element("Minimap Placeholder", "hud", -260, 20, 240, 180, "top_right", "", "", false, true, 0.9, 0, "stretch", true, false),
		},
	}


static func get_default_element_ids() -> Array[String]:
	var result: Array[String] = []
	for element_id in DEFAULT_ELEMENT_IDS:
		result.append(str(element_id))
	return result


static func get_element(layout: Dictionary, element_id: String) -> Dictionary:
	var result := _make_element_defaults("hud")
	var default_layout := get_default_layout()
	var default_elements: Dictionary = default_layout.get("elements", {})
	if default_elements.has(element_id) and default_elements[element_id] is Dictionary:
		result = _merge_dictionary(result, default_elements[element_id])

	var elements_variant: Variant = layout.get("elements", {})
	if elements_variant is Dictionary:
		var elements: Dictionary = elements_variant
		if elements.has(element_id) and elements[element_id] is Dictionary:
			result = _merge_dictionary(result, elements[element_id])

	return result.duplicate(true)


static func set_element(layout: Dictionary, element_id: String, element_data: Dictionary) -> void:
	if not layout.has("elements") or not (layout["elements"] is Dictionary):
		layout["elements"] = {}
	var elements: Dictionary = layout["elements"]
	var existing := get_element(layout, element_id)
	var merged := _merge_dictionary(existing, element_data)
	if merged.has("asset_path"):
		merged["asset_path"] = normalize_asset_path(str(merged.get("asset_path", "")))
	elements[element_id] = merged
	layout["elements"] = elements


static func remove_element(layout: Dictionary, element_id: String) -> void:
	if not layout.has("elements") or not (layout["elements"] is Dictionary):
		return
	var elements: Dictionary = layout["elements"]
	elements.erase(element_id)
	layout["elements"] = elements


static func duplicate_element(layout: Dictionary, source_id: String, target_id: String) -> bool:
	var source := get_element(layout, source_id)
	if source.is_empty():
		return false
	set_element(layout, target_id, source)
	return true


static func get_element_ids(layout: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var elements_variant: Variant = layout.get("elements", {})
	if elements_variant is Dictionary:
		for key in (elements_variant as Dictionary).keys():
			ids.append(str(key))
	return ids


static func get_next_custom_graphic_id(layout: Dictionary) -> String:
	var existing := {}
	var elements_variant: Variant = layout.get("elements", {})
	if elements_variant is Dictionary:
		for key in (elements_variant as Dictionary).keys():
			existing[str(key)] = true

	var index := 1
	while true:
		var candidate := "custom.graphic_%03d" % index
		if not existing.has(candidate):
			return candidate
		index += 1
	return "custom.graphic_001"


static func get_canvas_size(layout: Dictionary) -> Vector2:
	var canvas_variant: Variant = layout.get("canvas", {})
	if not canvas_variant is Dictionary:
		return Vector2(DEFAULT_CANVAS_WIDTH, DEFAULT_CANVAS_HEIGHT)

	var canvas: Dictionary = canvas_variant
	var width := int(canvas.get("width", DEFAULT_CANVAS_WIDTH))
	var height := int(canvas.get("height", DEFAULT_CANVAS_HEIGHT))
	if width <= 0:
		width = DEFAULT_CANVAS_WIDTH
	if height <= 0:
		height = DEFAULT_CANVAS_HEIGHT
	return Vector2(width, height)


static func normalize_asset_path(asset_path: String) -> String:
	var normalized := asset_path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return ""
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return normalized
	if normalized.begins_with("/"):
		normalized = normalized.substr(1, normalized.length() - 1)
	return "res://%s" % normalized


static func _make_element_defaults(type_name: String) -> Dictionary:
	var normalized_type := type_name if not str(type_name).is_empty() else "hud"
	var show_asset := false
	var show_rect := true
	var opacity := 1.0
	match normalized_type:
		"interaction":
			show_asset = false
			show_rect = true
			opacity = 0.35
		"graphic":
			show_asset = true
			show_rect = true
		"window":
			show_asset = true
			show_rect = true
		"hud":
			show_asset = true
			show_rect = true
		"hud_child":
			show_asset = true
			show_rect = true
		_:
			show_asset = true
			show_rect = true

	return {
		"label": "",
		"type": normalized_type,
		"parent": "",
		"anchor": "top_left",
		"x": 0,
		"y": 0,
		"width": 100,
		"height": 100,
		"visible": true,
		"locked": false,
		"asset_path": "",
		"show_asset": show_asset,
		"show_rect": show_rect,
		"opacity": opacity,
		"z_index": 0,
		"fit_mode": "stretch",
	}


static func _make_element(
	label: String,
	type_name: String,
	x: int,
	y: int,
	width: int,
	height: int,
	anchor: String = "top_left",
	parent: String = "",
	asset_path: String = "",
	show_asset: bool = false,
	show_rect: bool = true,
	opacity: float = 1.0,
	z_index: int = 0,
	fit_mode: String = "stretch",
	visible: bool = true,
	locked: bool = false
) -> Dictionary:
	return {
		"label": label,
		"type": type_name,
		"parent": parent,
		"anchor": anchor,
		"x": x,
		"y": y,
		"width": width,
		"height": height,
	"visible": visible,
	"locked": locked,
	"asset_path": normalize_asset_path(asset_path),
	"show_asset": show_asset,
	"show_rect": show_rect,
	"opacity": opacity,
	"z_index": z_index,
	"fit_mode": fit_mode,
	}


static func _merge_dictionary(base_dict: Dictionary, incoming_dict: Dictionary) -> Dictionary:
	var result := base_dict.duplicate(true)
	for key in incoming_dict.keys():
		var incoming_value: Variant = incoming_dict[key]
		if result.has(key) and result[key] is Dictionary and incoming_value is Dictionary:
			result[key] = _merge_dictionary(result[key], incoming_value)
		else:
			result[key] = incoming_value
	return result
