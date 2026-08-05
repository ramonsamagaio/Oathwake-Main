extends Node

signal floor_changed(previous_floor: int, current_floor: int)
signal floor_data_changed(floor_index: int)

const SAVE_KEY := "multi_floor_buildings"
const SAVE_VERSION := 3
const BUILD_TYPE_FLOOR := "floor"
const BUILD_TYPE_STAIRS_UP := "stairs_up"
const BUILD_TYPE_STAIRS_DOWN := "stairs_down"
const BUILD_TYPE_CAMPFIRE := "campfire"
const CAMPFIRE_ITEM_ID := "campfire"
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const VALID_FLOOR_PREVIEW_COLOR := Color(0.42, 0.30, 0.18, 0.68)
const VALID_BUILD_PREVIEW_COLOR := Color(0.50, 0.32, 0.18, 0.55)
const INVALID_PREVIEW_COLOR := Color(0.90, 0.12, 0.10, 0.55)
const FLOOR_SURFACE_COLOR := Color(0.33, 0.24, 0.16, 1.0)
const LOWER_FLOOR_SURFACE_COLOR := Color(0.12, 0.11, 0.14, 0.78)
const LOWER_FLOOR_TINT := Color(0.30, 0.31, 0.38, 0.72)
const SUPPORT_BUILDING_TYPES := ["wall", "door", "stairs_up", "stairs_down"]
const STAIR_UPPER_LANDING_OFFSET := Vector2i.UP
const STAIR_LOWER_LANDING_OFFSET := Vector2i.DOWN
const CARDINAL_DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

@export_range(2, 32, 1) var maximum_floor_count := 8
@export var stair_interaction_distance := 104.0
@export var stair_auto_trigger_distance := 22.0
@export var stair_use_cooldown_seconds := 0.8
@export var keep_ground_visible_above_ground := true

var current_floor := 0
var floor_buildings: Dictionary = {}
var floor_surfaces: Dictionary = {}

var _build_system: Node
var _main: Node
var _player: CharacterBody2D
var _build_layer: TileMapLayer
var _ground_layer: TileMapLayer
var _obstacle_layer: TileMapLayer
var _resources_root: Node2D
var _enemies_root: Node2D
var _npcs_root: Node2D
var _build_label: Label
var _surface_visual_root: Node2D
var _lower_floor_visual_root: Node2D
var _lower_floor_dim_visual: Polygon2D
var _empty_obstacle_layer: TileMapLayer
var _initialized := false
var _last_valid_player_position := Vector2.ZERO
var _stair_use_cooldown := 0.0
var _connected_save_button: Button
var _connected_load_button: Button


func _ready() -> void:
	process_priority = 1000
	process_physics_priority = 1000
	set_process_input(true)
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_resolve_context()
	if _build_system == null:
		push_warning("MultiFloorBuildManager could not find the active BuildSystem yet.")
		return

	_load_state_from_active_slot()
	if not floor_buildings.has(_floor_key(0)):
		_set_floor_buildings(0, _capture_active_buildings())
	if not _floor_exists(current_floor):
		current_floor = 0

	_load_floor_into_build_system(current_floor)
	_rebuild_floor_visuals()
	_apply_world_floor_state()
	_ensure_player_has_valid_position()
	_connect_manual_save_controls()
	_last_valid_player_position = _player.global_position if _player != null else Vector2.ZERO
	_initialized = true


func _process(_delta: float) -> void:
	if not _initialized:
		if _build_system == null or not is_instance_valid(_build_system):
			_resolve_context()
		return
	_refresh_preview_validation()
	_refresh_build_label()


func _physics_process(delta: float) -> void:
	if not _initialized or _player == null:
		return
	_stair_use_cooldown = maxf(_stair_use_cooldown - delta, 0.0)

	if current_floor <= 0:
		_last_valid_player_position = _player.global_position
	else:
		var player_cell := _global_position_to_cell(_player.global_position)
		if _is_walkable_upper_floor_cell(current_floor, player_cell):
			_last_valid_player_position = _player.global_position
		else:
			_player.global_position = _last_valid_player_position
			_player.velocity = Vector2.ZERO

	if not _is_build_mode_enabled() and _stair_use_cooldown <= 0.0:
		_try_auto_use_stairs()


func _input(event: InputEvent) -> void:
	if not _initialized or _build_system == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_R or event.keycode == KEY_E) and not _is_build_mode_enabled():
			if try_use_nearby_stairs():
				get_viewport().set_input_as_handled()
				return

		if _is_build_mode_enabled() and event.keycode == KEY_PAGEUP:
			if try_change_floor(current_floor + 1):
				get_viewport().set_input_as_handled()
			return

		if _is_build_mode_enabled() and event.keycode == KEY_PAGEDOWN:
			if try_change_floor(current_floor - 1):
				get_viewport().set_input_as_handled()
			return

	if not _is_build_mode_enabled() or not (event is InputEventMouseButton) or not event.pressed:
		return
	if _is_pointer_over_ui():
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_try_place_current_selection()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		_try_remove_at_cursor()


