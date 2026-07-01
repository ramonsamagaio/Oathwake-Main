extends RefCounted

signal changed

const EQUIPMENT_SLOT_IDS := ["weapon", "tool", "armor", "accessory"]

var equipment_slots := {}


func _init() -> void:
	_ensure_default_equipment()


func _ensure_default_equipment() -> void:
	for slot_id in EQUIPMENT_SLOT_IDS:
		if not equipment_slots.has(slot_id):
			equipment_slots[slot_id] = _empty_slot()


func _empty_slot() -> Dictionary:
	return {
		"item_id": "",
		"amount": 0,
		"metadata": {},
	}


func get_equipment_slots() -> Dictionary:
	return equipment_slots.duplicate(true)


func get_equipped_slot(slot_id: String) -> Dictionary:
	if equipment_slots.has(slot_id):
		return equipment_slots[slot_id].duplicate(true)
	return _empty_slot()


func set_equipped_slot(slot_id: String, slot_data: Dictionary) -> void:
	if not equipment_slots.has(slot_id):
		return
	equipment_slots[slot_id] = {
		"item_id": str(slot_data.get("item_id", "")),
		"amount": int(slot_data.get("amount", 0)),
		"metadata": slot_data.get("metadata", {}) if slot_data.get("metadata") is Dictionary else {},
	}


func clear_equipped_slot(slot_id: String) -> void:
	if equipment_slots.has(slot_id):
		equipment_slots[slot_id] = _empty_slot()


func can_equip_item(item_id: String, slot_id: String) -> bool:
	if not equipment_slots.has(slot_id):
		return false
	var valid_slot := get_valid_slot_for_item(item_id)
	return valid_slot == slot_id


func get_valid_slot_for_item(item_id: String) -> String:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return ""

	var item_data: Dictionary = content_db.get_item(item_id)

	var explicit_slot := str(item_data.get("equipment_slot", ""))
	if not explicit_slot.is_empty():
		return explicit_slot

	var item_type := str(item_data.get("item_type", ""))
	match item_type:
		"weapon":
			return "weapon"
		"tool":
			return "tool"
		"armor":
			return "armor"
		"accessory":
			return "accessory"

	return ""


func equip_from_inventory(inventory, inventory_slot_index: int, target_slot_id := "") -> bool:
	if inventory == null:
		return false

	var slot_data: Dictionary = inventory.get_slot(inventory_slot_index)
	var item_id := str(slot_data.get("item_id", ""))
	var amount := int(slot_data.get("amount", 0))

	if item_id.is_empty() or amount <= 0:
		return false
	if amount != 1:
		return false

	var slot_id := target_slot_id
	if slot_id.is_empty():
		slot_id = get_valid_slot_for_item(item_id)
	if slot_id.is_empty() or not equipment_slots.has(slot_id):
		return false

	var current_equipped = equipment_slots[slot_id]
	var current_item_id := str(current_equipped.get("item_id", ""))
	var current_amount := int(current_equipped.get("amount", 0))

	if current_item_id.is_empty() or current_amount <= 0:
		var metadata = slot_data.get("metadata", {})
		equipment_slots[slot_id] = {
			"item_id": item_id,
			"amount": 1,
			"metadata": metadata.duplicate(true) if metadata is Dictionary else {},
		}
		inventory.clear_slot(inventory_slot_index)
		changed.emit()
		return true
	else:
		if not can_equip_item(current_item_id, slot_id):
			return false

		var current_metadata = current_equipped.get("metadata", {})
		var incoming_metadata = slot_data.get("metadata", {})

		inventory.clear_slot(inventory_slot_index)
		equipment_slots[slot_id] = {
			"item_id": item_id,
			"amount": 1,
			"metadata": incoming_metadata.duplicate(true) if incoming_metadata is Dictionary else {},
		}
		inventory.set_slot(inventory_slot_index, current_item_id, current_amount)
		if inventory.has_method("set_slot_metadata") and current_metadata is Dictionary and not current_metadata.is_empty():
			inventory.set_slot_metadata(inventory_slot_index, current_metadata)
		changed.emit()
		return true


func unequip_to_inventory(inventory, slot_id: String) -> bool:
	if inventory == null or not equipment_slots.has(slot_id):
		return false

	var slot_data = equipment_slots[slot_id]
	var item_id := str(slot_data.get("item_id", ""))
	var amount := int(slot_data.get("amount", 0))

	if item_id.is_empty() or amount <= 0:
		return false

	var metadata = slot_data.get("metadata", {})
	if metadata is Dictionary and not metadata.is_empty():
		var empty_index := _find_empty_slot(inventory)
		if empty_index < 0:
			return false
		inventory.set_slot(empty_index, item_id, amount)
		inventory.set_slot_metadata(empty_index, metadata)
	else:
		var leftover = inventory.add_item(item_id, amount)
		if leftover > 0:
			return false

	equipment_slots[slot_id] = _empty_slot()
	changed.emit()
	return true


func _find_empty_slot(inventory) -> int:
	if inventory == null or not inventory.has_method("get_slot_count") or not inventory.has_method("get_slot"):
		return -1
	var count = inventory.get_slot_count()
	for i in range(count):
		var slot = inventory.get_slot(i)
		var slot_item = str(slot.get("item_id", ""))
		if slot_item.is_empty() or int(slot.get("amount", 0)) <= 0:
			return i
	return -1


func set_slots_from_save(save_slots: Variant) -> void:
	_ensure_default_equipment()
	if not save_slots is Dictionary:
		return
	for slot_id in EQUIPMENT_SLOT_IDS:
		if save_slots.has(slot_id):
			var data: Dictionary = save_slots[slot_id]
			equipment_slots[slot_id] = {
				"item_id": str(data.get("item_id", "")),
				"amount": int(data.get("amount", 0)),
				"metadata": data.get("metadata", {}) if data.get("metadata") is Dictionary else {},
			}


func get_slots_for_save() -> Dictionary:
	return equipment_slots.duplicate(true)


func _get_content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")
