class_name AlabasteadProceduralGameWorld
extends "res://scripts/world/RomesteadProceduralGameWorld.gd"

# The Romestead dense-forest bush and canopy sheets are 4x4 native autotiles.
# The base generator also uses the later entries of AutoTile16TileSet for larger
# terrain sheets, so feeding those candidates into a 4x4 forest sheet and then
# applying modulo 16 can select a different topology. Keep the forest walls on
# the first native 16-state table exactly.
const FOREST_FRAME_BY_MASK := {
	4: 0,
	3: 1,
	14: 2,
	6: 3,
	10: 4,
	7: 5,
	15: 6,
	13: 7,
	1: 8,
	9: 9,
	11: 10,
	12: 11,
	0: 12,
	2: 13,
	5: 14,
	8: 15,
}

# resources.json currently contains the five native 48x48 Romestead rock
# records below. The inherited pool still contains legacy rock1..rock5 ids,
# which are not part of the imported native resource set.
const NATIVE_BIG_ROCKS := ["rock6", "rock7", "rock8", "rock9", "rock10"]

# Spawn spacing is deliberately footprint-sized, not canopy-sized. This stops
# opaque resource pixels from occupying each other while keeping the organic,
# fairly dense Romestead distribution.
const RESOURCE_SPACING_BUCKET_SIZE := 64.0
const RESOURCE_SPACING_MARGIN := 2.0

# Romestead AutoTilerCliffs.DrawCliff uses an eight-column atlas and a two-tile
# cliff face for PlainsCliff. The cap stays on the logical structure tile and
# the two face rows extend DOWN from it. The earlier Godot port had this stack
# inverted (cap two tiles above, face ending on the logical tile), which made
# large formations look like stretched/stacked rock slabs.
const PLAINS_CLIFF_ATLAS_COLUMNS := 8
const PLAINS_CLIFF_HEIGHT := 2
const PLAINS_CLIFF_FACE_MASK := 0x3F3E


func _ready() -> void:
	super._ready()
	# The procedural world is generated before Main finishes restoring saved
	# player buildings. Reconcile after several process frames as well as through
	# BuildSystem's per-building callback, so a loaded house always wins over a
	# procedural resource regardless of node-ready order.
	call_deferred("_reconcile_resources_after_build_restore")


func _reconcile_resources_after_build_restore() -> void:
	for _frame in range(4):
		await get_tree().process_frame
		_reconcile_resources_with_player_buildings()


func _resource_type_for_prop(kind: PropKind, variation_seed: int) -> String:
	if kind == PropKind.ROCK_BIG:
		return _pick_variant(NATIVE_BIG_ROCKS, variation_seed)
	return super._resource_type_for_prop(kind, variation_seed)


func _reserve_initial_resource_position(candidate: Vector2, kind: PropKind) -> bool:
	var radius := _resource_radius_for_kind(kind)
	if _is_world_position_blocked(to_global(candidate), radius, false):
		return false

	var bucket := Vector2i(
		floori(candidate.x / RESOURCE_SPACING_BUCKET_SIZE),
		floori(candidate.y / RESOURCE_SPACING_BUCKET_SIZE)
	)
	for bucket_y in range(bucket.y - 1, bucket.y + 2):
		for bucket_x in range(bucket.x - 1, bucket.x + 2):
			var entries: Array = _initial_resource_spatial.get(Vector2i(bucket_x, bucket_y), []) as Array
			for entry_value in entries:
				var entry := entry_value as Dictionary
				var other_position := Vector2(entry.get("position", Vector2.ZERO))
				var other_radius := float(entry.get("radius", 6.0))
				var minimum := radius + other_radius + RESOURCE_SPACING_MARGIN
				if candidate.distance_squared_to(other_position) < minimum * minimum:
					return false

	if not _initial_resource_spatial.has(bucket):
		_initial_resource_spatial[bucket] = []
	(_initial_resource_spatial[bucket] as Array).append({
		"position": candidate,
		"radius": radius,
	})
	return true


func _instantiate_functional_resource(prop_position: Vector2, kind: PropKind, variation_seed: int, resource_type: String) -> void:
	# Pending streamed resources can materialize many frames after their original
	# reservation. Revalidate at the actual spawn moment against buildings AND
	# resources that may have moved/respawned since generation.
	var radius := _resource_radius_for_kind(kind)
	if _is_world_position_blocked(to_global(prop_position), radius, true):
		return
	super._instantiate_functional_resource(prop_position, kind, variation_seed, resource_type)


func _is_world_position_blocked(world_position: Vector2, radius: float, include_resources: bool) -> bool:
	if super._is_world_position_blocked(world_position, radius, include_resources):
		return true
	return _build_layer_blocks_resource(world_position, radius)


