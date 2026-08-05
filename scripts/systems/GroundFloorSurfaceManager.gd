extends Node

const MANAGER_PATH := "/root/MultiFloorBuildManager"
const FEEDBACK_UI_PATH := "/root/BuildMenuOverlay"
const BUILD_TYPE_FLOOR := "floor"
const SURFACE_COLOR := Color(0.33, 0.24, 0.16, 1.0)
const SURFACE_BORDER_COLOR := Color(0.46, 0.33, 0.20, 0.92)

var _floor_manager: Node
var _build_system: Node
var _build_layer: TileMapLayer
var _ground_layer: TileMapLayer
var _obstacle_layer: TileMapLayer
var _resources_root: Node2D
var _visual_root: Node2D
var _bound_world: Node
var _last_signature := ""
var _last_active_floor := -1


func _ready() -> void:
	process_priority = 880
	call_deferred("_resolve_context")


func _process(_delta: float) -> void:
	if not _has_valid_context():
		_resolve_context()
		return

	var active_floor := int(_floor_manager.call("get_current_floor"))
	var signature := JSON.stringify(_floor_manager.call("get_floor_surfaces", 0))
	if active_floor != _last_active_floor or signature != _last_signature:
		_last_active_floor = active_floor
		_last_signature = signature
		_rebuild_visuals()


func handles_current_selection() -> bool:
	return _has_valid_context() \
		and int(_floor_manager.call("get_current_floor")) == 0 \
		and str(_build_system.get("selected_build_type")) == BUILD_TYPE_FLOOR


func has_surface_at_cursor() -> bool:
	if not _has_valid_context() or int(_floor_manager.call("get_current_floor")) != 0:
		return false
	var cell: Vector2i = _build_system.call("_get_mouse_tile")
	return bool(_floor_manager.call("_has_surface", 0, cell))


func try_place_at_cursor() -> bool:
	if not handles_current_selection():
		return false

	var cell: Vector2i = _build_system.call("_get_mouse_tile")
	if bool(_floor_manager.call("_has_surface", 0, cell)):
		_show_feedback("There is already a floor tile here.")
		return false
	if not _is_cell_inside_map(cell):
		_show_feedback("Floor tiles must be placed inside the map.")
		return false
	if _obstacle_layer != null and _obstacle_layer.get_cell_source_id(cell) != -1:
		_show_feedback("Clear the obstacle before placing a floor tile.")
		return false
	if _is_resource_at_cell(cell):
		_show_feedback("Clear the resource before placing a floor tile.")
		return false
	if not bool(_build_system.call("_can_spend_building_cost", BUILD_TYPE_FLOOR)):
		_show_feedback("Not enough resources to build Floor Tile.\nRequired: %s." % _get_floor_cost_text())
		return false

	_build_system.call("_spend_building_cost", BUILD_TYPE_FLOOR)
	_floor_manager.call("_add_surface", 0, cell)
	_floor_manager.call("_save_state_to_active_slot")
	_floor_manager.emit_signal("floor_data_changed", 0)
	_last_signature = ""
	_rebuild_visuals()
	_show_feedback("Floor tile placed.", false, 1.25)
	return true


func try_remove_at_cursor() -> bool:
	if not _has_valid_context() or int(_floor_manager.call("get_current_floor")) != 0:
		return false

	var cell: Vector2i = _build_system.call("_get_mouse_tile")
	if not bool(_floor_manager.call("_has_surface", 0, cell)):
		return false

	var building_type := str(_build_system.call("_get_building_type_at_tile", cell))
	if not building_type.is_empty():
		_show_feedback("Remove the construction on this floor tile first.")
		return false

	_floor_manager.call("_remove_surface", 0, cell)
	_build_system.call("_refund_building_cost", BUILD_TYPE_FLOOR)
	_floor_manager.call("_save_state_to_active_slot")
	_floor_manager.emit_signal("floor_data_changed", 0)
	_last_signature = ""
	_rebuild_visuals()
	_show_feedback("Floor tile retrieved.", false, 1.25)
	return true


