extends StaticBody2D

const Inventory = preload("res://scripts/Inventory.gd")

@export var storage_id: String = ""
@export var building_id: String = "chest"
@export var display_name: String = "Chest"
@export var slot_count: int = 20
@export var interaction_range: float = 56.0

var storage_inventory: Inventory = Inventory.new(slot_count)


func _ready() -> void:
	add_to_group("storage")
	add_to_group("player_built_storage")
	if storage_id.is_empty():
		storage_id = "chest_%d" % Time.get_ticks_msec()


func try_interact_with_player(player: Node2D) -> bool:
	if player == null:
		return false
	if global_position.distance_to(player.global_position) > interaction_range:
		return false

	var main = get_tree().get_first_node_in_group("main")
	if main != null and main.has_method("open_storage"):
		main.open_storage(self)
		return true

	return false


func get_storage_id() -> String:
	return storage_id


func set_storage_id(new_storage_id: String) -> void:
	storage_id = new_storage_id


func get_building_id() -> String:
	return building_id


func set_building_id(new_building_id: String) -> void:
	building_id = new_building_id


func set_display_name(new_display_name: String) -> void:
	display_name = new_display_name


func set_slot_count(new_slot_count: int) -> void:
	slot_count = max(new_slot_count, 1)
	storage_inventory.resize_slots(slot_count)


func get_slot_count() -> int:
	return storage_inventory.get_slot_count()


func get_inventory():
	return storage_inventory


func get_storage_slots() -> Array:
	return storage_inventory.get_slots()


func set_storage_slots(slot_data: Array) -> void:
	var needed_slot_count: int = max(slot_count, slot_data.size(), _get_last_occupied_slot_index(slot_data) + 1)
	if needed_slot_count > slot_count:
		print("Storage %s expanded to %d slots to preserve saved items." % [storage_id, needed_slot_count])
		set_slot_count(needed_slot_count)
	storage_inventory.set_slots(slot_data)


func get_display_name() -> String:
	return display_name


func _get_last_occupied_slot_index(slot_data: Array) -> int:
	var last_index := -1
	for index in range(slot_data.size()):
		var raw_slot: Variant = slot_data[index]
		if not raw_slot is Dictionary:
			continue

		var slot: Dictionary = raw_slot
		var item_id := str(slot.get("item_id", ""))
		var amount := int(slot.get("amount", 0))
		if not item_id.is_empty() and amount > 0:
			last_index = index

	return last_index