func clear_spawnables_in_building(building: Node2D) -> void:
	# Preserve the collision-shape based relocation from the integrated world,
	# then also reconcile against BuildSystem's logical occupied cells. This
	# catches floors/interiors and metadata-only pieces whose physical collision
	# is smaller than the actual construction footprint.
	super.clear_spawnables_in_building(building)
	call_deferred("_reconcile_resources_with_player_buildings")


func _resource_radius_for_kind(kind: PropKind) -> float:
	match kind:
		PropKind.TREE_ROUND, PropKind.TREE_OLIVE, PropKind.APPLE_TREE:
			return 12.0
		PropKind.TREE_CYPRESS:
			return 9.0
		PropKind.STONE_PINE:
			return 13.0
		PropKind.ROCK_BIG:
			return 20.0
		PropKind.ROCK_SMALL:
			return 13.0
		PropKind.MOSSY_ROCK:
			return 27.0
		PropKind.BUSH:
			return 12.0
		PropKind.WHEAT:
			return 6.0
		PropKind.COPPER_ORE:
			return 8.0
		PropKind.MUSHROOM:
			return 6.0
		PropKind.FLOWER:
			return 8.0
		PropKind.PURPLE_BUSH, PropKind.SMALL_BUSH:
			return 7.0
		_:
			return 6.0


func _resource_radius_from_node(resource: Node2D) -> float:
	var resource_type := str(resource.call("get_resource_type_id")) if resource.has_method("get_resource_type_id") else ""
	var lowered := resource_type.to_lower()
	if lowered.begins_with("tree"):
		return 12.0
	if lowered.begins_with("rock"):
		return 20.0
	if lowered.begins_with("stone"):
		return 13.0
	if lowered.contains("mossy"):
		return 27.0

	var resource_data_value: Variant = resource.get("resource_data")
	if resource_data_value is Dictionary:
		var collision_value: Variant = (resource_data_value as Dictionary).get("collision", {})
		if collision_value is Dictionary:
			var body_radius := float((collision_value as Dictionary).get("body_radius", 6.0))
			return maxf(body_radius * 1.2, 4.0)
	return 6.0


func _build_layer_blocks_resource(world_position: Vector2, radius: float) -> bool:
	var build_system := get_tree().get_first_node_in_group("build_system")
	if build_system == null:
		return false
	var build_layer_value: Variant = build_system.get("build_layer")
	if not (build_layer_value is TileMapLayer):
		return false
	var build_layer := build_layer_value as TileMapLayer
	if build_layer.tile_set == null:
		return false

	var local_position := build_layer.to_local(world_position)
	var center_cell := build_layer.local_to_map(local_position)
	var build_tile_size := Vector2(build_layer.tile_set.tile_size)
	var half_tile := build_tile_size * 0.5
	var search_x := maxi(1, ceili(radius / maxf(build_tile_size.x, 1.0)) + 1)
	var search_y := maxi(1, ceili(radius / maxf(build_tile_size.y, 1.0)) + 1)

	for y in range(center_cell.y - search_y, center_cell.y + search_y + 1):
		for x in range(center_cell.x - search_x, center_cell.x + search_x + 1):
			var cell := Vector2i(x, y)
			var occupied := build_layer.get_cell_source_id(cell) != -1
			# Content-driven buildings may be metadata-only and therefore have no
			# fallback TileMap cell. Ask BuildSystem's own authoritative lookup too.
			if not occupied and build_system.has_method("_get_building_type_at_tile"):
				occupied = not str(build_system.call("_get_building_type_at_tile", cell)).is_empty()
			if not occupied:
				continue

			# Circle-vs-cell test avoids the old behavior where any non-zero radius
			# rounded up to a whole extra 32px build tile of empty padding.
			var cell_center := build_layer.map_to_local(cell)
			var delta := Vector2(
				maxf(absf(local_position.x - cell_center.x) - half_tile.x, 0.0),
				maxf(absf(local_position.y - cell_center.y) - half_tile.y, 0.0)
			)
			if delta.length_squared() <= radius * radius:
				return true
	return false


func _reconcile_resources_with_player_buildings() -> void:
	if not is_inside_tree():
		return

	# Existing resources: relocate when possible. If no legal respawn is found,
	# remove the node rather than leaving a harvestable object inside a building.
	for resource_value in _managed_resources.duplicate():
		var resource := resource_value as Node2D
		if resource == null or not is_instance_valid(resource):
			continue
		var radius := _resource_radius_from_node(resource)
		if not _build_layer_blocks_resource(resource.global_position, radius):
			continue
		var resource_type := str(resource.call("get_resource_type_id")) if resource.has_method("get_resource_type_id") else ""
		var old_position := resource.global_position
		var replacement := get_random_respawn_position(resource_type, old_position)
		if replacement != old_position and not _build_layer_blocks_resource(replacement, radius):
			resource.global_position = replacement
		else:
			resource.queue_free()

	# Streamed reservations: invalidate them before they ever become nodes.
	for key_value in _pending_resource_spawns.keys():
		var key := str(key_value)
		var pending := _pending_resource_spawns[key] as Dictionary
		var pending_world := to_global(Vector2(pending.get("position", Vector2.ZERO)))
		var kind: PropKind = int(pending.get("kind", int(PropKind.BUSH)))
		if _build_layer_blocks_resource(pending_world, _resource_radius_for_kind(kind)):
			_pending_resource_spawns.erase(key)


