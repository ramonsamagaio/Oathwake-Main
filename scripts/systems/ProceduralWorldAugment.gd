extends Node

const TILE_SIZE := 16
const WATER_BIOME := 0
const BIOME_DIRT := 1
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
const CLIFF_FACE_HEIGHT_TILES := 2

# WorldDepthRuntime keeps depth-sorted actors/resources above -4000. All flat
# procedural terrain additions stay in the reserved ground band so travelling
# north can never make a floor tile cover the player again.
const WATER_Z := -4088
const GROUND_DETAIL_Z := -4087
const ROAD_Z := -4086
const CLIFF_FINISH_Z := -4085

const CARDINAL := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MASK_N := 1
const MASK_E := 2
const MASK_S := 4
const MASK_W := 8

# Preserve the palette of the imported Romestead dirt-road reference while
# rebuilding its topology correctly instead of randomly shuffling source cells.
const ROAD_BASE := Color(0.710, 0.584, 0.341, 1.0)
const ROAD_DARK := Color(0.600, 0.467, 0.286, 1.0)
const ROAD_LIGHT := Color(0.765, 0.639, 0.388, 1.0)
const WATER_BASE := Color(0.205, 0.405, 0.480, 0.96)
const WATER_DARK := Color(0.160, 0.330, 0.405, 0.98)
const WATER_LIGHT := Color(0.285, 0.510, 0.565, 0.92)
const SHORE_WET := Color(0.285, 0.300, 0.210, 0.96)
const CLIFF_SHADOW := Color(0.165, 0.145, 0.125, 0.52)
const CLIFF_STONE := Color(0.410, 0.385, 0.335, 0.86)
const CLIFF_STONE_LIGHT := Color(0.500, 0.470, 0.405, 0.82)

var _attached_world: Node
var _water_layer: TileMapLayer
var _road_layer: TileMapLayer
var _ground_detail_layer: TileMapLayer
var _cliff_finish_layer: TileMapLayer
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
	_build_ground_details()
	_build_cliff_finish()
	_prune_generated_entities()
	_update_layers()


func _build_water() -> void:
	var size := Vector2i(_attached_world.get("world_size_tiles"))
	var start := Vector2i(-size.x / 2, -size.y / 2)
	var center_grid := Vector2(size) * 0.5
	var lake_center: Vector2 = _attached_world.get("_lake_center_grid")
	var radius := float(size.x) * WATER_RADIUS_FACTOR
	var biomes := _get_dictionary(_attached_world, "_biomes")

	# First decide the complete shoreline. Drawing after the set is complete lets
	# every tile select a deterministic topology mask from its real neighbours.
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
	_attached_world.set("_biomes", biomes)

	_water_layer = _make_water_layer("ProceduralWater", WATER_Z, true)
	if _water_layer == null:
		return
	_attached_world.add_child(_water_layer)
	for cell_value in _water_cells.keys():
		var cell := Vector2i(cell_value)
		var mask := _cardinal_mask(_water_cells, cell)
		_water_layer.set_cell(cell, 0, _mask_coord(mask), 0)


func _build_semantic_roads() -> void:
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

	# Construct the expensive weighted grid once. The old code rebuilt all
	# 512x320 weights for every individual road route.
	var astar := _make_road_astar(start, size)
	if astar == null:
		return
	_paint_costed_route(astar, spawn_cell, town_cell, ROAD_MAIN_WIDTH_TILES)
	_paint_costed_route(astar, town_cell, forest_cell, ROAD_MAIN_WIDTH_TILES)
	_paint_costed_route(astar, town_cell, lake_edge_cell, ROAD_TRAIL_WIDTH_TILES)

	_road_layer = _make_road_layer("ProceduralRoads", ROAD_Z)
	if _road_layer == null:
		return
	_attached_world.add_child(_road_layer)
	for cell_value in _road_cells.keys():
		var cell := Vector2i(cell_value)
		var mask := _cardinal_mask(_road_cells, cell)
		var variant := posmod(_cell_seed(cell, 0xD17A), 2)
		_road_layer.set_cell(cell, 0, _road_coord(mask, variant), 0)


func _make_road_astar(start: Vector2i, size: Vector2i) -> AStarGrid2D:
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
	return astar


func _paint_costed_route(astar: AStarGrid2D, from_cell: Vector2i, to_cell: Vector2i, width_tiles: int) -> void:
	var path := _find_costed_path(astar, from_cell, to_cell)
	if path.is_empty():
		return
	for index in range(path.size()):
		var center := path[index]
		var directions: Array[Vector2i] = []
		if index > 0:
			var from_previous := center - path[index - 1]
			if from_previous != Vector2i.ZERO:
				directions.append(from_previous)
		if index + 1 < path.size():
			var to_next := path[index + 1] - center
			if to_next != Vector2i.ZERO and not directions.has(to_next):
				directions.append(to_next)
		if directions.is_empty():
			directions.append(Vector2i.RIGHT)
		for direction in directions:
			_paint_road_cross_section(center, width_tiles, direction)


