class_name RomesteadBiomeWorld2D
extends Node2D

signal world_generated(seed: int, biome_counts: Dictionary)

const PROCEDURAL_SPRITE_ROOT := "res://assets/sprites/world/procedural"
const TERRAIN_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/terrain"
const TREE_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/trees"
const ROCK_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/rocks"
const PLANT_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/plants"
const OBJECT_SPRITE_ROOT := PROCEDURAL_SPRITE_ROOT + "/objects"
const BASE_TERRAIN_PATH := TERRAIN_SPRITE_ROOT + "/plainsgrass2.png"
const GREEN_TERRAIN_PATH := TERRAIN_SPRITE_ROOT + "/short_grass.png"
const DIRT_TERRAIN_PATH := TERRAIN_SPRITE_ROOT + "/plainsgrass3.png"
const FOREST_LIGHT_TERRAIN_PATH := TERRAIN_SPRITE_ROOT + "/plainsgrass1.png"
const FOREST_DEEP_TERRAIN_PATH := TERRAIN_SPRITE_ROOT + "/tall_grass.png"
const FOREST_PATH_PATH := TERRAIN_SPRITE_ROOT + "/forest_path_short_grass_autumn.png"
const FOREST_BARRIER_BOTTOM_PATH := TERRAIN_SPRITE_ROOT + "/forest_unbreakable_bushes_bottom_.png"
const FOREST_BARRIER_TOP_PATH := TERRAIN_SPRITE_ROOT + "/forest_unbreakable_bushes_top_.png"
const FOREST_TREE_WALL_PATH := TERRAIN_SPRITE_ROOT + "/tree_wall.png"
const FOREST_CANOPY_PATH := TERRAIN_SPRITE_ROOT + "/canopy_.png"
const PLAINS_CLIFF_PATH := TERRAIN_SPRITE_ROOT + "/plains_3D_cliffs.png"
const BASE_DETAILS_PATH := TERRAIN_SPRITE_ROOT + "/plainsgrass2_details.png"
const GREEN_DETAILS_PATH := TERRAIN_SPRITE_ROOT + "/shortgrass_details.png"
const DIRT_DETAILS_PATH := TERRAIN_SPRITE_ROOT + "/plainsgrass3_details.png"
const TREE_STUMP_PATH := TREE_SPRITE_ROOT + "/flora_stump.png"
const TREE_CANOPY_1_PATH := TREE_SPRITE_ROOT + "/flora_tree1.png"
const TREE_CANOPY_2_PATH := TREE_SPRITE_ROOT + "/flora_tree2.png"
const OLIVE_TREE_PATH := TREE_SPRITE_ROOT + "/flora_olive_tree_large.png"
const OLIVE_STUMP_PATH := TREE_SPRITE_ROOT + "/flora_olive_tree_stump.png"
const SKINNY_TREE_PATH := TREE_SPRITE_ROOT + "/flora_skinny_tree.png"
const CYPRESS_PATH := TREE_SPRITE_ROOT + "/flora_tall_cypress.png"
const ROCK_BIG_PATH := ROCK_SPRITE_ROOT + "/terrain_round_rocks_big.png"
const ROCK_SMALL_PATH := ROCK_SPRITE_ROOT + "/terrain_round_rocks_small.png"
const BUSH_PATH := PLANT_SPRITE_ROOT + "/flora_big_bushes1.png"
const GROUND_PLANTS_PATH := PLANT_SPRITE_ROOT + "/flora_ground_plants.png"
const WHEAT_PATH := PLANT_SPRITE_ROOT + "/flora_wheat_animated.png"
const APPLE_TREE_PATH := TREE_SPRITE_ROOT + "/flora_apple_tree_large.png"
const APPLE_STUMP_PATH := TREE_SPRITE_ROOT + "/flora_apple_tree_stump.png"
const STONE_PINE_PATH := TREE_SPRITE_ROOT + "/flora_stone_pine_large.png"
const STONE_PINE_STUMP_PATH := TREE_SPRITE_ROOT + "/flora_stone_pine_stump.png"
const MOSSY_BOULDER_PATH := ROCK_SPRITE_ROOT + "/poi_mossy_boulder_large.png"
const COPPER_ORE_PATH := ROCK_SPRITE_ROOT + "/resources_copper_ore.png"
const MUSHROOMS_PATH := PLANT_SPRITE_ROOT + "/flora_mushrooms.png"
const BELLFLOWERS_PATH := PLANT_SPRITE_ROOT + "/flora_bellflowers.png"
const PURPLE_BUSH_PATH := PLANT_SPRITE_ROOT + "/desert_purplebush.png"
const SMALL_BUSH_PATH := PLANT_SPRITE_ROOT + "/flora_small_bush1.png"
const TINY_FLOWERS_PATH := PLANT_SPRITE_ROOT + "/flora_tiny_flowers.png"
const TINY_LEAVES_PATH := PLANT_SPRITE_ROOT + "/flora_tiny_ground_leaves.png"
const BRAZIER_PATH := OBJECT_SPRITE_ROOT + "/tier0_brazier.png"
const LIGHT_COOKIE_PATH := "res://assets/world_lab/romestead_editable/light_cookie.svg"
const GROUND_SHADER: Shader = preload("res://shaders/labs/romestead_systems/romestead_ground_response.gdshader")

# These values are the native Romestead AutoTile16TileSet table. The array
# index is the frame on the 4-column PNG and its value is the topology mask.
const AUTOTILE_MASK_SETUP := [
	4, 3, 14, 6, 10, 7, 15, 13, 1, 9, 11, 12, 0, 2, 5, 8,
	3, 3, 12, 12, 6, 6, 9, 9,
	31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31,
	31, 31, 31, 31, 0, 0, 0, 0, 24, 18, 20, 17,
]
const SURROUNDING_ADJACENTS_TO_CORNERS := [0, 3, 6, 7, 12, 15, 14, 15, 9, 11, 15, 15, 13, 15, 15, 15]
const NEIGHBOR_OFFSETS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const NEIGHBOR_FLAGS := [128, 8, 16, 4, 1, 64, 2, 32]
# Romestead uses these overlapping four-bit masks for both the forest cleanup
# pass and the tall-tree auto-tilers. Diagonals therefore affect only the
# relevant corner instead of turning into a hard cardinal cut.
const FOREST_MASK_OFFSETS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const FOREST_MASK_FLAGS := [8, 9, 1, 12, 15, 3, 4, 6, 2]

# AutoTileRuleSet.PlainsCliff: the exact InOrderXy pair for every native
# four-bit diagonal mask. AutoTilerCliffs draws the following two atlas rows
# (+8 and +16) when that edge exposes the two-tile vertical rock face.
const PLAINS_CLIFF_BASE_FRAMES := [
	[], [32, 36], [34, 38], [99, 103], [35, 39], [0, 2], [98, 102], [67, 71],
	[33, 37], [96, 100], [1, 3], [64, 68], [97, 101], [65, 69], [66, 70], [4, 5],
]

const TERRAIN_BASE := 0
const TERRAIN_DIRT := 1
const TERRAIN_GREEN := 2
const TERRAIN_FOREST_LIGHT := 3
const TERRAIN_FOREST_DEEP := 4

const BIOME_WATER := 0
const BIOME_DIRT := 1
const BIOME_MEADOW := 2
const BIOME_FOREST := 3
const BIOME_SWAMP := 4
const BIOME_DRY := 5
const BIOME_FOREST_LIGHT := 6
const BIOME_FOREST_DEEP := 7
const BIOME_NAMES := {
	BIOME_WATER: "Agua",
	BIOME_DIRT: "Terra seca",
	BIOME_MEADOW: "Prado",
	BIOME_FOREST: "Bosque",
	BIOME_SWAMP: "Pantano",
	BIOME_DRY: "Campina dourada",
	BIOME_FOREST_LIGHT: "Transicao de floresta",
	BIOME_FOREST_DEEP: "Floresta fechada",
}

enum PropKind {
	TREE_ROUND,
	TREE_OLIVE,
	TREE_CYPRESS,
	ROCK_BIG,
	ROCK_SMALL,
	BUSH,
	WHEAT,
	GROUND_PLANT,
	BRAZIER,
	APPLE_TREE,
	STONE_PINE,
	MOSSY_ROCK,
	COPPER_ORE,
	MUSHROOM,
	FLOWER,
	PURPLE_BUSH,
	SMALL_BUSH,
	FLOOR_DETAIL,
}

@export var world_seed := 74291
@export var world_size_tiles := Vector2i(240, 140)
@export_range(16, 128, 1) var tile_size := 16
@export var auto_generate := true
@export_node_path("TileMapLayer") var ground_path := NodePath("Ground")
@export_node_path("TileMapLayer") var green_overlay_path := NodePath("GreenTerrain0")
@export_node_path("TileMapLayer") var dirt_overlay_path := NodePath("DirtTerrain0")
@export_node_path("Node2D") var props_path := NodePath("Props")
@export_node_path("Node2D") var vegetation_path := NodePath("WindVegetation")