func _apply_plains_cliff_second_pass(start: Vector2i, finish: Vector2i) -> void:
	# Re-enable the native formation cleanup. The previous hotfix cleared the
	# dictionary only because the rendered stack was inverted; the topology
	# filtering itself was not the problem.
	super._apply_plains_cliff_second_pass(start, finish)


func _draw_plains_cliff(cell: Vector2i) -> void:
	if not _plains_cliffs.has(cell):
		return

	var mask := _plains_cliff_mask(cell)
	if mask <= 0 or mask >= PLAINS_CLIFF_BASE_FRAMES.size():
		return
	var options := PLAINS_CLIFF_BASE_FRAMES[mask] as Array
	if options.is_empty():
		return

	# MultiTilePattern.Mode.InOrderXy: alternate the authored pair by x+y.
	var frame := int(options[posmod(cell.x + cell.y, options.size())])
	var top_coord := Vector2i(
		frame % PLAINS_CLIFF_ATLAS_COLUMNS,
		frame / PLAINS_CLIFF_ATLAS_COLUMNS
	)

	# Native AutoTilerCliffs.DrawCliff anchors the cap on the logical structure
	# coordinate. The wall is an extrusion toward screen-down, never screen-up.
	_plains_cliff_layers[0].set_cell(cell, 0, top_coord, 0)

	var exposes_face := ((1 << mask) & PLAINS_CLIFF_FACE_MASK) != 0
	if exposes_face:
		for face_row in range(1, PLAINS_CLIFF_HEIGHT + 1):
			var face_frame := frame + PLAINS_CLIFF_ATLAS_COLUMNS * face_row
			var face_coord := Vector2i(
				face_frame % PLAINS_CLIFF_ATLAS_COLUMNS,
				face_frame / PLAINS_CLIFF_ATLAS_COLUMNS
			)
			_plains_cliff_layers[face_row].set_cell(cell + Vector2i.DOWN * face_row, 0, face_coord, 0)

	# Keep physics on the authored logical structure cell, matching the native
	# structure-map contract rather than making the decorative vertical face a
	# three-cell-thick obstacle.
	_plains_cliff_collision.set_cell(cell, 0, Vector2i(0, 4), 0)


func _forest_frame_for_mask(mask: int) -> int:
	return int(FOREST_FRAME_BY_MASK.get(mask, -1))


func _draw_forest_barrier(cell: Vector2i) -> void:
	if not _is_forest_structure(cell):
		return

	if _forest_barriers.has(cell):
		var frame := _forest_frame_for_mask(_forest_bush_mask(cell))
		if frame >= 0:
			var coord := _frame_to_coord(frame)
			_forest_barrier_bottom.set_cell(cell, 0, coord, 0)
			# TallBushTopRule is one native tile above the logical structure.
			_forest_barrier_top.set_cell(cell + Vector2i.UP, 0, coord, 0)
	elif _forest_tree_left.has(cell) or _forest_tree_right.has(cell):
		var full_coord := _frame_to_coord(6)
		_forest_barrier_top.set_cell(cell, 0, full_coord, 0)
		_forest_barrier_top.set_cell(cell + Vector2i.DOWN, 0, full_coord, 0)
		# Preserve the source-derived TallTreeLeft/TallTreeRight wall sequence.
		var frames := [8, 6, 2, 0, 2, 0] if _forest_tree_left.has(cell) else [9, 7, 3, 1, 3, 1]
		for index in range(frames.size()):
			var wall_frame := int(frames[index])
			_forest_tree_wall.set_cell(cell + Vector2i(0, -index), 0, Vector2i(wall_frame % 2, wall_frame / 2), 0)

	# Romestead samples a second structure row five cells above and renders the
	# canopy six native tiles above. The canopy itself is another 4x4 16-state
	# atlas, so it must use the same dedicated forest frame lookup.
	var source := cell + Vector2i(0, -5)
	if _is_forest_structure(source):
		var canopy_mask := 15
		for index in range(FOREST_MASK_OFFSETS.size()):
			var offset: Vector2i = FOREST_MASK_OFFSETS[index]
			if not _is_forest_structure(cell + offset) or not _is_forest_structure(source + offset):
				canopy_mask &= ~int(FOREST_MASK_FLAGS[index])
		var canopy_frame := _forest_frame_for_mask(canopy_mask)
		if canopy_frame >= 0:
			_forest_canopy.set_cell(cell + Vector2i.UP * 6, 0, _frame_to_coord(canopy_frame), 0)
