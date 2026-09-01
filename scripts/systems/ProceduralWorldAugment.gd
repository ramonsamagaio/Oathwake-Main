extends Node

const TILE_SIZE := 16
const WATER_BIOME := 0
const BIOME_MEADOW := 2
const BIOME_FOREST := 3
const BIOME_SWAMP := 4
const BIOME_DRY := 5
const BIOME_FOREST_LIGHT := 6
const BIOME_FOREST_DEEP := 7
const WATER_SAFE_RADIUS_TILES := 52.0
const WATER_RADIUS_FACTOR := 0.085
const ROAD_MAIN_WIDTH_TILES := 3
const ROAD_TRAIL_WIDTH_TILES := 2
const WATER_TEXTURE_PATH := "res://assets/sprites/world/procedural/terrain/romestead_water.png"
const ROAD_TEXTURE_PATH := "res://assets/sprites/world/romestead_reference/dirt_road_source.png"
const CARDINAL := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _attached_world: Node
var _water_layer: TileMapLayer
var _road_layer: TileMapLayer
var _water_cells: Dictionary = {}
var _road_cells: Dictionary = {}

func _ready() -> void:
	process_priority = 850
	call_deferred("_try_attach")

func _process(_delta: float) -> void:
	if _attached_world == null or not is_instance_valid(_attached_world):
		_try_attach()

func _try_attach() -> void:
	var world: Node = get_tree().get_first_node_in_group("procedural_resource_world")
	if world == null or world == _attached_world:
		return
	_attached_world = world
	if world.has_signal("world_generated"):
		var callback := Callable(self, "_on_world_generated")
		if not world.is_connected("world_generated", callback):
			world.connect("world_generated", callback)
	if not _get_dictionary(world, "_biomes").is_empty():
		call_deferred("_augment_world")

func _on_world_generated(_seed: int, _counts: Dictionary) -> void:
	call_deferred("_augment_world")

func _augment_world() -> void:
	if _attached_world == null or not is_instance_valid(_attached_world):
		return
	_clear_layers()
	_build_water()
	_build_semantic_roads()
	_prune_generated_entities()
	_update_layers()

func _build_water() -> void:
	_water_layer = _make_source_layer("ProceduralWater", -8, WATER_TEXTURE_PATH, true)
	if _water_layer == null:
		return
	_water_layer.modulate = Color(0.34, 0.68, 0.78, 0.94)
	_attached_world.add_child(_water_layer)
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	var start := Vector2i(-size.x / 2, -size.y / 2)
	var center_grid := Vector2(size) * 0.5
	var lake_center: Vector2 = _attached_world.get("_lake_center_grid")
	var radius := float(size.x) * WATER_RADIUS_FACTOR
	var biomes := _get_dictionary(_attached_world, "_biomes")
	for y in range(size.y):
		for x in range(size.x):
			var grid := Vector2(x, y)
			if grid.distance_to(center_grid) < WATER_SAFE_RADIUS_TILES:
				continue
			var edge_noise := _hash_noise(x, y, int(_attached_world.get("world_seed"))) * 2.8
			if grid.distance_to(lake_center) > radius + edge_noise:
				continue
			var cell := start + Vector2i(x, y)
			_water_cells[cell] = true
			biomes[cell] = WATER_BIOME
			var variant := _texture_variant(cell, 16, 16, 0xA71E)
			_water_layer.set_cell(cell, 0, variant, 0)
	_attached_world.set("_biomes", biomes)

func _build_semantic_roads() -> void:
	_road_layer = _make_source_layer("ProceduralRoads", -7, ROAD_TEXTURE_PATH, false)
	if _road_layer == null:
		return
	_attached_world.add_child(_road_layer)
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	var start := Vector2i(-size.x / 2, -size.y / 2)
	var spawn_cell := Vector2i.ZERO
	var town_cell := _grid_to_world_cell(Vector2(_attached_world.get("_town_center_grid")), start)
	var forest_cell := _grid_to_world_cell(Vector2(_attached_world.get("_forest_center_grid")), start)
	var lake_grid: Vector2 = _attached_world.get("_lake_center_grid")
	var town_grid: Vector2 = _attached_world.get("_town_center_grid")
	var lake_vector := lake_grid - town_grid
	var lake_edge_grid := lake_grid - lake_vector.normalized() * float(size.x) * (WATER_RADIUS_FACTOR + 0.035)
	var lake_edge_cell := _grid_to_world_cell(lake_edge_grid, start)
	_paint_costed_route(spawn_cell, town_cell, ROAD_MAIN_WIDTH_TILES)
	_paint_costed_route(town_cell, forest_cell, ROAD_MAIN_WIDTH_TILES)
	_paint_costed_route(town_cell, lake_edge_cell, ROAD_TRAIL_WIDTH_TILES)

func _paint_costed_route(from_cell: Vector2i, to_cell: Vector2i, width_tiles: int) -> void:
	var path := _find_costed_path(from_cell, to_cell)
	if path.is_empty():
		return
	for path_cell in path:
		_paint_road_cross_section(path_cell, width_tiles)

