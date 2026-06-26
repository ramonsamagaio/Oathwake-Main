extends RefCounted

signal changed

const DEFAULT_SLOT_COUNT := 20
const EMPTY_SLOT := {
	"item_id": "",
	"amount": 0,
}

var inventory_slots := []


func _init(slot_count := DEFAULT_SLOT_COUNT) -> void:
	_resize_slots(slot_count)


func get_slots() -> Array:
	return inventory_slots.duplicate(true)


func get_slot(index: int) -> Dictionary:
	if not _is_valid_slot_index(index):
		return EMPTY_SLOT.duplicate(true)

	return inventory_slots[index].duplicate(true)


func set_slot(index: int, item_id: String, amount: int) -> void:
	if not _is_valid_slot_index(index):
		return

	var normalized_id := _normalize_item_id(item_id)
	if normalized_id.is_empty() or amount <= 0:
		clear_slot(index)
		return

	if not _is_known_item(normalized_id):
		push_error("Inventory cannot set unknown item_id: %s" % item_id)
		return

	inventory_slots[index] = {
		"item_id": normalized_id,
		"amount": min(amount, _get_stack_size(normalized_id)),
	}
	changed.emit()


func clear_slot(index: int) -> void:
	if not _is_valid_slot_index(index):
		return

	inventory_slots[index] = EMPTY_SLOT.duplicate(true)
	changed.emit()


