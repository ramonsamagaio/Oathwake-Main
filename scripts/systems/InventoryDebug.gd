extends RefCounted

const ItemInstanceHelper = preload("res://scripts/systems/ItemInstanceHelper.gd")

const EQUIPMENT_SLOT_IDS := ["weapon", "tool", "armor", "accessory"]
const DURABILITY_TYPES := ["tool", "weapon", "armor", "accessory"]


static func print_inventory(inventory, label: String) -> void:
	if inventory == null:
		print("%s: null" % label)
		return
	if not inventory.has_method("get_slots"):
		print("%s: no get_slots method" % label)
		return
	var slots: Array = inventory.get_slots()
	print("=== %s (%d slots) ===" % [label, slots.size()])
	var count := 0
	for i in range(slots.size()):
		var raw_data = slots[i]
		if not raw_data is Dictionary:
			continue
		var raw: Dictionary = raw_data
		var item_id := str(raw.get("item_id", ""))
		var amount := int(raw.get("amount", 0))
		if not item_id.is_empty() and amount > 0:
			print("  [%d] %s x%d" % [i, item_id, amount])
			count += 1
	if count == 0:
		print("  (empty)")
	print("")


static func print_world_items() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var nodes := tree.get_nodes_in_group("world_item")
	print("=== World Items (%d nodes) ===" % nodes.size())
	var counts := {}
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var item_id := str(node.get("item_id"))
		var amount := int(node.get("amount"))
		if item_id.is_empty() or amount <= 0:
			continue
		if not counts.has(item_id):
			counts[item_id] = 0
		counts[item_id] += amount
	if counts.is_empty():
		print("  (none)")
	else:
		for item_id in counts.keys():
			print("  %s x%d" % [item_id, counts[item_id]])
	print("")


static func print_chests() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var chests := tree.get_nodes_in_group("storage")
	print("=== Chests (%d) ===" % chests.size())
	for chest in chests:
		if not is_instance_valid(chest):
			continue
		var sid := "?"
		if chest.has_method("get_storage_id"):
			sid = str(chest.get_storage_id())
		var name := "?"
		if chest.has_method("get_display_name"):
			name = str(chest.get_display_name())
		var inv = null
		if chest.has_method("get_inventory"):
			inv = chest.get_inventory()
		var slot_count := 0
		if inv != null and inv.has_method("get_slot_count"):
			slot_count = int(inv.get_slot_count())
		var used := 0
		if inv != null and inv.has_method("get_slots"):
			for raw_s in inv.get_slots():
				if raw_s is Dictionary:
					var sd: Dictionary = raw_s
					if not str(sd.get("item_id", "")).is_empty() and int(sd.get("amount", 0)) > 0:
						used += 1
		var building_id := "?"
		if chest.has_method("get_building_id"):
			building_id = str(chest.get_building_id())
		print("  %s [%s] (bid=%s) %d/%d slots used" % [sid, name, building_id, used, slot_count])
	print("")


static func print_all(main: Node) -> void:
	if main == null:
		print("Main is null, cannot print")
		return
	print("=== DEBUG PRINT ALL ===")
	print_inventory(main.get("inventory"), "Player Inventory")
	print_equipment(main)
	print_world_items()
	print_chests()
	print("=== END DEBUG PRINT ===")


