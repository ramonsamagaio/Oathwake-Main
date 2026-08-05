extends Node

signal floor_changed(previous_floor: int, current_floor: int)
signal floor_data_changed(floor_index: int)

const SAVE_KEY := "multi_floor_buildings"
const SAVE_VERSION := 1
const BUILD_TYPE_FLOOR := "floor"
const BUILD_TYPE_STAIRS_UP := "stairs_up"
const BUILD_TYPE_STAIRS_DOWN := "stairs_down"
const INVALID_PREVIEW_COLOR := Color(0.90, 0.12, 0.10, 0.55)
const SUPPORT_TYPES := ["floor", "wall", "door", "stairs_up", "stairs_down"]
const INVALID_CELL := Vector2i(2147483647, 2147483647)

@export_range(2, 32, 1) var maximum_floor_count := 8
@export var stair_interaction_distance := 52.0
@export var keep_ground_visible_above_ground := true

var current_floor := 0
var floors: Dictionary = {}

var _build_system: Node
var _main: Node
var _player: CharacterBody2D
var _build_layer: TileMapLayer
var _obstacle_layer: TileMapLayer
var _resources_root: Node2D
var _enemies_root: Node2D
var _npcs_root: Node2D
var _build_label: Label
var _initialized := false
var _last_valid_player_position := Vector2.ZERO
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
	if not floors.has(_floor_key(0)):
		_set_floor_buildings(0, _capture_active_buildings())
	if not floors.has(_floor_key(current_floor)):
		current_floor = 0

	_load_floor_into_build_system(current_floor)
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


func _physics_process(_delta: float) -> void:
	if not _initialized or _player == null:
		return
	if current_floor <= 0:
		_last_valid_player_position = _player.global_position
		return

	var player_cell := _global_position_to_cell(_player.global_position)
	if _is_walkable_upper_floor_cell(current_floor, player_cell):
		_last_valid_player_position = _player.global_position
	else:
		_player.global_position = _last_valid_player_position
		_player.velocity = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if not _initialized or _build_system == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and not _is_build_mode_enabled():
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
	if not floors.has(_floor_key(target_floor)):
		print("Build stairs before accessing floor %d." % target_floor)
		return false

	var previous_floor := current_floor
	_capture_current_floor()
	current_floor = target_floor
	_load_floor_into_build_system(current_floor)
	_apply_world_floor_state()

	if _player != null and landing_cell != INVALID_CELL:
		_player.global_position = _cell_to_global_position(landing_cell)
	_ensure_player_has_valid_position()
	_last_valid_player_position = _player.global_position if _player != null else Vector2.ZERO
	_save_state_to_active_slot()
	floor_changed.emit(previous_floor, current_floor)
	return true


func try_use_nearby_stairs() -> bool:
	if _player == null or _build_layer == null:
		return false
	_capture_current_floor()

	var nearest_entry: Dictionary = {}
	var nearest_distance := stair_interaction_distance
	for entry_variant in _get_floor_buildings(current_floor):
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var building_type := str(entry.get("type", ""))
		if building_type != BUILD_TYPE_STAIRS_UP and building_type != BUILD_TYPE_STAIRS_DOWN:
			continue
		var cell := _entry_cell(entry)
		var distance := _player.global_position.distance_to(_cell_to_global_position(cell))
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_entry = entry

	if nearest_entry.is_empty():
		return false

	var stair_type := str(nearest_entry.get("type", ""))
	var stair_cell := _entry_cell(nearest_entry)
	if stair_type == BUILD_TYPE_STAIRS_UP:
		return try_change_floor(current_floor + 1, stair_cell)
	return try_change_floor(current_floor - 1, stair_cell)


func get_current_floor() -> int:
	return current_floor


func get_floor_buildings(floor_index: int) -> Array:
	if floor_index == current_floor:
		_capture_current_floor()
	return _get_floor_buildings(floor_index)


func get_all_floor_buildings() -> Dictionary:
	_capture_current_floor()
	return floors.duplicate(true)


func save_now() -> void:
	_capture_current_floor()
	_save_state_to_active_slot()


func reload_now() -> void:
	call_deferred("_reload_after_main_load")


func _try_place_current_selection() -> bool:
	if _build_system == null:
		return false
	var tile_position: Vector2i = _build_system.call("_get_mouse_tile")
	var building_type := str(_build_system.get("selected_build_type"))

	if current_floor > 0 and not _has_support_below(current_floor, tile_position):
		print("Upper floors require structural support directly below this tile.")
		return false
	if building_type == BUILD_TYPE_STAIRS_UP:
		if current_floor + 1 >= maximum_floor_count:
			print("Maximum building floor reached.")
			return false
		if not _get_building_at(current_floor + 1, tile_position).is_empty():
			print("The staircase exit is blocked on the floor above.")
			return false

	var placed := bool(_build_system.call("_try_place_selected_building", tile_position))
	if not placed:
		return false

	_capture_current_floor()
	if building_type == BUILD_TYPE_STAIRS_UP:
		_create_linked_stairs_down(current_floor + 1, tile_position)
	_save_state_to_active_slot()
	floor_data_changed.emit(current_floor)
	return true


