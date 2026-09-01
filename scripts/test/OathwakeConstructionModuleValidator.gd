extends SceneTree

const CONFIG_PATH := "res://data/world/construction_module.json"
const PLAYER_SCENE_PATH := "res://scenes/Player.tscn"
const BUILD_SYSTEM_PATH := "res://scripts/BuildSystem.gd"
const BIOME_PATH := "res://scripts/labs/romestead_systems/RomesteadBiomeWorld2D.gd"
const BUILDINGS_PATH := "res://data/buildings.json"
const DOOR_RUNTIME_PATH := "res://scripts/buildings/Door.gd"


func _init() -> void:
	var failures: Array[String] = []
	var config: Dictionary = _read_json(CONFIG_PATH, failures)
	if config.is_empty():
		_finish(failures)
		return

	var terrain_grid := int(config.get("terrain_grid_px", 0))
	var construction_grid := int(config.get("construction_grid_px", 0))
	_expect(terrain_grid == 16, "Romestead terrain grid must remain 16 px", failures)
	_expect(construction_grid == 32, "BuildSystem construction grid must remain 32 px", failures)
	_expect(construction_grid == terrain_grid * 2, "construction grid must remain exactly two Romestead terrain tiles", failures)

	var construction: Dictionary = config.get("construction", {})
	var player_config: Dictionary = config.get("player", {})
	var wall_footprint: Array = construction.get("wall_footprint_px", []) as Array
	var door_cell: Array = construction.get("door_placement_cell_px", []) as Array
	var door_collision: Array = construction.get("door_closed_collision_px", []) as Array
	_expect(_array_pair_equals(wall_footprint, construction_grid, construction_grid), "wall footprint contract must be one 32x32 construction cell", failures)
	_expect(_array_pair_equals(door_cell, construction_grid, construction_grid), "door placement contract must be one 32x32 construction cell", failures)
	_expect(_array_pair_equals(door_collision, 12, 30), "closed door collision contract must remain 12x30", failures)

	var player_radius := float(player_config.get("collision_radius_px", -1.0))
	var player_diameter := float(player_config.get("collision_diameter_px", -1.0))
	_expect(is_equal_approx(player_radius * 2.0, player_diameter), "player diameter must equal twice its radius", failures)
	var player_source := _read_text(PLAYER_SCENE_PATH, failures)
	_expect(player_source.contains("radius = 12.0"), "Player.tscn collision radius drifted from 12 px", failures)
	var open_clear_width := int(construction.get("open_door_clear_width_px", 0))
	var expected_clearance := int(construction.get("open_door_clearance_over_player_px", -1))
	_expect(open_clear_width == construction_grid, "open door clear width must equal one construction cell", failures)
	_expect(open_clear_width - int(player_diameter) == expected_clearance, "open-door/player clearance contract is inconsistent", failures)
	_expect(expected_clearance >= 8, "open door must keep at least 8 px total clearance over player collision", failures)

	var build_source := _read_text(BUILD_SYSTEM_PATH, failures)
	_expect(build_source.contains("tile_size: Vector2i = Vector2i(32, 32)"), "BuildSystem default tile size is no longer 32x32", failures)
	var biome_source := _read_text(BIOME_PATH, failures)
	_expect(biome_source.contains("tile_size := 16"), "Romestead biome tile_size is no longer 16", failures)

	var buildings: Dictionary = _read_json(BUILDINGS_PATH, failures)
	var wall: Dictionary = buildings.get("wall", {})
	var door: Dictionary = buildings.get("door", {})
	_expect(not wall.is_empty(), "wall building definition is missing", failures)
	_expect(not door.is_empty(), "door building definition is missing", failures)
	_validate_collision_size(wall, 32, 32, "wall", failures)
	_validate_collision_size(door, 12, 30, "door", failures)
	_expect(str(door.get("scene_path", "")) == "res://scenes/buildings/Door.tscn", "door must keep its dedicated runtime scene", failures)
	var door_runtime := _read_text(DOOR_RUNTIME_PATH, failures)
	_expect(door_runtime.contains("collision_shape.disabled = is_open"), "Door.gd must disable collision when open", failures)

	var room_px: Array = construction.get("recommended_room_module_px", []) as Array
	var room_cells: Array = construction.get("recommended_room_module_cells", []) as Array
	_expect(_array_pair_equals(room_px, 128, 96), "recommended room module must remain 128x96", failures)
	_expect(_array_pair_equals(room_cells, 4, 3), "recommended room module must remain 4x3 construction cells", failures)
	if room_px.size() >= 2 and room_cells.size() >= 2:
		_expect(int(room_px[0]) == int(room_cells[0]) * construction_grid and int(room_px[1]) == int(room_cells[1]) * construction_grid, "recommended room dimensions do not match construction grid", failures)

	var asset_audit: Dictionary = config.get("asset_audit", {})
	var forest_barrier := str(asset_audit.get("romestead_forest_barrier", ""))
	_expect(not forest_barrier.is_empty() and FileAccess.file_exists(forest_barrier), "Romestead forest barrier source is missing", failures)
	_expect(not bool(asset_audit.get("romestead_forest_barrier_is_building_wall", true)), "tree_wall.png must not be classified as a building wall", failures)
	var decorative_house := str(asset_audit.get("decorative_house_not_consumed_by_build_system", ""))
	_expect(not decorative_house.is_empty() and FileAccess.file_exists(decorative_house), "audited decorative house asset is missing", failures)
	_expect(asset_audit.get("romestead_dedicated_building_wall_asset", "sentinel") == null, "Romestead wall audit must remain explicit null until a dedicated kit exists", failures)
	_expect(asset_audit.get("romestead_dedicated_door_asset", "sentinel") == null, "Romestead door audit must remain explicit null until a dedicated kit exists", failures)
	_expect(asset_audit.get("alabaster_dedicated_building_wall_asset", "sentinel") == null, "Alabaster wall audit must remain explicit null until a dedicated kit exists", failures)
	_expect(asset_audit.get("alabaster_dedicated_door_asset", "sentinel") == null, "Alabaster door audit must remain explicit null until a dedicated kit exists", failures)

	if failures.is_empty():
		print("OATHWAKE_CONSTRUCTION_AUDIT_OK terrain_grid=%d construction_grid=%d player_diameter=%.0f open_door=%d wall=32x32 door_collision=12x30 room=128x96 romestead_building_kit=none alabaster_building_kit=none" % [terrain_grid, construction_grid, player_diameter, open_clear_width])
	_finish(failures)


func _validate_collision_size(entry: Dictionary, width: int, height: int, label: String, failures: Array[String]) -> void:
	var collision_value: Variant = entry.get("collision", {})
	if not collision_value is Dictionary:
		failures.append("%s collision definition is invalid" % label)
		return
	var collision := collision_value as Dictionary
	var size_value: Variant = collision.get("size", {})
	if not size_value is Dictionary:
		failures.append("%s collision size is invalid" % label)
		return
	var size := size_value as Dictionary
	_expect(int(size.get("w", -1)) == width and int(size.get("h", -1)) == height, "%s collision must remain %dx%d" % [label, width, height], failures)


func _array_pair_equals(value: Array, first: int, second: int) -> bool:
	return value.size() >= 2 and int(value[0]) == first and int(value[1]) == second


func _read_text(path: String, failures: Array[String]) -> String:
	if not FileAccess.file_exists(path):
		failures.append("missing file: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func _read_json(path: String, failures: Array[String]) -> Dictionary:
	var text := _read_text(path, failures)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		failures.append("invalid dictionary JSON: %s" % path)
		return {}
	return parsed as Dictionary


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error("OATHWAKE_CONSTRUCTION_AUDIT_FAIL %s" % failure)
		quit(1)
		return
	quit(0)
