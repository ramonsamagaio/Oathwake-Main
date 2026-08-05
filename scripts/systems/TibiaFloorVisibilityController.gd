extends Node

const FLOOR_MANAGER_PATH := "/root/MultiFloorBuildManager"
const CARDINAL_DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const DEFAULT_BUILDING_SCENE := "res://scenes/buildings/Building.tscn"
const ROOF_SURFACE_COLOR := Color(0.33, 0.24, 0.16, 1.0)
const ROOF_Z_INDEX := 220

@export_range(0.0, 4.0, 0.1) var reveal_distance_cells := 1.15
@export_range(0.01, 1.0, 0.01) var fade_seconds := 0.18
@export_range(0.0, 1.0, 0.01) var hidden_alpha := 0.0

var _floor_manager: Node
var _build_system: Node
var _player: Node2D
var _build_layer: TileMapLayer
var _visual_root: Node2D
var _components: Array[Dictionary] = []
var _displayed_floor := -1
var _dirty := true


func _ready() -> void:
	process_priority = 850
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_resolve_context()
	_connect_floor_signals()
	_rebuild_if_needed(true)
	set_process(true)


func _process(delta: float) -> void:
	if not _has_context():
		_resolve_context()
		if not _has_context():
			return
	var target_floor := int(_floor_manager.call("get_current_floor")) + 1
	if target_floor != _displayed_floor:
		_dirty = true
	_rebuild_if_needed(false)
	_update_component_visibility(delta)


func _resolve_context() -> void:
	_floor_manager = get_node_or_null(FLOOR_MANAGER_PATH)
	_build_system = get_tree().get_first_node_in_group("build_system")
	if _build_system == null:
		return
	_player = _build_system.get("player") as Node2D
	_build_layer = _build_system.get("build_layer") as TileMapLayer
	var world := _build_layer.get_parent() if _build_layer != null else null
	if world == null:
		return
	_visual_root = world.get_node_or_null("TibiaUpperFloorCover") as Node2D
	if _visual_root == null:
		_visual_root = Node2D.new()
		_visual_root.name = "TibiaUpperFloorCover"
		_visual_root.z_index = ROOF_Z_INDEX
		_visual_root.y_sort_enabled = false
		world.add_child(_visual_root)


func _connect_floor_signals() -> void:
	if _floor_manager == null:
		return
	if _floor_manager.has_signal("floor_changed"):
		var floor_callback := Callable(self, "_on_floor_changed")
		if not _floor_manager.is_connected("floor_changed", floor_callback):
			_floor_manager.connect("floor_changed", floor_callback)
	if _floor_manager.has_signal("floor_data_changed"):
		var data_callback := Callable(self, "_on_floor_data_changed")
		if not _floor_manager.is_connected("floor_data_changed", data_callback):
			_floor_manager.connect("floor_data_changed", data_callback)


func _on_floor_changed(_previous_floor: int, _current_floor: int) -> void:
	_dirty = true


func _on_floor_data_changed(_floor_index: int) -> void:
	_dirty = true


func _has_context() -> bool:
	return _floor_manager != null and is_instance_valid(_floor_manager) \
		and _build_system != null and is_instance_valid(_build_system) \
		and _player != null and is_instance_valid(_player) \
		and _build_layer != null and is_instance_valid(_build_layer) \
		and _visual_root != null and is_instance_valid(_visual_root)


func _rebuild_if_needed(force: bool) -> void:
	if not _has_context() or (not force and not _dirty):
		return
	_dirty = false
	_displayed_floor = int(_floor_manager.call("get_current_floor")) + 1
	_clear_visuals()

	var surfaces: Array = _floor_manager.call("get_floor_surfaces", _displayed_floor)
	var buildings: Array = _floor_manager.call("get_floor_buildings", _displayed_floor)
	var occupied := _collect_occupied_cells(surfaces, buildings)
	if occupied.is_empty():
		_visual_root.visible = false
		return

	_visual_root.visible = true
	var partitions := _partition_connected_cells(occupied)
	for partition_variant in partitions:
		var cells: Array = partition_variant
		var component_root := Node2D.new()
		component_root.name = "UpperFloorComponent_%d" % _components.size()
		component_root.z_index = _components.size()
		component_root.modulate.a = 1.0
		_visual_root.add_child(component_root)
		for cell in cells:
			if _array_has_cell(surfaces, cell):
				_create_surface_visual(component_root, cell)
		for entry_variant in buildings:
			if entry_variant is Dictionary:
				var entry: Dictionary = entry_variant
				if cells.has(_entry_cell(entry)):
					_create_building_visual(component_root, entry)
		_components.append({
			"root": component_root,
			"cells": cells,
			"alpha": 1.0,
		})
	_update_component_visibility(fade_seconds)


func _clear_visuals() -> void:
	_components.clear()
	if _visual_root == null:
		return
	for child in _visual_root.get_children():
		child.queue_free()


func _collect_occupied_cells(surfaces: Array, buildings: Array) -> Array[Vector2i]:
	var unique: Dictionary = {}
	for entry_variant in surfaces:
		if entry_variant is Dictionary:
			unique[_entry_cell(entry_variant)] = true
	for entry_variant in buildings:
		if entry_variant is Dictionary:
			unique[_entry_cell(entry_variant)] = true
	var cells: Array[Vector2i] = []
	for key in unique.keys():
		if key is Vector2i:
			cells.append(key)
	return cells


