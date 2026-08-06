extends RefCounted

signal changed

const CANONICAL_EQUIPMENT_SLOT_IDS := [
	"helm",
	"armor",
	"legs",
	"boots",
	"gloves",
	"neck",
	"hand_left",
	"hand_right",
	"ring_left",
	"ring_right",
	"back",
	"trinket",
]
const LEGACY_EQUIPMENT_SLOT_IDS := ["weapon", "tool", "accessory"]
const EQUIPMENT_SLOT_IDS := [
	"helm",
	"armor",
	"legs",
	"boots",
	"gloves",
	"neck",
	"hand_left",
	"hand_right",
	"ring_left",
	"ring_right",
	"back",
	"trinket",
	"weapon",
	"tool",
	"accessory",
]
const LEGACY_SLOT_ALIASES := {
	"weapon": "hand_right",
	"tool": "hand_right",
	"accessory": "ring_right",
}

var equipment_slots := {}


func _init() -> void:
	_reset_equipment_slots()


func _ensure_default_equipment() -> void:
	for slot_id in EQUIPMENT_SLOT_IDS:
		if not equipment_slots.has(slot_id):
			equipment_slots[slot_id] = _empty_slot()


func _reset_equipment_slots() -> void:
	equipment_slots.clear()
	_ensure_default_equipment()


func _empty_slot() -> Dictionary:
	return {
		"item_id": "",
		"amount": 0,
		"metadata": {},
	}


func get_equipment_slots() -> Dictionary:
	return equipment_slots.duplicate(true)


func get_equipped_slot(slot_id: String) -> Dictionary:
	var normalized_slot_id := _normalize_slot_id(slot_id)
	if equipment_slots.has(normalized_slot_id):
		return equipment_slots[normalized_slot_id].duplicate(true)
	if equipment_slots.has(slot_id):
		return equipment_slots[slot_id].duplicate(true)
	return _empty_slot()


func set_equipped_slot(slot_id: String, slot_data: Dictionary) -> void:
	var normalized_slot_id := _normalize_slot_id(slot_id)
	if not equipment_slots.has(normalized_slot_id):
		return
	equipment_slots[normalized_slot_id] = _sanitize_slot_data(slot_data)


func clear_equipped_slot(slot_id: String) -> void:
	var normalized_slot_id := _normalize_slot_id(slot_id)
	if equipment_slots.has(normalized_slot_id):
		equipment_slots[normalized_slot_id] = _empty_slot()


func can_equip_item(item_id: String, slot_id: String) -> bool:
	var normalized_slot_id := _normalize_slot_id(slot_id)
	if not equipment_slots.has(normalized_slot_id):
		return false
	var valid_slot := get_valid_slot_for_item(item_id)
	return valid_slot == normalized_slot_id


func get_valid_slot_for_item(item_id: String) -> String:
	return _get_declared_equipment_slot(item_id)


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
	else:
		slot_id = _normalize_slot_id(slot_id)
	if slot_id.is_empty() or not equipment_slots.has(slot_id):
		return false
	if not can_equip_item(item_id, slot_id):
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
	var normalized_slot_id := _normalize_slot_id(slot_id)
	if inventory == null or not equipment_slots.has(normalized_slot_id):
		return false

	var slot_data = equipment_slots[normalized_slot_id]
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

	equipment_slots[normalized_slot_id] = _empty_slot()
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
	# Loading must replace runtime state rather than merge into it. Merging left
	# stale equipment behind when changing saves and made old aliases overwrite
	# canonical slots depending on JSON key order.
	_reset_equipment_slots()
	if not save_slots is Dictionary:
		changed.emit()
		return

	var saved: Dictionary = save_slots
	# Canonical records always win, independent from dictionary iteration order.
	for slot_id in CANONICAL_EQUIPMENT_SLOT_IDS:
		if saved.has(slot_id) and saved[slot_id] is Dictionary:
			equipment_slots[slot_id] = _sanitize_slot_data(saved[slot_id])

	# Legacy records only fill an empty canonical destination.
	for legacy_slot_id in LEGACY_EQUIPMENT_SLOT_IDS:
		if not saved.has(legacy_slot_id) or not saved[legacy_slot_id] is Dictionary:
			continue
		var normalized_slot_id := _normalize_slot_id(legacy_slot_id)
		if _slot_has_item(equipment_slots.get(normalized_slot_id, {})):
			continue
		equipment_slots[normalized_slot_id] = _sanitize_slot_data(saved[legacy_slot_id])

	_repair_misplaced_saved_items()
	changed.emit()


