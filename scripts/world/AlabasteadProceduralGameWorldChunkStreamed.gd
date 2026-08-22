class_name AlabasteadProceduralGameWorldChunkStreamed
extends "res://scripts/world/AlabasteadProceduralGameWorldOptimized.gd"

# EntitySizeSpotsGenerator already resolves the deterministic placement/spacings
# for the complete seed. Keep that lightweight global result, but defer the
# expensive scatter work until the corresponding terrain chunk is materialized.
var _entity_spots_by_terrain_chunk: Dictionary = {}
var _materialized_prop_chunks: Dictionary = {}


func generate_world(new_seed: int = world_seed) -> void:
	_entity_spots_by_terrain_chunk.clear()
	_materialized_prop_chunks.clear()
	super.generate_world(new_seed)


func _scatter_cell(cell: Vector2i, biome: int, spot: Dictionary) -> void:
	# AlabasteadProceduralGameWorldOptimized performs one global scatter pass
	# before terrain streaming starts. During that pass, index only the accepted
	# cells. Detail sprites and functional resource dictionaries are created later
	# when the 16x16 terrain chunk enters the active streaming neighborhood.
	if not _terrain_generation_ready:
		var chunk: Vector2i = _terrain_chunk_for_cell(cell)
		if not _entity_spots_by_terrain_chunk.has(chunk):
			_entity_spots_by_terrain_chunk[chunk] = []
		var cells: Array = _entity_spots_by_terrain_chunk[chunk] as Array
		cells.append(cell)
		return

	super._scatter_cell(cell, biome, spot)


func _render_terrain_chunk(chunk: Vector2i) -> void:
	var already_rendered: bool = _rendered_terrain_chunks.has(chunk)
	super._render_terrain_chunk(chunk)
	if already_rendered or _materialized_prop_chunks.has(chunk):
		return

	_materialized_prop_chunks[chunk] = true
	var cells_value: Variant = _entity_spots_by_terrain_chunk.get(chunk, null)
	if not (cells_value is Array):
		return

	var cells: Array = cells_value as Array
	for cell_value: Variant in cells:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value as Vector2i
		var spot_value: Variant = _entity_spots.get(cell, null)
		if not (spot_value is Dictionary):
			continue
		super._scatter_cell(
			cell,
			int(_biomes.get(cell, BIOME_DRY)),
			spot_value as Dictionary
		)

	# Once a chunk has been materialized its temporary lookup list is no longer
	# needed. Deterministic source data remains in _entity_spots for save/respawn.
	_entity_spots_by_terrain_chunk.erase(chunk)


func _build_wildlife_resource_spatial() -> Dictionary:
	var spatial: Dictionary = super._build_wildlife_resource_spatial()
	# Distant props have not been scattered yet, but accepted EntitySizeSpots
	# already tell us where a prop may exist. Add those candidate positions as a
	# conservative clearance mask so globally seeded wildlife cannot appear inside
	# a tree/rock that will materialize when its chunk streams later.
	var world_start := Vector2i(-world_size_tiles.x / 2, -world_size_tiles.y / 2)
	for cell_value: Variant in _entity_spots.keys():
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value as Vector2i
		var spot_value: Variant = _entity_spots.get(cell, null)
		if not (spot_value is Dictionary):
			continue
		var spot: Dictionary = spot_value as Dictionary
		var source_position_value: Variant = spot.get("position", Vector2.ZERO)
		if not (source_position_value is Vector2):
			continue
		var source_position: Vector2 = source_position_value as Vector2
		var local_position: Vector2 = (
			Vector2(world_start) + source_position
		) * float(tile_size)
		var clearance: float = maxf(float(spot.get("size", 0.5)) * float(tile_size), 6.0)
		_wildlife_spatial_add(spatial, local_position, clearance)
	return spatial


func get_generation_diagnostics() -> Dictionary:
	var result: Dictionary = super.get_generation_diagnostics()
	result["deferred_prop_chunks"] = _entity_spots_by_terrain_chunk.size()
	result["materialized_prop_chunks"] = _materialized_prop_chunks.size()
	return result