var _region_noise := FastNoiseLite.new()
var _forest_noise := FastNoiseLite.new()
var _dirt_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _flower_noise := FastNoiseLite.new()
var _flower_variant_noise := FastNoiseLite.new()
var _ground_values2 := FastNoiseLite.new()
var _structure_values2 := FastNoiseLite.new()
var _ground_values := FastNoiseLite.new()
var _structure_values := FastNoiseLite.new()
var _terrain_world_noise := FastNoiseLite.new()
var _terrain_world_noise2 := FastNoiseLite.new()
var _humidity_world_noise := FastNoiseLite.new()
var _humidity_world_noise2 := FastNoiseLite.new()
var _forest_center_grid := Vector2.ZERO
var _desert_center_grid := Vector2.ZERO
var _lake_center_grid := Vector2.ZERO
var _volcano_center_grid := Vector2.ZERO
var _town_center_grid := Vector2.ZERO
var _biomes: Dictionary = {}
var _terrain_types: Dictionary = {}
var _terrain_values: Dictionary = {}
var _forest_barriers: Dictionary = {}
var _forest_tree_left: Dictionary = {}
var _forest_tree_right: Dictionary = {}
var _plains_cliffs: Dictionary = {}
var _entity_spots: Dictionary = {}
var _mask_frames: Dictionary = {}
var _terrain_materials: Array[ShaderMaterial] = []
var _wind_pivots: Array[Node2D] = []
var _wind_value := 0.0
var _textures: Dictionary = {}
var _light_cookie: Texture2D

@onready var _ground := get_node_or_null(ground_path) as TileMapLayer
@onready var _green_layers: Array[TileMapLayer] = [
	get_node_or_null(green_overlay_path) as TileMapLayer,
	get_node_or_null("GreenTerrain1") as TileMapLayer,
	get_node_or_null("GreenTerrain2") as TileMapLayer,
]
@onready var _dirt_layers: Array[TileMapLayer] = [
	get_node_or_null(dirt_overlay_path) as TileMapLayer,
	get_node_or_null("DirtTerrain1") as TileMapLayer,
	get_node_or_null("DirtTerrain2") as TileMapLayer,
]
@onready var _base_details := get_node_or_null("BaseDetails") as TileMapLayer
@onready var _green_details := get_node_or_null("GreenDetails") as TileMapLayer
@onready var _dirt_details := get_node_or_null("DirtDetails") as TileMapLayer
@onready var _forest_light_layers: Array[TileMapLayer] = [
	get_node_or_null("ForestLight0") as TileMapLayer,
	get_node_or_null("ForestLight1") as TileMapLayer,
	get_node_or_null("ForestLight2") as TileMapLayer,
]
@onready var _forest_deep_layers: Array[TileMapLayer] = [
	get_node_or_null("ForestDeep0") as TileMapLayer,
	get_node_or_null("ForestDeep1") as TileMapLayer,
	get_node_or_null("ForestDeep2") as TileMapLayer,
]
@onready var _forest_path := get_node_or_null("ForestPath") as TileMapLayer
@onready var _forest_barrier_bottom := get_node_or_null("ForestBarrierBottom") as TileMapLayer
@onready var _forest_barrier_top := get_node_or_null("ForestBarrierTop") as TileMapLayer
@onready var _forest_tree_wall := get_node_or_null("ForestTreeWall") as TileMapLayer
@onready var _forest_canopy := get_node_or_null("ForestCanopy") as TileMapLayer
@onready var _plains_cliff_layers: Array[TileMapLayer] = [
	get_node_or_null("PlainsCliff0") as TileMapLayer,
	get_node_or_null("PlainsCliff1") as TileMapLayer,
	get_node_or_null("PlainsCliff2") as TileMapLayer,
]
@onready var _plains_cliff_collision := get_node_or_null("PlainsCliffCollision") as TileMapLayer
@onready var _tiny_leaves := get_node_or_null("TinyLeaves") as TileMapLayer
@onready var _tiny_flowers := get_node_or_null("TinyFlowers") as TileMapLayer
@onready var _props := get_node_or_null(props_path) as Node2D
@onready var _vegetation := get_node_or_null(vegetation_path) as Node2D


func _ready() -> void:
	_load_editable_textures()
	_build_mask_frame_lookup()
	_light_cookie = _load_svg_texture(LIGHT_COOKIE_PATH)
	set_process(true)
	if auto_generate:
		call_deferred("generate_world")


func _process(delta: float) -> void:
	for pivot in _wind_pivots:
		if not is_instance_valid(pivot):
			continue
		var timer := float(pivot.get_meta("wind_timer", 0.0))
		var sway_speed := float(pivot.get_meta("sway_speed", 0.3))
		timer += delta * sway_speed * _wind_value
		pivot.set_meta("wind_timer", timer)
		var base_rotation := 0.0
		if absf(_wind_value) > 1.0:
			base_rotation = (_wind_value - signf(_wind_value)) * 1.5
		var flicker := (
			sin(timer * 3.0)
			+ sin(timer * 4.7921) * 0.5
			+ sin(timer * 7.123345) * 0.25
		) * (_wind_value * 3.0 / 1.75)
		var sway_scale := float(pivot.get_meta("sway_scale", 1.0))
		pivot.rotation = deg_to_rad((base_rotation + flicker) * sway_scale)


func generate_world(new_seed: int = world_seed) -> void:
	world_seed = new_seed
	if not _has_required_nodes():
		push_error("RomesteadBiomeWorld2D is missing one or more native terrain layers.")
		return
	_prepare_tilesets()
	_prepare_noise()
	_clear_generated_content()

	var start := Vector2i(-world_size_tiles.x / 2, -world_size_tiles.y / 2)
	var finish := start + world_size_tiles
	# Romestead generates the biome map first, the ground/structure map second,
	# and only then runs its forest cleanup pass. Keep the same order here.
	# Seven cells of padding are required by ForestBiomeTileSecondPass.
	for y in range(start.y - 7, finish.y + 7):
		for x in range(start.x - 7, finish.x + 7):
			var cell := Vector2i(x, y)
			var native_tile := _native_tile_at(cell, start)
			_terrain_types[cell] = int(native_tile["ground"])
			_biomes[cell] = int(native_tile["biome"])
			_terrain_values[cell] = float(native_tile["terrain_value"])
			if bool(native_tile["barrier"]):
				_forest_barriers[cell] = true
			if bool(native_tile.get("cliff", false)):
				_plains_cliffs[cell] = true
	_apply_forest_second_pass(start, finish)
	_apply_plains_cliff_second_pass(start, finish)
	_generate_entity_size_spots(start, finish)

	var biome_counts := {}
	for y in range(start.y, finish.y):
		for x in range(start.x, finish.x):
			var cell := Vector2i(x, y)
			var terrain_type := int(_terrain_types[cell])
			var biome := int(_biomes[cell])
			biome_counts[biome] = int(biome_counts.get(biome, 0)) + 1
			_ground.set_cell(cell, 0, Vector2i(2, 1), 0)
			_draw_native_autotile(cell, TERRAIN_DIRT, _dirt_layers)
			_draw_native_autotile(cell, TERRAIN_GREEN, _green_layers)
			_draw_native_autotile(cell, TERRAIN_FOREST_LIGHT, _forest_light_layers)
			_draw_native_autotile(cell, TERRAIN_FOREST_DEEP, _forest_deep_layers)
			_draw_forest_path(cell, terrain_type)
			_draw_plains_cliff(cell)
			_draw_forest_barrier(cell)
			_draw_native_detail(cell, terrain_type)
			if _entity_spots.has(cell):
				_scatter_cell(cell, biome, _entity_spots[cell] as Dictionary)

	for layer in _all_tile_layers():
		layer.update_internals()
	_spawn_light_landmarks()
	world_generated.emit(world_seed, biome_counts)


func set_environment(wetness: float, lightning: float, wind_strength: float, _wind_speed: float, wind_direction: Vector2, hour: float = 15.0, daylight: float = 1.0) -> void:
	for material in _terrain_materials:
		material.set_shader_parameter("wetness", wetness)
		material.set_shader_parameter("lightning_flash", lightning)
		material.set_shader_parameter("world_time", Time.get_ticks_msec() * 0.001)
	# Romestead stores wind as a signed scalar. The weather profile supplies a
	# normalized strength and the horizontal direction supplies its sign.
	_wind_value = clampf(wind_strength, 0.0, 1.0) * 2.4 * clampf(wind_direction.normalized().x, -1.0, 1.0)
	_update_projected_shadows(hour, daylight)


func get_biome_name_at_world(world_position: Vector2) -> String:
	if _ground == null:
		return "Desconhecido"
	var cell := _ground.local_to_map(_ground.to_local(world_position))
	return BIOME_NAMES.get(int(_biomes.get(cell, BIOME_DRY)), "Desconhecido")


func get_world_bounds() -> Rect2:
	var size := Vector2(world_size_tiles * tile_size)
	return Rect2(-size * 0.5 + Vector2.ONE * tile_size * 0.5, size - Vector2.ONE * tile_size)


func _has_required_nodes() -> bool:
	if _ground == null or _props == null or _vegetation == null:
		return false
	for layer in _all_tile_layers():
		if layer == null:
			return false
	return true


