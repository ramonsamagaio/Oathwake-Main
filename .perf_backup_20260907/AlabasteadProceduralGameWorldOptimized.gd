class_name AlabasteadProceduralGameWorldOptimized
extends "res://scripts/world/AlabasteadProceduralGameWorld.gd"

# Runtime-focused implementation for the real 512x320 Romestead world.
# The seed still defines the complete world up front, but expensive TileMap
# materialization is now chunked around gameplay instead of drawing 163,840
# cells across ~25 layers synchronously before the first frame.

const FAST_WILDLIFE_SCENE := preload("res://scenes/creatures/RomesteadWildlife.tscn")
const WILDLIFE_CLEARANCE_RADIUS: float = 7.0
const WILDLIFE_SPATIAL_BUCKET_PIXELS: float = 64.0
const WILDLIFE_ATTEMPTS_PER_CREATURE: int = 160
const TERRAIN_CHUNK_TILES: int = 16
const INITIAL_TERRAIN_MARGIN_PIXELS: float = 192.0

var _rendered_terrain_chunks: Dictionary = {}
var _terrain_world_start := Vector2i.ZERO
var _terrain_world_finish := Vector2i.ZERO
var _terrain_generation_ready: bool = false
var _generation_timings: Dictionary = {}


func generate_world(new_seed: int = world_seed) -> void:
	var total_started: int = Time.get_ticks_msec()
	world_seed = new_seed
	if not _has_required_nodes():
		push_error("RomesteadBiomeWorld2D is missing one or more native terrain layers.")
		return

	var stage_started: int = Time.get_ticks_msec()
	_prepare_tilesets()
	_prepare_noise()
	_clear_generated_content()
	_rendered_terrain_chunks.clear()
	_terrain_generation_ready = false
	_generation_timings.clear()
	_generation_timings["setup_ms"] = Time.get_ticks_msec() - stage_started

	_terrain_world_start = Vector2i(-world_size_tiles.x / 2, -world_size_tiles.y / 2)
	_terrain_world_finish = _terrain_world_start + world_size_tiles

	# Keep the native seven-cell padding because the forest cleanup pass needs
	# neighbor data. This stage computes dictionaries/noise only. It does not
	# touch TileMap cells and is therefore cheap compared with the old renderer.
	stage_started = Time.get_ticks_msec()
	var biome_counts: Dictionary = {}
	for y: int in range(_terrain_world_start.y - 7, _terrain_world_finish.y + 7):
		for x: int in range(_terrain_world_start.x - 7, _terrain_world_finish.x + 7):
			var cell := Vector2i(x, y)
			var native_tile: Dictionary = _native_tile_at(cell, _terrain_world_start)
			_terrain_types[cell] = int(native_tile["ground"])
			var biome: int = int(native_tile["biome"])
			_biomes[cell] = biome
			_terrain_values[cell] = float(native_tile["terrain_value"])
			if x >= _terrain_world_start.x and x < _terrain_world_finish.x and y >= _terrain_world_start.y and y < _terrain_world_finish.y:
				biome_counts[biome] = int(biome_counts.get(biome, 0)) + 1
			if bool(native_tile["barrier"]):
				_forest_barriers[cell] = true
			if bool(native_tile.get("cliff", false)):
				_plains_cliffs[cell] = true
	_generation_timings["metadata_ms"] = Time.get_ticks_msec() - stage_started

	stage_started = Time.get_ticks_msec()
	_apply_forest_second_pass(_terrain_world_start, _terrain_world_finish)
	_apply_plains_cliff_second_pass(_terrain_world_start, _terrain_world_finish)
	_generation_timings["second_pass_ms"] = Time.get_ticks_msec() - stage_started

	stage_started = Time.get_ticks_msec()
	_generate_entity_size_spots(_terrain_world_start, _terrain_world_finish)
	_generation_timings["entity_spots_ms"] = Time.get_ticks_msec() - stage_started

	# Resource placement remains deterministic for the complete world so save IDs
	# and respawn logic do not change. Far resources become lightweight pending
	# dictionaries rather than scenes. Only the initial camera neighborhood is
	# instantiated now.
	stage_started = Time.get_ticks_msec()
	_generation_resource_bounds = _compute_active_bounds().grow(64.0)
	for cell_value: Variant in _entity_spots.keys():
		if not (cell_value is Vector2i):
			continue
		var cell := cell_value as Vector2i
		_scatter_cell(cell, int(_biomes.get(cell, BIOME_DRY)), _entity_spots[cell] as Dictionary)
	_generation_resource_bounds = Rect2()
	_generation_timings["resource_plan_ms"] = Time.get_ticks_msec() - stage_started

	# Render only enough terrain to cover the first camera and a safety ring.
	# Runtime scheduling streams additional 16x16 chunks as the player moves.
	stage_started = Time.get_ticks_msec()
	_terrain_generation_ready = true
	stream_terrain_for_bounds(_compute_active_bounds().grow(INITIAL_TERRAIN_MARGIN_PIXELS), 1024)
	for layer: TileMapLayer in _all_tile_layers():
		layer.update_internals()
	_generation_timings["initial_terrain_ms"] = Time.get_ticks_msec() - stage_started

	stage_started = Time.get_ticks_msec()
	_spawn_light_landmarks()
	_spawn_procedural_wildlife()
	_apply_initial_runtime_culling(_compute_active_bounds())
	_generation_timings["wildlife_and_cull_ms"] = Time.get_ticks_msec() - stage_started
	_generation_timings["total_ms"] = Time.get_ticks_msec() - total_started

	print(
		"[RomesteadPerf] startup total %.3f s | setup %.3f | metadata %.3f | passes %.3f | spots %.3f | resources %.3f | terrain %.3f"
		% [
			float(_generation_timings["total_ms"]) / 1000.0,
			float(_generation_timings["setup_ms"]) / 1000.0,
			float(_generation_timings["metadata_ms"]) / 1000.0,
			float(_generation_timings["second_pass_ms"]) / 1000.0,
			float(_generation_timings["entity_spots_ms"]) / 1000.0,
			float(_generation_timings["resource_plan_ms"]) / 1000.0,
			float(_generation_timings["initial_terrain_ms"]) / 1000.0,
		]
	)
	world_generated.emit(world_seed, biome_counts)