func try_change_floor(target_floor: int, landing_cell := INVALID_CELL) -> bool:
	if target_floor < 0 or target_floor >= maximum_floor_count:
		return false
	if target_floor == current_floor:
		return true
	if not _floor_exists(target_floor):
		print("Build stairs before accessing floor %d." % target_floor)
		return false

	var previous_floor := current_floor
	_capture_current_floor()
	current_floor = target_floor
	_load_floor_into_build_system(current_floor)
	_rebuild_floor_visuals()
	_apply_world_floor_state()

	if _player != null and landing_cell != INVALID_CELL:
		_player.global_position = _cell_to_global_position(landing_cell)
	_ensure_player_has_valid_position()
	_last_valid_player_position = _player.global_position if _player != null else Vector2.ZERO
	_stair_use_cooldown = stair_use_cooldown_seconds
	_save_state_to_active_slot()
	floor_changed.emit(previous_floor, current_floor)
	return true


func try_use_nearby_stairs() -> bool:
	if _player == null or _build_layer == null or _stair_use_cooldown > 0.0:
		return false
	_capture_current_floor()
	var stair := _find_nearest_stair(stair_interaction_distance)
	if stair.is_empty():
		return false
	return _use_stair_entry(stair)


func _try_auto_use_stairs() -> void:
	var stair := _find_nearest_stair(stair_auto_trigger_distance)
	if stair.is_empty():
		return
	_use_stair_entry(stair)


func _find_nearest_stair(max_distance: float) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := max_distance
	for entry_variant in _get_floor_buildings(current_floor):
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var building_type := str(entry.get("type", ""))
		if building_type != BUILD_TYPE_STAIRS_UP and building_type != BUILD_TYPE_STAIRS_DOWN:
			continue
		var distance := _player.global_position.distance_to(_cell_to_global_position(_entry_cell(entry)))
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = entry.duplicate(true)
	return nearest


func _use_stair_entry(entry: Dictionary) -> bool:
	var building_type := str(entry.get("type", ""))
	var stair_cell := _entry_cell(entry)
	if building_type == BUILD_TYPE_STAIRS_UP:
		var upper_landing := _entry_upper_landing(entry, stair_cell)
		return try_change_floor(current_floor + 1, upper_landing)
	if building_type == BUILD_TYPE_STAIRS_DOWN:
		var lower_landing := _entry_lower_landing(entry, stair_cell)
		return try_change_floor(current_floor - 1, lower_landing)
	return false


func get_current_floor() -> int:
	return current_floor


func get_floor_buildings(floor_index: int) -> Array:
	if floor_index == current_floor:
		_capture_current_floor()
	return _get_floor_buildings(floor_index)


func get_floor_surfaces(floor_index: int) -> Array:
	return _get_floor_surfaces(floor_index)


func get_all_floor_data() -> Dictionary:
	_capture_current_floor()
	return {"buildings": floor_buildings.duplicate(true), "surfaces": floor_surfaces.duplicate(true)}


func save_now() -> void:
	_capture_current_floor()
	_save_state_to_active_slot()


func reload_now() -> void:
	call_deferred("_reload_after_main_load")


func _try_place_current_selection() -> bool:
	var building_type := str(_build_system.get("selected_build_type"))
	if building_type == BUILD_TYPE_FLOOR:
		return _try_place_floor_surface()
	return _try_place_building()


func _try_place_floor_surface() -> bool:
	var tile_position: Vector2i = _build_system.call("_get_mouse_tile")
	if not _can_place_floor_surface(current_floor, tile_position, true):
		return false
	_build_system.call("_spend_building_cost", BUILD_TYPE_FLOOR)
	_add_surface(current_floor, tile_position)
	_rebuild_floor_visuals()
	_save_state_to_active_slot()
	floor_data_changed.emit(current_floor)
	return true


func _try_place_building() -> bool:
	var tile_position: Vector2i = _build_system.call("_get_mouse_tile")
	var building_type := str(_build_system.get("selected_build_type"))
	if current_floor > 0 and not _has_walkable_surface(current_floor, tile_position):
		print("Place a floor tile here before adding a construction.")
		return false
	if building_type == BUILD_TYPE_STAIRS_UP:
		if current_floor + 1 >= maximum_floor_count:
			print("Maximum building floor reached.")
			return false
		if not _get_building_at(current_floor + 1, tile_position).is_empty():
			print("The staircase exit is blocked on the floor above.")
			return false

	var paid_with_campfire_item := false
	if building_type == BUILD_TYPE_CAMPFIRE:
		paid_with_campfire_item = _prepare_campfire_item_payment()
	var placed := _call_build_system_place(tile_position)
	if not placed:
		if paid_with_campfire_item:
			_restore_failed_campfire_item_payment()
		return false

	_capture_current_floor()
	if building_type == BUILD_TYPE_STAIRS_UP:
		_create_stair_link(current_floor, tile_position)
	_rebuild_floor_visuals()
	_save_state_to_active_slot()
	floor_data_changed.emit(current_floor)
	return true


func _try_remove_at_cursor() -> bool:
	var tile_position: Vector2i = _build_system.call("_get_mouse_tile")
	var building_type := str(_build_system.call("_get_building_type_at_tile", tile_position))
	if not building_type.is_empty():
		if building_type == BUILD_TYPE_STAIRS_DOWN:
			print("Remove this staircase from the floor below.")
			return false
		if SUPPORT_BUILDING_TYPES.has(building_type) and _has_dependent_structure_above(current_floor, tile_position):
			print("Cannot remove structural support while something depends on it above.")
			return false

		var removed := bool(_build_system.call("_try_remove_building", tile_position))
		if not removed:
			return false
		if building_type == BUILD_TYPE_CAMPFIRE:
			_convert_campfire_refund_to_item()
		_capture_current_floor()
		if building_type == BUILD_TYPE_STAIRS_UP:
			_remove_stair_link(current_floor, tile_position)
		_rebuild_floor_visuals()
		_save_state_to_active_slot()
		floor_data_changed.emit(current_floor)
		return true

	if _has_surface(current_floor, tile_position):
		return _try_remove_floor_surface(tile_position)
	print("There is no player-built construction here.")
	return false


