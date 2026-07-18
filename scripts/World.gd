extends Node2D

const TerrainMapScript = preload("res://scripts/world/TerrainMap.gd")
const LEGACY_WORLD_ATLAS: Texture2D = preload("res://assets/generated/legacy_world_tiles.svg")
const SOURCE_ID := 0
const TERRAIN_TYPE_CUSTOM_DATA := "terrain_type"
const TERRAIN_GRASS := "grass"
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

var terrain_map := TerrainMapScript.new()

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
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = LEGACY_WORLD_ATLAS
	atlas_source.texture_region_size = tile_size
	atlas_source.create_tile(GROUND_TILE)
	atlas_source.create_tile(ROCK_TILE)
	atlas_source.create_tile(WALL_TILE)
	atlas_source.create_tile(CAMPFIRE_TILE)
	atlas_source.create_tile(WORKBENCH_TILE)
	atlas_source.create_tile(BED_TILE)

	var tile_set := TileSet.new()
	tile_set.tile_size = tile_size
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, TERRAIN_TYPE_CUSTOM_DATA)
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 1)
	tile_set.add_source(atlas_source, SOURCE_ID)

	var ground_data := atlas_source.get_tile_data(GROUND_TILE, 0)
	ground_data.set_custom_data(TERRAIN_TYPE_CUSTOM_DATA, TERRAIN_GRASS)

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


func get_tile_type_at_position(global_position: Vector2) -> String:
	return terrain_map.get_tile_type_at_position(ground_layer, global_position)
