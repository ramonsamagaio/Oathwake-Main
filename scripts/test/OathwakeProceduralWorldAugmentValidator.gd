extends SceneTree

const AUGMENT_PATH := "res://scripts/systems/ProceduralWorldAugment.gd"
const ROMESTEAD_WORLD_PATH := "res://scripts/labs/romestead_systems/RomesteadBiomeWorld2D.gd"
const ROAD_PATH := "res://assets/sprites/world/romestead_reference/dirt_road_source.png"

func _initialize() -> void:
	var failures: Array[String] = []
	_expect(FileAccess.file_exists(AUGMENT_PATH), "missing procedural augment", failures)
	_expect(FileAccess.file_exists(ROAD_PATH), "missing curated Romestead dirt road source", failures)
	var road := _load_png(ROAD_PATH)
	_expect(road != null and road.get_size() == Vector2i(96, 96), "Romestead dirt-road source must remain 96x96", failures)
	var augment := FileAccess.get_file_as_string(AUGMENT_PATH)
	_expect(augment.contains("WATER_SAFE_RADIUS_TILES := 52.0"), "spawn-water safety radius drifted", failures)
	_expect(augment.contains("WATER_RADIUS_FACTOR := 0.085"), "lake radius factor drifted", failures)
	_expect(augment.contains("ROAD_MAIN_WIDTH_TILES := 3"), "main road must remain 48 px", failures)
	_expect(augment.contains("ROAD_TRAIL_WIDTH_TILES := 2"), "trail must remain 32 px", failures)
	_expect(augment.contains("AStarGrid2D"), "roads must use terrain-cost pathfinding", failures)
	_expect(augment.contains("_forest_barriers") and augment.contains("_plains_cliffs"), "road costs must account for native barriers and cliffs", failures)
	_expect(augment.contains("func _make_water_layer"), "water variants must be generated at runtime", failures)
	_expect(augment.contains("Image.create(TILE_SIZE * 4, TILE_SIZE * 4"), "water must keep its clean 4x4 native-tile variation family", failures)
	_expect(augment.contains("_load_png_texture"), "road runtime must not depend on imported PNG cache", failures)
	var native := FileAccess.get_file_as_string(ROMESTEAD_WORLD_PATH)
	_expect(native.contains("radius := Vector2(world_size_tiles) * 0.375"), "Romestead key-biome ring scale drifted", failures)
	_expect(native.contains("if absf(corners[lake_index].x) < 0.33"), "Romestead lake keypoint constraint missing", failures)
	_expect(native.contains("if absf(_circular_index_difference(town_index, lake_index, 6)) > 1.0"), "Romestead town/lake adjacency constraint missing", failures)
	_expect(native.contains("spawn_distance / 0.1"), "Romestead spawn terrain safety shaping missing", failures)
	if failures.is_empty():
		print("OATHWAKE_WORLD_AUGMENT_OK water=generated_4x4 safe_radius=52 lake_factor=0.085 road=48 trail=32 costed=true native_key_ring=0.375")
		quit(0)
		return
	for failure in failures:
		push_error("OATHWAKE_WORLD_AUGMENT_FAIL %s" % failure)
	quit(1)

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
