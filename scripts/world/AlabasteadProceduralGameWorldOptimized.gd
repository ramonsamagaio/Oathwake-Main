class_name AlabasteadProceduralGameWorldOptimized
extends "res://scripts/world/AlabasteadProceduralGameWorld.gd"

# Runtime-focused overrides for the real 512x320 Romestead world.
#
# The inherited wildlife startup path scanned every biome cell once per animal
# profile and, for each candidate, scanned every live + pending resource. On a
# large world that turns a tiny 36-animal placement problem into an O(cells *
# resources) startup pass. Keep resource reservations spatial and sample only
# the handful of cells that can actually become wildlife.

const FAST_WILDLIFE_SCENE := preload("res://scenes/creatures/RomesteadWildlife.tscn")
const WILDLIFE_CLEARANCE_RADIUS: float = 7.0
const WILDLIFE_SPATIAL_BUCKET_PIXELS: float = 64.0
const WILDLIFE_ATTEMPTS_PER_CREATURE: int = 160


func _compute_active_bounds() -> Rect2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return super._compute_active_bounds()
	var camera: Camera2D = viewport.get_camera_2d()
	var focus_position: Vector2 = global_position
	var zoom_value: Vector2 = Vector2.ONE
	if camera != null:
		# Camera2D.global_position is its target transform, not necessarily the
		# rendered screen position while smoothing/limits are active.
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

	# The generation pass has already reserved non-overlapping resource slots in
	# _initial_resource_spatial. Re-scanning every pending reservation when one
	# resource streams in is both redundant and catastrophically expensive.
	# Revalidate only late-authored terrain/building blockers here.
	var radius: float = _resource_radius_for_kind(kind)
	if _is_world_position_blocked(to_global(prop_position), radius, false):
		return

	# This is the lightweight materialization body from
	# RomesteadProceduralGameWorld. It intentionally bypasses the inherited
	# Alabastead override whose include_resources=true path performs the global
	# pending-resource scan described above.
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

	# Resources can be streamed inside the larger preload margin but outside the
	# rendered camera rectangle. Cull them immediately instead of waiting for a
	# later visibility lap.
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

	# Build one spatial hash of already materialized and still-pending resources.
	# Nearby checks below inspect at most the 3x3 neighboring buckets.
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
			if used_cells.has(cell):
				continue
			if Vector2(cell).length_squared() <= 100.0:
				continue
			if not allowed.has(int(_biomes.get(cell, BIOME_DRY))):
				continue
			# This keeps cliffs, forest structures and player buildings authoritative,
			# but deliberately omits the old global resource scan.
			if not _is_spawn_cell_clear(cell, false):
				continue

			var local_world_position := Vector2(cell * tile_size) + Vector2(tile_size, tile_size) * 0.5
			if not _wildlife_position_clear_of_resources(
				local_world_position,
				WILDLIFE_CLEARANCE_RADIUS,
				resource_spatial
			):
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
		_wildlife_spatial_add(
			spatial,
			to_local(resource.global_position),
			_resource_radius_from_node(resource)
		)

	for pending_value: Variant in _pending_resource_spawns.values():
		if not (pending_value is Dictionary):
			continue
		var pending := pending_value as Dictionary
		var position_value: Variant = pending.get("position", Vector2.ZERO)
		if not (position_value is Vector2):
			continue
		var pending_position := position_value as Vector2
		var pending_kind: int = int(pending.get("kind", int(PropKind.BUSH)))
		_wildlife_spatial_add(
			spatial,
			pending_position,
			_resource_radius_for_kind(pending_kind)
		)
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
	# EnemyBase.queue_free() used to leave a stale Object in this typed array.
	# Remove it while tree_exiting still guarantees a live instance.
	var index: int = _wildlife_instances.find(creature)
	if index >= 0:
		_wildlife_instances.remove_at(index)
	if _wildlife_scan_index >= _wildlife_instances.size():
		_wildlife_scan_index = 0
