extends ColorRect

signal trash_dropped(slot_index: int, inventory_id: String)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var data_dict: Dictionary = data
	var drop_type := str(data_dict.get("type", ""))
	return drop_type == "inventory_slot"


func _drop_data(_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var data_dict: Dictionary = data
	var slot_index := int(data_dict.get("slot_index", -1))
	var inventory_id := str(data_dict.get("inventory_id", ""))
	trash_dropped.emit(slot_index, inventory_id)
