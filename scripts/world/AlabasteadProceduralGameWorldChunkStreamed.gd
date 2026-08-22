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


func get_generation_diagnostics() -> Dictionary:
	var result: Dictionary = super.get_generation_diagnostics()
	result["deferred_prop_chunks"] = _entity_spots_by_terrain_chunk.size()
	result["materialized_prop_chunks"] = _materialized_prop_chunks.size()
	return result
