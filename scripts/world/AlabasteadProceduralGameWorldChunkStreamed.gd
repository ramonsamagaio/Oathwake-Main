class_name AlabasteadProceduralGameWorldChunkStreamed
extends "res://scripts/world/AlabasteadProceduralGameWorldOptimized.gd"

# The full seed/map stays deterministic, but runtime materialization is split
# into smaller packets so a streaming tick cannot monopolize a 16.67 ms frame.
const RUNTIME_TERRAIN_CHUNK_TILES: int = 8
const INITIAL_PROP_CELL_BUDGET: int = 64

# EntitySizeSpotsGenerator already resolves the deterministic placement/spacings
# for the complete seed. Keep that lightweight global result, but defer the
# expensive scatter work until the corresponding terrain chunk is materialized.
var _entity_spots_by_terrain_chunk: Dictionary = {}
var _scheduled_prop_chunks: Dictionary = {}
var _deferred_prop_cells: Array[Vector2i] = []
var _deferred_prop_cursor: int = 0


func generate_world(new_seed: int = world_seed) -> void:
	_entity_spots_by_terrain_chunk.clear()
	_scheduled_prop_chunks.clear()
	_deferred_prop_cells.clear()
	_deferred_prop_cursor = 0
	super.generate_world(new_seed)

	# Seed a small amount of nearby content immediately so the first playable
	# frame does not begin as an empty terrain shell. Everything beyond this tiny
	# budget is admitted by the runtime scheduler in bounded batches.
	_generation_resource_bounds = _compute_active_bounds().grow(64.0)
	process_deferred_props(INITIAL_PROP_CELL_BUDGET)
	_generation_resource_bounds = Rect2()


func _terrain_chunk_for_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(RUNTIME_TERRAIN_CHUNK_TILES)),
		floori(float(cell.y) / float(RUNTIME_TERRAIN_CHUNK_TILES))
	)


func _scatter_cell(cell: Vector2i, biome: int, spot: Dictionary) -> void:
	# Before terrain streaming starts, index accepted cells only. Detail sprites
	# and functional resource dictionaries are created later when the matching
	# microchunk enters the active streaming neighborhood.
	if not _terrain_generation_ready:
		var chunk: Vector2i = _terrain_chunk_for_cell(cell)
		if not _entity_spots_by_terrain_chunk.has(chunk):
			_entity_spots_by_terrain_chunk[chunk] = []
		var cells: Array = _entity_spots_by_terrain_chunk[chunk] as Array
		cells.append(cell)
		return

	super._scatter_cell(cell, biome, spot)


func _render_terrain_chunk(chunk: Vector2i) -> void:
	if _rendered_terrain_chunks.has(chunk):
		return

	# 8x8 runtime microchunks reduce the worst terrain packet from 256 cells to
	# 64 cells. The parent stream planner calls this virtual method, so world
	# topology and seed stay identical while frame-time spikes become much smaller.
	var chunk_start: Vector2i = chunk * RUNTIME_TERRAIN_CHUNK_TILES
	var chunk_finish: Vector2i = chunk_start + Vector2i.ONE * RUNTIME_TERRAIN_CHUNK_TILES
	var start_x: int = maxi(chunk_start.x, _terrain_world_start.x)
	var start_y: int = maxi(chunk_start.y, _terrain_world_start.y)
	var finish_x: int = mini(chunk_finish.x, _terrain_world_finish.x)
	var finish_y: int = mini(chunk_finish.y, _terrain_world_finish.y)

	for tile_y: int in range(start_y, finish_y):
		for tile_x: int in range(start_x, finish_x):
			var terrain_cell := Vector2i(tile_x, tile_y)
			var terrain_type: int = int(_terrain_types.get(terrain_cell, TERRAIN_BASE))
			_ground.set_cell(terrain_cell, 0, Vector2i(2, 1), 0)
			_draw_native_autotile(terrain_cell, TERRAIN_DIRT, _dirt_layers)
			_draw_native_autotile(terrain_cell, TERRAIN_GREEN, _green_layers)
			_draw_native_autotile(terrain_cell, TERRAIN_FOREST_LIGHT, _forest_light_layers)
			_draw_native_autotile(terrain_cell, TERRAIN_FOREST_DEEP, _forest_deep_layers)
			_draw_forest_path(terrain_cell, terrain_type)
			_draw_plains_cliff(terrain_cell)
			_draw_forest_barrier(terrain_cell)
			_draw_native_detail(terrain_cell, terrain_type)

	_rendered_terrain_chunks[chunk] = true
	_queue_props_for_chunk(chunk)