func _try_remove_floor_surface(tile_position: Vector2i) -> bool:
	if current_floor <= 0:
		return false
	if not _get_building_at(current_floor, tile_position).is_empty():
		print("Remove the construction on this floor tile first.")
		return false
	if _has_dependent_structure_above(current_floor, tile_position):
		print("Cannot remove this floor tile while something depends on it above.")
		return false
	_remove_surface(current_floor, tile_position)
	_build_system.call("_refund_building_cost", BUILD_TYPE_FLOOR)
	_rebuild_floor_visuals()
	_cleanup_empty_floor(current_floor)
	_save_state_to_active_slot()
	floor_data_changed.emit(current_floor)
	return true


func _prepare_campfire_item_payment() -> bool:
	if _main == null or not _main.has_method("can_spend_resource") or not _main.has_method("spend_resource"):
		return false
	if not bool(_main.call("can_spend_resource", CAMPFIRE_ITEM_ID, 1)):
		return false
	if not bool(_main.call("spend_resource", CAMPFIRE_ITEM_ID, 1)):
		return false
	for cost_variant in _get_raw_building_cost(BUILD_TYPE_CAMPFIRE):
		if cost_variant is Dictionary:
			_main.call("add_resource", str(cost_variant.get("resource", "")), int(cost_variant.get("amount", 0)))
	return true


func _restore_failed_campfire_item_payment() -> void:
	for cost_variant in _get_raw_building_cost(BUILD_TYPE_CAMPFIRE):
		if cost_variant is Dictionary:
			_main.call("spend_resource", str(cost_variant.get("resource", "")), int(cost_variant.get("amount", 0)))
	_return_item_to_player(CAMPFIRE_ITEM_ID, 1)


func _convert_campfire_refund_to_item() -> void:
	for cost_variant in _get_raw_building_cost(BUILD_TYPE_CAMPFIRE):
		if cost_variant is Dictionary:
			_main.call("spend_resource", str(cost_variant.get("resource", "")), int(cost_variant.get("amount", 0)))
	_return_item_to_player(CAMPFIRE_ITEM_ID, 1)


func _return_item_to_player(item_id: String, amount: int) -> void:
	if _main == null or amount <= 0:
		return
	var leftover := amount
	if _main.has_method("add_item_to_inventory"):
		leftover = int(_main.call("add_item_to_inventory", item_id, amount))
	if leftover > 0 and _main.has_method("drop_item_near_player"):
		_main.call("drop_item_near_player", item_id, leftover)


func _get_raw_building_cost(building_type: String) -> Array:
	if _build_system != null and _build_system.has_method("_get_building_cost"):
		var costs: Variant = _build_system.call("_get_building_cost", building_type)
		return costs.duplicate(true) if costs is Array else []
	return []


func _call_build_system_place(tile_position: Vector2i) -> bool:
	if current_floor <= 0:
		return bool(_build_system.call("_try_place_selected_building", tile_position))
	_ensure_empty_obstacle_layer()
	var original_obstacle: Variant = _build_system.get("obstacle_layer")
	var original_resources: Variant = _build_system.get("resources_root")
	_build_system.set("obstacle_layer", _empty_obstacle_layer)
	_build_system.set("resources_root", null)
	var placed := bool(_build_system.call("_try_place_selected_building", tile_position))
	_build_system.set("obstacle_layer", original_obstacle)
	_build_system.set("resources_root", original_resources)
	return placed


func _call_build_system_can_place(tile_position: Vector2i, building_type: String) -> bool:
	if current_floor <= 0:
		return bool(_build_system.call("_can_place_building", tile_position, building_type, false))
	_ensure_empty_obstacle_layer()
	var original_obstacle: Variant = _build_system.get("obstacle_layer")
	var original_resources: Variant = _build_system.get("resources_root")
	_build_system.set("obstacle_layer", _empty_obstacle_layer)
	_build_system.set("resources_root", null)
	var can_place := bool(_build_system.call("_can_place_building", tile_position, building_type, false))
	_build_system.set("obstacle_layer", original_obstacle)
	_build_system.set("resources_root", original_resources)
	return can_place


func _capture_current_floor() -> void:
	if _build_system != null and is_instance_valid(_build_system):
		_set_floor_buildings(current_floor, _capture_active_buildings())


func _capture_active_buildings() -> Array:
	if _build_system == null or not _build_system.has_method("get_built_buildings"):
		return []
	var result: Variant = _build_system.call("get_built_buildings")
	var buildings: Array = result.duplicate(true) if result is Array else []
	return _split_legacy_floor_entries(current_floor, buildings)


func _split_legacy_floor_entries(floor_index: int, entries: Array) -> Array:
	var buildings: Array = []
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("type", "")) == BUILD_TYPE_FLOOR:
			_add_surface(floor_index, _entry_cell(entry))
		else:
			buildings.append(entry.duplicate(true))
	return buildings


func _load_floor_into_build_system(floor_index: int) -> void:
	if _build_system != null and _build_system.has_method("load_built_buildings"):
		_build_system.call("load_built_buildings", _get_floor_buildings(floor_index))


