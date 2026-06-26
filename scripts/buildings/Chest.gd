extends StaticBody2D

const Inventory = preload("res://scripts/Inventory.gd")

@export var storage_id: String = ""
@export var display_name: String = "Chest"
@export var slot_count: int = 20
@export var interaction_range: float = 56.0

var storage_inventory := Inventory.new(slot_count)


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

	var main := get_tree().get_first_node_in_group("main")
	if main != null and main.has_method("open_storage"):
		main.open_storage(self)
		return true

	return false


func get_storage_id() -> String:
	return storage_id


func set_storage_id(new_storage_id: String) -> void:
	storage_id = new_storage_id


func get_inventory():
	return storage_inventory


func get_storage_slots() -> Array:
	return storage_inventory.get_slots()


func set_storage_slots(slot_data: Array) -> void:
	storage_inventory.set_slots(slot_data)


func get_display_name() -> String:
	return display_name