func get_slots_for_save() -> Dictionary:
	var save_slots := {}
	for slot_id in CANONICAL_EQUIPMENT_SLOT_IDS:
		save_slots[slot_id] = equipment_slots.get(slot_id, _empty_slot()).duplicate(true)
	for legacy_slot_id in LEGACY_EQUIPMENT_SLOT_IDS:
		save_slots[legacy_slot_id] = _empty_slot()
	return save_slots


func get_canonical_slot_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot_id in CANONICAL_EQUIPMENT_SLOT_IDS:
		ids.append(str(slot_id))
	return ids


func _repair_misplaced_saved_items() -> void:
	# Older saves and previous UI overlap bugs could leave a valid item under the
	# wrong slot key. Item content is the authority for armor/accessory placement.
	for source_slot_id in CANONICAL_EQUIPMENT_SLOT_IDS:
		var source_data: Dictionary = equipment_slots.get(source_slot_id, _empty_slot())
		if not _slot_has_item(source_data):
			continue
		var item_id := str(source_data.get("item_id", ""))
		var declared_slot_id := _get_declared_equipment_slot(item_id)
		if declared_slot_id.is_empty() or declared_slot_id == source_slot_id:
			continue
		if not equipment_slots.has(declared_slot_id):
			continue
		var destination_data: Dictionary = equipment_slots.get(declared_slot_id, _empty_slot())
		if _slot_has_item(destination_data):
			push_warning("EquipmentSystem could not move %s from %s to occupied %s while repairing save data." % [item_id, source_slot_id, declared_slot_id])
			continue
		equipment_slots[declared_slot_id] = source_data.duplicate(true)
		equipment_slots[source_slot_id] = _empty_slot()


func _get_declared_equipment_slot(item_id: String) -> String:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return ""

	var item_data: Dictionary = content_db.get_item(item_id)
	var item_type := str(item_data.get("item_type", "")).to_lower()
	if item_type == "tool" or item_type == "weapon":
		return ""

	var explicit_slot := _normalize_slot_id(str(item_data.get("equipment_slot", "")))
	if not explicit_slot.is_empty():
		if explicit_slot in ["tool", "weapon", "hand_right", "hand_left"]:
			return ""
		return explicit_slot if equipment_slots.has(explicit_slot) else ""

	match item_type:
		"armor":
			return "armor"
		"accessory":
			return "ring_right"

	return ""


func _sanitize_slot_data(slot_data: Dictionary) -> Dictionary:
	var metadata: Variant = slot_data.get("metadata", {})
	return {
		"item_id": str(slot_data.get("item_id", "")),
		"amount": int(slot_data.get("amount", 0)),
		"metadata": metadata.duplicate(true) if metadata is Dictionary else {},
	}


func _slot_has_item(slot_data: Variant) -> bool:
	if not slot_data is Dictionary:
		return false
	return not str(slot_data.get("item_id", "")).is_empty() and int(slot_data.get("amount", 0)) > 0


func _normalize_slot_id(slot_id: String) -> String:
	var normalized := slot_id.strip_edges().to_lower()
	if LEGACY_SLOT_ALIASES.has(normalized):
		return str(LEGACY_SLOT_ALIASES[normalized])
	return normalized


func _get_content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")