func _try_remove_at_cursor() -> bool:
	if _build_system == null:
		return false
	var tile_position: Vector2i = _build_system.call("_get_mouse_tile")
	var building_type := str(_build_system.call("_get_building_type_at_tile", tile_position))
	if building_type.is_empty():
		print("There is no player-built construction here.")
		return false
	if building_type == BUILD_TYPE_STAIRS_DOWN:
		print("Remove this staircase from the floor below.")
		return false
	if building_type != BUILD_TYPE_STAIRS_UP and _has_dependent_structure_above(current_floor, tile_position):
		print("Cannot remove structural support while something is built above it.")
		return false

	var removed := bool(_build_system.call("_try_remove_building", tile_position))
	if not removed:
		return false

	_capture_current_floor()
	if building_type == BUILD_TYPE_STAIRS_UP:
		_remove_entry_from_floor(current_floor + 1, tile_position, BUILD_TYPE_STAIRS_DOWN)
	_save_state_to_active_slot()
	floor_data_changed.emit(current_floor)
	return true


func _capture_current_floor() -> void:
	if _build_system == null or not is_instance_valid(_build_system):
		return
	_set_floor_buildings(current_floor, _capture_active_buildings())


func _capture_active_buildings() -> Array:
	if _build_system == null or not _build_system.has_method("get_built_buildings"):
		return []
	var result: Variant = _build_system.call("get_built_buildings")
	return result.duplicate(true) if result is Array else []


func _load_floor_into_build_system(floor_index: int) -> void:
	if _build_system == null or not _build_system.has_method("load_built_buildings"):
		return
	_build_system.call("load_built_buildings", _get_floor_buildings(floor_index))


func _create_linked_stairs_down(target_floor: int, tile_position: Vector2i) -> void:
	var target_buildings := _get_floor_buildings(target_floor)
	if _find_entry_index(target_buildings, tile_position) >= 0:
		return
	target_buildings.append({
		"type": BUILD_TYPE_STAIRS_DOWN,
		"x": tile_position.x,
		"y": tile_position.y,
		"generated": true,
	})
	_set_floor_buildings(target_floor, target_buildings)
	floor_data_changed.emit(target_floor)


func _remove_entry_from_floor(floor_index: int, tile_position: Vector2i, required_type := "") -> bool:
	var floor_buildings := _get_floor_buildings(floor_index)
	for index in range(floor_buildings.size() - 1, -1, -1):
		var entry: Variant = floor_buildings[index]
		if not entry is Dictionary:
			continue
		if _entry_cell(entry) != tile_position:
			continue
		if not required_type.is_empty() and str(entry.get("type", "")) != required_type:
			continue
		floor_buildings.remove_at(index)
		_set_floor_buildings(floor_index, floor_buildings)
		return true
	return false


func _has_support_below(floor_index: int, tile_position: Vector2i) -> bool:
	if floor_index <= 0:
		return true
	var below := _get_building_at(floor_index - 1, tile_position)
	return SUPPORT_TYPES.has(str(below.get("type", "")))


func _has_dependent_structure_above(floor_index: int, tile_position: Vector2i) -> bool:
	if floor_index + 1 >= maximum_floor_count:
		return false
	return not _get_building_at(floor_index + 1, tile_position).is_empty()


func _is_walkable_upper_floor_cell(floor_index: int, tile_position: Vector2i) -> bool:
	return _has_support_below(floor_index, tile_position)


func _get_building_at(floor_index: int, tile_position: Vector2i) -> Dictionary:
	for entry_variant in _get_floor_buildings(floor_index):
		if entry_variant is Dictionary and _entry_cell(entry_variant) == tile_position:
			return entry_variant.duplicate(true)
	return {}


func _find_entry_index(entries: Array, tile_position: Vector2i) -> int:
	for index in range(entries.size()):
		var entry: Variant = entries[index]
		if entry is Dictionary and _entry_cell(entry) == tile_position:
			return index
	return -1


func _entry_cell(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))


func _floor_key(floor_index: int) -> String:
	return str(maxi(floor_index, 0))


func _get_floor_buildings(floor_index: int) -> Array:
	var value: Variant = floors.get(_floor_key(floor_index), [])
	return value.duplicate(true) if value is Array else []


