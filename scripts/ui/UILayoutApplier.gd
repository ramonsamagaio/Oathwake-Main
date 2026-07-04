extends RefCounted

const UILayoutConfig = preload("res://scripts/ui/UILayoutConfig.gd")


static func apply_element_to_control(control: Control, layout: Dictionary, element_id: String) -> void:
	if control == null:
		return

	var element := UILayoutConfig.get_element(layout, element_id)
	if element.is_empty():
		return

	_apply_visibility(control, element)
	_apply_anchor(control, str(element.get("anchor", "top_left")))
	_apply_offsets(control, element)
	control.z_index = int(element.get("z_index", 0))


static func apply_element_to_local_control(control: Control, layout: Dictionary, element_id: String) -> void:
	if control == null:
		return

	var element := UILayoutConfig.get_element(layout, element_id)
	if element.is_empty():
		return

	_apply_visibility(control, element)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_apply_offsets(control, element)
	control.z_index = int(element.get("z_index", 0))


static func get_element_rect(layout: Dictionary, element_id: String) -> Rect2:
	var elements_variant: Variant = layout.get("elements", {})
	if not elements_variant is Dictionary:
		return Rect2()
	var elements: Dictionary = elements_variant
	if not elements.has(element_id) or not (elements[element_id] is Dictionary):
		return Rect2()
	var element: Dictionary = (elements[element_id] as Dictionary).duplicate(true)

	var width := float(element.get("width", 0.0))
	var height := float(element.get("height", 0.0))
	var local_position := Vector2(float(element.get("x", 0.0)), float(element.get("y", 0.0)))
	var parent_id := str(element.get("parent", ""))
	if not parent_id.is_empty():
		var parent_rect := get_element_rect(layout, parent_id)
		return Rect2(parent_rect.position + local_position, Vector2(width, height))

	var canvas_size := UILayoutConfig.get_canvas_size(layout)
	var anchor_position := _get_anchor_position(str(element.get("anchor", "top_left")), canvas_size)
	return Rect2(anchor_position + local_position, Vector2(width, height))


static func get_anchor_preset(anchor_name: String) -> int:
	match anchor_name:
		"top_left":
			return Control.PRESET_TOP_LEFT
		"top_right":
			return Control.PRESET_TOP_RIGHT
		"bottom_left":
			return Control.PRESET_BOTTOM_LEFT
		"bottom_right":
			return Control.PRESET_BOTTOM_RIGHT
		"bottom_center":
			return Control.PRESET_CENTER_BOTTOM
		"top_center":
			return Control.PRESET_CENTER_TOP
		"center":
			return Control.PRESET_CENTER
		_:
			return Control.PRESET_TOP_LEFT


static func _apply_visibility(control: Control, element: Dictionary) -> void:
	control.visible = bool(element.get("visible", true))


static func _apply_anchor(control: Control, anchor_name: String) -> void:
	match anchor_name:
		"top_left", "top_right", "bottom_left", "bottom_right", "bottom_center", "top_center":
			control.set_anchors_preset(get_anchor_preset(anchor_name))
		"center":
			control.anchor_left = 0.5
			control.anchor_top = 0.5
			control.anchor_right = 0.5
			control.anchor_bottom = 0.5
		_:
			control.set_anchors_preset(Control.PRESET_TOP_LEFT)


static func _apply_offsets(control: Control, element: Dictionary) -> void:
	var x := float(element.get("x", 0.0))
	var y := float(element.get("y", 0.0))
	var width := float(element.get("width", 0.0))
	var height := float(element.get("height", 0.0))
	control.offset_left = x
	control.offset_top = y
	control.offset_right = x + width
	control.offset_bottom = y + height


static func _get_anchor_position(anchor_name: String, canvas_size: Vector2) -> Vector2:
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
