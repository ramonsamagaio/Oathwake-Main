extends Node

signal active_floor_changed(building_id: String, floor_index: int)
signal building_registered(building_id: String)

const SAVE_KEY := "multi_floor_buildings"

var _active_floors: Dictionary = {}
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


func set_active_floor(building_id: String, floor_index: int, persist := true) -> void:
	var clean_id := building_id.strip_edges()
	if clean_id.is_empty():
		return
	var next_floor := maxi(floor_index, 0)
	if int(_active_floors.get(clean_id, 0)) == next_floor:
		_apply_building_visibility(clean_id)
		return

	_active_floors[clean_id] = next_floor
	_apply_building_visibility(clean_id)
	active_floor_changed.emit(clean_id, next_floor)
	if persist:
		save_to_session()


func move_floor(building_id: String, offset: int, persist := true) -> int:
	var next_floor := maxi(get_active_floor(building_id) + offset, 0)
	set_active_floor(building_id, next_floor, persist)
	return next_floor


func get_active_floor(building_id: String) -> int:
	return int(_active_floors.get(building_id, 0))


func get_building_state(building_id: String) -> Dictionary:
	return {"active_floor": get_active_floor(building_id)}


func load_from_session() -> void:
	_active_floors.clear()
	if not is_instance_valid(GameSession):
		return
	var map_data := GameSession.get_current_map_data()
	var saved_buildings: Variant = map_data.get(SAVE_KEY, {})
	if saved_buildings is Dictionary:
		for building_id: Variant in saved_buildings:
			var state: Variant = saved_buildings[building_id]
			if state is Dictionary:
				_active_floors[str(building_id)] = maxi(int(state.get("active_floor", 0)), 0)
	refresh_all()


func save_to_session() -> void:
	if not is_instance_valid(GameSession) or GameSession.world_data.is_empty() or GameSession.current_map_id.is_empty():
		return

	var serialized: Dictionary = {}
	for building_id: Variant in _active_floors:
		serialized[str(building_id)] = {"active_floor": int(_active_floors[building_id])}

	var maps_value: Variant = GameSession.world_data.get("maps", {})
	var maps: Dictionary = maps_value if maps_value is Dictionary else {}
	var map_value: Variant = maps.get(GameSession.current_map_id, {})
	var map_data: Dictionary = map_value if map_value is Dictionary else {}
	map_data[SAVE_KEY] = serialized
	maps[GameSession.current_map_id] = map_data
	GameSession.world_data["maps"] = maps


func refresh_all() -> void:
	for building_id: Variant in _registered_layers:
		_apply_building_visibility(str(building_id))


func _apply_building_visibility(building_id: String) -> void:
	if not _registered_layers.has(building_id):
		return
	var floors: Dictionary = _registered_layers[building_id]
	var invalid_indices: Array[int] = []
	for floor_index: Variant in floors:
		var reference: Variant = floors[floor_index]
		var layer: Node = reference.get_ref() if reference is WeakRef else null
		if not is_instance_valid(layer):
			invalid_indices.append(int(floor_index))
			continue
		if layer.has_method("apply_floor_state"):
			layer.apply_floor_state(get_active_floor(building_id))
	for floor_index: int in invalid_indices:
		floors.erase(floor_index)
	_registered_layers[building_id] = floors
