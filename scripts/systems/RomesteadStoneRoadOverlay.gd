extends Node
## Builds the playable road network using the native Romestead stone-road sheets.
## Roads are semantic overlays only: coastline/water remain owned by the world generator.

const TILE_SIZE := 16
const BIOME_WATER := 0
const BIOME_DIRT := 1
const BIOME_MEADOW := 2
const BIOME_FOREST := 3
const BIOME_SWAMP := 4
const BIOME_DRY := 5
const BIOME_FOREST_LIGHT := 6
const BIOME_FOREST_DEEP := 7

const ROAD_Z := -4086
# Romestead roads are broad enough to read, but they are corridors, not terrain blobs.
const ROAD_MAIN_RADIUS_TILES := 2
const ROAD_TRAIL_RADIUS_TILES := 1
const TOWN_GREY_RADIUS_TILES := 14.0
const WATER_RADIUS_FACTOR := 0.085

const COBBLE_ROAD_PATH := "res://assets/world_lab/romestead_native_png/sources/floors/cobblestone_road_tileset.png"
const GREY_ROAD_PATH := "res://assets/world_lab/romestead_native_png/sources/floors/brick_light_grey_road_tileset.png"

var _attached_world: Node
var _beige_layer: TileMapLayer
var _grey_layer: TileMapLayer
var _road_cells: Dictionary = {}
var _water_cells: Dictionary = {}
var _rebuild_serial := 0


func _ready() -> void:
	process_priority = 930
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
	_schedule_rebuild()


func _on_world_generated(_seed: int, _counts: Dictionary) -> void:
	_schedule_rebuild()


func _schedule_rebuild() -> void:
	_rebuild_serial += 1
	var serial := _rebuild_serial
	_rebuild_after_augments(serial)


