extends Button

var hotbar_ui: Node = null
var slot_index: int = -1


func setup(new_hotbar_ui: Node, new_slot_index: int) -> void:
	hotbar_ui = new_hotbar_ui
	slot_index = new_slot_index


func _get_drag_data(_at_position: Vector2) -> Variant:
	if hotbar_ui == null or not hotbar_ui.has_method("_get_hotbar_drag_data"):
		return null

	var drag_data: Variant = hotbar_ui.call("_get_hotbar_drag_data", slot_index)
	if not drag_data is Dictionary:
		return null

	var preview: Variant = hotbar_ui.call("_make_hotbar_drag_preview", slot_index)
	if preview is Control:
		set_drag_preview(preview)

	return drag_data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if hotbar_ui == null or not hotbar_ui.has_method("_can_drop_on_hotbar_slot"):
		print_debug("HotbarSlot drop rejected: missing hotbar_ui/helper slot=%d data=%s" % [slot_index, str(data)])
		return false
	var can_drop: bool = bool(hotbar_ui.call("_can_drop_on_hotbar_slot", slot_index, data))
	if not can_drop:
		var reason := "unknown"
		if hotbar_ui.has_method("_get_hotbar_drop_reject_reason"):
			reason = str(hotbar_ui.call("_get_hotbar_drop_reject_reason", slot_index, data))
		print_debug("HotbarSlot drop rejected: slot=%d reason=%s data=%s" % [slot_index, reason, str(data)])
	return can_drop


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if hotbar_ui == null or not hotbar_ui.has_method("_drop_on_hotbar_slot"):
		return
	hotbar_ui.call("_drop_on_hotbar_slot", slot_index, data)