func _create_stair_link(source_floor: int, stair_cell: Vector2i) -> void:
	var target_floor := source_floor + 1
	var upper_landing := _pick_valid_landing(stair_cell + STAIR_UPPER_LANDING_OFFSET, stair_cell)
	var lower_landing := _pick_valid_landing(stair_cell + STAIR_LOWER_LANDING_OFFSET, stair_cell)
	_annotate_stair_entry(source_floor, stair_cell, upper_landing, lower_landing)

	var target_buildings := _get_floor_buildings(target_floor)
	if _find_entry_index(target_buildings, stair_cell) < 0:
		target_buildings.append({
			"type": BUILD_TYPE_STAIRS_DOWN,
			"x": stair_cell.x,
			"y": stair_cell.y,
			"generated": true,
			"upper_landing_x": upper_landing.x,
			"upper_landing_y": upper_landing.y,
			"lower_landing_x": lower_landing.x,
			"lower_landing_y": lower_landing.y,
		})
		_set_floor_buildings(target_floor, target_buildings)

	_add_surface(target_floor, stair_cell, true)
	_add_surface(target_floor, upper_landing, true)
	floor_data_changed.emit(target_floor)


func _annotate_stair_entry(floor_index: int, stair_cell: Vector2i, upper_landing: Vector2i, lower_landing: Vector2i) -> void:
	var buildings := _get_floor_buildings(floor_index)
	var index := _find_entry_index(buildings, stair_cell)
	if index < 0:
		return
	var entry: Dictionary = buildings[index]
	entry["upper_landing_x"] = upper_landing.x
	entry["upper_landing_y"] = upper_landing.y
	entry["lower_landing_x"] = lower_landing.x
	entry["lower_landing_y"] = lower_landing.y
	buildings[index] = entry
	_set_floor_buildings(floor_index, buildings)


func _remove_stair_link(source_floor: int, stair_cell: Vector2i) -> void:
	var target_floor := source_floor + 1
	var upper_landing := stair_cell + STAIR_UPPER_LANDING_OFFSET
	var target_entry := _get_building_at(target_floor, stair_cell)
	if not target_entry.is_empty():
		upper_landing = _entry_upper_landing(target_entry, stair_cell)
	_remove_entry_from_floor(target_floor, stair_cell, BUILD_TYPE_STAIRS_DOWN)
	_remove_generated_surface_if_unused(target_floor, stair_cell)
	_remove_generated_surface_if_unused(target_floor, upper_landing)
	_cleanup_empty_floor(target_floor)


func _remove_entry_from_floor(floor_index: int, tile_position: Vector2i, required_type := "") -> bool:
	var buildings := _get_floor_buildings(floor_index)
	for index in range(buildings.size() - 1, -1, -1):
		var entry_variant: Variant = buildings[index]
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if _entry_cell(entry) != tile_position:
			continue
		if not required_type.is_empty() and str(entry.get("type", "")) != required_type:
			continue
		buildings.remove_at(index)
		_set_floor_buildings(floor_index, buildings)
		return true
	return false


func _entry_upper_landing(entry: Dictionary, stair_cell: Vector2i) -> Vector2i:
	return Vector2i(int(entry.get("upper_landing_x", stair_cell.x + STAIR_UPPER_LANDING_OFFSET.x)), int(entry.get("upper_landing_y", stair_cell.y + STAIR_UPPER_LANDING_OFFSET.y)))


func _entry_lower_landing(entry: Dictionary, stair_cell: Vector2i) -> Vector2i:
	return Vector2i(int(entry.get("lower_landing_x", stair_cell.x + STAIR_LOWER_LANDING_OFFSET.x)), int(entry.get("lower_landing_y", stair_cell.y + STAIR_LOWER_LANDING_OFFSET.y)))


func _pick_valid_landing(preferred: Vector2i, fallback: Vector2i) -> Vector2i:
	if _is_cell_inside_map(preferred):
		return preferred
	for direction in CARDINAL_DIRECTIONS:
		var candidate := fallback + direction
		if _is_cell_inside_map(candidate):
			return candidate
	return fallback


func _can_place_floor_surface(floor_index: int, tile_position: Vector2i, show_message := false) -> bool:
	if floor_index <= 0:
		if show_message:
			print("Ground level already has terrain. Change to an upper floor first.")
		return false
	if _has_surface(floor_index, tile_position) or not _is_cell_inside_map(tile_position):
		return false
	var player_cell := _global_position_to_cell(_player.global_position) if _player != null else INVALID_CELL
	if player_cell == tile_position and not _is_stair_landing(floor_index, tile_position):
		return false
	var anchored := _has_vertical_support_below(floor_index, tile_position) or _has_adjacent_surface(floor_index, tile_position) or _is_stair_landing(floor_index, tile_position)
	if not anchored:
		if show_message:
			print("Connect this floor tile to stairs, another floor tile, or support below.")
		return false
	return bool(_build_system.call("_can_spend_building_cost", BUILD_TYPE_FLOOR))


func _has_vertical_support_below(floor_index: int, tile_position: Vector2i) -> bool:
	if floor_index <= 0 or _has_surface(floor_index - 1, tile_position):
		return true
	var below := _get_building_at(floor_index - 1, tile_position)
	return SUPPORT_BUILDING_TYPES.has(str(below.get("type", "")))