func stream_terrain_for_bounds(global_bounds: Rect2, max_chunks: int = 1) -> int:
	if not _terrain_generation_ready or max_chunks <= 0:
		return 0
	var local_a: Vector2 = to_local(global_bounds.position)
	var local_b: Vector2 = to_local(global_bounds.end)
	var min_local := Vector2(minf(local_a.x, local_b.x), minf(local_a.y, local_b.y))
	var max_local := Vector2(maxf(local_a.x, local_b.x), maxf(local_a.y, local_b.y))
	var first_cell := Vector2i(
		floori(min_local.x / float(tile_size)) - 1,
		floori(min_local.y / float(tile_size)) - 1
	)
	var last_cell := Vector2i(
		floori(max_local.x / float(tile_size)) + 1,
		floori(max_local.y / float(tile_size)) + 1
	)
	first_cell.x = maxi(first_cell.x, _terrain_world_start.x)
	first_cell.y = maxi(first_cell.y, _terrain_world_start.y)
	last_cell.x = mini(last_cell.x, _terrain_world_finish.x - 1)
	last_cell.y = mini(last_cell.y, _terrain_world_finish.y - 1)
	if first_cell.x > last_cell.x or first_cell.y > last_cell.y:
		return 0

	var first_chunk := _terrain_chunk_for_cell(first_cell)
	var last_chunk := _terrain_chunk_for_cell(last_cell)
	var center_local: Vector2 = to_local(global_bounds.get_center())
	var center_cell := Vector2i(
		floori(center_local.x / float(tile_size)),
		floori(center_local.y / float(tile_size))
	)
	var center_chunk := _terrain_chunk_for_cell(center_cell)
	var missing: Array[Vector2i] = []
	for chunk_y: int in range(first_chunk.y, last_chunk.y + 1):
		for chunk_x: int in range(first_chunk.x, last_chunk.x + 1):
			var chunk := Vector2i(chunk_x, chunk_y)
			if not _rendered_terrain_chunks.has(chunk):
				missing.append(chunk)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(center_chunk) < b.distance_squared_to(center_chunk)
	)

	var rendered: int = 0
	for chunk: Vector2i in missing:
		if rendered >= max_chunks:
			break
		_render_terrain_chunk(chunk)
		rendered += 1
	return rendered


func get_generation_diagnostics() -> Dictionary:
	var result := _generation_timings.duplicate(true)
	result["rendered_terrain_chunks"] = _rendered_terrain_chunks.size()
	result["pending_resources"] = _pending_resource_spawns.size()
	result["planned_resource_spots"] = _entity_spots.size()
	return result


func _terrain_chunk_for_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(TERRAIN_CHUNK_TILES)),
		floori(float(cell.y) / float(TERRAIN_CHUNK_TILES))
	)