func _all_tile_layers() -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = [_ground]
	layers.append_array(_dirt_layers)
	layers.append_array(_green_layers)
	layers.append_array(_forest_light_layers)
	layers.append_array(_forest_deep_layers)
	layers.append_array([_forest_path, _base_details, _dirt_details, _green_details, _tiny_leaves, _tiny_flowers, _forest_barrier_bottom, _forest_barrier_top, _forest_tree_wall, _forest_canopy])
	layers.append_array(_plains_cliff_layers)
	layers.append(_plains_cliff_collision)
	return layers


func _load_editable_textures() -> void:
	_textures = {
		"base": _load_png_texture(BASE_TERRAIN_PATH),
		"green": _load_png_texture(GREEN_TERRAIN_PATH),
		"dirt": _load_png_texture(DIRT_TERRAIN_PATH),
		"forest_light": _load_png_texture(FOREST_LIGHT_TERRAIN_PATH),
		"forest_deep": _load_png_texture(FOREST_DEEP_TERRAIN_PATH),
		"forest_path": _load_png_texture(FOREST_PATH_PATH),
		"forest_barrier_bottom": _load_png_texture(FOREST_BARRIER_BOTTOM_PATH),
		"forest_barrier_top": _load_png_texture(FOREST_BARRIER_TOP_PATH),
		"forest_tree_wall": _load_png_texture(FOREST_TREE_WALL_PATH),
		"forest_canopy": _load_png_texture(FOREST_CANOPY_PATH),
		"plains_cliff": _load_png_texture(PLAINS_CLIFF_PATH),
		"base_details": _load_png_texture(BASE_DETAILS_PATH),
		"green_details": _load_png_texture(GREEN_DETAILS_PATH),
		"dirt_details": _load_png_texture(DIRT_DETAILS_PATH),
		"stump": _load_png_texture(TREE_STUMP_PATH),
		"tree1": _load_png_texture(TREE_CANOPY_1_PATH),
		"tree2": _load_png_texture(TREE_CANOPY_2_PATH),
		"olive_tree": _load_png_texture(OLIVE_TREE_PATH),
		"olive_stump": _load_png_texture(OLIVE_STUMP_PATH),
		"skinny_tree": _load_png_texture(SKINNY_TREE_PATH),
		"cypress": _load_png_texture(CYPRESS_PATH),
		"rock_big": _load_png_texture(ROCK_BIG_PATH),
		"rock_small": _load_png_texture(ROCK_SMALL_PATH),
		"bush": _load_png_texture(BUSH_PATH),
		"ground_plants": _load_png_texture(GROUND_PLANTS_PATH),
		"wheat": _load_png_texture(WHEAT_PATH),
		"apple_tree": _load_png_texture(APPLE_TREE_PATH),
		"apple_stump": _load_png_texture(APPLE_STUMP_PATH),
		"stone_pine": _load_png_texture(STONE_PINE_PATH),
		"stone_pine_stump": _load_png_texture(STONE_PINE_STUMP_PATH),
		"mossy_boulder": _load_png_texture(MOSSY_BOULDER_PATH),
		"copper_ore": _load_png_texture(COPPER_ORE_PATH),
		"mushrooms": _load_png_texture(MUSHROOMS_PATH),
		"bellflowers": _load_png_texture(BELLFLOWERS_PATH),
		"purple_bush": _load_png_texture(PURPLE_BUSH_PATH),
		"small_bush": _load_png_texture(SMALL_BUSH_PATH),
		"tiny_flowers": _load_png_texture(TINY_FLOWERS_PATH),
		"tiny_leaves": _load_png_texture(TINY_LEAVES_PATH),
		"brazier": _load_png_texture(BRAZIER_PATH),
	}


func _prepare_tilesets() -> void:
	_assign_native_tileset(_ground, _textures["base"])
	for layer in _green_layers:
		_assign_native_tileset(layer, _textures["green"])
	for layer in _dirt_layers:
		_assign_native_tileset(layer, _textures["dirt"])
	for layer in _forest_light_layers:
		_assign_native_tileset(layer, _textures["forest_light"])
	for layer in _forest_deep_layers:
		_assign_native_tileset(layer, _textures["forest_deep"])
	_assign_native_tileset(_forest_path, _textures["forest_path"])
	_assign_native_tileset(_forest_barrier_bottom, _textures["forest_barrier_bottom"], true)
	_assign_native_tileset(_forest_barrier_top, _textures["forest_barrier_top"])
	_assign_native_tileset(_forest_tree_wall, _textures["forest_tree_wall"])
	_assign_native_tileset(_forest_canopy, _textures["forest_canopy"])
	for layer in _plains_cliff_layers:
		_assign_native_tileset(layer, _textures["plains_cliff"])
	_assign_native_tileset(_plains_cliff_collision, _textures["plains_cliff"], true)
	_assign_native_tileset(_base_details, _textures["base_details"])
	_assign_native_tileset(_green_details, _textures["green_details"])
	_assign_native_tileset(_dirt_details, _textures["dirt_details"])
	_assign_native_tileset(_tiny_leaves, _textures["tiny_leaves"])
	_assign_native_tileset(_tiny_flowers, _textures["tiny_flowers"])

	_terrain_materials.clear()
	for layer in _all_tile_layers():
		var material := ShaderMaterial.new()
		material.shader = GROUND_SHADER
		material.set_shader_parameter("reference_grade", Vector3.ONE)
		layer.material = material
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_terrain_materials.append(material)


func _assign_native_tileset(layer: TileMapLayer, texture: Texture2D, with_collision := false) -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	if with_collision:
		tile_set.add_physics_layer()
		tile_set.set_physics_layer_collision_layer(0, 1)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(tile_size, tile_size)
	tile_set.add_source(atlas, 0)
	for y in range(texture.get_height() / tile_size):
		for x in range(texture.get_width() / tile_size):
			atlas.create_tile(Vector2i(x, y))
			if with_collision:
				var tile_data := atlas.get_tile_data(Vector2i(x, y), 0)
				tile_data.add_collision_polygon(0)
				tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
				]))
	layer.tile_set = tile_set


func _build_mask_frame_lookup() -> void:
	_mask_frames.clear()
	for frame in range(AUTOTILE_MASK_SETUP.size()):
		var mask := int(AUTOTILE_MASK_SETUP[frame])
		if not _mask_frames.has(mask):
			_mask_frames[mask] = []
		(_mask_frames[mask] as Array).append(frame)


func _draw_native_autotile(cell: Vector2i, target_type: int, layers: Array[TileMapLayer]) -> void:
	if int(_terrain_types[cell]) == target_type:
		layers[0].set_cell(cell, 0, _frame_to_coord(6), 0)
		return
	var surrounding_mask := 0
	for index in range(NEIGHBOR_OFFSETS.size()):
		if int(_terrain_types.get(cell + NEIGHBOR_OFFSETS[index], TERRAIN_BASE)) == target_type:
			surrounding_mask |= int(NEIGHBOR_FLAGS[index])
	var pieces := _surrounding_mask_to_piece_masks(surrounding_mask)
	for piece_index in range(mini(pieces.size(), layers.size())):
		var topology_mask := int(pieces[piece_index])
		var frame := _frame_for_mask(topology_mask, cell, piece_index, target_type)
		if frame >= 0:
			layers[piece_index].set_cell(cell, 0, _frame_to_coord(frame), 0)


func _surrounding_mask_to_piece_masks(mask: int) -> Array[int]:
	if (mask & 15) == 15:
		return [0]
	var result: Array[int] = []
	var bit := 1
	while bit <= 8:
		if (mask & bit) != 0:
			var right := ((bit >> 1) | (bit << 3)) & 15
			var left := ((bit << 1) | (bit >> 3)) & 15
			var opposite := ((bit >> 2) | (bit << 2)) & 15
			var flags := 0
			if (mask & opposite) == opposite:
				flags |= 4
			if (mask & left) == left:
				flags |= 1
			if (mask & right) == right:
				flags |= 2
				if flags == 2:
					result.append(int(SURROUNDING_ADJACENTS_TO_CORNERS[bit | right]))
				elif flags == 3:
					result.append(bit | 16)
			if (flags & 3) == 0:
				result.append(int(SURROUNDING_ADJACENTS_TO_CORNERS[bit]))
		bit <<= 1
	bit = 16
	while bit <= 128:
		if (mask & bit) != 0:
			var corner := bit >> 4
			var rotated := ((corner >> 1) | (corner << 3)) & 15
			if (mask & (corner | rotated)) == 0:
				result.append(corner)
		bit <<= 1
	if result.has(1) and result.has(4):
		result.erase(1)
		result.erase(4)
		result.append(5)
	elif result.has(2) and result.has(8):
		result.erase(2)
		result.erase(8)
		result.append(10)
	return result


func _frame_for_mask(mask: int, cell: Vector2i, piece_index: int, target_type: int) -> int:
	var candidates := _mask_frames.get(mask, []) as Array
	if candidates.is_empty():
		return -1
	var variant_seed := _cell_seed(cell) ^ (piece_index * 83492791) ^ (target_type * 297121507)
	return int(candidates[variant_seed % candidates.size()])


func _frame_to_coord(frame: int) -> Vector2i:
	return Vector2i(frame % 4, frame / 4)


