extends Node2D

const SOURCE_ID := 0
const GROUND_TILE := Vector2i(0, 0)
const ROCK_TILE := Vector2i(1, 0)
const WALL_TILE := Vector2i(2, 0)
const CAMPFIRE_TILE := Vector2i(3, 0)
const WORKBENCH_TILE := Vector2i(4, 0)
const BED_TILE := Vector2i(5, 0)
const MAP_MIN := Vector2i(-15, -10)
const MAP_MAX := Vector2i(15, 10)
const ROCK_CELLS := [
	Vector2i(4, -2),
	Vector2i(5, -2),
	Vector2i(4, -1),
	Vector2i(-5, 2),
	Vector2i(-4, 2),
	Vector2i(-5, 3),
	Vector2i(0, 5),
	Vector2i(1, 5),
	Vector2i(8, 3),
]

@export var tile_size: Vector2i = Vector2i(32, 32)

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var obstacle_layer: TileMapLayer = $ObstacleLayer
@onready var build_layer: TileMapLayer = $BuildLayer


func _ready() -> void:
	var generated_tile_set := _create_tile_set()
	ground_layer.tile_set = generated_tile_set
	obstacle_layer.tile_set = generated_tile_set
	build_layer.tile_set = generated_tile_set

	_paint_ground()
	_place_rocks()


func _create_tile_set() -> TileSet:
	var image := Image.create(tile_size.x * 6, tile_size.y, false, Image.FORMAT_RGBA8)
	_fill_tile(image, 0, Color(0.22, 0.45, 0.24))
	_fill_tile(image, 1, Color(0.36, 0.36, 0.39))
	_fill_tile(image, 2, Color(0.50, 0.32, 0.18))
	_fill_tile(image, 3, Color(0.88, 0.34, 0.10))
	_fill_tile(image, 4, Color(0.44, 0.28, 0.14))
	_fill_tile(image, 5, Color(0.42, 0.34, 0.62))
	_draw_tile_border(image, 0, Color(0.17, 0.34, 0.18))
	_draw_tile_border(image, 1, Color(0.24, 0.24, 0.27))
	_draw_tile_border(image, 2, Color(0.30, 0.18, 0.10))
	_draw_tile_border(image, 3, Color(0.45, 0.14, 0.04))
	_draw_tile_border(image, 4, Color(0.20, 0.12, 0.06))
	_draw_tile_border(image, 5, Color(0.22, 0.17, 0.36))

	var texture := ImageTexture.create_from_image(image)
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = texture
	atlas_source.texture_region_size = tile_size
	atlas_source.create_tile(GROUND_TILE)
	atlas_source.create_tile(ROCK_TILE)
	atlas_source.create_tile(WALL_TILE)
	atlas_source.create_tile(CAMPFIRE_TILE)
	atlas_source.create_tile(WORKBENCH_TILE)
	atlas_source.create_tile(BED_TILE)

	var tile_set := TileSet.new()
	tile_set.tile_size = tile_size
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 1)
	tile_set.add_source(atlas_source, SOURCE_ID)

	var rock_half_size := Vector2((tile_size.x * 0.5) - 2.0, (tile_size.y * 0.5) - 2.0)
	var rock_data := atlas_source.get_tile_data(ROCK_TILE, 0)
	rock_data.set_collision_polygons_count(0, 1)
	rock_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-rock_half_size.x, -rock_half_size.y),
		Vector2(rock_half_size.x, -rock_half_size.y),
		Vector2(rock_half_size.x, rock_half_size.y),
		Vector2(-rock_half_size.x, rock_half_size.y),
	]))

	var wall_half_size := Vector2(tile_size.x * 0.5, tile_size.y * 0.5)
	var wall_data := atlas_source.get_tile_data(WALL_TILE, 0)
	wall_data.set_collision_polygons_count(0, 1)
	wall_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-wall_half_size.x, -wall_half_size.y),
		Vector2(wall_half_size.x, -wall_half_size.y),
		Vector2(wall_half_size.x, wall_half_size.y),
		Vector2(-wall_half_size.x, wall_half_size.y),
	]))

	var workbench_data := atlas_source.get_tile_data(WORKBENCH_TILE, 0)
	workbench_data.set_collision_polygons_count(0, 1)
	workbench_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-wall_half_size.x, -wall_half_size.y),
		Vector2(wall_half_size.x, -wall_half_size.y),
		Vector2(wall_half_size.x, wall_half_size.y),
		Vector2(-wall_half_size.x, wall_half_size.y),
	]))

	return tile_set


func _paint_ground() -> void:
	ground_layer.clear()

	for x in range(MAP_MIN.x, MAP_MAX.x):
		for y in range(MAP_MIN.y, MAP_MAX.y):
			ground_layer.set_cell(Vector2i(x, y), SOURCE_ID, GROUND_TILE)


func _place_rocks() -> void:
	obstacle_layer.clear()

	for cell in ROCK_CELLS:
		obstacle_layer.set_cell(cell, SOURCE_ID, ROCK_TILE)


func _fill_tile(image: Image, tile_index: int, color: Color) -> void:
	var start_x := tile_index * tile_size.x

	for x in range(start_x, start_x + tile_size.x):
		for y in range(tile_size.y):
			image.set_pixel(x, y, color)


func _draw_tile_border(image: Image, tile_index: int, color: Color) -> void:
	var start_x := tile_index * tile_size.x
	var end_x := start_x + tile_size.x - 1
	var end_y := tile_size.y - 1

	for x in range(start_x, start_x + tile_size.x):
		image.set_pixel(x, 0, color)
		image.set_pixel(x, end_y, color)

	for y in range(tile_size.y):
		image.set_pixel(start_x, y, color)
		image.set_pixel(end_x, y, color)
