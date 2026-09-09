extends "res://scripts/world/AlabasteadProceduralGameWorldChunkStreamed.gd"

# Final Romestead retarget layer. It keeps the inherited native biome keypoint
# selection and streaming architecture, but exposes the values needed by the
# Content Editor and turns the already-selected desert keypoint into a real biome.

const BIOME_DESERT := 8
const RETARGET_WORLD_GEN_CONFIG_PATH := "res://data/world_gen.json"
const NATIVE_KEYPOINT_RADIUS_RATIO := 0.375

var biome_noise_scale := 1.0
var biome_keypoint_radius_ratio := NATIVE_KEYPOINT_RADIUS_RATIO
var desert_radius_tiles := 100
var desert_transition_tiles := 32
var desert_irregularity := 0.3
var desert_prop_density := 0.22
var runtime_terrain_chunk_tiles := 8


func _apply_world_gen_config() -> void:
	super._apply_world_gen_config()
	if not FileAccess.file_exists(RETARGET_WORLD_GEN_CONFIG_PATH):
		return
	var file := FileAccess.open(RETARGET_WORLD_GEN_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	var document: Dictionary = json.data
	var record_value: Variant = document.get("default", {})
	if not record_value is Dictionary:
		return
	var config: Dictionary = record_value

	biome_noise_scale = clampf(float(config.get("biome_noise_scale", biome_noise_scale)), 0.35, 3.0)
	biome_keypoint_radius_ratio = clampf(
		float(config.get("biome_keypoint_radius_ratio", biome_keypoint_radius_ratio)),
		0.15,
		0.49
	)
	desert_radius_tiles = clampi(int(config.get("desert_radius_tiles", desert_radius_tiles)), 0, 384)
	desert_transition_tiles = clampi(
		int(config.get("desert_transition_tiles", desert_transition_tiles)),
		0,
		192
	)
	desert_irregularity = clampf(float(config.get("desert_irregularity", desert_irregularity)), 0.0, 1.0)
	desert_prop_density = clampf(float(config.get("desert_prop_density", desert_prop_density)), 0.0, 1.0)
	runtime_terrain_chunk_tiles = clampi(
		int(config.get("runtime_terrain_chunk_tiles", runtime_terrain_chunk_tiles)),
		4,
		32
	)


func _prepare_noise() -> void:
	super._prepare_noise()
	if is_equal_approx(biome_noise_scale, 1.0):
		return

	var safe_world_width := float(maxi(world_size_tiles.x, 1))
	_configure_noise(
		_terrain_world_noise,
		world_seed,
		(8.0 / safe_world_width) * biome_noise_scale,
		1
	)
	_configure_noise(
		_terrain_world_noise2,
		world_seed ^ 0xFBB0,
		(16.0 / safe_world_width) * biome_noise_scale,
		1
	)
	_configure_noise(
		_humidity_world_noise,
		world_seed,
		(8.0 / safe_world_width) * biome_noise_scale,
		1
	)
	_configure_noise(
		_humidity_world_noise2,
		world_seed ^ 0xFBB0,
		(16.0 / safe_world_width) * biome_noise_scale,
		1
	)
	# Pond coverage is calibrated from humidity, so changing biome scale requires
	# recalibrating the pond quantile after the four native biome noises move.
	_calibrate_pond_field()


func _prepare_key_biome_centers() -> void:
	super._prepare_key_biome_centers()
	if is_equal_approx(biome_keypoint_radius_ratio, NATIVE_KEYPOINT_RADIUS_RATIO):
		return

	var center := Vector2(world_size_tiles) * 0.5
	var radius_scale := biome_keypoint_radius_ratio / NATIVE_KEYPOINT_RADIUS_RATIO
	_forest_center_grid = center + (_forest_center_grid - center) * radius_scale
	_desert_center_grid = center + (_desert_center_grid - center) * radius_scale
	_lake_center_grid = center + (_lake_center_grid - center) * radius_scale
	_volcano_center_grid = center + (_volcano_center_grid - center) * radius_scale
	_town_center_grid = center + (_town_center_grid - center) * radius_scale


func _native_tile_at(cell: Vector2i, start: Vector2i) -> Dictionary:
	var tile: Dictionary = super._native_tile_at(cell, start)
	if desert_radius_tiles <= 0:
		return tile

	var native_biome := int(tile.get("biome", BIOME_DRY))
	var native_ground := int(tile.get("ground", TERRAIN_BASE))
	# Coastline and all interior water are authoritative. Desert can replace only
	# ordinary land, never ocean/lake water or their authored sand margins.
	if native_biome == BIOME_WATER or native_ground in [TERRAIN_WATER, TERRAIN_SAND]:
		return tile

	var grid := Vector2(cell - start)
	var distance := grid.distance_to(_desert_center_grid)
	var edge_noise := _region_noise.get_noise_2d(grid.x + 713.0, grid.y - 119.0)
	var irregular_scale := clampf(1.0 + edge_noise * desert_irregularity, 0.55, 1.45)
	var local_radius := float(desert_radius_tiles) * irregular_scale
	var is_desert := distance <= local_radius

	if not is_desert and desert_transition_tiles > 0:
		var transition_distance := distance - local_radius
		if transition_distance <= float(desert_transition_tiles):
			var blend := 1.0 - clampf(
				transition_distance / float(desert_transition_tiles),
				0.0,
				1.0
			)
			is_desert = _tile_random_unit(cell, 0xD35E) <= blend

	if not is_desert:
		return tile

	tile["biome"] = BIOME_DESERT
	tile["ground"] = TERRAIN_SAND
	tile["barrier"] = false
	tile["cliff"] = false
	tile["terrain_value"] = minf(float(tile.get("terrain_value", 0.0)), -0.75)
	return tile


func _draw_native_detail(cell: Vector2i, terrain_type: int) -> void:
	if int(_biomes.get(cell, BIOME_DRY)) == BIOME_DESERT:
		return
	super._draw_native_detail(cell, terrain_type)


func _terrain_chunk_for_cell(cell: Vector2i) -> Vector2i:
	var chunk_tiles := maxi(runtime_terrain_chunk_tiles, 1)
	return Vector2i(
		floori(float(cell.x) / float(chunk_tiles)),
		floori(float(cell.y) / float(chunk_tiles))
	)


func _render_terrain_chunk(chunk: Vector2i) -> void:
	if _rendered_terrain_chunks.has(chunk):
		return

	var chunk_tiles := maxi(runtime_terrain_chunk_tiles, 1)
	var chunk_start := chunk * chunk_tiles
	var chunk_finish := chunk_start + Vector2i.ONE * chunk_tiles
	var start_x := maxi(chunk_start.x, _terrain_world_start.x)
	var start_y := maxi(chunk_start.y, _terrain_world_start.y)
	var finish_x := mini(chunk_finish.x, _terrain_world_finish.x)
	var finish_y := mini(chunk_finish.y, _terrain_world_finish.y)

	for tile_y in range(start_y, finish_y):
		for tile_x in range(start_x, finish_x):
			var terrain_cell := Vector2i(tile_x, tile_y)
			var terrain_type := int(_terrain_types.get(terrain_cell, TERRAIN_BASE))
			if terrain_type == TERRAIN_WATER:
				_draw_water_cell(terrain_cell)
				_draw_shore(terrain_cell)
				continue
			_ground.set_cell(terrain_cell, 0, Vector2i(2, 1), 0)
			_draw_native_autotile(terrain_cell, TERRAIN_DIRT, _dirt_layers)
			_draw_native_autotile(terrain_cell, TERRAIN_GREEN, _green_layers)
			_draw_native_autotile(terrain_cell, TERRAIN_FOREST_LIGHT, _forest_light_layers)
			_draw_native_autotile(terrain_cell, TERRAIN_FOREST_DEEP, _forest_deep_layers)
			_draw_forest_path(terrain_cell, terrain_type)
			_draw_plains_cliff(terrain_cell)
			_draw_forest_barrier(terrain_cell)
			_draw_shore(terrain_cell)
			_draw_native_detail(terrain_cell, terrain_type)

	_rendered_terrain_chunks[chunk] = true
	_queue_props_for_chunk(chunk)


func process_deferred_props(max_cells: int) -> int:
	if max_cells <= 0:
		return 0

	var processed := 0
	while processed < max_cells and _deferred_prop_cursor < _deferred_prop_cells.size():
		var prop_cell := _deferred_prop_cells[_deferred_prop_cursor]
		_deferred_prop_cursor += 1
		processed += 1

		var spot_value: Variant = _entity_spots.get(prop_cell, null)
		if not spot_value is Dictionary:
			continue
		var biome := int(_biomes.get(prop_cell, BIOME_DRY))
		if biome == BIOME_DESERT:
			_scatter_desert_cell(prop_cell, spot_value as Dictionary)
		else:
			super._scatter_cell(prop_cell, biome, spot_value as Dictionary)

	if _deferred_prop_cursor >= _deferred_prop_cells.size():
		_deferred_prop_cells.clear()
		_deferred_prop_cursor = 0
	return processed


func _scatter_desert_cell(cell: Vector2i, spot: Dictionary) -> void:
	if Vector2(cell).length() < 8.5 or _is_forest_structure(cell) or _plains_cliffs.has(cell):
		return
	if _tile_random_unit(cell, 0xD351) > desert_prop_density:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(cell)
	var start := Vector2i(-world_size_tiles.x / 2, -world_size_tiles.y / 2)
	var position := (
		Vector2(start) + Vector2(spot.get("position", Vector2.ZERO))
	) * float(tile_size)
	var entity_size := float(spot.get("size", 0.5))
	var choice := _tile_random_unit(cell, 0xD352)

	if entity_size >= 1.0:
		if choice < 0.72:
			_spawn_prop(position, PropKind.ROCK_BIG, rng.randi())
		else:
			_spawn_prop(position, PropKind.PURPLE_BUSH, rng.randi())
		return

	if choice < 0.58:
		_spawn_prop(position, PropKind.PURPLE_BUSH, rng.randi())
	else:
		_spawn_prop(position, PropKind.ROCK_SMALL, rng.randi())


func get_biome_name_at_world(world_position: Vector2) -> String:
	if _ground == null:
		return "Desconhecido"
	var cell := _ground.local_to_map(_ground.to_local(world_position))
	if int(_biomes.get(cell, BIOME_DRY)) == BIOME_DESERT:
		return "Deserto"
	return super.get_biome_name_at_world(world_position)


func get_biome_id_at_world(world_position: Vector2) -> String:
	if _ground == null:
		return "dry"
	var cell := _ground.local_to_map(_ground.to_local(world_position))
	if int(_biomes.get(cell, BIOME_DRY)) == BIOME_DESERT:
		return "desert"
	return super.get_biome_id_at_world(world_position)


func _biome_is_allowed(biome: int, allowed: Array) -> bool:
	if biome == BIOME_DESERT:
		return allowed.is_empty() or allowed.has("desert")
	return super._biome_is_allowed(biome, allowed)


func get_generation_diagnostics() -> Dictionary:
	var result: Dictionary = super.get_generation_diagnostics()
	result["runtime_terrain_chunk_tiles"] = runtime_terrain_chunk_tiles
	result["biome_noise_scale"] = biome_noise_scale
	result["biome_keypoint_radius_ratio"] = biome_keypoint_radius_ratio
	result["desert_radius_tiles"] = desert_radius_tiles
	result["desert_transition_tiles"] = desert_transition_tiles
	result["desert_prop_density"] = desert_prop_density
	return result