func _queue_props_for_chunk(chunk: Vector2i) -> void:
	if _scheduled_prop_chunks.has(chunk):
		return
	_scheduled_prop_chunks[chunk] = true

	var cells_value: Variant = _entity_spots_by_terrain_chunk.get(chunk, null)
	if not (cells_value is Array):
		return
	var cells: Array = cells_value as Array
	for cell_value: Variant in cells:
		if cell_value is Vector2i:
			_deferred_prop_cells.append(cell_value as Vector2i)

	# Source placement data remains authoritative in _entity_spots. Only this
	# temporary chunk lookup can be released once its cells enter the queue.
	_entity_spots_by_terrain_chunk.erase(chunk)


func process_deferred_props(max_cells: int) -> int:
	if max_cells <= 0:
		return 0
	var processed: int = 0
	while processed < max_cells and _deferred_prop_cursor < _deferred_prop_cells.size():
		var prop_cell: Vector2i = _deferred_prop_cells[_deferred_prop_cursor]
		_deferred_prop_cursor += 1
		processed += 1

		var spot_value: Variant = _entity_spots.get(prop_cell, null)
		if not (spot_value is Dictionary):
			continue
		super._scatter_cell(
			prop_cell,
			int(_biomes.get(prop_cell, BIOME_DRY)),
			spot_value as Dictionary
		)

	# Normally the scheduler catches up quickly. Clearing a fully consumed queue
	# keeps explored-world bookkeeping from growing forever without pop_front().
	if _deferred_prop_cursor >= _deferred_prop_cells.size():
		_deferred_prop_cells.clear()
		_deferred_prop_cursor = 0
	return processed


func _draw_plains_cliff(cell: Vector2i) -> void:
	if not _plains_cliffs.has(cell):
		return
	var mask: int = _plains_cliff_mask(cell)
	if mask <= 0 or mask >= PLAINS_CLIFF_BASE_FRAMES.size():
		return
	var options: Array = PLAINS_CLIFF_BASE_FRAMES[mask] as Array
	if options.is_empty():
		return

	var frame: int = int(options[posmod(cell.x + cell.y, options.size())])
	var top_coord := Vector2i(
		frame % PLAINS_CLIFF_ATLAS_COLUMNS,
		frame / PLAINS_CLIFF_ATLAS_COLUMNS
	)
	_plains_cliff_layers[0].set_cell(cell, 0, top_coord, 0)

	# A face is a SOUTHERN boundary extrusion. The previous port also extruded
	# cells that had another cliff directly below them, so vertically adjacent
	# structures painted 2-tile walls over each other's caps. That produced the
	# tall rectangular "rock tower" seen in-game. Preserve the native mask gate,
	# but never emit a wall through another logical cliff cell.
	var native_face: bool = ((1 << mask) & PLAINS_CLIFF_FACE_MASK) != 0
	var southern_boundary: bool = not _plains_cliffs.has(cell + Vector2i.DOWN)
	if native_face and southern_boundary:
		for face_row: int in range(1, PLAINS_CLIFF_HEIGHT + 1):
			var face_frame: int = frame + PLAINS_CLIFF_ATLAS_COLUMNS * face_row
			var face_coord := Vector2i(
				face_frame % PLAINS_CLIFF_ATLAS_COLUMNS,
				face_frame / PLAINS_CLIFF_ATLAS_COLUMNS
			)
			_plains_cliff_layers[face_row].set_cell(
				cell + Vector2i.DOWN * face_row,
				0,
				face_coord,
				0
			)

	_plains_cliff_collision.set_cell(cell, 0, Vector2i(0, 4), 0)


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
		var entity_cell: Vector2i = cell_value as Vector2i
		var spot_value: Variant = _entity_spots.get(entity_cell, null)
		if not (spot_value is Dictionary):
			continue
		var spot: Dictionary = spot_value as Dictionary
		var source_position_value: Variant = spot.get("position", Vector2.ZERO)
		if not (source_position_value is Vector2):
			continue
		var source_position: Vector2 = source_position_value as Vector2
		var local_prop_position: Vector2 = (
			Vector2(world_start) + source_position
		) * float(tile_size)
		var clearance: float = maxf(float(spot.get("size", 0.5)) * float(tile_size), 6.0)
		_wildlife_spatial_add(spatial, local_prop_position, clearance)
	return spatial


func get_generation_diagnostics() -> Dictionary:
	var result: Dictionary = super.get_generation_diagnostics()
	result["runtime_terrain_chunk_tiles"] = RUNTIME_TERRAIN_CHUNK_TILES
	result["deferred_prop_chunks"] = _entity_spots_by_terrain_chunk.size()
	result["scheduled_prop_chunks"] = _scheduled_prop_chunks.size()
	result["pending_deferred_prop_cells"] = maxi(
		_deferred_prop_cells.size() - _deferred_prop_cursor,
		0
	)
	return result
