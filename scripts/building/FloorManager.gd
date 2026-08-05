extends Node

signal active_floor_changed(building_id: String, floor_index: int)
signal floor_construction_changed(building_id: String, floor_index: int, is_built: bool)
signal building_registered(building_id: String)

const SAVE_KEY := "multi_floor_buildings"

var _active_floors: Dictionary = {}
var _built_floors: Dictionary = {}
var _registered_layers: Dictionary = {}


func _ready() -> void:
	load_from_session()


func register_floor_layer(building_id: String, floor_index: int, layer: Node) -> void:
	var clean_id := building_id.strip_edges()
	if clean_id.is_empty() or not is_instance_valid(layer):
		push_warning("FloorManager ignored an invalid floor registration.")
		return
	if not _registered_layers.has(clean_id):
		_registered_layers[clean_id] = {}
		building_registered.emit(clean_id)
	var floors: Dictionary = _registered_layers[clean_id]
	floors[floor_index] = weakref(layer)
	_registered_layers[clean_id] = floors
	if not _active_floors.has(clean_id):
		_active_floors[clean_id] = 0
	if not _built_floors.has(clean_id):
		_built_floors[clean_id] = [0]
	_apply_building_visibility(clean_id)


func unregister_floor_layer(building_id: String, floor_index: int, layer: Node) -> void:
	if not _registered_layers.has(building_id):
		return
	var floors: Dictionary = _registered_layers[building_id]
	var reference: Variant = floors.get(floor_index)
	if reference is WeakRef and reference.get_ref() == layer:
		floors.erase(floor_index)
	if floors.is_empty():
		_registered_layers.erase(building_id)
	else:
		_registered_layers[building_id] = floors


func construct_floor(building_id: String, floor_index: int, persist := true) -> bool:
	var clean_id := building_id.strip_edges()
	var target := maxi(floor_index, 0)
	if clean_id.is_empty() or target > 0 and not is_floor_built(clean_id, target - 1):
		return false
	var built: Array = _built_floors.get(clean_id, [0]).duplicate()
	if target in built:
		return true
	built.append(target)
	built.sort()
	_built_floors[clean_id] = built
	_apply_building_visibility(clean_id)
	floor_construction_changed.emit(clean_id, target, true)
	if persist:
		save_to_session()
	return true


func demolish_floor(building_id: String, floor_index: int, persist := true) -> bool:
	if floor_index <= 0 or not is_floor_built(building_id, floor_index):
		return false
	var built: Array = _built_floors.get(building_id, [0]).duplicate()
	for index in range(built.size() - 1, -1, -1):
		if int(built[index]) >= floor_index:
			floor_construction_changed.emit(building_id, int(built[index]), false)
			built.remove_at(index)
	_built_floors[building_id] = built
	if get_active_floor(building_id) >= floor_index:
		_active_floors[building_id] = maxi(floor_index - 1, 0)
	_apply_building_visibility(building_id)
	if persist:
		save_to_session()
	return true


func is_floor_built(building_id: String, floor_index: int) -> bool:
	var built: Array = _built_floors.get(building_id, [0])
	return floor_index in built


func set_active_floor(building_id: String, floor_index: int, persist := true) -> bool:
	var clean_id := building_id.strip_edges()
	var next_floor := maxi(floor_index, 0)
	if clean_id.is_empty() or not is_floor_built(clean_id, next_floor):
		return false
	_active_floors[clean_id] = next_floor
	_apply_building_visibility(clean_id)
	active_floor_changed.emit(clean_id, next_floor)
	if persist:
		save_to_session()
	return true


func move_floor(building_id: String, offset: int, persist := true) -> int:
	var next_floor := maxi(get_active_floor(building_id) + offset, 0)
	return next_floor if set_active_floor(building_id, next_floor, persist) else get_active_floor(building_id)


func get_active_floor(building_id: String) -> int:
	return int(_active_floors.get(building_id, 0))


func get_building_state(building_id: String) -> Dictionary:
	return {"active_floor": get_active_floor(building_id), "built_floors": _built_floors.get(building_id, [0]).duplicate()}


func load_from_session() -> void:
	_active_floors.clear()
	_built_floors.clear()
	var map_data := GameSession.get_current_map_data()
	var saved_buildings: Variant = map_data.get(SAVE_KEY, {})
	if saved_buildings is Dictionary:
		for building_id in saved_buildings:
			var state: Variant = saved_buildings[building_id]
			if state is Dictionary:
				var id := str(building_id)
				var built: Array = state.get("built_floors", [0]).duplicate()
				if not 0 in built:
					built.append(0)
				built.sort()
				_built_floors[id] = built
				var active := maxi(int(state.get("active_floor", 0)), 0)
				_active_floors[id] = active if active in built else 0
	refresh_all()


func save_to_session() -> void:
	if GameSession.world_data.is_empty() or GameSession.current_map_id.is_empty():
		return
	var serialized: Dictionary = {}
	for building_id in _built_floors:
		serialized[str(building_id)] = get_building_state(str(building_id))
	var maps_value: Variant = GameSession.world_data.get("maps", {})
	var maps: Dictionary = maps_value if maps_value is Dictionary else {}
	var map_value: Variant = maps.get(GameSession.current_map_id, {})
	var map_data: Dictionary = map_value if map_value is Dictionary else {}
	map_data[SAVE_KEY] = serialized
	maps[GameSession.current_map_id] = map_data
	GameSession.world_data["maps"] = maps


func refresh_all() -> void:
	for building_id in _registered_layers:
		_apply_building_visibility(str(building_id))


func _apply_building_visibility(building_id: String) -> void:
	if not _registered_layers.has(building_id):
		return
	var floors: Dictionary = _registered_layers[building_id]
	var invalid_indices: Array[int] = []
	for floor_index in floors:
		var reference: Variant = floors[floor_index]
		var layer: Node = reference.get_ref() if reference is WeakRef else null
		if not is_instance_valid(layer):
			invalid_indices.append(int(floor_index))
		elif layer.has_method("apply_floor_state"):
			layer.apply_floor_state(get_active_floor(building_id), is_floor_built(building_id, int(floor_index)))
	for floor_index in invalid_indices:
		floors.erase(floor_index)
	_registered_layers[building_id] = floors
