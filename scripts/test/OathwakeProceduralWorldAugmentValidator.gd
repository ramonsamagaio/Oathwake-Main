extends SceneTree

const AUGMENT_PATH := "res://scripts/systems/ProceduralWorldAugment.gd"
const ROMESTEAD_WORLD_PATH := "res://scripts/labs/romestead_systems/RomesteadBiomeWorld2D.gd"

func _initialize() -> void:
	var failures: Array[String] = []
	_expect(FileAccess.file_exists(AUGMENT_PATH), "missing procedural augment", failures)
	var augment := FileAccess.get_file_as_string(AUGMENT_PATH)
	_expect(augment.contains("WATER_SAFE_RADIUS_TILES := 52.0"), "spawn-water safety radius drifted", failures)
	_expect(augment.contains("WATER_RADIUS_FACTOR := 0.085"), "lake radius factor drifted", failures)
	_expect(augment.contains("ROAD_MAIN_WIDTH_TILES := 3"), "main road must remain 48 px", failures)
	_expect(augment.contains("ROAD_TRAIL_WIDTH_TILES := 2"), "trail must remain 32 px", failures)
	_expect(augment.contains("AStarGrid2D"), "roads must use terrain-cost pathfinding", failures)
	_expect(augment.contains("_make_road_astar") and augment.contains("_paint_costed_route(astar"), "road routes must reuse one weighted AStar grid", failures)
	_expect(augment.contains("_forest_barriers") and augment.contains("_plains_cliffs"), "road costs must account for native barriers and cliffs", failures)
	_expect(augment.contains("_cardinal_mask(_road_cells"), "road tiles must be selected from actual neighbour topology", failures)
	_expect(augment.contains("func _make_road_layer") and augment.contains("func _road_pixel_inside"), "road atlas must be generated as connected pixel-perfect topology", failures)
	_expect(augment.contains("func _make_water_layer"), "water variants must be generated at runtime", failures)
	_expect(augment.contains("_cardinal_mask(_water_cells"), "shoreline must derive from actual water neighbours", failures)
	_expect(augment.contains("transparent_edge") and augment.contains("SHORE_WET"), "water must expose a clean shoreline transition", failures)
	_expect(augment.contains("ProceduralGroundDetails") and augment.contains("_detail_density_for_biome"), "non-dark terrain must receive lightweight decorative detail", failures)
	_expect(augment.contains("BIOME_FOREST_DEEP") and augment.contains("return -1"), "deep grass should keep its existing authored detail instead of double-scattering", failures)
	_expect(augment.contains("ProceduralCliffFinish") and augment.contains("CLIFF_FACE_HEIGHT_TILES := 2"), "cliff feet must receive a grounding finish matched to the native two-tile face", failures)
	_expect(augment.contains("WATER_Z := -4088") and augment.contains("ROAD_Z := -4086"), "flat procedural layers must remain in the terrain z-band below depth-sorted actors", failures)
	var native := FileAccess.get_file_as_string(ROMESTEAD_WORLD_PATH)
	_expect(native.contains("radius := Vector2(world_size_tiles) * 0.375"), "Romestead key-biome ring scale drifted", failures)
	_expect(native.contains("if absf(corners[lake_index].x) < 0.33"), "Romestead lake keypoint constraint missing", failures)
	_expect(native.contains("if absf(_circular_index_difference(town_index, lake_index, 6)) > 1.0"), "Romestead town/lake adjacency constraint missing", failures)
	_expect(native.contains("spawn_distance / 0.1"), "Romestead spawn terrain safety shaping missing", failures)
	if failures.is_empty():
		print("OATHWAKE_WORLD_AUGMENT_OK water=topology_shore road=topology_48 trail=32 details=lightweight cliff_finish=true z_band=reserved costed=true")
		quit(0)
		return
	for failure in failures:
		push_error("OATHWAKE_WORLD_AUGMENT_FAIL %s" % failure)
	quit(1)

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