func _set_floor_buildings(floor_index: int, buildings: Array) -> void:
	floors[_floor_key(floor_index)] = buildings.duplicate(true)


func _global_position_to_cell(global_position: Vector2) -> Vector2i:
	if _build_system != null and _build_system.has_method("_global_position_to_grid_cell"):
		return _build_system.call("_global_position_to_grid_cell", global_position)
	return Vector2i.ZERO


func _cell_to_global_position(cell: Vector2i) -> Vector2:
	if _build_layer == null or _build_system == null:
		return Vector2.ZERO
	var local_position: Vector2 = _build_system.call("_grid_cell_to_local_center", cell)
	return _build_layer.to_global(local_position)


func _resolve_context() -> void:
	_build_system = get_tree().get_first_node_in_group("build_system")
	if _build_system == null:
		return
	_main = _build_system.get("main") as Node
	_player = _build_system.get("player") as CharacterBody2D
	_build_layer = _build_system.get("build_layer") as TileMapLayer
	_obstacle_layer = _build_system.get("obstacle_layer") as TileMapLayer
	_resources_root = _build_system.get("resources_root") as Node2D
	_build_label = _build_system.get("build_label") as Label

	var world := _build_layer.get_parent() if _build_layer != null else null
	if world != null:
		_enemies_root = world.get_node_or_null("Enemies") as Node2D
		_npcs_root = world.get_node_or_null("NPCs") as Node2D


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
	if not _is_build_mode_enabled() or current_floor <= 0:
		return
	var preview := _build_system.get("preview") as Polygon2D
	if preview == null:
		return
	var tile_position: Vector2i = _build_system.call("_get_mouse_tile")
	var building_type := str(_build_system.get("selected_build_type"))
	var invalid := not _has_support_below(current_floor, tile_position)
	if building_type == BUILD_TYPE_STAIRS_UP:
		if current_floor + 1 >= maximum_floor_count or not _get_building_at(current_floor + 1, tile_position).is_empty():
			invalid = true
	if invalid:
		preview.color = INVALID_PREVIEW_COLOR


func _refresh_build_label() -> void:
	if _build_label == null:
		return
	var lines := _build_label.text.split("\n")
	var cleaned := PackedStringArray()
	for line in lines:
		var text := str(line)
		if text.begins_with("Floor:") or text.begins_with("PgUp/PgDn:") or text.begins_with("R: Use stairs"):
			continue
		cleaned.append(text)
	cleaned.append("Floor: %d / %d" % [current_floor, maximum_floor_count - 1])
	cleaned.append("PgUp/PgDn: Change floor while building")
	cleaned.append("R: Use stairs")
	_build_label.text = "\n".join(cleaned)


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
	_capture_current_floor()
	_save_state_to_active_slot()


func _on_manual_load_pressed() -> void:
	call_deferred("_reload_after_main_load")


func _reload_after_main_load() -> void:
	await get_tree().process_frame
	_load_state_from_active_slot()
	_load_floor_into_build_system(current_floor)
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
	if landing_cell == INVALID_CELL:
		return
	_player.global_position = _cell_to_global_position(landing_cell)


func _find_landing_cell(floor_index: int) -> Vector2i:
	for entry_variant in _get_floor_buildings(floor_index):
		if entry_variant is Dictionary and str(entry_variant.get("type", "")) == BUILD_TYPE_STAIRS_DOWN:
			return _entry_cell(entry_variant)
	for entry_variant in _get_floor_buildings(floor_index - 1):
		if not entry_variant is Dictionary:
			continue
		if SUPPORT_TYPES.has(str(entry_variant.get("type", ""))):
			return _entry_cell(entry_variant)
	return INVALID_CELL


func _load_state_from_active_slot() -> void:
	floors.clear()
	current_floor = 0
	var save_data := _read_active_save_data()
	var payload: Variant = save_data.get(SAVE_KEY, {})
	if not payload is Dictionary:
		return
	if int(payload.get("version", 0)) > SAVE_VERSION:
		push_warning("Multi-floor save data is newer than this build supports.")
		return
	var saved_floors: Variant = payload.get("floors", {})
	if saved_floors is Dictionary:
		for floor_key_variant in saved_floors.keys():
			var floor_entries: Variant = saved_floors[floor_key_variant]
			if floor_entries is Array:
				floors[str(floor_key_variant)] = floor_entries.duplicate(true)
	current_floor = clampi(int(payload.get("current_floor", 0)), 0, maximum_floor_count - 1)


func _save_state_to_active_slot() -> void:
	var save_path := _get_active_save_path()
	if save_path.is_empty():
		return
	var save_data := _read_active_save_data()
	var payload := {
		"version": SAVE_VERSION,
		"current_floor": current_floor,
		"floors": floors.duplicate(true),
	}
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