func _find_costed_path(astar: AStarGrid2D, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
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


func _paint_road_cross_section(center: Vector2i, width_tiles: int, direction: Vector2i) -> void:
	_mark_road_cell(center)
	if width_tiles <= 1:
		return
	var cardinal_direction := direction
	if cardinal_direction.x != 0:
		cardinal_direction = Vector2i(signi(cardinal_direction.x), 0)
	else:
		cardinal_direction = Vector2i(0, signi(cardinal_direction.y))
	if cardinal_direction == Vector2i.ZERO:
		cardinal_direction = Vector2i.RIGHT
	var perpendicular := Vector2i(-cardinal_direction.y, cardinal_direction.x)
	_mark_road_cell(center + perpendicular)
	if width_tiles >= 3:
		_mark_road_cell(center - perpendicular)


func _mark_road_cell(cell: Vector2i) -> void:
	if not _water_cells.has(cell):
		_road_cells[cell] = true


func _build_ground_details() -> void:
	_ground_detail_layer = _make_ground_detail_layer("ProceduralGroundDetails", GROUND_DETAIL_Z)
	if _ground_detail_layer == null:
		return
	_attached_world.add_child(_ground_detail_layer)
	var biomes := _get_dictionary(_attached_world, "_biomes")
	var world_seed := int(_attached_world.get("world_seed"))
	for cell_value in biomes.keys():
		if not cell_value is Vector2i:
			continue
		var cell := Vector2i(cell_value)
		if _water_cells.has(cell) or _road_cells.has(cell) or _is_near_road(cell, 1):
			continue
		var biome := int(biomes.get(cell, BIOME_DRY))
		var row := _detail_row_for_biome(biome)
		if row < 0:
			# Deep/dark grass already has the successful authored litter pass. Do
			# not pile another decoration system on top of the part that is working.
			continue
		var density := _detail_density_for_biome(biome)
		if _static_hash01(cell.x, cell.y, world_seed ^ 0x51A7) > density:
			continue
		var variant := posmod(_cell_seed(cell, 0xB10F), 4)
		_ground_detail_layer.set_cell(cell, 0, Vector2i(variant, row), 0)


func _build_cliff_finish() -> void:
	var cliffs := _get_dictionary(_attached_world, "_plains_cliffs")
	if cliffs.is_empty():
		return
	_cliff_finish_layer = _make_cliff_finish_layer("ProceduralCliffFinish", CLIFF_FINISH_Z)
	if _cliff_finish_layer == null:
		return
	_attached_world.add_child(_cliff_finish_layer)
	for cell_value in cliffs.keys():
		if not cell_value is Vector2i:
			continue
		var cliff_cell := Vector2i(cell_value)
		# The native cliff face extrudes two cells downward. Only exposed bottom
		# edges get the grounding shadow/pebbles, avoiding stacked decoration in
		# the middle of a formation.
		if cliffs.has(cliff_cell + Vector2i.DOWN):
			continue
		var foot_cell := cliff_cell + Vector2i.DOWN * (CLIFF_FACE_HEIGHT_TILES + 1)
		if _water_cells.has(foot_cell) or _road_cells.has(foot_cell):
			continue
		var variant := posmod(_cell_seed(foot_cell, 0xC11F), 4)
		_cliff_finish_layer.set_cell(foot_cell, 0, Vector2i(variant, 0), 0)


func _detail_row_for_biome(biome: int) -> int:
	match biome:
		BIOME_DIRT:
			return 0
		BIOME_MEADOW:
			return 1
		BIOME_FOREST:
			return 2
		BIOME_SWAMP:
			return 3
		BIOME_DRY:
			return 4
		BIOME_FOREST_LIGHT:
			return 5
		_:
			return -1


func _detail_density_for_biome(biome: int) -> float:
	match biome:
		BIOME_DIRT:
			return 0.045
		BIOME_MEADOW:
			return 0.070
		BIOME_FOREST:
			return 0.040
		BIOME_SWAMP:
			return 0.060
		BIOME_DRY:
			return 0.055
		BIOME_FOREST_LIGHT:
			return 0.050
		_:
			return 0.0


func _make_water_layer(name_value: String, z_value: int, collision: bool) -> TileMapLayer:
	var image := Image.create(TILE_SIZE * 4, TILE_SIZE * 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for mask in range(16):
		_draw_water_tile(image, mask, mask % 4, mask / 4)
	return _make_layer_from_texture(name_value, z_value, ImageTexture.create_from_image(image), collision)


func _draw_water_tile(image: Image, mask: int, tile_x: int, tile_y: int) -> void:
	for py in range(TILE_SIZE):
		for px in range(TILE_SIZE):
			var missing_n := (mask & MASK_N) == 0
			var missing_e := (mask & MASK_E) == 0
			var missing_s := (mask & MASK_S) == 0
			var missing_w := (mask & MASK_W) == 0
			var transparent_edge := (
				(missing_n and py < 2)
				or (missing_s and py >= TILE_SIZE - 2)
				or (missing_w and px < 2)
				or (missing_e and px >= TILE_SIZE - 2)
			)
			if transparent_edge:
				continue
			var bank_pixel := (
				(missing_n and py == 2)
				or (missing_s and py == TILE_SIZE - 3)
				or (missing_w and px == 2)
				or (missing_e and px == TILE_SIZE - 3)
			)
			var color := WATER_BASE
			if bank_pixel:
				color = SHORE_WET
			else:
				var near_bank := (
					(missing_n and py == 3)
					or (missing_s and py == TILE_SIZE - 4)
					or (missing_w and px == 3)
					or (missing_e and px == TILE_SIZE - 4)
				)
				if near_bank:
					color = WATER_DARK
				elif posmod(py + tile_x * 2 + tile_y, 7) == 0 and posmod(px + tile_y * 3, 8) in [2, 3, 4]:
					color = WATER_LIGHT
			_set_tile_pixel(image, tile_x, tile_y, px, py, color)


func _make_road_layer(name_value: String, z_value: int) -> TileMapLayer:
	# Two visual variants for every 4-bit topology mask: 8 columns x 4 rows.
	var image := Image.create(TILE_SIZE * 8, TILE_SIZE * 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for variant in range(2):
		for mask in range(16):
			_draw_road_tile(image, mask, variant, (mask % 4) + variant * 4, mask / 4)
	return _make_layer_from_texture(name_value, z_value, ImageTexture.create_from_image(image), false)


func _draw_road_tile(image: Image, mask: int, variant: int, tile_x: int, tile_y: int) -> void:
	for py in range(TILE_SIZE):
		for px in range(TILE_SIZE):
			if not _road_pixel_inside(px, py, mask):
				continue
			var color := ROAD_BASE
			# Sparse two-tone gravel detail. It deliberately stays much cleaner than
			# the old random source-cell montage.
			var pattern := posmod(px * 5 + py * 3 + mask * 7 + variant * 11, 29)
			if pattern in [0, 1]:
				color = ROAD_DARK
			elif pattern == 14:
				color = ROAD_LIGHT
			_set_tile_pixel(image, tile_x, tile_y, px, py, color)


func _road_pixel_inside(px: int, py: int, mask: int) -> bool:
	var center_x := px >= 4 and px <= 11
	var center_y := py >= 4 and py <= 11
	if center_x and center_y:
		return true
	if (mask & MASK_N) != 0 and center_x and py < 8:
		return true
	if (mask & MASK_S) != 0 and center_x and py >= 8:
		return true
	if (mask & MASK_W) != 0 and center_y and px < 8:
		return true
	if (mask & MASK_E) != 0 and center_y and px >= 8:
		return true
	# Fill connected corner quadrants so broad roads and bends do not expose a
	# checkerboard of terrain between otherwise connected pieces.
	if (mask & MASK_N) != 0 and (mask & MASK_E) != 0 and px >= 8 and py < 8:
		return true
	if (mask & MASK_N) != 0 and (mask & MASK_W) != 0 and px < 8 and py < 8:
		return true
	if (mask & MASK_S) != 0 and (mask & MASK_E) != 0 and px >= 8 and py >= 8:
		return true
	if (mask & MASK_S) != 0 and (mask & MASK_W) != 0 and px < 8 and py >= 8:
		return true
	return false


func _make_ground_detail_layer(name_value: String, z_value: int) -> TileMapLayer:
	var image := Image.create(TILE_SIZE * 4, TILE_SIZE * 6, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for row in range(6):
		for variant in range(4):
			_draw_ground_detail_tile(image, row, variant)
	return _make_layer_from_texture(name_value, z_value, ImageTexture.create_from_image(image), false)


func _draw_ground_detail_tile(image: Image, row: int, variant: int) -> void:
	var base_colors := [
		Color(0.34, 0.29, 0.22, 0.72),
		Color(0.38, 0.49, 0.25, 0.78),
		Color(0.24, 0.31, 0.18, 0.78),
		Color(0.27, 0.36, 0.28, 0.78),
		Color(0.50, 0.42, 0.23, 0.76),
		Color(0.34, 0.43, 0.24, 0.78),
	]
	var accent_colors := [
		Color(0.48, 0.43, 0.35, 0.72),
		Color(0.64, 0.66, 0.38, 0.72),
		Color(0.42, 0.43, 0.24, 0.70),
		Color(0.44, 0.49, 0.36, 0.70),
		Color(0.63, 0.54, 0.31, 0.72),
		Color(0.52, 0.56, 0.31, 0.70),
	]
	var base: Color = base_colors[row]
	var accent: Color = accent_colors[row]
	match variant:
		0:
			_set_tile_pixel(image, variant, row, 5, 11, base)
			_set_tile_pixel(image, variant, row, 6, 10, base)
			_set_tile_pixel(image, variant, row, 6, 11, base)
			_set_tile_pixel(image, variant, row, 10, 7, accent)
		1:
			_set_tile_pixel(image, variant, row, 4, 6, base)
			_set_tile_pixel(image, variant, row, 5, 6, base)
			_set_tile_pixel(image, variant, row, 11, 11, accent)
			_set_tile_pixel(image, variant, row, 12, 11, base)
		2:
			_set_tile_pixel(image, variant, row, 7, 8, base)
			_set_tile_pixel(image, variant, row, 8, 7, accent)
			_set_tile_pixel(image, variant, row, 8, 8, base)
			_set_tile_pixel(image, variant, row, 9, 8, base)
		3:
			_set_tile_pixel(image, variant, row, 5, 12, base)
			_set_tile_pixel(image, variant, row, 6, 11, accent)
			_set_tile_pixel(image, variant, row, 9, 5, base)
			_set_tile_pixel(image, variant, row, 10, 5, accent)


func _make_cliff_finish_layer(name_value: String, z_value: int) -> TileMapLayer:
	var image := Image.create(TILE_SIZE * 4, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for variant in range(4):
		for x in range(2, 14):
			if posmod(x + variant * 3, 5) != 0:
				_set_tile_pixel(image, variant, 0, x, 1, CLIFF_SHADOW)
		var rock_x := 4 + variant * 2
		_set_tile_pixel(image, variant, 0, rock_x, 4, CLIFF_STONE)
		_set_tile_pixel(image, variant, 0, mini(rock_x + 1, 14), 4, CLIFF_STONE_LIGHT)
		if variant % 2 == 0:
			_set_tile_pixel(image, variant, 0, 11, 6, CLIFF_STONE)
	return _make_layer_from_texture(name_value, z_value, ImageTexture.create_from_image(image), false)


func _make_layer_from_texture(name_value: String, z_value: int, texture: Texture2D, collision: bool) -> TileMapLayer:
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
				data.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
				]))
	layer.tile_set = tile_set
	return layer


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


func _cardinal_mask(cells: Dictionary, cell: Vector2i) -> int:
	var mask := 0
	if cells.has(cell + Vector2i.UP):
		mask |= MASK_N
	if cells.has(cell + Vector2i.RIGHT):
		mask |= MASK_E
	if cells.has(cell + Vector2i.DOWN):
		mask |= MASK_S
	if cells.has(cell + Vector2i.LEFT):
		mask |= MASK_W
	return mask


func _mask_coord(mask: int) -> Vector2i:
	return Vector2i(mask % 4, mask / 4)


func _road_coord(mask: int, variant: int) -> Vector2i:
	return Vector2i((mask % 4) + variant * 4, mask / 4)


func _set_tile_pixel(image: Image, tile_x: int, tile_y: int, px: int, py: int, color: Color) -> void:
	if px < 0 or py < 0 or px >= TILE_SIZE or py >= TILE_SIZE:
		return
	image.set_pixel(tile_x * TILE_SIZE + px, tile_y * TILE_SIZE + py, color)


func _clear_layers() -> void:
	_water_cells.clear()
	_road_cells.clear()
	for node in [_water_layer, _road_layer, _ground_detail_layer, _cliff_finish_layer]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_water_layer = null
	_road_layer = null
	_ground_detail_layer = null
	_cliff_finish_layer = null


func _update_layers() -> void:
	for layer in [_water_layer, _road_layer, _ground_detail_layer, _cliff_finish_layer]:
		if layer != null:
			layer.update_internals()


func _get_dictionary(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value if value is Dictionary else {}


func _cell_seed(cell: Vector2i, salt: int) -> int:
	var world_seed := int(_attached_world.get("world_seed")) if _attached_world != null else 0
	var mixed := world_seed ^ salt
	mixed ^= cell.x * 73856093
	mixed ^= cell.y * 19349663
	return absi(mixed)


func _static_hash01(x: int, y: int, salt: int) -> float:
	var mixed := x * 374761393 + y * 668265263 + salt * 69069
	mixed = (mixed ^ (mixed >> 13)) * 1274126177
	mixed = mixed ^ (mixed >> 16)
	return float(posmod(mixed, 10000)) / 9999.0


func _hash_noise(x: int, y: int, seed: int) -> float:
	return _static_hash01(x, y, seed) - 0.5