func _rebuild_after_augments(serial: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if serial != _rebuild_serial:
		return
	_rebuild_roads()


func _rebuild_roads() -> void:
	if _attached_world == null or not is_instance_valid(_attached_world):
		return
	_clear_layers()
	_collect_water_cells()
	_build_semantic_road_mask()
	if _road_cells.is_empty():
		return

	var beige_texture := load(COBBLE_ROAD_PATH) as Texture2D
	var grey_texture := load(GREY_ROAD_PATH) as Texture2D
	if beige_texture == null or grey_texture == null:
		push_warning("RomesteadStoneRoadOverlay: native Romestead road textures are missing.")
		return

	_beige_layer = _make_native_road_layer("RomesteadStoneRoads", beige_texture)
	_grey_layer = _make_native_road_layer("RomesteadGreyStoneRoads", grey_texture)
	if _beige_layer == null or _grey_layer == null:
		return
	_attached_world.add_child(_beige_layer)
	_attached_world.add_child(_grey_layer)

	var town_cell := _town_cell()
	for value in _road_cells.keys():
		var cell := Vector2i(value)
		var layer := _road_layer_for_cell(cell, town_cell)
		var variant := posmod(_cell_seed(cell, 0xC0BB1E), 8)
		layer.set_cell(cell, 0, Vector2i(variant % 4, 6 + variant / 4), 0)

	# Only one tile of authored transition around the core. This is what gives
	# the road its broken-stone silhouette without letting three routes merge
	# into the giant beige polygon that appeared in the playtest screenshot.
	var fringe := _build_road_fringe()
	for value in fringe.keys():
		var cell := Vector2i(value)
		if not _road_cell_allowed(cell):
			continue
		var coord := _native_fringe_coord(_road_cells, cell)
		if coord.x < 0:
			continue
		var layer := _road_layer_for_cell(cell, town_cell)
		layer.set_cell(cell, 0, coord, 0)

	_hide_previous_road_visuals()
	_prune_resources_from_roads()
	_beige_layer.update_internals()
	_grey_layer.update_internals()


func _collect_water_cells() -> void:
	_water_cells.clear()
	var augment := get_node_or_null("/root/ProceduralWorldAugment")
	if augment != null:
		var augment_water: Variant = augment.get("_water_cells")
		if augment_water is Dictionary:
			_water_cells = (augment_water as Dictionary).duplicate()
	var biomes := _dict_property(_attached_world, "_biomes")
	for value in biomes.keys():
		if value is Vector2i and int(biomes.get(value, -1)) == BIOME_WATER:
			_water_cells[value] = true


func _build_semantic_road_mask() -> void:
	_road_cells.clear()
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	if size.x <= 0 or size.y <= 0:
		return
	var start := Vector2i(-size.x / 2, -size.y / 2)
	var spawn_cell := Vector2i.ZERO
	var town_cell := _grid_to_world_cell(Vector2(_attached_world.get("_town_center_grid")), start)
	var forest_cell := _grid_to_world_cell(Vector2(_attached_world.get("_forest_center_grid")), start)
	var lake_grid := Vector2(_attached_world.get("_lake_center_grid"))
	var town_grid := Vector2(_attached_world.get("_town_center_grid"))
	var lake_vector := lake_grid - town_grid
	var lake_edge_grid := lake_grid
	if lake_vector.length_squared() > 0.001:
		lake_edge_grid = lake_grid - lake_vector.normalized() * float(size.x) * (WATER_RADIUS_FACTOR + 0.035)
	var lake_edge_cell := _grid_to_world_cell(lake_edge_grid, start)

	var astar := _make_road_astar(start, size)
	_paint_route(astar, spawn_cell, town_cell, ROAD_MAIN_RADIUS_TILES)
	_paint_route(astar, town_cell, forest_cell, ROAD_MAIN_RADIUS_TILES)
	_paint_route(astar, town_cell, lake_edge_cell, ROAD_TRAIL_RADIUS_TILES)


func _make_road_astar(start: Vector2i, size: Vector2i) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(start, size)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	astar.update()
	var biomes := _dict_property(_attached_world, "_biomes")
	var barriers := _dict_property(_attached_world, "_forest_barriers")
	var tree_left := _dict_property(_attached_world, "_forest_tree_left")
	var tree_right := _dict_property(_attached_world, "_forest_tree_right")
	var cliffs := _dict_property(_attached_world, "_plains_cliffs")
	for y in range(start.y, start.y + size.y):
		for x in range(start.x, start.x + size.x):
			var cell := Vector2i(x, y)
			if _water_cells.has(cell) or int(biomes.get(cell, -1)) == BIOME_WATER or cliffs.has(cell) or barriers.has(cell) or tree_left.has(cell) or tree_right.has(cell):
				astar.set_point_solid(cell, true)
				continue
			astar.set_point_weight_scale(cell, _road_weight_for_biome(int(biomes.get(cell, BIOME_DRY))))
	return astar


func _paint_route(astar: AStarGrid2D, from_cell: Vector2i, to_cell: Vector2i, radius: int) -> void:
	if not astar.is_in_boundsv(from_cell) or not astar.is_in_boundsv(to_cell):
		return
	if astar.is_point_solid(from_cell) or astar.is_point_solid(to_cell):
		return
	var path: PackedVector2Array = astar.get_id_path(from_cell, to_cell)
	for point in path:
		_paint_road_brush(Vector2i(point), radius)


func _paint_road_brush(center: Vector2i, radius: int) -> void:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var offset := Vector2i(ox, oy)
			if Vector2(offset).length() > float(radius) + 0.15:
				continue
			var cell := center + offset
			if not _road_cell_allowed(cell):
				continue
			_road_cells[cell] = true


func _road_cell_allowed(cell: Vector2i) -> bool:
	if _is_water(cell) or not _is_in_world_bounds(cell):
		return false
	if _dict_property(_attached_world, "_plains_cliffs").has(cell):
		return false
	if _dict_property(_attached_world, "_forest_barriers").has(cell):
		return false
	if _dict_property(_attached_world, "_forest_tree_left").has(cell):
		return false
	if _dict_property(_attached_world, "_forest_tree_right").has(cell):
		return false
	return true


func _is_in_world_bounds(cell: Vector2i) -> bool:
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	var start := Vector2i(-size.x / 2, -size.y / 2)
	return Rect2i(start, size).has_point(cell)


func _build_road_fringe() -> Dictionary:
	var fringe: Dictionary = {}
	for value in _road_cells.keys():
		var cell := Vector2i(value)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var neighbour := cell + Vector2i(ox, oy)
				if not _road_cells.has(neighbour):
					fringe[neighbour] = true
	return fringe


func _native_fringe_coord(cells: Dictionary, cell: Vector2i) -> Vector2i:
	var n := cells.has(cell + Vector2i.UP)
	var e := cells.has(cell + Vector2i.RIGHT)
	var s := cells.has(cell + Vector2i.DOWN)
	var w := cells.has(cell + Vector2i.LEFT)

	# Exact 16px transition pieces from the native Romestead cobblestone sheet.
	# The previous mapping used unrelated cells from rows 0-3 and produced the
	# rectangular cut-outs visible around every diagonal border.
	if s and w and not n and not e:
		return Vector2i(0, 0)
	if s and e and not n and not w:
		return Vector2i(1, 3)
	if n and e and not s and not w:
		return Vector2i(0, 2)
	if n and w and not s and not e:
		return Vector2i(3, 3)
	if s and not n and not e and not w:
		return Vector2i(0, 8)
	if n and not s and not e and not w:
		return Vector2i(2, 8)
	if e and not n and not s and not w:
		return Vector2i(0, 9)
	if w and not n and not s and not e:
		return Vector2i(2, 9)

	# At a junction or a very tight diagonal there is no useful "outside" tile.
	# Keep it full instead of punching a transparent square into the road.
	var cardinal_count := int(n) + int(e) + int(s) + int(w)
	if cardinal_count >= 2:
		return Vector2i(posmod(_cell_seed(cell, 0xE661), 4), 6)
	return Vector2i(-1, -1)


func _road_layer_for_cell(cell: Vector2i, town_cell: Vector2i) -> TileMapLayer:
	return _grey_layer if Vector2(cell).distance_to(Vector2(town_cell)) <= TOWN_GREY_RADIUS_TILES else _beige_layer


func _make_native_road_layer(layer_name: String, texture: Texture2D) -> TileMapLayer:
	if texture.get_width() < TILE_SIZE or texture.get_height() < TILE_SIZE:
		return null
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.z_index = ROAD_Z
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(atlas, 0)
	var columns := int(texture.get_width() / TILE_SIZE)
	var rows := int(texture.get_height() / TILE_SIZE)
	for y in range(rows):
		for x in range(columns):
			atlas.create_tile(Vector2i(x, y))
	layer.tile_set = tile_set
	return layer


func _hide_previous_road_visuals() -> void:
	var old_layer := _attached_world.get_node_or_null("ProceduralRoads") as CanvasItem
	if old_layer != null:
		old_layer.visible = false


func _prune_resources_from_roads() -> void:
	var resources := _attached_world.get_node_or_null("../Resources")
	if resources == null:
		resources = _attached_world.get_node_or_null("Resources")
	if resources == null:
		return
	for child in resources.get_children():
		if not child is Node2D:
			continue
		var cell := _world_to_cell((child as Node2D).global_position)
		if _road_cells.has(cell) or _near_road(cell, 1):
			child.queue_free()


func _near_road(cell: Vector2i, clearance: int) -> bool:
	for y in range(-clearance, clearance + 1):
		for x in range(-clearance, clearance + 1):
			if _road_cells.has(cell + Vector2i(x, y)):
				return true
	return false


func _town_cell() -> Vector2i:
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	var start := Vector2i(-size.x / 2, -size.y / 2)
	return _grid_to_world_cell(Vector2(_attached_world.get("_town_center_grid")), start)


func _is_water(cell: Vector2i) -> bool:
	if _water_cells.has(cell):
		return true
	var biomes := _dict_property(_attached_world, "_biomes")
	return int(biomes.get(cell, -1)) == BIOME_WATER


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
		BIOME_DIRT:
			return 1.25
		_:
			return 1.5


func _world_to_cell(world_position: Vector2) -> Vector2i:
	var world_node := _attached_world as Node2D
	if world_node == null:
		return Vector2i.ZERO
	var local_position := world_node.to_local(world_position)
	return Vector2i(roundi(local_position.x / TILE_SIZE), roundi(local_position.y / TILE_SIZE))


func _grid_to_world_cell(grid: Vector2, start: Vector2i) -> Vector2i:
	return start + Vector2i(roundi(grid.x), roundi(grid.y))


func _dict_property(object: Object, property_name: String) -> Dictionary:
	if object == null:
		return {}
	var value: Variant = object.get(property_name)
	return value if value is Dictionary else {}


func _cell_seed(cell: Vector2i, salt: int) -> int:
	var world_seed := int(_attached_world.get("world_seed")) if _attached_world != null else 0
	var mixed := world_seed ^ salt
	mixed ^= cell.x * 73856093
	mixed ^= cell.y * 19349663
	return absi(mixed)


func _clear_layers() -> void:
	for layer in [_beige_layer, _grey_layer]:
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
	_beige_layer = null
	_grey_layer = null
	_road_cells.clear()