func _has_adjacent_surface(floor_index: int, tile_position: Vector2i) -> bool:
	for direction in CARDINAL_DIRECTIONS:
		if _has_surface(floor_index, tile_position + direction):
			return true
	return false


func _has_walkable_surface(floor_index: int, tile_position: Vector2i) -> bool:
	return floor_index <= 0 or _has_surface(floor_index, tile_position) or _is_stair_landing(floor_index, tile_position)


func _is_walkable_upper_floor_cell(floor_index: int, tile_position: Vector2i) -> bool:
	return _has_walkable_surface(floor_index, tile_position)


func _is_stair_landing(floor_index: int, tile_position: Vector2i) -> bool:
	var building := _get_building_at(floor_index, tile_position)
	var building_type := str(building.get("type", ""))
	return building_type == BUILD_TYPE_STAIRS_DOWN or building_type == BUILD_TYPE_STAIRS_UP


func _has_dependent_structure_above(floor_index: int, tile_position: Vector2i) -> bool:
	if floor_index + 1 >= maximum_floor_count:
		return false
	return _has_surface(floor_index + 1, tile_position) or not _get_building_at(floor_index + 1, tile_position).is_empty()


func _get_building_at(floor_index: int, tile_position: Vector2i) -> Dictionary:
	for entry_variant in _get_floor_buildings(floor_index):
		if entry_variant is Dictionary and _entry_cell(entry_variant) == tile_position:
			return entry_variant.duplicate(true)
	return {}


func _find_entry_index(entries: Array, tile_position: Vector2i) -> int:
	for index in range(entries.size()):
		var entry_variant: Variant = entries[index]
		if entry_variant is Dictionary and _entry_cell(entry_variant) == tile_position:
			return index
	return -1


func _entry_cell(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))


func _floor_key(floor_index: int) -> String:
	return str(maxi(floor_index, 0))


func _floor_exists(floor_index: int) -> bool:
	return floor_index == 0 or not _get_floor_buildings(floor_index).is_empty() or not _get_floor_surfaces(floor_index).is_empty()


func _get_floor_buildings(floor_index: int) -> Array:
	var value: Variant = floor_buildings.get(_floor_key(floor_index), [])
	return value.duplicate(true) if value is Array else []


func _set_floor_buildings(floor_index: int, buildings: Array) -> void:
	floor_buildings[_floor_key(floor_index)] = buildings.duplicate(true)


func _get_floor_surfaces(floor_index: int) -> Array:
	var value: Variant = floor_surfaces.get(_floor_key(floor_index), [])
	return value.duplicate(true) if value is Array else []


func _set_floor_surfaces(floor_index: int, surfaces: Array) -> void:
	floor_surfaces[_floor_key(floor_index)] = surfaces.duplicate(true)


func _has_surface(floor_index: int, tile_position: Vector2i) -> bool:
	for entry_variant in _get_floor_surfaces(floor_index):
		if entry_variant is Dictionary and _entry_cell(entry_variant) == tile_position:
			return true
	return false


func _add_surface(floor_index: int, tile_position: Vector2i, generated := false) -> void:
	if _has_surface(floor_index, tile_position):
		return
	var surfaces := _get_floor_surfaces(floor_index)
	surfaces.append({"x": tile_position.x, "y": tile_position.y, "generated": generated})
	_set_floor_surfaces(floor_index, surfaces)


func _remove_surface(floor_index: int, tile_position: Vector2i) -> bool:
	var surfaces := _get_floor_surfaces(floor_index)
	for index in range(surfaces.size() - 1, -1, -1):
		var entry_variant: Variant = surfaces[index]
		if entry_variant is Dictionary and _entry_cell(entry_variant) == tile_position:
			surfaces.remove_at(index)
			_set_floor_surfaces(floor_index, surfaces)
			return true
	return false


func _remove_generated_surface_if_unused(floor_index: int, tile_position: Vector2i) -> void:
	if not _get_building_at(floor_index, tile_position).is_empty():
		return
	var surfaces := _get_floor_surfaces(floor_index)
	for index in range(surfaces.size() - 1, -1, -1):
		var entry_variant: Variant = surfaces[index]
		if entry_variant is Dictionary and _entry_cell(entry_variant) == tile_position and bool(entry_variant.get("generated", false)):
			surfaces.remove_at(index)
	_set_floor_surfaces(floor_index, surfaces)


func _cleanup_empty_floor(floor_index: int) -> void:
	if floor_index <= 0:
		return
	if _get_floor_buildings(floor_index).is_empty() and _get_floor_surfaces(floor_index).is_empty():
		floor_buildings.erase(_floor_key(floor_index))
		floor_surfaces.erase(_floor_key(floor_index))


func _global_position_to_cell(global_position: Vector2) -> Vector2i:
	if _build_system != null and _build_system.has_method("_global_position_to_grid_cell"):
		return _build_system.call("_global_position_to_grid_cell", global_position)
	return Vector2i.ZERO


func _cell_to_global_position(cell: Vector2i) -> Vector2:
	if _build_layer == null or _build_system == null:
		return Vector2.ZERO
	var local_position: Vector2 = _build_system.call("_grid_cell_to_local_center", cell)
	return _build_layer.to_global(local_position)


func _is_cell_inside_map(tile_position: Vector2i) -> bool:
	return _ground_layer != null and _ground_layer.get_cell_source_id(tile_position) != -1


