extends Node2D

@export_range(20.0, 400.0, 5.0) var follow_speed := 145.0
@export_range(20.0, 500.0, 5.0) var fetch_speed := 190.0
@export_range(32.0, 500.0, 4.0) var pickup_search_radius := 190.0
@export_range(0.05, 2.0, 0.05) var search_interval := 0.20
@export_range(2.0, 32.0, 1.0) var collect_distance := 10.0
@export var follow_offset := Vector2(-22.0, -20.0)

var player: Node2D
var pet_data: Dictionary = {}
var target_item: Node2D
var _search_time_left := 0.0
var _flight_phase := 0.0


func setup(owner_player: Node2D, item_data: Dictionary = {}) -> void:
	player = owner_player
	pet_data = item_data.duplicate(true)
	pickup_search_radius = float(item_data.get("pet_pickup_radius", pickup_search_radius))
	set_meta("pet_id", str(item_data.get("pet_id", "butterfly_pickup")))


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return

	_flight_phase += delta * 5.5
	_search_time_left = maxf(_search_time_left - delta, 0.0)
	if target_item == null or not is_instance_valid(target_item) or _is_item_collected(target_item):
		target_item = null
		if _search_time_left <= 0.0:
			_search_time_left = search_interval
			target_item = _find_nearest_world_item()

	if target_item != null and is_instance_valid(target_item):
		_update_fetch(delta)
	else:
		_update_follow(delta)


func _update_follow(delta: float) -> void:
	var bob := Vector2(0.0, sin(_flight_phase) * 3.0)
	var desired := player.global_position + follow_offset + bob
	global_position = global_position.move_toward(desired, follow_speed * delta)
	z_index = player.z_index + 2


func _update_fetch(delta: float) -> void:
	if target_item.global_position.distance_to(player.global_position) > pickup_search_radius * 1.35:
		target_item = null
		return
	var bob := Vector2(0.0, sin(_flight_phase * 1.35) * 2.0)
	global_position = global_position.move_toward(target_item.global_position + bob, fetch_speed * delta)
	z_index = target_item.z_index + 2
	if global_position.distance_to(target_item.global_position) > collect_distance:
		return
	if target_item.has_method("collect_for_player"):
		target_item.call("collect_for_player", player)
	else:
		target_item.set("player", player)
		target_item.set("magnet_active", true)
	target_item = null
	_search_time_left = search_interval


func _find_nearest_world_item() -> Node2D:
	var nearest: Node2D
	var nearest_distance := pickup_search_radius
	for candidate in get_tree().get_nodes_in_group("world_item"):
		if not candidate is Node2D:
			continue
		var item := candidate as Node2D
		if _is_item_collected(item):
			continue
		var distance := player.global_position.distance_to(item.global_position)
		if distance > nearest_distance:
			continue
		nearest = item
		nearest_distance = distance
	return nearest


func _is_item_collected(item: Node) -> bool:
	return item.has_method("is_collected") and bool(item.call("is_collected"))


func get_fetch_target() -> Node2D:
	return target_item if target_item != null and is_instance_valid(target_item) else null