func _find_costed_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	var start := Vector2i(-size.x / 2, -size.y / 2)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(start, size)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	var biomes := _get_dictionary(_attached_world, "_biomes")
	var barriers := _get_dictionary(_attached_world, "_forest_barriers")
	var cliffs := _get_dictionary(_attached_world, "_plains_cliffs")
	for y in range(start.y, start.y + size.y):
		for x in range(start.x, start.x + size.x):
			var cell := Vector2i(x, y)
			if _water_cells.has(cell):
				astar.set_point_solid(cell, true)
				continue
			var weight := _road_weight_for_biome(int(biomes.get(cell, BIOME_DRY)))
			if barriers.has(cell):
				weight += 14.0
			if cliffs.has(cell):
				weight += 24.0
			astar.set_point_weight_scale(cell, weight)
	if not astar.is_in_boundsv(from_cell) or not astar.is_in_boundsv(to_cell):
		return []
	if astar.is_point_solid(from_cell) or astar.is_point_solid(to_cell):
		return []
	var raw: PackedVector2Array = astar.get_id_path(from_cell, to_cell)
	var result: Array[Vector2i] = []
	for point in raw:
		result.append(Vector2i(point))
	return result

func _road_weight_for_biome(biome: int) -> float:
	match biome:
		BIOME_MEADOW:
			return 1.0
		BIOME_DRY:
			return 1.15
		BIOME_FOREST_LIGHT:
			return 1.8
		BIOME_FOREST:
			return 3.2
		BIOME_FOREST_DEEP:
			return 5.5
		BIOME_SWAMP:
			return 7.0
		_:
			return 1.5

func _paint_road_cross_section(center: Vector2i, width_tiles: int) -> void:
	var offsets: Array[Vector2i] = [Vector2i.ZERO]
	if width_tiles >= 2:
		offsets.append(Vector2i.RIGHT if posmod(center.x + center.y, 2) == 0 else Vector2i.DOWN)
	if width_tiles >= 3:
		offsets.append(Vector2i.LEFT)
	for offset in offsets:
		var cell := center + offset
		if _water_cells.has(cell):
			continue
		_road_cells[cell] = true
		var variant_pool: Array[Vector2i] = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)]
		var index := posmod(_cell_seed(cell, 0xD17A), variant_pool.size())
		_road_layer.set_cell(cell, 0, variant_pool[index], 0)

func _make_source_layer(name_value: String, z_value: int, texture_path: String, collision: bool) -> TileMapLayer:
	var texture := _load_png_texture(texture_path)
	if texture == null:
		push_warning("ProceduralWorldAugment missing or invalid PNG texture: %s" % texture_path)
		return null
	var layer := TileMapLayer.new()
	layer.name = name_value
	layer.z_index = z_value
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	if collision:
		tile_set.add_physics_layer()
		tile_set.set_physics_layer_collision_layer(0, 1)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(atlas, 0)
	var columns: int = texture.get_width() / TILE_SIZE
	var rows: int = texture.get_height() / TILE_SIZE
	for y in range(rows):
		for x in range(columns):
			var coord := Vector2i(x, y)
			atlas.create_tile(coord)
			if collision:
				var data := atlas.get_tile_data(coord, 0)
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-8,-8), Vector2(8,-8), Vector2(8,8), Vector2(-8,8)]))
	layer.tile_set = tile_set
	return layer

func _load_png_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _prune_generated_entities() -> void:
	var resources: Node = _attached_world.get_node_or_null("../Resources")
	if resources == null:
		resources = _attached_world.get_node_or_null("Resources")
	if resources != null:
		for child in resources.get_children():
			if not child is Node2D:
				continue
			var cell := _world_to_cell((child as Node2D).global_position)
			if _water_cells.has(cell) or _is_near_road(cell, 1):
				child.queue_free()
	var wildlife: Node = _attached_world.get_node_or_null("../Enemies")
	if wildlife == null:
		wildlife = _attached_world.get_node_or_null("Enemies")
	if wildlife != null:
		for child in wildlife.get_children():
			if child is Node2D and _water_cells.has(_world_to_cell((child as Node2D).global_position)):
				child.queue_free()

func _is_near_road(cell: Vector2i, clearance: int) -> bool:
	for y in range(-clearance, clearance + 1):
		for x in range(-clearance, clearance + 1):
			if _road_cells.has(cell + Vector2i(x, y)):
				return true
	return false

func _world_to_cell(world_position: Vector2) -> Vector2i:
	var world_node := _attached_world as Node2D
	if world_node == null:
		return Vector2i.ZERO
	var local_position: Vector2 = world_node.to_local(world_position)
	return Vector2i(roundi(local_position.x / TILE_SIZE), roundi(local_position.y / TILE_SIZE))

func _grid_to_world_cell(grid: Vector2, start: Vector2i) -> Vector2i:
	return start + Vector2i(roundi(grid.x), roundi(grid.y))

func _texture_variant(cell: Vector2i, columns: int, rows: int, salt: int) -> Vector2i:
	var seed := _cell_seed(cell, salt)
	return Vector2i(posmod(seed, columns), posmod(seed / maxi(columns, 1), rows))

func _clear_layers() -> void:
	_water_cells.clear()
	_road_cells.clear()
	for node in [_water_layer, _road_layer]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_water_layer = null
	_road_layer = null

func _update_layers() -> void:
	if _water_layer != null:
		_water_layer.update_internals()
	if _road_layer != null:
		_road_layer.update_internals()

func _get_dictionary(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value if value is Dictionary else {}

func _cell_seed(cell: Vector2i, salt: int) -> int:
	var world_seed := int(_attached_world.get("world_seed")) if _attached_world != null else 0
	var mixed := world_seed ^ salt
	mixed ^= cell.x * 73856093
	mixed ^= cell.y * 19349663
	return absi(mixed)

func _hash_noise(x: int, y: int, seed: int) -> float:
	var n := x * 374761393 + y * 668265263 + seed * 69069
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(posmod(n, 10000)) / 9999.0 - 0.5
