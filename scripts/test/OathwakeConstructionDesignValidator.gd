extends SceneTree

const ArtContract := preload("res://scripts/buildings/ConstructionWallTopology.gd")
const ART_PATH := "res://data/world/construction_art_contract.json"
const ABSORPTION_PATH := "res://data/world/romestead_absorption_plan.json"


func _initialize() -> void:
	var failures: Array[String] = []
	var art := _read_json(ART_PATH, failures)
	var world_plan := _read_json(ABSORPTION_PATH, failures)
	if art.is_empty() or world_plan.is_empty():
		_finish(failures)
		return

	_validate_scale(art, failures)
	_validate_assets(art, failures)
	_validate_wall_grammar(art, failures)
	_validate_topology_code(failures)
	_validate_world_plan(world_plan, failures)

	if failures.is_empty():
		print("OATHWAKE_BUILD_DESIGN_OK character=25.5x60.5 wall_canvas=32x64 floor_subtile=16 wall_sprites=9 stairs=32x64/64x32 road=48 trail=32 masks=16")
	_finish(failures)


func _validate_scale(art: Dictionary, failures: Array[String]) -> void:
	var reference: Dictionary = art.get("reference_character", {})
	_expect(_pair(reference.get("idle_south_px", []), 25.5, 60.5), "Juno south idle reference drifted", failures)
	_expect(int(reference.get("design_height_reference_px", 0)) == 64, "character design reference must remain 64 px", failures)
	_expect(int(reference.get("ground_collision_diameter_px", 0)) == 24, "player ground collision contract must remain 24 px", failures)
	var grids: Dictionary = art.get("grids", {})
	_expect(_pair(grids.get("terrain_subtile_px", []), 16, 16), "terrain subtile must remain 16x16", failures)
	_expect(_pair(grids.get("construction_cell_px", []), 32, 32), "construction cell must remain 32x32", failures)


func _validate_assets(art: Dictionary, failures: Array[String]) -> void:
	var specs: Dictionary = art.get("asset_specs", {})
	_expect(_pair(_entry(specs, "floor_basic").get("authoring_subtile_px", []), 16, 16), "floor art must use 16 px subtiles", failures)
	_expect(int(_entry(specs, "floor_basic").get("minimum_authored_variants", 0)) >= 4, "floor needs at least four authored variants", failures)
	for wall_key in ["wall_horizontal", "wall_vertical", "wall_window_horizontal", "wall_window_vertical", "wall_doorway_horizontal", "wall_doorway_vertical"]:
		_expect(_pair(_entry(specs, wall_key).get("sprite_canvas_px", []), 32, 64), "%s canvas must remain 32x64" % wall_key, failures)
		_expect(_pair(_entry(specs, wall_key).get("build_footprint_px", []), 32, 32), "%s footprint must remain one 32x32 cell" % wall_key, failures)
	_expect(_pair(_entry(specs, "wall_joint_post").get("sprite_canvas_px", []), 16, 64), "joint post must remain 16x64", failures)
	_expect(_pair(_entry(specs, "door_leaf_horizontal").get("sprite_canvas_px", []), 32, 60), "horizontal door canvas must remain 32x60", failures)
	_expect(_pair(_entry(specs, "door_leaf_vertical").get("sprite_canvas_px", []), 32, 60), "vertical door canvas must remain 32x60", failures)
	_expect(_pair(_entry(specs, "stairs_north_south").get("build_footprint_cells", []), 1, 2), "north/south stairs must remain 1x2 cells", failures)
	_expect(_pair(_entry(specs, "stairs_north_south").get("sprite_canvas_px", []), 32, 64), "north/south stairs canvas must remain 32x64", failures)
	_expect(_pair(_entry(specs, "stairs_east_west").get("build_footprint_cells", []), 2, 1), "east/west stairs must remain 2x1 cells", failures)
	_expect(_pair(_entry(specs, "stairs_east_west").get("sprite_canvas_px", []), 64, 32), "east/west stairs canvas must remain 64x32", failures)