func _resolve_context() -> void:
	_floor_manager = get_node_or_null(MANAGER_PATH)
	_build_system = get_tree().get_first_node_in_group("build_system")
	if _floor_manager == null or _build_system == null:
		return

	_build_layer = _build_system.get("build_layer") as TileMapLayer
	_ground_layer = _build_system.get("ground_layer") as TileMapLayer
	_obstacle_layer = _build_system.get("obstacle_layer") as TileMapLayer
	_resources_root = _build_system.get("resources_root") as Node2D
	var world := _build_layer.get_parent() if _build_layer != null else null
	if world == null:
		return
	if world != _bound_world:
		_bound_world = world
		_visual_root = world.get_node_or_null("GroundFloorSurfaces") as Node2D
		if _visual_root == null:
			_visual_root = Node2D.new()
			_visual_root.name = "GroundFloorSurfaces"
			_visual_root.z_index = -2
			world.add_child(_visual_root)
		_last_signature = ""
		_last_active_floor = -1
	_rebuild_visuals()


func _has_valid_context() -> bool:
	return _floor_manager != null and is_instance_valid(_floor_manager) \
		and _build_system != null and is_instance_valid(_build_system) \
		and _build_layer != null and is_instance_valid(_build_layer) \
		and _ground_layer != null and is_instance_valid(_ground_layer)


func _rebuild_visuals() -> void:
	if _visual_root == null or not is_instance_valid(_visual_root) or _floor_manager == null:
		return
	for child in _visual_root.get_children():
		child.queue_free()

	var active_floor := int(_floor_manager.call("get_current_floor"))
	_visual_root.visible = active_floor == 0
	if active_floor != 0:
		return

	for entry_variant in _floor_manager.call("get_floor_surfaces", 0):
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		_create_surface_visual(Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))))


func _create_surface_visual(cell: Vector2i) -> void:
	var tile_size_value: Variant = _build_system.get("tile_size")
	var tile_size := Vector2(tile_size_value) if tile_size_value is Vector2i else Vector2(32, 32)
	var half := tile_size * 0.5
	var points := PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])

	var surface := Polygon2D.new()
	surface.name = "GroundFloor_%d_%d" % [cell.x, cell.y]
	surface.polygon = points
	surface.color = SURFACE_COLOR
	_visual_root.add_child(surface)
	surface.global_position = _floor_manager.call("_cell_to_global_position", cell)

	var border := Line2D.new()
	border.width = 1.0
	border.default_color = SURFACE_BORDER_COLOR
	border.closed = true
	border.points = points
	surface.add_child(border)


func _is_cell_inside_map(cell: Vector2i) -> bool:
	return _ground_layer != null and _ground_layer.get_cell_source_id(cell) != -1


func _is_resource_at_cell(cell: Vector2i) -> bool:
	if _build_system != null and _build_system.has_method("_is_resource_at_tile"):
		return bool(_build_system.call("_is_resource_at_tile", cell))
	if _resources_root == null:
		return false
	for resource_node in _resources_root.get_children():
		if resource_node is Node2D and not resource_node.is_queued_for_deletion():
			var resource_cell: Vector2i = _build_system.call("_global_position_to_grid_cell", resource_node.global_position)
			if resource_cell == cell:
				return true
	return false


func _get_floor_cost_text() -> String:
	if _build_system == null or not _build_system.has_method("_get_building_cost"):
		return "the required materials"
	var costs: Variant = _build_system.call("_get_building_cost", BUILD_TYPE_FLOOR)
	if not costs is Array:
		return "the required materials"
	var parts := PackedStringArray()
	for cost_variant in costs:
		if cost_variant is Dictionary:
			parts.append("%d %s" % [int(cost_variant.get("amount", 0)), str(cost_variant.get("resource", "")).capitalize()])
	return ", ".join(parts)


func _show_feedback(message: String, is_error := true, duration := 2.4) -> void:
	var feedback_ui := get_node_or_null(FEEDBACK_UI_PATH)
	if feedback_ui != null and feedback_ui.has_method("show_feedback"):
		feedback_ui.call("show_feedback", message, is_error, duration)
	else:
		print(message)