func _resolve_context() -> void:
	_build_system = get_tree().get_first_node_in_group("build_system")
	if _build_system == null:
		return
	_main = _build_system.get("main") as Node
	_player = _build_system.get("player") as CharacterBody2D
	_build_layer = _build_system.get("build_layer") as TileMapLayer
	_ground_layer = _build_system.get("ground_layer") as TileMapLayer
	_obstacle_layer = _build_system.get("obstacle_layer") as TileMapLayer
	_resources_root = _build_system.get("resources_root") as Node2D
	_build_label = _build_system.get("build_label") as Label
	var world := _build_layer.get_parent() if _build_layer != null else null
	if world != null:
		_enemies_root = world.get_node_or_null("Enemies") as Node2D
		_npcs_root = world.get_node_or_null("NPCs") as Node2D
		_surface_visual_root = _get_or_create_world_root(world, "MultiFloorSurfaces", -2)
		_lower_floor_visual_root = _get_or_create_world_root(world, "MultiFloorLowerGhosts", -3)
		_lower_floor_visual_root.y_sort_enabled = true
		_lower_floor_dim_visual = world.get_node_or_null("MultiFloorDim") as Polygon2D
		if _lower_floor_dim_visual == null:
			_lower_floor_dim_visual = Polygon2D.new()
			_lower_floor_dim_visual.name = "MultiFloorDim"
			_lower_floor_dim_visual.z_index = -4
			_lower_floor_dim_visual.color = Color(0.025, 0.03, 0.055, 0.58)
			world.add_child(_lower_floor_dim_visual)


func _get_or_create_world_root(world: Node, node_name: String, z_value: int) -> Node2D:
	var root := world.get_node_or_null(node_name) as Node2D
	if root == null:
		root = Node2D.new()
		root.name = node_name
		root.z_index = z_value
		world.add_child(root)
	return root


func _ensure_empty_obstacle_layer() -> void:
	if _empty_obstacle_layer != null and is_instance_valid(_empty_obstacle_layer):
		return
	var world := _build_layer.get_parent() if _build_layer != null else null
	if world == null:
		return
	_empty_obstacle_layer = TileMapLayer.new()
	_empty_obstacle_layer.name = "MultiFloorEmptyObstacleLayer"
	_empty_obstacle_layer.visible = false
	world.add_child(_empty_obstacle_layer)


func _rebuild_floor_visuals() -> void:
	_rebuild_surface_visuals()
	_rebuild_lower_floor_visuals()
	_rebuild_lower_floor_dim()


func _rebuild_surface_visuals() -> void:
	_clear_children(_surface_visual_root)
	if _surface_visual_root == null:
		return
	_surface_visual_root.visible = current_floor > 0
	if current_floor <= 0:
		return
	for entry_variant in _get_floor_surfaces(current_floor):
		if entry_variant is Dictionary:
			_create_surface_polygon(_surface_visual_root, _entry_cell(entry_variant), FLOOR_SURFACE_COLOR)


func _rebuild_lower_floor_visuals() -> void:
	_clear_children(_lower_floor_visual_root)
	if _lower_floor_visual_root == null:
		return
	_lower_floor_visual_root.visible = current_floor > 0
	if current_floor <= 0:
		return
	for floor_index in range(current_floor):
		if floor_index > 0:
			for surface_variant in _get_floor_surfaces(floor_index):
				if surface_variant is Dictionary:
					_create_surface_polygon(_lower_floor_visual_root, _entry_cell(surface_variant), LOWER_FLOOR_SURFACE_COLOR)
		for building_variant in _get_floor_buildings(floor_index):
			if building_variant is Dictionary:
				_create_lower_building_ghost(building_variant)


func _create_surface_polygon(parent: Node2D, cell: Vector2i, color: Color) -> void:
	var tile_size_value: Variant = _build_system.get("tile_size")
	var tile_size := Vector2(tile_size_value) if tile_size_value is Vector2i else Vector2(32, 32)
	var half := tile_size * 0.5
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	visual.color = color
	parent.add_child(visual)
	visual.global_position = _cell_to_global_position(cell)


func _create_lower_building_ghost(entry: Dictionary) -> void:
	var building_type := str(entry.get("type", ""))
	if building_type.is_empty():
		return
	var scene_path := _get_building_scene_path(building_type)
	var packed: Variant = load(scene_path) if not scene_path.is_empty() and ResourceLoader.exists(scene_path) else null
	if not packed is PackedScene:
		packed = load("res://scenes/buildings/Building.tscn")
	if not packed is PackedScene:
		return
	var ghost := (packed as PackedScene).instantiate()
	ghost.set_meta("multifloor_ghost", true)
	if _object_has_property(ghost, "building_id"):
		ghost.set("building_id", building_type)
	_lower_floor_visual_root.add_child(ghost)
	if ghost is Node2D:
		(ghost as Node2D).global_position = _cell_to_global_position(_entry_cell(entry))
	if ghost.has_method("set_building_id"):
		ghost.call("set_building_id", building_type)
	_disable_ghost_tree(ghost)


