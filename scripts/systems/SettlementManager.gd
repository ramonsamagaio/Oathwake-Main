extends Node

signal changed

@export var main_path: NodePath = ".."
@export var player_path: NodePath = "../World/Player"
@export var build_system_path: NodePath = "../BuildSystem"
@export var housing_system_path: NodePath = "../HousingSystem"
@export var npc_assignment_range: float = 96.0
@export var bed_assignment_range: float = 96.0

var main: Node
var player: Node2D
var build_system: Node
var housing_system: Node


func _ready() -> void:
	add_to_group("settlement_manager")
	setup({})


func setup(context: Dictionary) -> void:
	main = context.get("controller", context.get("main", main)) as Node
	player = context.get("player", player) as Node2D
	build_system = context.get("build_system", build_system) as Node
	housing_system = context.get("housing_system", housing_system) as Node
	if main == null:
		main = get_node_or_null(main_path)
	if player == null:
		player = get_node_or_null(player_path) as Node2D
	if build_system == null:
		build_system = get_node_or_null(build_system_path)
	if housing_system == null:
		housing_system = get_node_or_null(housing_system_path)


func recruit_npc(npc: Node) -> bool:
	if npc == null or not npc.has_method("set_recruited"):
		return false

	if npc.has_method("is_recruited") and npc.is_recruited():
		return false

	npc.set_recruited(true, true)
	changed.emit()
	return true


func get_recruited_count() -> int:
	var count := 0

	for npc in _get_npcs():
		if npc.has_method("is_recruited") and npc.is_recruited():
			count += 1

	return count


func get_housed_count() -> int:
	var count := 0

	for npc in _get_npcs():
		if npc.has_method("is_recruited") and npc.is_recruited() and npc.has_method("has_valid_house") and npc.has_valid_house():
			count += 1

	return count


func get_save_data() -> Dictionary:
	var npc_save_data := []

	for npc in _get_npcs():
		if npc.has_method("get_save_data"):
			npc_save_data.append(npc.get_save_data())

	return {
		"npcs": npc_save_data,
	}


func load_save_data(save_data) -> void:
	if not save_data is Dictionary:
		changed.emit()
		return

	var npc_data_by_instance_id := {}
	var saved_npcs = save_data.get("npcs", [])
	if saved_npcs is Array:
		for npc_data in saved_npcs:
			if not npc_data is Dictionary:
				continue

			var npc_instance_id := str(npc_data.get("npc_instance_id", ""))
			if npc_instance_id.is_empty():
				continue

			npc_data_by_instance_id[npc_instance_id] = npc_data

	for npc in _get_npcs():
		if not npc.has_method("get_npc_instance_id") or not npc.has_method("load_save_data"):
			continue

		var npc_instance_id := str(npc.get_npc_instance_id())
		npc.load_save_data(npc_data_by_instance_id.get(npc_instance_id, {}))

	if build_system.has_method("clear_all_bed_occupancy"):
		build_system.clear_all_bed_occupancy()

	_restore_bed_occupancy()
	validate_assignments()
	changed.emit()


func assign_nearby_npc_to_house() -> bool:
	if housing_system.has_method("validate_houses"):
		housing_system.validate_houses(false)

	var npc := _get_nearest_recruited_unhoused_npc()
	if npc == null:
		print("Need a recruited NPC nearby without a house.")
		return false

	var bed: Dictionary = housing_system.get_nearest_valid_bed(player.global_position, bed_assignment_range, true)
	if bed.is_empty():
		print("Need a valid unoccupied house nearby.")
		return false

	var bed_id := str(bed.get("bed_id", ""))
	var npc_instance_id := str(npc.get_npc_instance_id())
	npc.assign_bed(bed_id)
	build_system.set_bed_occupied_by_npc_id(bed_id, npc_instance_id)
	print("NPC assigned to house")
	changed.emit()
	return true


func validate_assignments() -> void:
	if housing_system.has_method("validate_houses"):
		housing_system.validate_houses(false)

	for npc in _get_npcs():
		if not npc.has_method("get_assigned_bed_id") or not npc.has_method("clear_house_assignment"):
			continue

		var assigned_bed_id := str(npc.get_assigned_bed_id())
		if assigned_bed_id.is_empty():
			continue

		if not build_system.has_bed_id(assigned_bed_id) or not housing_system.is_bed_valid_house(assigned_bed_id):
			build_system.clear_bed_occupancy_for_npc(npc.get_npc_instance_id())
			npc.clear_house_assignment()

	changed.emit()


func on_bed_removed(bed_id: String) -> void:
	if bed_id.is_empty():
		return

	for npc in _get_npcs():
		if not npc.has_method("get_assigned_bed_id") or not npc.has_method("clear_house_assignment"):
			continue

		if str(npc.get_assigned_bed_id()) == bed_id:
			npc.clear_house_assignment()

	changed.emit()


func _restore_bed_occupancy() -> void:
	for npc in _get_npcs():
		if not npc.has_method("is_recruited") or not npc.is_recruited():
			continue

		if not npc.has_method("get_assigned_bed_id") or not npc.has_method("get_npc_instance_id"):
			continue

		var assigned_bed_id := str(npc.get_assigned_bed_id())
		if assigned_bed_id.is_empty():
			continue

		build_system.set_bed_occupied_by_npc_id(assigned_bed_id, npc.get_npc_instance_id())


func _get_nearest_recruited_unhoused_npc() -> Node:
	var nearest_npc: Node = null
	var nearest_distance := npc_assignment_range

	for npc in _get_npcs():
		if not npc is Node2D:
			continue

		if not npc.has_method("is_recruited") or not npc.is_recruited():
			continue

		if npc.has_method("has_valid_house") and npc.has_valid_house():
			continue

		var distance := player.global_position.distance_to((npc as Node2D).global_position)
		if distance <= nearest_distance:
			nearest_npc = npc
			nearest_distance = distance

	return nearest_npc


func _get_npcs() -> Array:
	return get_tree().get_nodes_in_group("npc")