func _render_terrain_chunk(chunk: Vector2i) -> void:
	if _rendered_terrain_chunks.has(chunk):
		return
	var chunk_start := chunk * TERRAIN_CHUNK_TILES
	var chunk_finish := chunk_start + Vector2i.ONE * TERRAIN_CHUNK_TILES
	var start_x: int = maxi(chunk_start.x, _terrain_world_start.x)
	var start_y: int = maxi(chunk_start.y, _terrain_world_start.y)
	var finish_x: int = mini(chunk_finish.x, _terrain_world_finish.x)
	var finish_y: int = mini(chunk_finish.y, _terrain_world_finish.y)
	for y: int in range(start_y, finish_y):
		for x: int in range(start_x, finish_x):
			var cell := Vector2i(x, y)
			var terrain_type: int = int(_terrain_types.get(cell, TERRAIN_BASE))
			_ground.set_cell(cell, 0, Vector2i(2, 1), 0)
			_draw_native_autotile(cell, TERRAIN_DIRT, _dirt_layers)
			_draw_native_autotile(cell, TERRAIN_GREEN, _green_layers)
			_draw_native_autotile(cell, TERRAIN_FOREST_LIGHT, _forest_light_layers)
			_draw_native_autotile(cell, TERRAIN_FOREST_DEEP, _forest_deep_layers)
			_draw_forest_path(cell, terrain_type)
			_draw_plains_cliff(cell)
			_draw_forest_barrier(cell)
			_draw_native_detail(cell, terrain_type)
	_rendered_terrain_chunks[chunk] = true


func _compute_active_bounds() -> Rect2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return super._compute_active_bounds()
	var camera: Camera2D = viewport.get_camera_2d()
	var focus_position: Vector2 = global_position
	var zoom_value: Vector2 = Vector2.ONE
	if camera != null:
		focus_position = camera.get_screen_center_position()
		zoom_value = camera.zoom
	var half_view: Vector2 = viewport.get_visible_rect().size * 0.5
	half_view /= Vector2(
		maxf(absf(zoom_value.x), 0.01),
		maxf(absf(zoom_value.y), 0.01)
	)
	return Rect2(
		focus_position - half_view - Vector2(48.0, 32.0),
		half_view * 2.0 + Vector2(96.0, 144.0)
	)


func _instantiate_functional_resource(prop_position: Vector2, kind: PropKind, variation_seed: int, resource_type: String) -> void:
	if _resources == null or resource_type.is_empty():
		return
	var radius: float = _resource_radius_for_kind(kind)
	if _is_world_position_blocked(to_global(prop_position), radius, false):
		return

	var cell := Vector2i(
		roundi(prop_position.x / float(tile_size)),
		roundi(prop_position.y / float(tile_size))
	)
	var resource_id := "romestead_resource_%d_%d_%s" % [cell.x, cell.y, resource_type]
	var local_resource_position := _resources.to_local(to_global(prop_position.round()))
	var resource_node: Node = _resource_factory.instantiate_resource(
		resource_type,
		resource_id,
		local_resource_position
	) as Node
	if resource_node == null:
		return
	resource_node.name = ("Resource_%d_%d" % [cell.x, cell.y]).validate_node_name()
	resource_node.set_meta("procedural_biome", int(_biomes.get(cell, BIOME_DRY)))
	_resources.add_child(resource_node)
	_managed_resources.append(resource_node)
	if resource_node.has_method("uses_romestead_wind") and bool(resource_node.call("uses_romestead_wind")):
		_wind_resources.append(resource_node)
	if resource_node.has_method("uses_player_occlusion") and bool(resource_node.call("uses_player_occlusion")):
		_occlusion_resources.append(resource_node)
	if resource_node.has_method("set_runtime_culled") and resource_node is Node2D:
		var resource_2d := resource_node as Node2D
		resource_node.call(
			"set_runtime_culled",
			not _compute_active_bounds().has_point(resource_2d.global_position)
		)