func _get_building_scene_path(building_type: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_building") and bool(content_db.call("has_building", building_type)):
		var data: Dictionary = content_db.call("get_building", building_type)
		return str(data.get("scene_path", "res://scenes/buildings/Building.tscn"))
	return "res://scenes/buildings/Building.tscn"


func _disable_ghost_tree(node: Node) -> void:
	for group_name in node.get_groups():
		node.remove_from_group(group_name)
	if node is CanvasItem:
		(node as CanvasItem).modulate = LOWER_FLOOR_TINT
	if node is CollisionObject2D:
		(node as CollisionObject2D).collision_layer = 0
		(node as CollisionObject2D).collision_mask = 0
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_ghost_tree(child)
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _object_has_property(object: Object, property_name: String) -> bool:
	for property_data in object.get_property_list():
		if str(property_data.get("name", "")) == property_name:
			return true
	return false


func _rebuild_lower_floor_dim() -> void:
	if _lower_floor_dim_visual == null or _ground_layer == null:
		return
	_lower_floor_dim_visual.visible = current_floor > 0
	if current_floor <= 0:
		return
	var used_rect := _ground_layer.get_used_rect()
	var tile_size_value: Variant = _build_system.get("tile_size")
	var tile_size := Vector2(tile_size_value) if tile_size_value is Vector2i else Vector2(32, 32)
	var world := _lower_floor_dim_visual.get_parent() as Node2D
	var top_left_global := _build_layer.to_global(Vector2(used_rect.position) * tile_size)
	var bottom_right_global := _build_layer.to_global(Vector2(used_rect.end) * tile_size)
	var top_left := world.to_local(top_left_global)
	var bottom_right := world.to_local(bottom_right_global)
	_lower_floor_dim_visual.polygon = PackedVector2Array([top_left, Vector2(bottom_right.x, top_left.y), bottom_right, Vector2(top_left.x, bottom_right.y)])


func _clear_children(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()


func _apply_world_floor_state() -> void:
	var on_ground := current_floor == 0
	if _obstacle_layer != null:
		_obstacle_layer.visible = on_ground or keep_ground_visible_above_ground
		_obstacle_layer.set("collision_enabled", on_ground)
	_set_world_root_active(_resources_root, on_ground)
	_set_world_root_active(_enemies_root, on_ground)
	_set_world_root_active(_npcs_root, on_ground)


func _set_world_root_active(root: Node, active: bool) -> void:
	if root == null:
		return
	if root is CanvasItem:
		(root as CanvasItem).visible = active
	root.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_set_collision_tree_active(root, active)


func _set_collision_tree_active(node: Node, active: bool) -> void:
	if node is CollisionObject2D:
		var collision_object := node as CollisionObject2D
		if not collision_object.has_meta("multifloor_original_layer"):
			collision_object.set_meta("multifloor_original_layer", collision_object.collision_layer)
			collision_object.set_meta("multifloor_original_mask", collision_object.collision_mask)
		collision_object.collision_layer = int(collision_object.get_meta("multifloor_original_layer", 0)) if active else 0
		collision_object.collision_mask = int(collision_object.get_meta("multifloor_original_mask", 0)) if active else 0
	for child in node.get_children():
		_set_collision_tree_active(child, active)


func _is_build_mode_enabled() -> bool:
	return _build_system != null and bool(_build_system.get("build_mode_enabled"))


func _is_pointer_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _refresh_preview_validation() -> void:
	if not _is_build_mode_enabled():
		return
	var preview := _build_system.get("preview") as Polygon2D
	if preview == null:
		return
	var tile_position: Vector2i = _build_system.call("_get_mouse_tile")
	var building_type := str(_build_system.get("selected_build_type"))
	if building_type == BUILD_TYPE_FLOOR:
		preview.color = VALID_FLOOR_PREVIEW_COLOR if _can_place_floor_surface(current_floor, tile_position) else INVALID_PREVIEW_COLOR
		return
	if current_floor > 0:
		var valid := _has_walkable_surface(current_floor, tile_position) and _call_build_system_can_place(tile_position, building_type)
		if building_type == BUILD_TYPE_STAIRS_UP:
			valid = valid and current_floor + 1 < maximum_floor_count and _get_building_at(current_floor + 1, tile_position).is_empty()
		preview.color = VALID_BUILD_PREVIEW_COLOR if valid else INVALID_PREVIEW_COLOR


func _refresh_build_label() -> void:
	if _build_label == null:
		return
	_build_label.visible = false


func _connect_manual_save_controls() -> void:
	if _main == null:
		return
	_connected_save_button = _main.get_node_or_null("UI/SaveButton") as Button
	_connected_load_button = _main.get_node_or_null("UI/LoadButton") as Button
	if _connected_save_button != null:
		var save_callback := Callable(self, "_on_manual_save_pressed")
		if not _connected_save_button.pressed.is_connected(save_callback):
			_connected_save_button.pressed.connect(save_callback, CONNECT_DEFERRED)
	if _connected_load_button != null:
		var load_callback := Callable(self, "_on_manual_load_pressed")
		if not _connected_load_button.pressed.is_connected(load_callback):
			_connected_load_button.pressed.connect(load_callback, CONNECT_DEFERRED)


func _on_manual_save_pressed() -> void:
	save_now()


func _on_manual_load_pressed() -> void:
	call_deferred("_reload_after_main_load")


func _reload_after_main_load() -> void:
	await get_tree().process_frame
	_load_state_from_active_slot()
	if not _floor_exists(current_floor):
		current_floor = 0
	_load_floor_into_build_system(current_floor)
	_rebuild_floor_visuals()
	_apply_world_floor_state()
	_ensure_player_has_valid_position()
	_last_valid_player_position = _player.global_position if _player != null else Vector2.ZERO


func _ensure_player_has_valid_position() -> void:
	if _player == null or current_floor <= 0:
		return
	var current_cell := _global_position_to_cell(_player.global_position)
	if _is_walkable_upper_floor_cell(current_floor, current_cell):
		return
	var landing_cell := _find_landing_cell(current_floor)
	if landing_cell != INVALID_CELL:
		_player.global_position = _cell_to_global_position(landing_cell)


func _find_landing_cell(floor_index: int) -> Vector2i:
	for entry_variant in _get_floor_buildings(floor_index):
		if entry_variant is Dictionary and str(entry_variant.get("type", "")) == BUILD_TYPE_STAIRS_DOWN:
			var entry: Dictionary = entry_variant
			return _entry_upper_landing(entry, _entry_cell(entry))
	for entry_variant in _get_floor_surfaces(floor_index):
		if entry_variant is Dictionary:
			return _entry_cell(entry_variant)
	return INVALID_CELL


func _load_state_from_active_slot() -> void:
	floor_buildings.clear()
	floor_surfaces.clear()
	current_floor = 0
	var save_data := _read_active_save_data()
	var payload: Variant = save_data.get(SAVE_KEY, {})
	if not payload is Dictionary:
		return
	var version := int(payload.get("version", 0))
	if version >= 2:
		_load_modern_payload(payload)
	elif payload.has("floors"):
		_load_legacy_payload(payload)


func _load_modern_payload(payload: Dictionary) -> void:
	var saved_buildings: Variant = payload.get("buildings", {})
	if saved_buildings is Dictionary:
		for floor_key_variant in saved_buildings.keys():
			var floor_index := int(str(floor_key_variant))
			var entries: Variant = saved_buildings[floor_key_variant]
			if entries is Array:
				_set_floor_buildings(floor_index, _split_legacy_floor_entries(floor_index, entries))
	var saved_surfaces: Variant = payload.get("surfaces", {})
	if saved_surfaces is Dictionary:
		for floor_key_variant in saved_surfaces.keys():
			var floor_index := int(str(floor_key_variant))
			var entries: Variant = saved_surfaces[floor_key_variant]
			if entries is Array:
				_set_floor_surfaces(floor_index, _normalize_surface_entries(entries))
	current_floor = clampi(int(payload.get("current_floor", 0)), 0, maximum_floor_count - 1)
	_ensure_saved_stair_landings()


func _load_legacy_payload(payload: Dictionary) -> void:
	var legacy_floors: Variant = payload.get("floors", {})
	if legacy_floors is Dictionary:
		for floor_key_variant in legacy_floors.keys():
			var floor_index := int(str(floor_key_variant))
			var entries: Variant = legacy_floors[floor_key_variant]
			if entries is Array:
				_set_floor_buildings(floor_index, _split_legacy_floor_entries(floor_index, entries))
	current_floor = clampi(int(payload.get("current_floor", 0)), 0, maximum_floor_count - 1)
	_ensure_saved_stair_landings()


func _ensure_saved_stair_landings() -> void:
	for floor_index in range(maximum_floor_count - 1):
		for entry_variant in _get_floor_buildings(floor_index):
			if entry_variant is Dictionary and str(entry_variant.get("type", "")) == BUILD_TYPE_STAIRS_UP:
				var entry: Dictionary = entry_variant
				var cell := _entry_cell(entry)
				var upper := _entry_upper_landing(entry, cell)
				_add_surface(floor_index + 1, cell, true)
				_add_surface(floor_index + 1, upper, true)


func _normalize_surface_entries(entries: Array) -> Array:
	var normalized: Array = []
	var seen: Dictionary = {}
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var cell := _entry_cell(entry_variant)
		var key := "%d,%d" % [cell.x, cell.y]
		if seen.has(key):
			continue
		seen[key] = true
		normalized.append({"x": cell.x, "y": cell.y, "generated": bool(entry_variant.get("generated", false))})
	return normalized


func _save_state_to_active_slot() -> void:
	var save_path := _get_active_save_path()
	if save_path.is_empty():
		return
	var save_data := _read_active_save_data()
	var payload := {"version": SAVE_VERSION, "current_floor": current_floor, "buildings": floor_buildings.duplicate(true), "surfaces": floor_surfaces.duplicate(true)}
	save_data[SAVE_KEY] = payload
	var directory := save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("MultiFloorBuildManager could not write %s" % save_path)
		return
	file.store_string(JSON.stringify(save_data, "\t") + "\n")
	_mirror_state_to_game_session(payload)


func _read_active_save_data() -> Dictionary:
	var save_path := _get_active_save_path()
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data.duplicate(true)


func _get_active_save_path() -> String:
	var slot_manager := get_node_or_null("/root/SaveSlotManager")
	if slot_manager == null or not slot_manager.has_method("get_active_save_path"):
		return ""
	return str(slot_manager.call("get_active_save_path"))


func _mirror_state_to_game_session(payload: Dictionary) -> void:
	var game_session := get_node_or_null("/root/GameSession")
	if game_session == null:
		return
	var world_data: Variant = game_session.get("world_data")
	var map_id := str(game_session.get("current_map_id"))
	if not world_data is Dictionary or world_data.is_empty() or map_id.is_empty():
		return
	var maps_value: Variant = world_data.get("maps", {})
	var maps: Dictionary = maps_value if maps_value is Dictionary else {}
	var map_value: Variant = maps.get(map_id, {})
	var map_data: Dictionary = map_value if map_value is Dictionary else {}
	map_data[SAVE_KEY] = payload.duplicate(true)
	maps[map_id] = map_data
	world_data["maps"] = maps
	game_session.set("world_data", world_data)