static func print_equipment(main: Node) -> void:
	if main == null:
		return
	print("=== Equipment ===")
	var eq_system = main.get("equipment_system")
	if eq_system == null or not eq_system.has_method("get_equipment_slots"):
		print("  (no equipment system)")
		print("")
		return
	var raw_slots = eq_system.get_equipment_slots()
	if not raw_slots is Dictionary:
		print("  (invalid)")
		print("")
		return
	var slots: Dictionary = raw_slots
	for slot_id in EQUIPMENT_SLOT_IDS:
		var slot_data: Dictionary = slots.get(slot_id, {})
		var item_id := str(slot_data.get("item_id", ""))
		var amount := int(slot_data.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			print("  %s: empty" % slot_id)
		else:
			var raw_meta = slot_data.get("metadata")
			var meta: Dictionary = raw_meta if raw_meta is Dictionary else {}
			var dura_str := ""
			var max_dura := ItemInstanceHelper.get_max_durability(item_id)
			if max_dura > 0:
				var current := int(meta.get("current_durability", max_dura))
				dura_str = " (dur %d/%d)" % [current, max_dura]
			print("  %s: %s x%d%s" % [slot_id, item_id, amount, dura_str])
	print("")


static func print_durability_snapshot(main: Node) -> void:
	if main == null:
		print("Main is null")
		return
	print("=== Durability Snapshot ===")
	var lines := []

	if main.get("inventory") != null:
		var inv = main.get("inventory")
		if inv.has_method("get_slots"):
			for i in range(inv.get_slot_count()):
				var slot: Dictionary = inv.get_slot(i)
				var item_id := str(slot.get("item_id", ""))
				if item_id.is_empty():
					continue
				var max_dura := ItemInstanceHelper.get_max_durability(item_id)
				if max_dura <= 0:
					continue
				var current := ItemInstanceHelper.get_current_durability(slot)
				var broken := " [BROKEN]" if current <= 0 else ""
				lines.append("  inventory[%d] %s: %d/%d%s" % [i, item_id, current, max_dura, broken])

	if main.get("equipment_system") != null:
		var eq = main.get("equipment_system")
		if eq.has_method("get_equipment_slots"):
			var raw_slots = eq.get_equipment_slots()
			if raw_slots is Dictionary:
				var slots: Dictionary = raw_slots
				for slot_id in EQUIPMENT_SLOT_IDS:
					var slot_data: Dictionary = slots.get(slot_id, {})
					var item_id := str(slot_data.get("item_id", ""))
					if item_id.is_empty():
						continue
					var max_dura := ItemInstanceHelper.get_max_durability(item_id)
					if max_dura <= 0:
						continue
					var current := ItemInstanceHelper.get_current_durability(slot_data)
					var broken := " [BROKEN]" if current <= 0 else ""
					lines.append("  equipment.%s %s: %d/%d%s" % [slot_id, item_id, current, max_dura, broken])

	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for chest in tree.get_nodes_in_group("storage"):
			if not is_instance_valid(chest):
				continue
			var sid := "?"
			if chest.has_method("get_storage_id"):
				sid = str(chest.get_storage_id())
			var inv = null
			if chest.has_method("get_inventory"):
				inv = chest.get_inventory()
			if inv != null and inv.has_method("get_slots"):
				for i in range(inv.get_slot_count()):
					var slot: Dictionary = inv.get_slot(i)
					var item_id := str(slot.get("item_id", ""))
					if item_id.is_empty():
						continue
					var max_dura := ItemInstanceHelper.get_max_durability(item_id)
					if max_dura <= 0:
						continue
					var current := ItemInstanceHelper.get_current_durability(slot)
					var broken := " [BROKEN]" if current <= 0 else ""
					lines.append("  chest_%s[%d] %s: %d/%d%s" % [sid, i, item_id, current, max_dura, broken])

		for node in tree.get_nodes_in_group("world_item"):
			if not is_instance_valid(node):
				continue
			var item_id := str(node.get("item_id"))
			var amount := int(node.get("amount"))
			if item_id.is_empty() or amount <= 0:
				continue
			var max_dura := ItemInstanceHelper.get_max_durability(item_id)
			if max_dura <= 0:
				continue
			var raw_meta = node.get("metadata")
			var meta: Dictionary = raw_meta if raw_meta is Dictionary else {}
			var current := int(meta.get("current_durability", max_dura))
			var broken := " [BROKEN]" if current <= 0 else ""
			lines.append("  world_item %s x%d: %d/%d%s" % [item_id, amount, current, max_dura, broken])

	if lines.is_empty():
		print("  (no items with durability)")
	else:
		for line in lines:
			print(line)
	print("")


static func get_item_count_snapshot(main: Node) -> Dictionary:
	var snapshot := {}
	if main == null:
		return snapshot

	if main.get("inventory") != null:
		var inv = main.get("inventory")
		if inv.has_method("get_slots"):
			for raw_slot in inv.get_slots():
				if not raw_slot is Dictionary:
					continue
				var slot: Dictionary = raw_slot
				var item_id := str(slot.get("item_id", ""))
				var amount := int(slot.get("amount", 0))
				if item_id.is_empty() or amount <= 0:
					continue
				snapshot[item_id] = snapshot.get(item_id, 0) + amount

	if main.get("equipment_system") != null:
		var eq = main.get("equipment_system")
		if eq.has_method("get_equipment_slots"):
			var raw_eq_slots = eq.get_equipment_slots()
			if raw_eq_slots is Dictionary:
				var slots: Dictionary = raw_eq_slots
				for slot_id in EQUIPMENT_SLOT_IDS:
					var slot: Dictionary = slots.get(slot_id, {})
					var item_id := str(slot.get("item_id", ""))
					var amount := int(slot.get("amount", 0))
					if item_id.is_empty() or amount <= 0:
						continue
					snapshot[item_id] = snapshot.get(item_id, 0) + amount

	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for chest in tree.get_nodes_in_group("storage"):
			if not is_instance_valid(chest):
				continue
			var inv = null
			if chest.has_method("get_inventory"):
				inv = chest.get_inventory()
			if inv != null and inv.has_method("get_slots"):
				for raw_slot in inv.get_slots():
					if not raw_slot is Dictionary:
						continue
					var slot: Dictionary = raw_slot
					var item_id := str(slot.get("item_id", ""))
					var amount := int(slot.get("amount", 0))
					if item_id.is_empty() or amount <= 0:
						continue
					snapshot[item_id] = snapshot.get(item_id, 0) + amount

		for node in tree.get_nodes_in_group("world_item"):
			if not is_instance_valid(node):
				continue
			var item_id := str(node.get("item_id"))
			var amount := int(node.get("amount"))
			if item_id.is_empty() or amount <= 0:
				continue
			snapshot[item_id] = snapshot.get(item_id, 0) + amount

	return snapshot


static func get_full_item_snapshot(main: Node) -> Dictionary:
	return get_item_count_snapshot(main)


static func print_full_item_snapshot(main: Node) -> void:
	var snapshot := get_full_item_snapshot(main)
	print("=== Full Item Snapshot ===")
	if snapshot.is_empty():
		print("  (empty)")
	else:
		var item_ids := snapshot.keys()
		item_ids.sort()
		for item_id in item_ids:
			print("  %s: %d" % [str(item_id), int(snapshot[item_id])])
	print("=== End Full Item Snapshot ===")


static func validate_full_item_state(main: Node) -> bool:
	var errors: Array[String] = []
	var content_db = _get_content_db()

	if main == null:
		errors.append("Main is null")
	else:
		if main.get("inventory") != null:
			var inv = main.get("inventory")
			if inv.has_method("get_slots"):
				_validate_slots("Player inventory", inv.get_slots(), content_db, errors)
				_validate_metadata_in_slots("Player inventory", inv.get_slots(), content_db, errors)

		_validate_equipment_slots(main, content_db, errors)
		_validate_chests(content_db, errors)
		_validate_world_items(content_db, errors)
		_validate_world_item_metadata(content_db, errors)

	if errors.is_empty():
		print("Full item state validation passed")
		return true
	else:
		for err in errors:
			print(err)
		return false


static func _validate_slots(owner_name: String, slots: Array, content_db: Node, errors: Array[String]) -> void:
	for index in range(slots.size()):
		var raw_slot: Variant = slots[index]
		if not raw_slot is Dictionary:
			errors.append("%s has invalid slot data at index %d" % [owner_name, index])
			continue

		var slot: Dictionary = raw_slot
		var item_id: String = str(slot.get("item_id", ""))
		var amount: int = int(slot.get("amount", 0))
		if item_id.is_empty() and amount > 0:
			errors.append("Invalid slot found at index %d in %s: empty item_id with amount %d" % [index, owner_name, amount])
			continue
		if not item_id.is_empty() and amount <= 0:
			errors.append("Invalid slot found at index %d in %s: %s has amount %d" % [index, owner_name, item_id, amount])
			continue
		if item_id.is_empty():
			continue
		if not _has_item(content_db, item_id):
			errors.append("%s slot %d has invalid item_id: %s" % [owner_name, index, item_id])
			continue

		var stack_size: int = _get_stack_size(content_db, item_id)
		if amount > stack_size:
			errors.append("%s slot %d has %d %s, above stack_size %d" % [owner_name, index, amount, item_id, stack_size])


static func _validate_equipment_slots(main: Node, content_db: Node, errors: Array[String]) -> void:
	if main == null:
		return
	var eq_system = main.get("equipment_system")
	if eq_system == null:
		errors.append("No equipment system found")
		return
	if not eq_system.has_method("get_equipment_slots"):
		errors.append("Equipment system missing get_equipment_slots")
		return

	var raw_slots = eq_system.get_equipment_slots()
	if not raw_slots is Dictionary:
		errors.append("Equipment slots is not a Dictionary")
		return
	var slots: Dictionary = raw_slots

	for slot_id in EQUIPMENT_SLOT_IDS:
		if not slots.has(slot_id):
			errors.append("Equipment slot missing: %s" % slot_id)
			continue

		var slot_data: Dictionary = slots.get(slot_id, {})
		if not slot_data is Dictionary:
			errors.append("Equipment slot %s has invalid data" % slot_id)
			continue

		var item_id := str(slot_data.get("item_id", ""))
		var amount := int(slot_data.get("amount", 0))

		if item_id.is_empty():
			if amount != 0:
				errors.append("Equipment slot %s: empty item_id but amount is %d" % [slot_id, amount])
			continue

		if amount != 1:
			errors.append("Equipment slot %s: %s has amount %d, expected 1" % [slot_id, item_id, amount])

		if not _has_item(content_db, item_id):
			errors.append("Equipment slot %s has invalid item_id: %s" % [slot_id, item_id])
			continue

		if eq_system.has_method("can_equip_item") and not eq_system.can_equip_item(item_id, slot_id):
			errors.append("Equipment slot %s: %s cannot be equipped in this slot" % [slot_id, item_id])

		var raw_metadata: Variant = slot_data.get("metadata", {})
		if not raw_metadata is Dictionary:
			errors.append("Equipment slot %s: %s has non-Dictionary metadata" % [slot_id, item_id])
			continue
		var metadata: Dictionary = raw_metadata

		var max_dura := ItemInstanceHelper.get_max_durability(item_id)
		if max_dura > 0:
			if not metadata.has("current_durability"):
				errors.append("Equipment slot %s: %s has durability %d but missing current_durability metadata" % [slot_id, item_id, max_dura])
			else:
				var current := int(metadata.get("current_durability", 0))
				if current < 0 or current > max_dura:
					errors.append("Equipment slot %s: %s has current_durability %d, out of range [0, %d]" % [slot_id, item_id, current, max_dura])


static func _validate_metadata_in_slots(owner_name: String, slots: Array, content_db: Node, errors: Array[String]) -> void:
	for index in range(slots.size()):
		var raw_slot: Variant = slots[index]
		if not raw_slot is Dictionary:
			continue
		var slot: Dictionary = raw_slot
		var item_id := str(slot.get("item_id", ""))
		if item_id.is_empty():
			continue

		var item_data := _get_item_data(content_db, item_id)
		var item_type := str(item_data.get("item_type", ""))
		var max_dura := int(item_data.get("durability", 0))

		if max_dura > 0:
			if not DURABILITY_TYPES.has(item_type):
				continue
			var raw_metadata: Variant = slot.get("metadata", {})
			if not raw_metadata is Dictionary:
				errors.append("%s slot %d: %s has durability %d but missing metadata" % [owner_name, index, item_id, max_dura])
				continue
			var metadata: Dictionary = raw_metadata
			if not metadata.has("current_durability"):
				errors.append("%s slot %d: %s has durability %d but missing current_durability" % [owner_name, index, item_id, max_dura])
			else:
				var current := int(metadata.get("current_durability", 0))
				if current < 0 or current > max_dura:
					errors.append("%s slot %d: %s has current_durability %d, out of range [0, %d]" % [owner_name, index, item_id, current, max_dura])


static func _validate_world_items(content_db: Node, errors: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	for node in tree.get_nodes_in_group("world_item"):
		if not node is Node:
			continue

		var item_id: String = str(node.get("item_id"))
		var amount: int = int(node.get("amount"))
		if item_id.is_empty() or not _has_item(content_db, item_id):
			errors.append("WorldItem has invalid item_id: %s" % item_id)
		if amount <= 0:
			errors.append("WorldItem %s has invalid amount: %d" % [item_id, amount])
		if node.has_method("is_collected") and node.is_collected() and not node.is_queued_for_deletion():
			errors.append("WorldItem %s is collected but still in the world." % item_id)


static func _validate_world_item_metadata(_content_db: Node, errors: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	for node in tree.get_nodes_in_group("world_item"):
		if not node is Node:
			continue
		var item_id: String = str(node.get("item_id"))
		if item_id.is_empty():
			continue
		var max_dura := ItemInstanceHelper.get_max_durability(item_id)
		if max_dura <= 0:
			continue
		var meta: Variant = node.get("metadata")
		if meta == null:
			errors.append("WorldItem %s has durability %d but no metadata stored" % [item_id, max_dura])


static func _validate_chests(content_db: Node, errors: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	var storage_ids := {}
	var inventory_instance_ids := {}
	for chest in tree.get_nodes_in_group("storage"):
		if not chest is Node:
			continue

		var storage_id: String = ""
		if chest.has_method("get_storage_id"):
			storage_id = str(chest.get_storage_id())
		if storage_id.is_empty():
			errors.append("Chest has empty storage_id")
		elif storage_ids.has(storage_id):
			errors.append("Chest storage_id duplicated: %s" % storage_id)
		else:
			storage_ids[storage_id] = true

		if not chest.has_method("get_inventory"):
			errors.append("Chest %s has no inventory method" % storage_id)
			continue

		var storage_inventory = chest.get_inventory()
		if storage_inventory == null:
			errors.append("Chest %s has null inventory" % storage_id)
			continue

		var instance_id: int = storage_inventory.get_instance_id()
		if inventory_instance_ids.has(instance_id):
			errors.append("Chest %s shares storage inventory reference with another chest" % storage_id)
		else:
			inventory_instance_ids[instance_id] = true

		if storage_inventory.has_method("get_slots"):
			var slots: Array = storage_inventory.get_slots()
			_validate_slots("Chest %s" % storage_id, slots, content_db, errors)
			_validate_metadata_in_slots("Chest %s" % storage_id, slots, content_db, errors)

		var building_id: String = ""
		if chest.has_method("get_building_id"):
			building_id = str(chest.get_building_id())
		if building_id.is_empty():
			errors.append("Chest %s has empty building_id" % storage_id)

		var display_name: String = ""
		if chest.has_method("get_display_name"):
			display_name = str(chest.get_display_name())
		if display_name.is_empty():
			errors.append("Chest %s has empty display_name" % storage_id)


static func validate_game_state(main: Node) -> bool:
	var errors: Array[String] = []
	var content_db := _get_content_db()

	if main != null and main.get("inventory") != null:
		var player_inventory = main.get("inventory")
		if player_inventory.has_method("get_slots"):
			_validate_slots("Player inventory", player_inventory.get_slots(), content_db, errors)

	_validate_world_items(content_db, errors)
	_validate_chests(content_db, errors)

	if errors.is_empty():
		print("Inventory validation passed")
		return true

	for error_message in errors:
		print(error_message)
	return false


static func _has_item(content_db: Node, item_id: String) -> bool:
	if item_id.is_empty():
		return true
	if content_db == null or not content_db.has_method("has_item"):
		return true
	return content_db.has_item(item_id)


static func _get_stack_size(content_db: Node, item_id: String) -> int:
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return 99
	var item_data: Dictionary = content_db.get_item(item_id)
	return max(int(item_data.get("stack_size", 99)), 1)


static func _get_item_data(content_db: Node, item_id: String) -> Dictionary:
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}
	return content_db.get_item(item_id)


static func _get_content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")
