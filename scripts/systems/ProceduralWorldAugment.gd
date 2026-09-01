extends Node

const TILE_SIZE := 16
const WATER_BIOME := 0
const WATER_SAFE_RADIUS_TILES := 52.0
const WATER_RADIUS_FACTOR := 0.085
const ROAD_MAIN_HALF_WIDTH := 1
const ROAD_TRAIL_HALF_WIDTH := 0

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
	var world := get_tree().get_first_node_in_group("procedural_resource_world")
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
	_water_layer = _make_layer("ProceduralWater", -8, Color("#406F83"), Color("#4A7D8FFF"), true)
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
			var spawn_distance := grid.distance_to(center_grid)
			if spawn_distance < WATER_SAFE_RADIUS_TILES:
				continue
			var edge_noise := _hash_noise(x, y, int(_attached_world.get("world_seed"))) * 2.8
			if grid.distance_to(lake_center) > radius + edge_noise:
				continue
			var cell := start + Vector2i(x, y)
			_water_cells[cell] = true
			biomes[cell] = WATER_BIOME
			_water_layer.set_cell(cell, 0, Vector2i(posmod(x + y, 2), posmod(x * 3 + y, 2)), 0)
	_attached_world.set("_biomes", biomes)

func _build_semantic_roads() -> void:
	_road_layer = _make_layer("ProceduralRoads", -7, Color("#78634A"), Color("#8A7252FF"), false)
	_attached_world.add_child(_road_layer)
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	var start := Vector2i(-size.x / 2, -size.y / 2)
	var spawn_grid := Vector2(size) * 0.5
	var town_grid: Vector2 = _attached_world.get("_town_center_grid")
	var forest_grid: Vector2 = _attached_world.get("_forest_center_grid")
	var lake_grid: Vector2 = _attached_world.get("_lake_center_grid")
	_paint_route(start, spawn_grid, town_grid, ROAD_MAIN_HALF_WIDTH)
	_paint_route(start, town_grid, forest_grid, ROAD_MAIN_HALF_WIDTH)
	var lake_vector := (lake_grid - town_grid)
	var lake_edge := lake_grid - lake_vector.normalized() * float(size.x) * (WATER_RADIUS_FACTOR + 0.035)
	_paint_route(start, town_grid, lake_edge, ROAD_TRAIL_HALF_WIDTH)

func _paint_route(start: Vector2i, from_grid: Vector2, to_grid: Vector2, half_width: int) -> void:
	var delta := to_grid - from_grid
	var steps := maxi(1, ceili(delta.length() * 1.35))
	for index in range(steps + 1):
		var t := float(index) / float(steps)
		var grid := from_grid.lerp(to_grid, t)
		var bend := sin(t * PI) * sin(t * 7.3 + float(_attached_world.get("world_seed") % 19)) * 1.8
		var normal := Vector2(-delta.y, delta.x).normalized()
		grid += normal * bend
		var center_cell := start + Vector2i(roundi(grid.x), roundi(grid.y))
		for oy in range(-half_width, half_width + 1):
			for ox in range(-half_width, half_width + 1):
				var cell := center_cell + Vector2i(ox, oy)
				if _water_cells.has(cell):
					continue
				_road_cells[cell] = true
				_road_layer.set_cell(cell, 0, Vector2i(posmod(cell.x, 2), posmod(cell.y, 2)), 0)

func _make_layer(name_value: String, z_value: int, first: Color, second: Color, collision: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name_value
	layer.z_index = z_value
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var image := Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE * 2):
		for x in range(TILE_SIZE * 2):
			var checker := ((x / 4) + (y / 4)) % 2 == 0
			image.set_pixel(x, y, first if checker else second)
	var texture := ImageTexture.create_from_image(image)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	if collision:
		tile_set.add_physics_layer()
		tile_set.set_physics_layer_collision_layer(0, 1)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(atlas, 0)
	for y in range(2):
		for x in range(2):
			var coord := Vector2i(x, y)
			atlas.create_tile(coord)
			if collision:
				var data := atlas.get_tile_data(coord, 0)
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-8,-8), Vector2(8,-8), Vector2(8,8), Vector2(-8,8)]))
	layer.tile_set = tile_set
	return layer

func _prune_generated_entities() -> void:
	var resources := _attached_world.get_node_or_null("../Resources")
	if resources == null:
		resources = _attached_world.get_node_or_null("Resources")
	if resources != null:
		for child in resources.get_children():
			if not child is Node2D:
				continue
			var cell := _world_to_cell((child as Node2D).global_position)
			if _water_cells.has(cell) or _road_cells.has(cell):
				child.queue_free()
	var wildlife := _attached_world.get_node_or_null("../Enemies")
	if wildlife == null:
		wildlife = _attached_world.get_node_or_null("Enemies")
	if wildlife != null:
		for child in wildlife.get_children():
			if child is Node2D and _water_cells.has(_world_to_cell((child as Node2D).global_position)):
				child.queue_free()

func _world_to_cell(world_position: Vector2) -> Vector2i:
	var local := _attached_world.to_local(world_position)
	return Vector2i(roundi(local.x / TILE_SIZE), roundi(local.y / TILE_SIZE))

func _clear_layers() -> void:
	_water_cells.clear()
	_road_cells.clear()
	for node in [_water_layer, _road_layer]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_water_layer = null
	_road_layer = null

func _update_layers() -> void:
	if _water_layer != null: _water_layer.update_internals()
	if _road_layer != null: _road_layer.update_internals()

func _get_dictionary(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value if value is Dictionary else {}

func _hash_noise(x: int, y: int, seed: int) -> float:
	var n := x * 374761393 + y * 668265263 + seed * 69069
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(posmod(n, 10000)) / 9999.0 - 0.5