func _validate_wall_grammar(art: Dictionary, failures: Array[String]) -> void:
	var network: Dictionary = art.get("wall_network", {})
	_expect(str(network.get("visual_strategy", "")) == "contiguous_run_renderer", "wall renderer must remain run-based", failures)
	_expect(not bool(network.get("player_selects_orientation", true)), "player should not need separate H/V wall tools", failures)
	var burden: Dictionary = network.get("artist_burden", {})
	_expect(int(burden.get("required_wall_family_sprites", 0)) == 9, "wall family artist burden must remain nine required sprites", failures)
	var not_required: Variant = burden.get("not_required", [])
	_expect(not_required is Array and (not_required as Array).has("cross") and (not_required as Array).has("corner_NE"), "derived wall combinations must stay code-generated", failures)
	var readability: Dictionary = art.get("interior_readability", {})
	_expect(bool(readability.get("south_wall_cutaway", false)), "64 px walls require interior cutaway", failures)
	_expect(int(readability.get("cutaway_base_height_px", 0)) == 16, "wall cutaway base should remain one terrain subtile high", failures)


func _validate_topology_code(failures: Array[String]) -> void:
	var counts := {"isolated": 0, "end": 0, "straight": 0, "corner": 0, "tee": 0, "cross": 0}
	for mask in range(16):
		var kind := ArtContract.classify(mask)
		_expect(counts.has(kind), "unknown topology classification for mask %d" % mask, failures)
		if counts.has(kind):
			counts[kind] = int(counts[kind]) + 1
	_expect(int(counts["isolated"]) == 1, "there must be one isolated cardinal mask", failures)
	_expect(int(counts["end"]) == 4, "there must be four end masks", failures)
	_expect(int(counts["straight"]) == 2, "there must be two straight masks", failures)
	_expect(int(counts["corner"]) == 4, "there must be four corner masks", failures)
	_expect(int(counts["tee"]) == 4, "there must be four tee masks", failures)
	_expect(int(counts["cross"]) == 1, "there must be one cross mask", failures)
	_expect(ArtContract.infer_axis(ArtContract.EAST | ArtContract.WEST) == ArtContract.AXIS_EW, "EW straight axis inference failed", failures)
	_expect(ArtContract.infer_axis(ArtContract.NORTH | ArtContract.SOUTH) == ArtContract.AXIS_NS, "NS straight axis inference failed", failures)
	_expect(ArtContract.requires_joint_post(ArtContract.NORTH | ArtContract.EAST), "corner must request joint post", failures)
	_expect(not ArtContract.requires_joint_post(ArtContract.EAST | ArtContract.WEST), "straight run must not request joint post", failures)
	_expect(ArtContract.preferred_axis_from_drag(Vector2i(4, 1)) == ArtContract.AXIS_EW, "horizontal drag axis inference failed", failures)
	_expect(ArtContract.preferred_axis_from_drag(Vector2i(1, -4)) == ArtContract.AXIS_NS, "vertical drag axis inference failed", failures)


func _validate_world_plan(plan: Dictionary, failures: Array[String]) -> void:
	var inventory: Dictionary = plan.get("drive_inventory_summary", {})
	_expect(int(inventory.get("extracted_autotile_textures", 0)) >= 200, "Romestead autotile audit unexpectedly shrank", failures)
	var roads_contract: Dictionary = inventory.get("roads2_tiled_contract", {})
	_expect(_pair(roads_contract.get("tile_px", []), 16, 16), "Romestead roads2 reference must remain 16x16", failures)
	var priorities: Variant = plan.get("priority_now", [])
	var rural := _find_system(priorities, "rural_dirt_roads")
	_expect(not rural.is_empty(), "rural dirt road plan is missing", failures)
	var width: Dictionary = rural.get("width", {})
	_expect(int(width.get("main_road_px", 0)) == 48, "main rural road width should remain 48 px", failures)
	_expect(int(width.get("trail_px", 0)) == 32, "secondary trail width should remain 32 px", failures)


func _find_system(entries: Variant, system_name: String) -> Dictionary:
	if not entries is Array:
		return {}
	for value in entries as Array:
		if value is Dictionary and str((value as Dictionary).get("system", "")) == system_name:
			return value as Dictionary
	return {}


func _entry(specs: Dictionary, key: String) -> Dictionary:
	var value: Variant = specs.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _pair(value: Variant, first: float, second: float) -> bool:
	if not value is Array or (value as Array).size() < 2:
		return false
	return is_equal_approx(float((value as Array)[0]), first) and is_equal_approx(float((value as Array)[1]), second)


func _read_json(path: String, failures: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		failures.append("missing file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		failures.append("invalid JSON dictionary: %s" % path)
		return {}
	return parsed as Dictionary


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if not failures.is_empty():
		for failure in failures:
			push_error("OATHWAKE_BUILD_DESIGN_FAIL %s" % failure)
		quit(1)
		return
	quit(0)
