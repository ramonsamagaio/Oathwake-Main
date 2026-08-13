@tool
class_name ProceduralTerrainRegion2D
extends Node2D

signal terrain_generated(seed: int, generated_cell_count: int)

const TERRAIN_SOURCE_ID := 0

# The existing dual-mask atlas is a complete 4-corner terrain set. Mapping the
# sampled corner mask directly to atlas coordinates guarantees that every
# generated cell receives a valid tile instead of asking terrain-connect to
# solve a partially authored neighborhood at runtime.
const TERRAIN_ATLAS_BY_CORNER_MASK := {
	0: Vector2i(0, 3),
	1: Vector2i(1, 3),
	2: Vector2i(0, 0),
	3: Vector2i(3, 0),
	4: Vector2i(3, 3),
	5: Vector2i(0, 1),
	6: Vector2i(3, 2),
	7: Vector2i(2, 0),
	8: Vector2i(0, 2),
	9: Vector2i(1, 0),
	10: Vector2i(2, 3),
	11: Vector2i(1, 1),
	12: Vector2i(1, 2),
	13: Vector2i(2, 2),
	14: Vector2i(3, 1),
	15: Vector2i(2, 1),
}

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

	var generated_cell_count := 0
	var start := Vector2i(
		-floori(float(generation_size_tiles.x) * 0.5),
		-floori(float(generation_size_tiles.y) * 0.5)
	)

	for y in range(generation_size_tiles.y):
		for x in range(generation_size_tiles.x):
			var cell := start + Vector2i(x, y)
			var corner_mask := _terrain_corner_mask(ground, cell)
			var atlas_coords: Vector2i = TERRAIN_ATLAS_BY_CORNER_MASK.get(
				corner_mask,
				Vector2i(0, 3)
			)
			ground.set_cell(cell, TERRAIN_SOURCE_ID, atlas_coords, 0)
			generated_cell_count += 1

	ground.update_internals()

	var grass_field := get_node_or_null(grass_field_path)
	if grass_field != null and grass_field.has_method("rebuild"):
		grass_field.call_deferred("rebuild")

	terrain_generated.emit(profile.world_seed, generated_cell_count)


func regenerate_with_seed(new_seed: int) -> void:
	if profile == null:
		return
	profile.world_seed = new_seed
	generate()


func get_sampler() -> ProceduralTerrainSampler:
	if _sampler == null and profile != null:
		_sampler = ProceduralTerrainSampler.new(profile)
	return _sampler


func _terrain_corner_mask(ground: TileMapLayer, cell: Vector2i) -> int:
	var local_center := ground.map_to_local(cell)
	var half_tile := float(profile.tile_size_pixels) * 0.5
	var mask := 0

	# Bit order mirrors the TileSet peering bits used by the authored atlas:
	# 1 bottom-right, 2 bottom-left, 4 top-left, 8 top-right.
	if _is_grass_at_local(ground, local_center + Vector2(half_tile, half_tile)):
		mask |= 1
	if _is_grass_at_local(ground, local_center + Vector2(-half_tile, half_tile)):
		mask |= 2
	if _is_grass_at_local(ground, local_center + Vector2(-half_tile, -half_tile)):
		mask |= 4
	if _is_grass_at_local(ground, local_center + Vector2(half_tile, -half_tile)):
		mask |= 8

	return mask


func _is_grass_at_local(ground: TileMapLayer, local_position: Vector2) -> bool:
	return _sampler.is_grass(ground.to_global(local_position))