func _partition_connected_cells(cells: Array) -> Array:
	var remaining: Dictionary = {}
	for cell in cells:
		remaining[cell] = true
	var partitions: Array = []
	while not remaining.is_empty():
		var seed := Vector2i(remaining.keys()[0])
		var queue: Array[Vector2i] = [seed]
		var component: Array[Vector2i] = []
		remaining.erase(seed)
		while not queue.is_empty():
			var current: Vector2i = queue.pop_front()
			component.append(current)
			for direction in CARDINAL_DIRECTIONS:
				var neighbor := current + direction
				if remaining.has(neighbor):
					remaining.erase(neighbor)
					queue.append(neighbor)
		partitions.append(component)
	return partitions


func partition_cells_for_test(cells: Array) -> Array:
	return _partition_connected_cells(cells)


func _update_component_visibility(delta: float) -> void:
	if _components.is_empty() or _player == null:
		return
	var player_cell := _global_position_to_cell(_player.global_position)
	var fade_step := delta / maxf(fade_seconds, 0.01)
	for index in range(_components.size()):
		var component: Dictionary = _components[index]
		var component_root := component.get("root") as Node2D
		var cells: Array = component.get("cells", [])
		if component_root == null or not is_instance_valid(component_root):
			continue
		var covered := _distance_to_cells(player_cell, cells) <= reveal_distance_cells
		var target_alpha := hidden_alpha if covered else 1.0
		var current_alpha := float(component.get("alpha", component_root.modulate.a))
		current_alpha = move_toward(current_alpha, target_alpha, fade_step)
		component_root.modulate.a = current_alpha
		component_root.visible = current_alpha > 0.005
		component["alpha"] = current_alpha
		_components[index] = component


func _distance_to_cells(origin: Vector2i, cells: Array) -> float:
	var nearest := INF
	for cell_variant in cells:
		if not cell_variant is Vector2i:
			continue
		var cell: Vector2i = cell_variant
		var delta := Vector2(cell - origin)
		nearest = minf(nearest, maxf(absf(delta.x), absf(delta.y)))
	return nearest


func _create_surface_visual(parent: Node2D, cell: Vector2i) -> void:
	var tile_size := _tile_size()
	var half := tile_size * 0.5
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	visual.color = ROOF_SURFACE_COLOR
	visual.z_index = 0
	parent.add_child(visual)
	visual.global_position = _cell_to_global_position(cell)


func _create_building_visual(parent: Node2D, entry: Dictionary) -> void:
	var building_type := str(entry.get("type", ""))
	if building_type.is_empty():
		return
	var scene_path := _get_building_scene_path(building_type)
	var packed: Variant = load(scene_path) if ResourceLoader.exists(scene_path) else null
	if not packed is PackedScene:
		packed = load(DEFAULT_BUILDING_SCENE)
	if not packed is PackedScene:
		return
	var visual := (packed as PackedScene).instantiate()
	visual.set_meta("tibia_upper_floor_visual", true)
	if _object_has_property(visual, "building_id"):
		visual.set("building_id", building_type)
	parent.add_child(visual)
	if visual.has_method("set_building_id"):
		visual.call("set_building_id", building_type)
	if visual is Node2D:
		(visual as Node2D).global_position = _cell_to_global_position(_entry_cell(entry))
	_disable_visual_tree(visual)


func _get_building_scene_path(building_type: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_building") and bool(content_db.call("has_building", building_type)):
		var data: Dictionary = content_db.call("get_building", building_type)
		return str(data.get("scene_path", DEFAULT_BUILDING_SCENE))
	return DEFAULT_BUILDING_SCENE


func _disable_visual_tree(node: Node) -> void:
	for group_name in node.get_groups():
		node.remove_from_group(group_name)
	if node is CollisionObject2D:
		(node as CollisionObject2D).collision_layer = 0
		(node as CollisionObject2D).collision_mask = 0
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_visual_tree(child)
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _array_has_cell(entries: Array, cell: Vector2i) -> bool:
	for entry_variant in entries:
		if entry_variant is Dictionary and _entry_cell(entry_variant) == cell:
			return true
	return false


func _entry_cell(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))


func _global_position_to_cell(global_position: Vector2) -> Vector2i:
	if _build_system != null and _build_system.has_method("_global_position_to_grid_cell"):
		return _build_system.call("_global_position_to_grid_cell", global_position)
	return Vector2i.ZERO


func _cell_to_global_position(cell: Vector2i) -> Vector2:
	if _build_layer == null or _build_system == null:
		return Vector2.ZERO
	var local_position: Vector2 = _build_system.call("_grid_cell_to_local_center", cell)
	return _build_layer.to_global(local_position)


func _tile_size() -> Vector2:
	var value: Variant = _build_system.get("tile_size") if _build_system != null else Vector2i(32, 32)
	if value is Vector2i:
		return Vector2(value)
	if value is Vector2:
		return value
	return Vector2(32, 32)


func _object_has_property(object: Object, property_name: String) -> bool:
	for property_data in object.get_property_list():
		if str(property_data.get("name", "")) == property_name:
			return true
	return false
