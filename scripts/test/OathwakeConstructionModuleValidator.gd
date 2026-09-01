extends SceneTree

const CONFIG_PATH := "res://data/world/construction_module.json"
const PLAYER_SCENE_PATH := "res://scenes/Player.tscn"
const BUILD_SYSTEM_PATH := "res://scripts/BuildSystem.gd"
const BIOME_PATH := "res://scripts/labs/romestead_systems/RomesteadBiomeWorld2D.gd"
const BUILDINGS_PATH := "res://data/buildings.json"


func _init() -> void:
	var failures: Array[String] = []
	var config := _read_json(CONFIG_PATH, failures)
	if config.is_empty():
		_finish(failures)
		return

	var grid := int(config.get("grid_px", 0))
	_expect(grid == 16, "grid must remain 16 px", failures)

	var construction: Dictionary = config.get("construction", {})
	var player_config: Dictionary = config.get("player", {})
	var wall_module := int(construction.get("wall_module_px", 0))
	var door_opening := int(construction.get("door_opening_px", 0))
	var minimum_walkable := int(construction.get("minimum_walkable_width_px", 0))
	_expect(wall_module == grid, "wall module must equal one grid cell", failures)
	_expect(door_opening % grid == 0 and door_opening >= grid * 2, "door opening must be at least two grid cells", failures)
	_expect(minimum_walkable >= door_opening, "walkable width must not be narrower than the door contract", failures)

	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	_expect(player_scene != null, "Player.tscn must load", failures)
	var player_radius := -1.0
	if player_scene != null:
		var player := player_scene.instantiate()
		var collision := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision != null and collision.shape is CircleShape2D:
			player_radius = (collision.shape as CircleShape2D).radius
		else:
			failures.append("Player collision must remain CircleShape2D")
		player.free()
	_expect(is_equal_approx(player_radius, float(player_config.get("collision_radius_px", -2))), "player collision radius drifted from construction contract", failures)
	var player_diameter := player_radius * 2.0
	_expect(float(door_opening) - player_diameter >= 8.0, "door needs at least 8 px total collision clearance", failures)

	var build_source := _read_text(BUILD_SYSTEM_PATH, failures)
	_expect(build_source.contains("grid_size: int = 16"), "BuildSystem grid_size is no longer 16", failures)
	var biome_source := _read_text(BIOME_PATH, failures)
	_expect(biome_source.contains("tile_size := 16"), "Romestead biome tile_size is no longer 16", failures)

	var buildings := _read_json_array(BUILDINGS_PATH, failures)
	for entry_value in buildings:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var size_value: Variant = entry.get("size", [])
		if not size_value is Array or (size_value as Array).size() < 2:
			failures.append("building %s has invalid size" % str(entry.get("id", "?")))
			continue
		var size := size_value as Array
		var width := int(size[0])
		var height := int(size[1])
		_expect(width % grid == 0 and height % grid == 0, "building %s is off the 16 px construction grid" % str(entry.get("id", "?")), failures)

	var asset_audit: Dictionary = config.get("asset_audit", {})
	var forest_barrier := str(asset_audit.get("romestead_forest_barrier", ""))
	_expect(not forest_barrier.is_empty() and ResourceLoader.exists(forest_barrier), "Romestead forest barrier source is missing", failures)
	_expect(not bool(asset_audit.get("romestead_forest_barrier_is_building_wall", true)), "tree_wall.png must not be classified as a building wall", failures)
	var decorative_house := str(asset_audit.get("decorative_house_not_consumed_by_build_system", ""))
	_expect(not decorative_house.is_empty() and ResourceLoader.exists(decorative_house), "audited decorative house asset is missing", failures)
	_expect(asset_audit.get("romestead_dedicated_building_wall_asset", "sentinel") == null, "Romestead wall audit must be explicit null until a dedicated kit exists", failures)
	_expect(asset_audit.get("romestead_dedicated_door_asset", "sentinel") == null, "Romestead door audit must be explicit null until a dedicated kit exists", failures)
	_expect(asset_audit.get("alabaster_dedicated_building_wall_asset", "sentinel") == null, "Alabaster wall audit must be explicit null until a dedicated kit exists", failures)
	_expect(asset_audit.get("alabaster_dedicated_door_asset", "sentinel") == null, "Alabaster door audit must be explicit null until a dedicated kit exists", failures)

	if failures.is_empty():
		print("OATHWAKE_CONSTRUCTION_AUDIT_OK grid=%d player_diameter=%.0f door=%d wall_module=%d buildings=%d romestead_wall=procedural alabaster_wall=none" % [grid, player_diameter, door_opening, wall_module, buildings.size()])
	_finish(failures)


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


func _read_json_array(path: String, failures: Array[String]) -> Array:
	var text := _read_text(path, failures)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Array:
		failures.append("invalid array JSON: %s" % path)
		return []
	return parsed as Array


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