func _spawn_procedural_wildlife() -> void:
	if _wildlife_root == null or _biomes.is_empty():
		return

	var started_msec: int = Time.get_ticks_msec()
	var profiles: Array = [
		{"id": "squirrel", "count": 12, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT, BIOME_FOREST]},
		{"id": "rabbit", "count": 9, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT]},
		{"id": "deer_female", "count": 5, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT, BIOME_FOREST]},
		{"id": "bird", "count": 10, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT, BIOME_FOREST]},
	]
	var cells: Array = _biomes.keys()
	if cells.is_empty():
		return
	var resource_spatial: Dictionary = _build_wildlife_resource_spatial()
	var used_cells: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x6A91F4
	var total_spawned: int = 0

	for profile_value: Variant in profiles:
		var profile := profile_value as Dictionary
		var allowed: Array = profile.get("biomes", []) as Array
		var requested: int = int(profile.get("count", 0))
		var spawned: int = 0
		var attempts: int = 0
		var attempt_budget: int = maxi(requested * WILDLIFE_ATTEMPTS_PER_CREATURE, 1)
		while spawned < requested and attempts < attempt_budget:
			attempts += 1
			var cell_value: Variant = cells[rng.randi_range(0, cells.size() - 1)]
			if not (cell_value is Vector2i):
				continue
			var cell: Vector2i = cell_value as Vector2i
			if used_cells.has(cell) or Vector2(cell).length_squared() <= 100.0:
				continue
			if not allowed.has(int(_biomes.get(cell, BIOME_DRY))):
				continue
			if not _is_spawn_cell_clear(cell, false):
				continue
			var local_world_position := Vector2(cell * tile_size) + Vector2(tile_size, tile_size) * 0.5
			if not _wildlife_position_clear_of_resources(local_world_position, WILDLIFE_CLEARANCE_RADIUS, resource_spatial):
				continue
			var creature := FAST_WILDLIFE_SCENE.instantiate() as Node2D
			if creature == null:
				continue
			creature.set("monster_id", str(profile.get("id", "")))
			creature.position = _wildlife_root.to_local(to_global(local_world_position))
			_wildlife_root.add_child(creature)
			_wildlife_instances.append(creature)
			creature.tree_exiting.connect(_on_runtime_wildlife_tree_exiting.bind(creature))
			creature.call("set_runtime_active", false)
			used_cells[cell] = true
			spawned += 1
			total_spawned += 1

	var elapsed_msec: int = Time.get_ticks_msec() - started_msec
	print(
		"[RomesteadPerf] wildlife startup: %d animals in %.3f s (%d resource buckets)"
		% [total_spawned, float(elapsed_msec) / 1000.0, resource_spatial.size()]
	)


func _build_wildlife_resource_spatial() -> Dictionary:
	var spatial: Dictionary = {}
	for resource_value: Variant in _managed_resources:
		if not is_instance_valid(resource_value) or not (resource_value is Node2D):
			continue
		var resource := resource_value as Node2D
		_wildlife_spatial_add(spatial, to_local(resource.global_position), _resource_radius_from_node(resource))
	for pending_value: Variant in _pending_resource_spawns.values():
		if not (pending_value is Dictionary):
			continue
		var pending := pending_value as Dictionary
		var position_value: Variant = pending.get("position", Vector2.ZERO)
		if not (position_value is Vector2):
			continue
		var pending_position := position_value as Vector2
		var pending_kind: int = int(pending.get("kind", int(PropKind.BUSH)))
		_wildlife_spatial_add(spatial, pending_position, _resource_radius_for_kind(pending_kind))
	return spatial


func _wildlife_spatial_add(spatial: Dictionary, local_point: Vector2, radius: float) -> void:
	var bucket := Vector2i(
		floori(local_point.x / WILDLIFE_SPATIAL_BUCKET_PIXELS),
		floori(local_point.y / WILDLIFE_SPATIAL_BUCKET_PIXELS)
	)
	if not spatial.has(bucket):
		spatial[bucket] = []
	var entries: Array = spatial[bucket] as Array
	entries.append({"point": local_point, "radius": radius})


func _wildlife_position_clear_of_resources(local_point: Vector2, radius: float, spatial: Dictionary) -> bool:
	var bucket := Vector2i(
		floori(local_point.x / WILDLIFE_SPATIAL_BUCKET_PIXELS),
		floori(local_point.y / WILDLIFE_SPATIAL_BUCKET_PIXELS)
	)
	for bucket_y: int in range(bucket.y - 1, bucket.y + 2):
		for bucket_x: int in range(bucket.x - 1, bucket.x + 2):
			var entries_value: Variant = spatial.get(Vector2i(bucket_x, bucket_y), null)
			if not (entries_value is Array):
				continue
			var entries := entries_value as Array
			for entry_value: Variant in entries:
				if not (entry_value is Dictionary):
					continue
				var entry := entry_value as Dictionary
				var point_value: Variant = entry.get("point", Vector2.ZERO)
				var other_point: Vector2 = point_value as Vector2 if point_value is Vector2 else Vector2.ZERO
				var minimum: float = radius + float(entry.get("radius", 6.0))
				if local_point.distance_squared_to(other_point) <= minimum * minimum:
					return false
	return true


func _on_runtime_wildlife_tree_exiting(creature: Node2D) -> void:
	var index: int = _wildlife_instances.find(creature)
	if index >= 0:
		_wildlife_instances.remove_at(index)
	if _wildlife_scan_index >= _wildlife_instances.size():
		_wildlife_scan_index = 0