func add_item(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0

	var normalized_id := _normalize_item_id(item_id)
	if not _is_known_item(normalized_id):
		push_error("Inventory cannot add unknown item_id: %s" % item_id)
		return amount

	var remaining := amount
	var stack_size := _get_stack_size(normalized_id)

	for index in range(inventory_slots.size()):
		if remaining <= 0:
			break

		var slot: Dictionary = inventory_slots[index]
		if str(slot.get("item_id", "")) != normalized_id:
			continue

		var current_amount := int(slot.get("amount", 0))
		if current_amount >= stack_size:
			continue

		var add_amount: int = min(stack_size - current_amount, remaining)
		slot["amount"] = current_amount + add_amount
		inventory_slots[index] = slot
		remaining -= add_amount

	for index in range(inventory_slots.size()):
		if remaining <= 0:
			break

		var slot: Dictionary = inventory_slots[index]
		if not str(slot.get("item_id", "")).is_empty():
			continue

		var add_amount: int = min(stack_size, remaining)
		inventory_slots[index] = {
			"item_id": normalized_id,
			"amount": add_amount,
		}
		remaining -= add_amount

	if remaining != amount:
		changed.emit()

	return remaining


func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true

	var normalized_id := _normalize_item_id(item_id)
	if not _is_known_item(normalized_id):
		push_error("Inventory cannot remove unknown item_id: %s" % item_id)
		return false

	if not has_item(normalized_id, amount):
		return false

	var remaining := amount
	for index in range(inventory_slots.size() - 1, -1, -1):
		if remaining <= 0:
			break

		var slot: Dictionary = inventory_slots[index]
		if str(slot.get("item_id", "")) != normalized_id:
			continue

		var current_amount := int(slot.get("amount", 0))
		var remove_amount: int = min(current_amount, remaining)
		current_amount -= remove_amount
		remaining -= remove_amount
		if current_amount <= 0:
			inventory_slots[index] = EMPTY_SLOT.duplicate(true)
		else:
			slot["amount"] = current_amount
			inventory_slots[index] = slot

	changed.emit()
	return true


func remove_from_slot(index: int, amount: int) -> Dictionary:
	if amount <= 0 or not _is_valid_slot_index(index):
		return EMPTY_SLOT.duplicate(true)

	var slot: Dictionary = inventory_slots[index]
	var item_id := str(slot.get("item_id", ""))
	var current_amount := int(slot.get("amount", 0))
	if item_id.is_empty() or current_amount <= 0:
		return EMPTY_SLOT.duplicate(true)

	var removed_amount: int = min(amount, current_amount)
	current_amount -= removed_amount
	if current_amount <= 0:
		inventory_slots[index] = EMPTY_SLOT.duplicate(true)
	else:
		slot["amount"] = current_amount
		inventory_slots[index] = slot

	changed.emit()
	return {
		"item_id": item_id,
		"amount": removed_amount,
	}


func move_slot(from_index: int, to_index: int) -> void:
	if not _is_valid_slot_index(from_index) or not _is_valid_slot_index(to_index):
		return
	if from_index == to_index:
		return

	var from_slot: Dictionary = inventory_slots[from_index]
	var to_slot: Dictionary = inventory_slots[to_index]
	var from_item := str(from_slot.get("item_id", ""))
	var to_item := str(to_slot.get("item_id", ""))
	if from_item.is_empty():
		return

	if to_item.is_empty():
		inventory_slots[to_index] = from_slot
		inventory_slots[from_index] = EMPTY_SLOT.duplicate(true)
		changed.emit()
		return

	if to_item == from_item:
		var stack_size := _get_stack_size(from_item)
		var from_amount := int(from_slot.get("amount", 0))
		var to_amount := int(to_slot.get("amount", 0))
		var transfer_amount: int = min(stack_size - to_amount, from_amount)
		if transfer_amount <= 0:
			return

		to_slot["amount"] = to_amount + transfer_amount
		from_amount -= transfer_amount
		inventory_slots[to_index] = to_slot
		if from_amount <= 0:
			inventory_slots[from_index] = EMPTY_SLOT.duplicate(true)
		else:
			from_slot["amount"] = from_amount
			inventory_slots[from_index] = from_slot
		changed.emit()
		return

	inventory_slots[from_index] = to_slot
	inventory_slots[to_index] = from_slot
	changed.emit()


func split_stack(from_index: int, amount: int) -> Dictionary:
	return remove_from_slot(from_index, amount)


func can_add_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true

	var normalized_id := _normalize_item_id(item_id)
	if not _is_known_item(normalized_id):
		return false

	var remaining := amount
	var stack_size := _get_stack_size(normalized_id)
	for slot in inventory_slots:
		var slot_item := str(slot.get("item_id", ""))
		if slot_item == normalized_id:
			remaining -= max(stack_size - int(slot.get("amount", 0)), 0)
		elif slot_item.is_empty():
			remaining -= stack_size

		if remaining <= 0:
			return true

	return false


func count_item(item_id: String) -> int:
	return get_count(item_id)


func get_count(item_id: String) -> int:
	var normalized_id := _normalize_item_id(item_id)
	var total := 0
	for slot in inventory_slots:
		if str(slot.get("item_id", "")) == normalized_id:
			total += int(slot.get("amount", 0))
	return total


func get_all_items() -> Dictionary:
	var items := {}
	for slot in inventory_slots:
		var item_id := str(slot.get("item_id", ""))
		var amount := int(slot.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue

		items[item_id] = int(items.get(item_id, 0)) + amount
	return items


func get_hotbar_slots(slot_count: int) -> Array:
	return inventory_slots.slice(0, min(slot_count, inventory_slots.size())).duplicate(true)


func has_item(item_id: String, amount: int) -> bool:
	return get_count(item_id) >= amount


func add_resource(resource_name: String, amount: int) -> void:
	add_item(resource_name, amount)


func can_spend_resource(resource_name: String, amount: int) -> bool:
	return has_item(resource_name, amount)


func spend_resource(resource_name: String, amount: int) -> bool:
	return remove_item(resource_name, amount)


func get_resource_amount(resource_name: String) -> int:
	return get_count(resource_name)


func set_resource_amount(resource_name: String, amount: int) -> void:
	var normalized_id := _normalize_item_id(resource_name)
	if not _is_known_item(normalized_id):
		push_error("Inventory cannot set unknown item_id: %s" % resource_name)
		return

	remove_item(normalized_id, get_count(normalized_id))
	add_item(normalized_id, amount)


func set_items(item_data: Dictionary) -> void:
	_clear_all_slots()
	for item_id in item_data.keys():
		var normalized_id := _normalize_item_id(str(item_id))
		var amount: int = max(int(item_data[item_id]), 0)
		if amount <= 0:
			continue

		add_item(normalized_id, amount)
	changed.emit()


func set_slots(slot_data: Array) -> void:
	_clear_all_slots()
	for index in range(min(slot_data.size(), inventory_slots.size())):
		var raw_slot: Variant = slot_data[index]
		if not raw_slot is Dictionary:
			continue

		var slot: Dictionary = raw_slot
		var item_id := _normalize_item_id(str(slot.get("item_id", "")))
		var amount := int(slot.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		if not _is_known_item(item_id):
			push_error("Inventory cannot load unknown item_id: %s" % item_id)
			continue

		inventory_slots[index] = {
			"item_id": item_id,
			"amount": min(amount, _get_stack_size(item_id)),
		}

	changed.emit()


func _clear_all_slots() -> void:
	for index in range(inventory_slots.size()):
		inventory_slots[index] = EMPTY_SLOT.duplicate(true)


func _resize_slots(slot_count: int) -> void:
	inventory_slots.clear()
	for _index in range(slot_count):
		inventory_slots.append(EMPTY_SLOT.duplicate(true))


func _is_valid_slot_index(index: int) -> bool:
	return index >= 0 and index < inventory_slots.size()


func _normalize_item_id(item_id: String) -> String:
	match item_id:
		"Wood":
			return "wood"
		"Stone":
			return "stone"
		"Gel":
			return "gel"
		_:
			return item_id.strip_edges().to_lower()


func _is_known_item(item_id: String) -> bool:
	if item_id.is_empty():
		return true

	var content_db := _get_content_db()
	if content_db == null:
		return true

	return content_db.has_item(item_id)


func _get_stack_size(item_id: String) -> int:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return 99

	var item_data: Dictionary = content_db.get_item(item_id)
	return max(int(item_data.get("stack_size", 99)), 1)


func _get_content_db() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null

	return main_loop.root.get_node_or_null("ContentDB")