func _draw_native_detail(cell: Vector2i, terrain_type: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(cell) ^ 0x4D3A9B1
	var layer: TileMapLayer
	var frame_count := 4
	var chance := 0.30
	match terrain_type:
		TERRAIN_GREEN, TERRAIN_FOREST_LIGHT, TERRAIN_FOREST_DEEP:
			layer = _green_details
			frame_count = 5
			chance = 0.25
		TERRAIN_DIRT:
			layer = _dirt_details
		_:
			layer = _base_details
	if rng.randf() < chance:
		layer.set_cell(cell, 0, Vector2i(rng.randi_range(0, frame_count - 1), 0), 0)
	if terrain_type not in [TERRAIN_GREEN, TERRAIN_FOREST_LIGHT, TERRAIN_FOREST_DEEP]:
		return
	if _is_forest_structure(cell) or _plains_cliffs.has(cell):
		return
	# AutoTiler.DrawFlowersNew uses two fixed noise fields (1/32 at seed 141,
	# 0.125 at seed 141199), the 0.66 cluster gate, and separate sprite rows for
	# Grass and TallGrass. Keep those authored rules and frame ranges here.
	var tall_grass := terrain_type in [TERRAIN_FOREST_LIGHT, TERRAIN_FOREST_DEEP]
	var value := absf(_flower_noise.get_noise_2d(cell.x + 16, cell.y + 16))
	value += (_tile_random_unit(cell, 0) - 0.5) * 0.1
	if tall_grass:
		value -= 0.1
	if value < 0.66:
		return
	var cluster_strength := clampf((value - 0.66) / 0.25, 0.0, 1.0)
	var variant_noise := _flower_variant_noise.get_noise_2d(cell.x + 16, cell.y + 16)
	var row := 1 if tall_grass else 0
	if _tile_random_unit(cell, 141) <= cluster_strength:
		if variant_noise <= (_tile_random_unit(cell, 141199) * 2.0 - 1.0) * 0.5:
			var first_leaf_frame := 0 if value > 0.9 + (_tile_random_unit(cell, 1) * 2.0 - 1.0) * 0.05 else 4
			_tiny_leaves.set_cell(cell, 0, Vector2i(first_leaf_frame + posmod(_cell_seed(cell), 4), row), 0)
		else:
			_tiny_flowers.set_cell(cell, 0, Vector2i(posmod(_cell_seed(cell), 2), row), 0)
	# BigPlantSheet2 is the third, rare 0.008 pass of DrawFlowersNew. It is a
	# decorative grounded plant, never a ResourceNode or collision blocker.
	if _tile_random_unit(cell, 0xB16) < 0.008:
		var offset := Vector2(
			floorf(_tile_random_unit(cell, 0xB17) * 16.0) - 8.0,
			floorf(_tile_random_unit(cell, 0xB18) * 16.0) - 8.0
		)
		_spawn_prop(Vector2(cell * tile_size) + offset, PropKind.GROUND_PLANT, _cell_seed(cell) ^ 0xB19)


func _prepare_noise() -> void:
	_configure_noise(_region_noise, world_seed + 101, 0.038, 3)
	_configure_noise(_forest_noise, world_seed + 307, 0.072, 3)
	_configure_noise(_dirt_noise, world_seed + 601, 0.050, 3)
	_configure_noise(_detail_noise, world_seed + 911, 0.19, 2)
	_configure_noise(_flower_noise, 141, 1.0 / 32.0, 1)
	_configure_noise(_flower_variant_noise, 141199, 0.125, 1)
	# Romestead's closed-forest gate is abs(StructureValues2 * GroundValues2)
	# with both fields sampled at the native 1/64 world scale.
	_configure_noise(_ground_values2, world_seed ^ 0x12E6F, 1.0 / 64.0, 1)
	_configure_noise(_structure_values2, world_seed ^ 0x53A11, 1.0 / 64.0, 1)
	_configure_noise(_ground_values, world_seed ^ 1, 1.0 / 32.0, 1)
	_configure_noise(_structure_values, world_seed ^ 0x2481, 1.0 / 32.0, 1)
	# GenerateBaseMaps samples these fields at 4096/world_width and then at
	# /512 or /256. These are the native spatial scales, expressed per tile.
	_configure_noise(_terrain_world_noise, world_seed, 8.0 / float(world_size_tiles.x), 1)
	_configure_noise(_terrain_world_noise2, world_seed ^ 0xFBB0, 16.0 / float(world_size_tiles.x), 1)
	_configure_noise(_humidity_world_noise, world_seed, 8.0 / float(world_size_tiles.x), 1)
	_configure_noise(_humidity_world_noise2, world_seed ^ 0xFBB0, 16.0 / float(world_size_tiles.x), 1)
	_prepare_key_biome_centers()


func _prepare_key_biome_centers() -> void:
	# WorldGenerator.DecideKeyPoints: six slightly jittered points on a ring,
	# followed by repeated shuffling until the lake/desert/town/volcano spacing
	# constraints are all satisfied. Keeping those constraints is what prevents
	# the biome chain from collapsing into tiny, unsafe islands.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var corners: Array[Vector2] = []
	var first_angle := rng.randf() * TAU / 6.0
	for index in range(6):
		var fraction := (float(index) + rng.randf_range(-0.15, 0.15)) / 6.0
		var angle := first_angle + fraction * TAU
		corners.append(Vector2(cos(angle), sin(angle)))
	var keys := ["town", "desert", "lake", "volcano", "forest", "placeholder"]
	for _attempt in range(5001):
		_shuffle_with_rng(keys, rng)
		var lake_index := keys.find("lake")
		var desert_index := keys.find("desert")
		var town_index := keys.find("town")
		var volcano_index := keys.find("volcano")
		if absf(corners[lake_index].x) < 0.33:
			continue
		if corners[desert_index].y < 0.33:
			continue
		if absf(_circular_index_difference(desert_index, lake_index, 6)) < 2.0:
			continue
		if absf(_circular_index_difference(town_index, lake_index, 6)) > 1.0:
			continue
		if absf(_circular_index_difference(volcano_index, lake_index, 6)) < 2.0:
			continue
		break
	var center := Vector2(world_size_tiles) * 0.5
	var radius := Vector2(world_size_tiles) * 0.375
	_forest_center_grid = center + corners[keys.find("forest")] * radius
	_desert_center_grid = center + corners[keys.find("desert")] * radius
	_lake_center_grid = center + corners[keys.find("lake")] * radius
	_volcano_center_grid = center + corners[keys.find("volcano")] * radius
	_town_center_grid = center + corners[keys.find("town")] * radius


func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[other]
		values[other] = temporary


func _circular_index_difference(a: int, b: int, length: int) -> float:
	var difference := fposmod(float(a - b), float(length))
	if difference > float(length) * 0.5:
		difference -= float(length)
	return difference


func _configure_noise(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.52
	noise.fractal_lacunarity = 2.0


func _native_tile_at(cell: Vector2i, start: Vector2i) -> Dictionary:
	var grid := Vector2(cell - start)
	var size := Vector2(world_size_tiles)
	var world_center := size * 0.5
	var scale := 1.0 / size.x

	var terrain_noise := _terrain_world_noise.get_noise_2d(grid.x - 48.0, grid.y - 48.0)
	var terrain_noise2 := _terrain_world_noise2.get_noise_2d(grid.x + 486.0, grid.y + 234741.0)
	var humidity_noise := _humidity_world_noise.get_noise_2d(grid.x - 10027.0, grid.y + 215539.0)
	var humidity_noise2 := _humidity_world_noise2.get_noise_2d(grid.x - 234837.0, grid.y - 582.0)
	var forest_distance := grid.distance_to(_forest_center_grid) * scale
	var desert_distance := grid.distance_to(_desert_center_grid) * scale
	var lake_distance := grid.distance_to(_lake_center_grid) * scale
	var spawn_distance := grid.distance_to(world_center) * scale

	var terrain_value := 0.4 + 0.4 * (terrain_noise2 + 1.0)
	terrain_value -= 0.6 * _cube_in_out(clampf(forest_distance, 0.0, 1.0))
	terrain_value += 3.0 * (1.0 - _quad_in(clampf(forest_distance / 0.25, 0.0, 1.0)))
	terrain_value -= 0.9 * _sine_in(clampf(1.0 - desert_distance / 0.4, 0.0, 1.0))
	terrain_value -= 2.9 * _sine_in(clampf(1.0 - spawn_distance / 0.1, 0.0, 1.0))
	terrain_value -= _quad_in(absf(terrain_noise) * 1.725)
	var spawn_ring := 1.0 - _quad_in_out(clampf(absf(1.0 - (spawn_distance - 0.028) / 0.024), 0.0, 1.0))
	terrain_value = lerpf(terrain_value, 1.0 - _quad_in(absf(terrain_noise) * 1.725) * 0.25, spawn_ring)

	var humidity := 0.5 * (1.0 - lake_distance * 2.0) + humidity_noise2 * 0.05
	var lake_blend := 1.0 - _quad_in(clampf((lake_distance + humidity_noise * 0.03) / 0.115, 0.0, 1.0))
	humidity += lerpf(0.24 + humidity_noise2 * 0.24, 1.0, lake_blend)
	humidity = lerpf(clampf(humidity, 0.0, 10.0), 0.2, 1.0 - _quad_in(clampf(desert_distance / 0.4, 0.0, 1.0)))
	humidity = lerpf(clampf(humidity, 0.25, 10.0), 0.0, 1.0 - _quad_in(clampf((desert_distance + terrain_noise * 0.03) / 0.13, 0.0, 1.0)))

	var biome := BIOME_DRY
	if humidity >= 0.21:
		if humidity < 0.25:
			terrain_value -= 0.4 - humidity * humidity
		if terrain_value < -0.33 - humidity * humidity * 3.0:
			biome = BIOME_DRY
		elif terrain_value < 0.05:
			biome = BIOME_MEADOW
		elif terrain_value < 0.33:
			biome = BIOME_FOREST_LIGHT
		elif terrain_value < 2.25:
			biome = BIOME_FOREST
		else:
			biome = BIOME_FOREST_DEEP

	var seed_x := world_seed % 32
	var seed_y := (world_seed + 13) % 32
	var ground_value := _ground_values.get_noise_2d(grid.x + seed_x, grid.y + seed_y)
	var ground_value2 := _ground_values2.get_noise_2d(grid.x + seed_x, grid.y + seed_y)
	var structure_value := _structure_values.get_noise_2d(grid.x + seed_x + 7, grid.y + seed_y + 13)
	var structure_value2 := _structure_values2.get_noise_2d(grid.x + seed_x + 14, grid.y + seed_y + 26)
	var ground := TERRAIN_BASE
	var barrier := false
	match biome:
		BIOME_MEADOW:
			ground = TERRAIN_FOREST_DEEP if ground_value >= 0.5 else (TERRAIN_GREEN if ground_value >= -0.65 else TERRAIN_DIRT)
		BIOME_FOREST_LIGHT:
			var blend_x := clampf(1.0 - (0.33 - terrain_value) / (0.33 - 0.05), 0.0, 1.0)
			var forest_density := absf(structure_value2 * ground_value2)
			var ground_blend := lerpf((ground_value + 0.65) / 1.15 - 1.0, (forest_density - 0.035) / 0.165, _quad_in(blend_x))
			ground = TERRAIN_DIRT if ground_blend <= -1.0 else (TERRAIN_GREEN if ground_blend <= 0.0 else TERRAIN_FOREST_DEEP)
			barrier = ground_blend > 1.0
		BIOME_FOREST, BIOME_FOREST_DEEP:
			var forest_density := absf(structure_value2 * ground_value2)
			barrier = forest_density > 0.2
			ground = TERRAIN_FOREST_DEEP if forest_density > 0.035 else TERRAIN_GREEN
		_:
			ground = TERRAIN_FOREST_DEEP if ground_value >= 0.7 else (TERRAIN_FOREST_LIGHT if ground_value >= 0.3 else (TERRAIN_BASE if ground_value >= -0.65 else TERRAIN_DIRT))
	# PlainsBiomeTileGenerator creates this non-interactive structure only on
	# ordinary grass when StructureValues reaches its native 0.8 cutoff.
	var cliff := biome == BIOME_MEADOW and ground == TERRAIN_GREEN and structure_value >= 0.8
	return {"biome": biome, "ground": ground, "barrier": barrier, "cliff": cliff, "terrain_value": terrain_value}


func _terrain_type_at(cell: Vector2i) -> int:
	return int(_terrain_types.get(cell, TERRAIN_BASE))


func _classify_biome(cell: Vector2i, _terrain_type: int) -> int:
	return int(_biomes.get(cell, BIOME_DRY))


func _apply_plains_cliff_second_pass(start: Vector2i, finish: Vector2i) -> void:
	# WaterTileSecondPass invokes FilterOutSingleTiles for PlainsCliff before
	# rendering. It mutates in row order, just like the forest pass.
	for y in range(start.y - 1, finish.y + 1):
		for x in range(start.x - 1, finish.x + 1):
			var cell := Vector2i(x, y)
			if _plains_cliffs.has(cell) and _plains_cliff_mask(cell) == 0:
				_plains_cliffs.erase(cell)


func _plains_cliff_mask(cell: Vector2i) -> int:
	var mask := 15
	for index in range(FOREST_MASK_OFFSETS.size()):
		if not _plains_cliffs.has(cell + FOREST_MASK_OFFSETS[index]):
			mask &= ~int(FOREST_MASK_FLAGS[index])
	return mask


func _draw_plains_cliff(cell: Vector2i) -> void:
	if not _plains_cliffs.has(cell):
		return
	var mask := _plains_cliff_mask(cell)
	if mask <= 0 or mask >= PLAINS_CLIFF_BASE_FRAMES.size():
		return
	var options := PLAINS_CLIFF_BASE_FRAMES[mask] as Array
	if options.is_empty():
		return
	# MultiTilePattern.Mode.InOrderXy selects by (x + y) modulo two.
	var frame := int(options[posmod(cell.x + cell.y, options.size())])
	_plains_cliff_layers[0].set_cell(cell + Vector2i.UP * 2, 0, Vector2i(frame % 8, frame / 8), 0)
	var exposes_face := ((1 << mask) & 0x3F3E) != 0
	if exposes_face:
		_plains_cliff_layers[1].set_cell(cell + Vector2i.UP, 0, Vector2i((frame + 8) % 8, (frame + 8) / 8), 0)
		_plains_cliff_layers[2].set_cell(cell, 0, Vector2i((frame + 16) % 8, (frame + 16) / 8), 0)
	# Collision belongs to the logical structure cell, not to a breakable
	# ResourceNode. The layer is visually transparent but physically authored.
	# Frame 0 is intentionally transparent in the authored atlas. Use frame 32,
	# the first real PlainsCliff tile, for the hidden physics cell.
	_plains_cliff_collision.set_cell(cell, 0, Vector2i(0, 4), 0)


func _apply_forest_second_pass(start: Vector2i, finish: Vector2i) -> void:
	# ForestBiomeTileSecondPass runs in row order and mutates the same structure
	# map it is reading. Preserve that order: first apply the native 3x3 filter
	# to this cell, then attempt the six-tile TallTreeLeft/Right replacement.
	var required := [
		Vector2i(1, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
	]
	for x in range(-1, 3):
		for y in range(-1, -7, -1):
			required.append(Vector2i(x, y))
	for y in range(start.y - 1, finish.y + 1):
		for x in range(start.x - 1, finish.x + 1):
			var cell := Vector2i(x, y)
			if not _forest_barriers.has(cell):
				continue
			if _forest_bush_mask(cell) == 0:
				_forest_barriers.erase(cell)
				continue
			var valid := true
			for offset in required:
				if not _is_forest_structure(cell + offset):
					valid = false
					break
			if valid:
				_forest_barriers.erase(cell)
				_forest_barriers.erase(cell + Vector2i.RIGHT)
				_forest_tree_left[cell] = true
				_forest_tree_right[cell + Vector2i.RIGHT] = true
	# The replacement pass can consume the final neighbour of a filtered bush.
	# Remove that leftover immediately so a one-cell piece of closed-forest wall
	# can never appear by itself at a generated boundary.
	var isolated: Array[Vector2i] = []
	for cell_value in _forest_barriers.keys():
		var barrier_cell := cell_value as Vector2i
		var has_cardinal := false
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if _is_forest_structure(barrier_cell + offset):
				has_cardinal = true
				break
		if not has_cardinal:
			isolated.append(barrier_cell)
	for barrier_cell in isolated:
		_forest_barriers.erase(barrier_cell)


func _is_forest_structure(cell: Vector2i) -> bool:
	return _forest_barriers.has(cell) or _forest_tree_left.has(cell) or _forest_tree_right.has(cell)


func _forest_structure_mask(cell: Vector2i) -> int:
	var mask := 15
	for index in range(FOREST_MASK_OFFSETS.size()):
		if not _is_forest_structure(cell + FOREST_MASK_OFFSETS[index]):
			mask &= ~int(FOREST_MASK_FLAGS[index])
	return mask


func _forest_bush_mask(cell: Vector2i) -> int:
	var mask := 15
	for index in range(FOREST_MASK_OFFSETS.size()):
		if not _forest_barriers.has(cell + FOREST_MASK_OFFSETS[index]):
			mask &= ~int(FOREST_MASK_FLAGS[index])
	return mask


func _draw_forest_barrier(cell: Vector2i) -> void:
	if not _is_forest_structure(cell):
		return
	if _forest_barriers.has(cell):
		var frame := _frame_for_mask(_forest_bush_mask(cell), cell, 0, 91)
		if frame >= 0:
			var coord := _frame_to_coord(posmod(frame, 16))
			_forest_barrier_bottom.set_cell(cell, 0, coord, 0)
			# AutoTilerLayers gives TallBushTopRule Height=16, so this texture
			# is rendered exactly one native tile above its logical structure.
			_forest_barrier_top.set_cell(cell + Vector2i.UP, 0, coord, 0)
	elif _forest_tree_left.has(cell) or _forest_tree_right.has(cell):
		var full_coord := _frame_to_coord(6)
		_forest_barrier_top.set_cell(cell, 0, full_coord, 0)
		_forest_barrier_top.set_cell(cell + Vector2i.DOWN, 0, full_coord, 0)
		var frames := [8, 6, 2, 0, 2, 0] if _forest_tree_left.has(cell) else [9, 7, 3, 1, 3, 1]
		for index in range(frames.size()):
			var frame := int(frames[index])
			_forest_tree_wall.set_cell(cell + Vector2i(0, -index), 0, Vector2i(frame % 2, frame / 2), 0)

	# The canopy is sampled against a second structure row five tiles above, then
	# AutoTilerLayers renders the entire layer at Height=96 (six native tiles up).
	# The height translation is essential: without it the black treetop appears
	# below the trunk wall and the whole closed forest reads upside down.
	var source := cell + Vector2i(0, -5)
	if _is_forest_structure(source):
		var canopy_mask := 15
		for index in range(FOREST_MASK_OFFSETS.size()):
			var offset: Vector2i = FOREST_MASK_OFFSETS[index]
			if not _is_forest_structure(cell + offset) or not _is_forest_structure(source + offset):
				canopy_mask &= ~int(FOREST_MASK_FLAGS[index])
		var canopy_frame := _frame_for_mask(canopy_mask, cell, 0, 103)
		if canopy_frame >= 0:
			_forest_canopy.set_cell(cell + Vector2i.UP * 6, 0, _frame_to_coord(posmod(canopy_frame, 16)), 0)


func _draw_forest_path(_cell: Vector2i, _terrain_type: int) -> void:
	# DirtRoad is generated by ForestBiomeTileGenerator, but the previous
	# implementation used an unrelated authored road frame as a repeating strip.
	# Leave this layer empty until its native DirtRoad 36-rule tileset is present.
	pass


func _quad_in(value: float) -> float:
	return value * value


func _quad_in_out(value: float) -> float:
	return 2.0 * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 2.0) * 0.5


func _cube_in_out(value: float) -> float:
	return 4.0 * value * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 3.0) * 0.5


func _sine_in(value: float) -> float:
	return 1.0 - cos(value * PI * 0.5)


func _generate_entity_size_spots(start: Vector2i, finish: Vector2i) -> void:
	_entity_spots.clear()
	var width := finish.x - start.x
	var height := finish.y - start.y
	var macro_columns := ceili(float(width) / 16.0)
	var macro_rows := ceili(float(height) / 16.0)
	var macro_width := width / macro_columns
	var macro_height := height / macro_rows
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var spatial: Dictionary = {}
	const SPATIAL_BUCKET_SIZE := 2.0
	for macro_x in range(macro_columns):
		for macro_y in range(macro_rows):
			var accepted := 1.0
			var attempts := 0
			while float(attempts) < accepted * 1.33 + 16.0:
				attempts += 1
				var local_position := Vector2(
					rng.randf_range(float(macro_x), float(macro_x) + 0.99999) * float(macro_width),
					rng.randf_range(float(macro_y), float(macro_y) + 0.99999) * float(macro_height)
				)
				var local_cell := Vector2i(floori(local_position.x), floori(local_position.y))
				if local_cell.x < 0 or local_cell.y < 0 or local_cell.x >= width or local_cell.y >= height:
					continue
				var cell := start + local_cell
				if _entity_spots.has(cell):
					continue
				var sizes := _entity_sizes_for_biome(int(_biomes.get(cell, BIOME_DRY)))
				if sizes.is_empty():
					continue
				var entity_size := float(sizes[rng.randi_range(0, sizes.size() - 1)])
				var bucket := Vector2i(floori(local_position.x / SPATIAL_BUCKET_SIZE), floori(local_position.y / SPATIAL_BUCKET_SIZE))
				var overlaps := false
				for bucket_y in range(bucket.y - 2, bucket.y + 3):
					for bucket_x in range(bucket.x - 2, bucket.x + 3):
						for entry_value in spatial.get(Vector2i(bucket_x, bucket_y), []):
							var entry := entry_value as Dictionary
							var minimum := entity_size + float(entry.get("size", 0.5))
							if local_position.distance_squared_to(entry.get("position", Vector2.ZERO)) <= minimum * minimum:
								overlaps = true
								break
						if overlaps:
							break
					if overlaps:
						break
				if overlaps:
					continue
				var entry := {"position": local_position, "size": entity_size}
				_entity_spots[cell] = entry
				if not spatial.has(bucket):
					spatial[bucket] = []
				(spatial[bucket] as Array).append(entry)
				accepted += 1.0
				attempts = 0


func _entity_sizes_for_biome(biome: int) -> Array[float]:
	match biome:
		BIOME_WATER:
			return []
		BIOME_FOREST_LIGHT:
			return [0.5, 0.5, 0.5, 1.0, 1.0, 1.5]
		BIOME_FOREST_DEEP:
			return [0.5, 0.5, 0.5, 1.0, 1.0, 1.5, 1.5]
		_:
			return [0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.5]


func _scatter_cell(cell: Vector2i, biome: int, spot: Dictionary) -> void:
	if Vector2(cell).length() < 8.5 or _is_forest_structure(cell) or _plains_cliffs.has(cell):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(cell)
	var start := Vector2i(-world_size_tiles.x / 2, -world_size_tiles.y / 2)
	var position := (Vector2(start) + Vector2(spot.get("position", Vector2.ZERO))) * float(tile_size)
	var entity_size := float(spot.get("size", 0.5))
	var seed_x := world_seed % 32
	var seed_y := (world_seed + 13) % 32
	var ground_value := _ground_values.get_noise_2d(cell.x + seed_x, cell.y + seed_y)
	var structure_value := _structure_values.get_noise_2d(cell.x + seed_x + 7, cell.y + seed_y + 13)
	var ground_value2 := _ground_values2.get_noise_2d(cell.x + seed_x, cell.y + seed_y)
	var structure_value2 := _structure_values2.get_noise_2d(cell.x + seed_x + 14, cell.y + seed_y + 26)
	var density := absf(structure_value2 * ground_value2)
	var product := structure_value * ground_value
	var choice := _tile_random_unit(cell, 0)

	if biome in [BIOME_FOREST, BIOME_FOREST_DEEP]:
		# ForestBiomeEntityGenerator, including its 0.035/0.2 density gates.
		if density > 0.2:
			return
		# The native forest POI catalog contributes mossy boulders separately from
		# the ordinary entity roll. Reserve only large EntitySizeSpots for them so
		# they inherit the same clearance and never form the former rock piles.
		if entity_size >= 1.5 and _tile_random_unit(cell, 0x4D05) <= 0.018:
			_spawn_prop(position, PropKind.MOSSY_ROCK, rng.randi())
			return
		if entity_size <= 0.5 and density > 0.008 and _tile_random_unit(cell, 0xC022) <= 0.012:
			_spawn_prop(position, PropKind.COPPER_ORE, rng.randi())
			return
		var tree_factor := lerpf(0.0, 1.5, density / 0.2)
		if density <= 0.035:
			tree_factor = 0.0
		if _tile_random_unit(cell, 2) <= tree_factor * 0.22:
			var tree_kind := PropKind.TREE_ROUND
			if choice <= 0.33:
				tree_kind = PropKind.TREE_CYPRESS
			elif choice <= 0.345:
				tree_kind = PropKind.APPLE_TREE
			elif choice <= 0.358:
				tree_kind = PropKind.STONE_PINE
			_spawn_prop(position, tree_kind, rng.randi())
			return
		var bush_factor := clampf(lerpf(0.09, 4.0, product), 0.09, 4.0) + tree_factor
		if density > 0.008 and _tile_random_unit(cell, 1) <= bush_factor * 0.11:
			_spawn_prop(position, PropKind.BUSH if choice <= 0.33 else PropKind.SMALL_BUSH, rng.randi())
			return
		if density > 0.008 and _tile_random_unit(cell, 245) <= bush_factor * 0.035:
			_spawn_prop(position, PropKind.MUSHROOM, rng.randi())
			return
		var rock_factor := clampf(lerpf(0.02, 2.0, -product), 0.02, 2.0)
		if density > 0.008 and _tile_random_unit(cell, 7) <= rock_factor * 0.5:
			if -product > 0.8:
				if choice <= 0.13:
					_spawn_prop(position, PropKind.ROCK_SMALL, rng.randi())
				elif choice < 0.29:
					_spawn_prop(position, PropKind.ROCK_BIG, rng.randi())
			elif choice < 0.33:
				_spawn_prop(position, PropKind.ROCK_SMALL, rng.randi())
			elif choice <= 0.40:
				_spawn_prop(position, PropKind.ROCK_BIG, rng.randi())
		return

	if biome == BIOME_FOREST_LIGHT:
		var terrain_value := float(_terrain_values.get(cell, 0.19))
		var blend_x := clampf(1.0 - (0.33 - terrain_value) / 0.28, 0.0, 1.0)
		var transition := lerpf((ground_value + 0.65) / 1.15 - 1.0, (density - 0.035) / 0.165, _quad_in(blend_x))
		if transition > 1.0:
			return
		if entity_size >= 1.5 and _tile_random_unit(cell, 0x4D05) <= 0.014:
			_spawn_prop(position, PropKind.MOSSY_ROCK, rng.randi())
			return
		if entity_size <= 0.5 and density > 0.008 and _tile_random_unit(cell, 0xC022) <= 0.009:
			_spawn_prop(position, PropKind.COPPER_ORE, rng.randi())
			return
		var tree_factor := clampf((transition + 1.0) * 0.5, 0.0, 1.0)
		if _tile_random_unit(cell, 2) <= tree_factor * 0.19:
			var tree_kind := PropKind.TREE_ROUND
			if choice <= 0.33:
				tree_kind = PropKind.TREE_CYPRESS
			elif choice <= 0.355:
				tree_kind = PropKind.APPLE_TREE
			elif choice <= 0.38:
				tree_kind = PropKind.STONE_PINE
			_spawn_prop(position, tree_kind, rng.randi())
			return
		var bush_factor := clampf(lerpf(0.09, 4.0, transition), 0.09, 4.0) + tree_factor
		if density > 0.008 and _tile_random_unit(cell, 1) <= bush_factor * 0.11:
			_spawn_prop(position, PropKind.BUSH if choice <= 0.33 else PropKind.SMALL_BUSH, rng.randi())
			return
		var rock_factor := clampf(lerpf(0.02, 2.0, -transition), 0.02, 2.0)
		if density > 0.008 and _tile_random_unit(cell, 7) <= rock_factor * 0.03:
			if -product > 0.8:
				if choice <= 0.13:
					_spawn_prop(position, PropKind.ROCK_SMALL, rng.randi())
				elif choice < 0.29:
					_spawn_prop(position, PropKind.ROCK_BIG, rng.randi())
			elif choice < 0.33:
				_spawn_prop(position, PropKind.ROCK_SMALL, rng.randi())
			elif choice <= 0.40:
				_spawn_prop(position, PropKind.ROCK_BIG, rng.randi())
		return

	if biome == BIOME_MEADOW:
		# PlainsBiomeEntityGenerator: bushes/trees rise with GroundValues; rocks
		# use a separate deterministic roll. Decorative flowers belong to the
		# ground renderer and are deliberately not spawned as cut resource sprites.
		if ground_value > 0.0 and _tile_random_unit(cell, 5) <= clampf(ground_value / 0.5, 0.0, 1.0) * 0.084375:
			_spawn_prop(position, PropKind.BUSH, rng.randi())
			return
		if entity_size <= 0.5 and _tile_random_unit(cell, 0xC022) <= 0.008:
			_spawn_prop(position, PropKind.COPPER_ORE, rng.randi())
			return
		if ground_value > -0.65 and _tile_random_unit(cell, 6) <= clampf(ground_value * 1.2, 0.0, 1.0) * 0.12:
			_spawn_prop(position, PropKind.TREE_CYPRESS if choice <= 0.33 else PropKind.TREE_ROUND, rng.randi())
			return
		if _tile_random_unit(cell, 7) <= 0.13:
			if choice < 0.33:
				_spawn_prop(position, PropKind.ROCK_SMALL, rng.randi())
			elif choice < 0.40:
				_spawn_prop(position, PropKind.ROCK_BIG, rng.randi())
		return

	# DryPlainsBiomeEntityGenerator. Dry-tall cells carry trees/wheat; open
	# ground carries the native round rocks, bushes and occasional olive tree.
	if int(_terrain_types.get(cell, TERRAIN_BASE)) == TERRAIN_FOREST_DEEP:
		if entity_size >= 1.0:
			if choice < 0.40:
				_spawn_prop(position, PropKind.TREE_ROUND, rng.randi())
			elif choice < 0.55:
				_spawn_prop(position, PropKind.TREE_CYPRESS, rng.randi())
			elif choice < 0.60:
				_spawn_prop(position, PropKind.TREE_CYPRESS, rng.randi())
			elif choice < 0.65:
				_spawn_prop(position, PropKind.STONE_PINE, rng.randi())
			return
		if _tile_random_unit(cell, 3) < 0.041:
			_spawn_prop(position, PropKind.WHEAT, rng.randi())
		return
	if entity_size >= 1.0:
		if choice < 0.09:
			_spawn_prop(position, PropKind.ROCK_BIG, rng.randi())
		elif choice < 0.11:
			_spawn_prop(position, PropKind.TREE_OLIVE, rng.randi())
		elif choice < 0.12:
			_spawn_prop(position, PropKind.STONE_PINE, rng.randi())
		return
	if _tile_random_unit(cell, 6) <= 0.12 and choice < 0.34:
		_spawn_prop(position, PropKind.ROCK_SMALL, rng.randi())
	elif _tile_random_unit(cell, 9) <= 0.02:
		_spawn_prop(position, PropKind.TREE_OLIVE, rng.randi())


func _tile_random_unit(cell: Vector2i, salt: int) -> float:
	var value := _cell_seed(cell) ^ (salt * 374761393)
	value = int((value ^ (value >> 13)) * 1274126177)
	value ^= value >> 16
	return float(posmod(value, 1000000)) / 999999.0


func _spawn_prop(prop_position: Vector2, kind: PropKind, variation_seed: int = 0) -> void:
	if kind == PropKind.FLOOR_DETAIL:
		var detail_cell := Vector2i(roundi(prop_position.x / float(tile_size)), roundi(prop_position.y / float(tile_size)))
		var detail_rng := RandomNumberGenerator.new()
		detail_rng.seed = variation_seed
		if detail_rng.randf() < 0.45:
			_tiny_flowers.set_cell(detail_cell, 0, Vector2i(detail_rng.randi_range(0, 1), detail_rng.randi_range(0, 1)), 0)
		else:
			_tiny_leaves.set_cell(detail_cell, 0, Vector2i(detail_rng.randi_range(0, 7), detail_rng.randi_range(0, 1)), 0)
		return
	var root := Node2D.new()
	root.position = prop_position.round()
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	if kind in [PropKind.BUSH, PropKind.WHEAT, PropKind.GROUND_PLANT, PropKind.FLOWER, PropKind.PURPLE_BUSH, PropKind.SMALL_BUSH, PropKind.FLOOR_DETAIL]:
		_vegetation.add_child(root)
	else:
		_props.add_child(root)
	match kind:
		PropKind.TREE_ROUND:
			_build_round_tree(root, rng)
		PropKind.TREE_OLIVE:
			_build_olive_tree(root, rng)
		PropKind.TREE_CYPRESS:
			_build_cypress(root, rng)
		PropKind.ROCK_BIG:
			_build_single_sprite_prop(root, _textures["rock_big"], Rect2i(rng.randi_range(0, 4) * 48, rng.randi_range(0, 1) * 48, 48, 48))
		PropKind.ROCK_SMALL:
			_build_single_sprite_prop(root, _textures["rock_small"], Rect2i(rng.randi_range(0, 3) * 32, rng.randi_range(0, 1) * 32, 32, 32))
		PropKind.BUSH:
			_build_wind_sprite(root, _textures["bush"], Rect2i(rng.randi_range(0, 6) * 32, rng.randi_range(0, 2) * 32, 32, 32), rng.randf(), 1.0)
		PropKind.WHEAT:
			_build_wind_sprite(root, _textures["wheat"], Rect2i(rng.randi_range(0, 3) * 16, rng.randi_range(2, 7) * 32, 16, 32), rng.randf(), 1.0)
		PropKind.GROUND_PLANT:
			_build_wind_sprite(root, _textures["ground_plants"], Rect2i(rng.randi_range(0, 5) * 32, rng.randi_range(0, 1) * 32, 32, 32), rng.randf(), 0.42)
		PropKind.APPLE_TREE:
			_build_layered_native_tree(root, _textures["apple_stump"], Rect2i(64, 0, 64, 80), _textures["apple_tree"], Rect2i(64, 0, 64, 80), rng)
		PropKind.STONE_PINE:
			var pine_frame := rng.randi_range(0, 5)
			_build_layered_native_tree(root, _textures["stone_pine_stump"], Rect2i(pine_frame * 80, 0, 80, 80), _textures["stone_pine"], Rect2i(pine_frame * 80, 0, 80, 80), rng)
		PropKind.MOSSY_ROCK:
			_build_single_sprite_prop(root, _textures["mossy_boulder"], Rect2i(0, 0, 64, 80))
		PropKind.COPPER_ORE:
			_build_single_sprite_prop(root, _textures["copper_ore"], Rect2i(rng.randi_range(0, 1) * 16, rng.randi_range(0, 3) * 16, 16, 16))
		PropKind.MUSHROOM:
			_build_single_sprite_prop(root, _textures["mushrooms"], Rect2i(rng.randi_range(0, 5) * 16, 0, 16, 16))
		PropKind.FLOWER:
			_build_wind_sprite(root, _textures["bellflowers"], Rect2i(rng.randi_range(0, 3) * 16, rng.randi_range(0, 9) * 16, 16, 16), rng.randf(), 0.45)
		PropKind.PURPLE_BUSH:
			_build_wind_sprite(root, _textures["purple_bush"], Rect2i(0, rng.randi_range(0, 2) * 32, 16, 32), rng.randf(), 0.75)
		PropKind.SMALL_BUSH:
			_build_wind_sprite(root, _textures["small_bush"], Rect2i(rng.randi_range(0, 10) * 16, 0, 16, 16), rng.randf(), 0.55)
		PropKind.BRAZIER:
			_build_brazier(root)


func _build_layered_native_tree(root: Node2D, stump_texture: Texture2D, stump_rect: Rect2i, canopy_texture: Texture2D, canopy_rect: Rect2i, rng: RandomNumberGenerator) -> void:
	_add_sprite(root, stump_texture, stump_rect, Vector2(0.0, -float(stump_rect.size.y) * 0.5), 1)
	_add_projected_shadow(root, canopy_texture, canopy_rect, Vector2(0.0, -float(canopy_rect.size.y) * 0.5 - 5.0), 0.16)
	_add_wind_pivot_sprite(root, canopy_texture, canopy_rect, Vector2(0.0, -float(canopy_rect.size.y) * 0.5 - 5.0), rng.randf(), 0.2, 1.0)


func _build_round_tree(root: Node2D, rng: RandomNumberGenerator) -> void:
	var stump_rect := Rect2i(rng.randi_range(0, 1) * 32, 0, 32, 32)
	_add_projected_shadow(root, _textures["stump"], stump_rect, Vector2(0.0, -16.0), 0.12)
	_add_sprite(root, _textures["stump"], stump_rect, Vector2(0.0, -16.0), 1)
	if rng.randf() < 0.72:
		var canopy_rect := Rect2i(rng.randi_range(0, 1) * 48, 0, 48, 80)
		_add_projected_shadow(root, _textures["tree1"], canopy_rect, Vector2(0.0, -40.0), 0.16)
		_add_wind_pivot_sprite(root, _textures["tree1"], canopy_rect, Vector2(0.0, -40.0), rng.randf(), 0.2, 1.0)
	else:
		var canopy_rect := Rect2i(rng.randi_range(0, 2) * 64, rng.randi_range(0, 1) * 96, 64, 96)
		_add_projected_shadow(root, _textures["tree2"], canopy_rect, Vector2(0.0, -48.0), 0.15)
		_add_wind_pivot_sprite(root, _textures["tree2"], canopy_rect, Vector2(0.0, -48.0), rng.randf(), 0.2, 1.0)


func _build_olive_tree(root: Node2D, rng: RandomNumberGenerator) -> void:
	var stump_rect := Rect2i(0, 0, 32, 32)
	var canopy_rect := Rect2i(rng.randi_range(0, 1) * 64, 0, 64, 80)
	_add_projected_shadow(root, _textures["olive_stump"], stump_rect, Vector2(0.0, -16.0), 0.12)
	_add_projected_shadow(root, _textures["olive_tree"], canopy_rect, Vector2(0.0, -40.0), 0.16)
	_add_sprite(root, _textures["olive_stump"], stump_rect, Vector2(0.0, -16.0), 1)
	_add_wind_pivot_sprite(root, _textures["olive_tree"], canopy_rect, Vector2(0.0, -40.0), rng.randf(), 0.2, 1.0)


func _build_cypress(root: Node2D, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.60:
		var rect := Rect2i(0, 0, 32, 96)
		_add_projected_shadow(root, _textures["cypress"], rect, Vector2(0.0, -48.0), 0.15)
		_add_wind_pivot_sprite(root, _textures["cypress"], rect, Vector2(0.0, -48.0), rng.randf(), 0.2, 1.0)
	else:
		var rect := Rect2i(rng.randi_range(0, 3) * 32, rng.randi_range(0, 6) * 80, 32, 80)
		_add_projected_shadow(root, _textures["skinny_tree"], rect, Vector2(0.0, -40.0), 0.15)
		_add_wind_pivot_sprite(root, _textures["skinny_tree"], rect, Vector2(0.0, -40.0), rng.randf(), 0.2, 1.0)


func _build_single_sprite_prop(root: Node2D, texture: Texture2D, rect: Rect2i) -> void:
	var position := Vector2(0.0, -float(rect.size.y) * 0.5)
	_add_projected_shadow(root, texture, rect, position, 0.13)
	_add_sprite(root, texture, rect, position, 2)


func _build_wind_sprite(root: Node2D, texture: Texture2D, rect: Rect2i, phase: float, sway_scale: float) -> void:
	var position := Vector2(0.0, -float(rect.size.y) * 0.5)
	_add_projected_shadow(root, texture, rect, position, 0.11)
	_add_wind_pivot_sprite(root, texture, rect, position, phase, 0.3, sway_scale)


func _add_wind_pivot_sprite(root: Node2D, texture: Texture2D, rect: Rect2i, sprite_position: Vector2, phase: float, sway_speed: float, sway_scale: float) -> Sprite2D:
	# The native game rotates a rigid sprite around its grounded mesh offset.
	# Keeping the pivot at the entity root makes every bottom pixel stationary.
	var pivot := Node2D.new()
	pivot.set_meta("wind_timer", lerpf(-10000.0, -1000.0, phase))
	pivot.set_meta("sway_speed", sway_speed)
	pivot.set_meta("sway_scale", sway_scale)
	pivot.add_to_group("romestead_wind_pivots")
	root.add_child(pivot)
	_wind_pivots.append(pivot)
	return _add_sprite(pivot, texture, rect, sprite_position, 2)


func _build_brazier(root: Node2D) -> void:
	_add_sprite(root, _textures["brazier"], Rect2i(0, 0, 32, 32), Vector2(0.0, -16.0), 2)
	var light := PointLight2D.new()
	light.texture = _light_cookie
	light.texture_scale = 1.8
	light.color = Color(1.0, 0.57, 0.24)
	light.energy = 1.15
	light.shadow_enabled = false
	light.position = Vector2(0.0, -10.0)
	light.set_meta("base_energy", 1.15)
	light.set_meta("flicker_phase", float(_props.get_child_count()) * 1.73)
	light.add_to_group("romestead_lab_lights")
	root.add_child(light)


func _add_sprite(root: Node2D, texture: Texture2D, rect: Rect2i, position: Vector2, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _atlas_region(texture, rect)
	sprite.position = position
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = z
	root.add_child(sprite)
	return sprite


func _add_projected_shadow(root: Node2D, texture: Texture2D, rect: Rect2i, source_position: Vector2, alpha: float) -> void:
	var shadow := Sprite2D.new()
	shadow.texture = _atlas_region(texture, rect)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.modulate = Color(0.11, 0.12, 0.075, alpha)
	shadow.z_index = -2
	shadow.set_meta("source_position", source_position)
	shadow.set_meta("base_alpha", alpha)
	shadow.add_to_group("romestead_projected_shadows")
	root.add_child(shadow)
	_apply_shadow_transform(shadow, 15.0, 1.0)


func _update_projected_shadows(hour: float, daylight: float) -> void:
	for node in get_tree().get_nodes_in_group("romestead_projected_shadows"):
		var shadow := node as Sprite2D
		if shadow != null:
			_apply_shadow_transform(shadow, hour, daylight)


func _apply_shadow_transform(shadow: Sprite2D, hour: float, daylight: float) -> void:
	var solar_angle := clampf((hour - 6.0) / 12.0, 0.0, 1.0) * PI
	var horizontal := clampf(-cos(solar_angle), -1.0, 1.0) * 0.42
	var vertical_scale := 0.18 + absf(cos(solar_angle)) * 0.12
	var source_position: Vector2 = shadow.get_meta("source_position", Vector2.ZERO)
	var y_basis := Vector2(-horizontal, vertical_scale)
	var projected_position := Vector2(source_position.x + y_basis.x * source_position.y, y_basis.y * source_position.y)
	shadow.transform = Transform2D(Vector2(1.0, 0.0), y_basis, projected_position)
	var base_alpha := float(shadow.get_meta("base_alpha", 0.14))
	var light_strength := lerpf(0.28, 1.0, clampf(daylight * 1.15, 0.0, 1.0))
	shadow.modulate.a = base_alpha * light_strength


func _spawn_light_landmarks() -> void:
	for position in [Vector2(-620.0, 360.0), Vector2(610.0, -330.0), Vector2(600.0, 350.0)]:
		_spawn_prop(position, PropKind.BRAZIER, int(position.x * 17.0 + position.y * 31.0))


func _clear_generated_content() -> void:
	for layer in _all_tile_layers():
		layer.clear()
	_biomes.clear()
	_terrain_types.clear()
	_terrain_values.clear()
	_forest_barriers.clear()
	_forest_tree_left.clear()
	_forest_tree_right.clear()
	_plains_cliffs.clear()
	_entity_spots.clear()
	_wind_pivots.clear()
	for container in [_props, _vegetation]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()


func _atlas_region(texture: Texture2D, rect: Rect2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(rect)
	return atlas


func _cell_seed(cell: Vector2i) -> int:
	var mixed := world_seed
	mixed ^= cell.x * 73856093
	mixed ^= cell.y * 19349663
	return absi(mixed)


func _normalized(value: float) -> float:
	return clampf((value + 1.0) * 0.5, 0.0, 1.0)


func _load_svg_texture(resource_path: String) -> Texture2D:
	var svg_text := FileAccess.get_file_as_string(resource_path)
	if svg_text.is_empty():
		push_error("Could not read editable lab asset: %s" % resource_path)
		return ImageTexture.new()
	var image := Image.new()
	var error := image.load_svg_from_string(svg_text, 1.0)
	if error != OK:
		push_error("Could not rasterize editable lab asset: %s" % resource_path)
		return ImageTexture.new()
	return ImageTexture.create_from_image(image)


func _load_png_texture(resource_path: String) -> Texture2D:
	var texture := load(resource_path) as Texture2D
	if texture == null:
		push_error("Could not load native PNG lab asset: %s" % resource_path)
		return ImageTexture.new()
	return texture
