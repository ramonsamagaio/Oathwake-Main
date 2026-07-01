extends RefCounted

signal changed

const ItemInstanceHelper = preload("res://scripts/systems/ItemInstanceHelper.gd")

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


func get_slot_count() -> int:
	return inventory_slots.size()


func get_slot(index: int) -> Dictionary:
	if not _is_valid_slot_index(index):
		return EMPTY_SLOT.duplicate(true)

	return inventory_slots[index].duplicate(true)


func set_slot(index: int, item_id: String, amount: int, metadata: Dictionary = {}) -> void:
	if not _is_valid_slot_index(index):
		return

	var normalized_id := _normalize_item_id(item_id)
	if normalized_id.is_empty() or amount <= 0:
		clear_slot(index)
		return

	if not _is_known_item(normalized_id):
		push_error("Inventory cannot set unknown item_id: %s" % item_id)
		return

	var new_slot := {
		"item_id": normalized_id,
		"amount": min(amount, _get_stack_size(normalized_id)),
	}
	if not metadata.is_empty():
		new_slot["metadata"] = metadata.duplicate(true)
		ItemInstanceHelper.ensure_item_metadata(new_slot)
	else:
		ItemInstanceHelper.ensure_item_metadata(new_slot)
	inventory_slots[index] = new_slot
	changed.emit()


func set_slot_metadata(index: int, metadata: Dictionary) -> void:
	if not _is_valid_slot_index(index):
		return
	if metadata.is_empty():
		return
	var slot: Dictionary = inventory_slots[index]
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		return
	slot["metadata"] = metadata.duplicate(true)
	inventory_slots[index] = slot
	changed.emit()


func clear_slot(index: int) -> void:
	if not _is_valid_slot_index(index):
		return

	inventory_slots[index] = EMPTY_SLOT.duplicate(true)
	changed.emit()


func add_item(item_id: String, amount: int, metadata: Dictionary = {}) -> int:
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
		var new_slot := {
			"item_id": normalized_id,
			"amount": add_amount,
		}
		if not metadata.is_empty():
			new_slot["metadata"] = metadata.duplicate(true)
			ItemInstanceHelper.ensure_item_metadata(new_slot)
		else:
			ItemInstanceHelper.ensure_item_metadata(new_slot)
		inventory_slots[index] = new_slot
		remaining -= add_amount

	if remaining != amount:
		changed.emit()

	return remaining


func add_item_with_metadata(item_id: String, amount: int, metadata: Dictionary = {}) -> int:
	var normalized_id := _normalize_item_id(item_id)
	return add_item(normalized_id, amount, metadata)


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
	var slot_metadata: Variant = slot.get("metadata")
	return {
		"item_id": item_id,
		"amount": removed_amount,
		"metadata": slot_metadata.duplicate(true) if slot_metadata is Dictionary else {},
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


func split_half_to_empty_slot(from_index: int) -> bool:
	if not _is_valid_slot_index(from_index):
		return false

	var from_slot: Dictionary = inventory_slots[from_index]
	var item_id := str(from_slot.get("item_id", ""))
	var amount := int(from_slot.get("amount", 0))
	if item_id.is_empty() or amount <= 1:
		return false

	var empty_index := get_first_empty_slot_index()
	if empty_index == -1:
		return false

	var split_amount: int = int(floor(float(amount) * 0.5))
	if split_amount <= 0:
		return false

	from_slot["amount"] = amount - split_amount
	var metadata: Variant = from_slot.get("metadata")
	inventory_slots[from_index] = from_slot
	var new_slot := {
		"item_id": item_id,
		"amount": split_amount,
	}
	if metadata is Dictionary and not metadata.is_empty():
		new_slot["metadata"] = metadata.duplicate(true)
	inventory_slots[empty_index] = new_slot
	changed.emit()
	return true


func get_first_empty_slot_index() -> int:
	for index in range(inventory_slots.size()):
		var slot: Dictionary = inventory_slots[index]
		if str(slot.get("item_id", "")).is_empty() or int(slot.get("amount", 0)) <= 0:
			return index

	return -1


func sort_items() -> void:
	var occupied_slots := []
	for slot in inventory_slots:
		if not slot is Dictionary:
			continue
		var item_id := str(slot.get("item_id", ""))
		var amount := int(slot.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		occupied_slots.append(slot.duplicate(true))

	occupied_slots.sort_custom(_compare_slots_for_sort)
	_clear_all_slots()
	for index in range(min(occupied_slots.size(), inventory_slots.size())):
		inventory_slots[index] = occupied_slots[index]
	changed.emit()


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

		var new_slot := {
			"item_id": item_id,
			"amount": min(amount, _get_stack_size(item_id)),
		}
		var metadata = slot.get("metadata", {})
		if metadata is Dictionary and not metadata.is_empty():
			new_slot["metadata"] = metadata.duplicate(true)
		ItemInstanceHelper.ensure_item_metadata(new_slot)
		inventory_slots[index] = new_slot

	changed.emit()


func resize_slots(new_slot_count: int) -> void:
	var safe_slot_count: int = max(new_slot_count, 1)
	if safe_slot_count == inventory_slots.size():
		return

	if safe_slot_count > inventory_slots.size():
		for _index in range(safe_slot_count - inventory_slots.size()):
			inventory_slots.append(EMPTY_SLOT.duplicate(true))
	else:
		inventory_slots.resize(safe_slot_count)

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


func _compare_item_ids_for_sort(a, b) -> bool:
	var a_key := _get_item_sort_key(str(a))
	var b_key := _get_item_sort_key(str(b))
	return a_key < b_key


func _compare_slots_for_sort(a, b) -> bool:
	var a_slot: Dictionary = a if a is Dictionary else {}
	var b_slot: Dictionary = b if b is Dictionary else {}
	var a_item := str(a_slot.get("item_id", ""))
	var b_item := str(b_slot.get("item_id", ""))
	var a_key := _get_item_sort_key(a_item)
	var b_key := _get_item_sort_key(b_item)
	if a_key == b_key:
		var a_dura := _get_sort_durability(a_slot)
		var b_dura := _get_sort_durability(b_slot)
		return a_dura < b_dura
	return a_key < b_key


func _get_sort_durability(slot: Dictionary) -> int:
	var metadata = slot.get("metadata", {})
	if not metadata is Dictionary:
		return 999999
	if not metadata.has("current_durability"):
		return 999999
	return int(metadata.get("current_durability", 999999))


func _get_item_sort_key(item_id: String) -> String:
	var item_data := _get_item_data(item_id)
	return "%04d|%s|%s|%s|%s" % [
		int(item_data.get("tier", 999)),
		str(item_data.get("item_type", "")),
		str(item_data.get("material_family", "")),
		str(item_data.get("display_name", item_id.capitalize())),
		item_id,
	]


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}

	return content_db.get_item(item_id)


func _get_content_db() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null

	return main_loop.root.get_node_or_null("ContentDB")
