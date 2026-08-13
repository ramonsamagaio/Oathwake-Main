@tool
class_name ProceduralTerrainRegion2D
extends Node2D

signal terrain_generated(seed: int, generated_cell_count: int)

@export var profile: ProceduralTerrainProfile
@export var generation_size_tiles: Vector2i = Vector2i(44, 28)
@export var generate_on_ready := true
@export var clear_before_generate := true
@export_node_path("TileMapLayer") var ground_layer_path := NodePath("Ground")
@export_node_path("Node2D") var grass_field_path := NodePath("Grass")

var _sampler: ProceduralTerrainSampler


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if generate_on_ready:
		call_deferred("generate")


func generate() -> void:
	var ground := get_node_or_null(ground_layer_path) as TileMapLayer
	if ground == null:
		push_error("ProceduralTerrainRegion2D requires a TileMapLayer at ground_layer_path.")
		return
	if profile == null:
		push_error("ProceduralTerrainRegion2D requires a ProceduralTerrainProfile.")
		return

	if clear_before_generate:
		ground.clear()

	_sampler = ProceduralTerrainSampler.new(profile)

	var dirt_cells: Array[Vector2i] = []
	var grass_cells: Array[Vector2i] = []
	var start := Vector2i(
		-floori(float(generation_size_tiles.x) * 0.5),
		-floori(float(generation_size_tiles.y) * 0.5)
	)

	for y in range(generation_size_tiles.y):
		for x in range(generation_size_tiles.x):
			var cell := start + Vector2i(x, y)
			var local_center := ground.map_to_local(cell)
			var world_center := ground.to_global(local_center)
			if _sampler.is_grass(world_center):
				grass_cells.append(cell)
			else:
				dirt_cells.append(cell)

	if not dirt_cells.is_empty():
		ground.set_cells_terrain_connect(dirt_cells, 0, 0, true)
	if not grass_cells.is_empty():
		ground.set_cells_terrain_connect(grass_cells, 0, 1, true)
	ground.update_internals()

	var grass_field := get_node_or_null(grass_field_path)
	if grass_field != null and grass_field.has_method("rebuild"):
		grass_field.call_deferred("rebuild")

	terrain_generated.emit(profile.world_seed, dirt_cells.size() + grass_cells.size())


func regenerate_with_seed(new_seed: int) -> void:
	if profile == null:
		return
	profile.world_seed = new_seed
	generate()


func get_sampler() -> ProceduralTerrainSampler:
	if _sampler == null and profile != null:
		_sampler = ProceduralTerrainSampler.new(profile)
	return _sampler
