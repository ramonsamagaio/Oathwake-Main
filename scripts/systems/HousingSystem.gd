extends Node

signal changed(valid_house_count: int)

@export var build_system_path: NodePath = "../BuildSystem"
@export var nearby_wall_radius: int = 2
@export var required_nearby_walls: int = 6

var valid_house_bed_ids := {}

@onready var build_system = get_node(build_system_path)


func _ready() -> void:
	add_to_group("housing_system")
	validate_houses(false)


func validate_houses(print_result := true) -> int:
	valid_house_bed_ids.clear()

	if not build_system.has_method("get_beds"):
		return 0

	for bed in build_system.get_beds():
		var bed_id := str(bed.get("bed_id", ""))
		if bed_id.is_empty():
			continue

		var bed_cell := Vector2i(int(bed.get("x", 0)), int(bed.get("y", 0)))
		var wall_count: int = build_system.get_wall_count_near_cell(bed_cell, nearby_wall_radius)
		if wall_count >= required_nearby_walls:
			valid_house_bed_ids[bed_id] = true

	var valid_count := get_valid_house_count()
	if print_result:
		print("Valid houses: %d" % valid_count)

	changed.emit(valid_count)
	return valid_count


func get_valid_house_count() -> int:
	return valid_house_bed_ids.size()


func is_bed_valid_house(bed_id: String) -> bool:
	return valid_house_bed_ids.has(bed_id)


func get_nearest_valid_bed(global_position: Vector2, max_distance: float, require_unoccupied := true) -> Dictionary:
	var nearest_bed := {}
	var nearest_distance := max_distance

	for bed in build_system.get_beds():
		var bed_id := str(bed.get("bed_id", ""))
		if bed_id.is_empty() or not is_bed_valid_house(bed_id):
			continue

		if require_unoccupied and not str(bed.get("occupied_by_npc_id", "")).is_empty():
			continue

		var bed_position: Vector2 = bed.get("position", Vector2.INF)
		var distance: float = global_position.distance_to(bed_position)
		if distance <= nearest_distance:
			nearest_bed = bed
			nearest_distance = distance

	return nearest_bed
