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


func _ready() -> void:
	super._ready()
	# The procedural world is generated before Main finishes restoring saved
	# player buildings. Reconcile one deferred tick later so a loaded house/wall
	# always wins over a procedural resource generated underneath it.
	call_deferred("_reconcile_resources_with_player_buildings")


func _instantiate_functional_resource(prop_position: Vector2, kind: PropKind, variation_seed: int, resource_type: String) -> void:
	# Pending streamed resources can materialize many frames after their original
	# reservation. Revalidate at the actual spawn moment, after the player may
	# have built or loaded a construction on that cell.
	var radius := _resource_radius_for_kind(kind)
	if _is_world_position_blocked(to_global(prop_position), radius, false):
		return
	super._instantiate_functional_resource(prop_position, kind, variation_seed, resource_type)


func _is_world_position_blocked(world_position: Vector2, radius: float, include_resources: bool) -> bool:
	if super._is_world_position_blocked(world_position, radius, include_resources):
		return true
	return _build_layer_blocks_resource(world_position, radius)


func clear_spawnables_in_building(building: Node2D) -> void:
	# Preserve the collision-shape based relocation from the integrated world,
	# then also reconcile against BuildSystem's logical TileMap. This catches
	# tile-fallback walls and any construction whose visual collision is smaller
	# than its occupied build footprint.
	super.clear_spawnables_in_building(building)
	call_deferred("_reconcile_resources_with_player_buildings")


func _resource_radius_for_kind(kind: PropKind) -> float:
	if kind in [PropKind.TREE_ROUND, PropKind.TREE_OLIVE, PropKind.TREE_CYPRESS, PropKind.APPLE_TREE, PropKind.STONE_PINE]:
		return 10.0
	if kind in [PropKind.ROCK_BIG, PropKind.MOSSY_ROCK]:
		return 9.0
	return 6.0


func _resource_radius_from_node(resource: Node2D) -> float:
	var resource_data_value: Variant = resource.get("resource_data")
	if resource_data_value is Dictionary:
		var collision_value: Variant = (resource_data_value as Dictionary).get("collision", {})
		if collision_value is Dictionary:
			return maxf(float((collision_value as Dictionary).get("body_radius", 6.0)), 4.0)
	var resource_type := str(resource.call("get_resource_type_id")) if resource.has_method("get_resource_type_id") else ""
	return 10.0 if _is_tree_type(resource_type) else 6.0


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

	var center_cell := build_layer.local_to_map(build_layer.to_local(world_position))
	var build_tile_size := build_layer.tile_set.tile_size
	var radius_x := maxi(0, ceili(radius / maxf(float(build_tile_size.x), 1.0)))
	var radius_y := maxi(0, ceili(radius / maxf(float(build_tile_size.y), 1.0)))
	for y in range(center_cell.y - radius_y, center_cell.y + radius_y + 1):
		for x in range(center_cell.x - radius_x, center_cell.x + radius_x + 1):
			if build_layer.get_cell_source_id(Vector2i(x, y)) != -1:
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
		if not _is_world_position_blocked(resource.global_position, radius, false):
			continue
		var resource_type := str(resource.call("get_resource_type_id")) if resource.has_method("get_resource_type_id") else ""
		var old_position := resource.global_position
		var replacement := get_random_respawn_position(resource_type, old_position)
		if replacement != old_position and not _is_world_position_blocked(replacement, radius, false):
			resource.global_position = replacement
		else:
			resource.queue_free()

	# Streamed reservations: invalidate them before they ever become nodes.
	for key_value in _pending_resource_spawns.keys():
		var key := str(key_value)
		var pending := _pending_resource_spawns[key] as Dictionary
		var pending_world := to_global(Vector2(pending.get("position", Vector2.ZERO)))
		var kind: PropKind = int(pending.get("kind", int(PropKind.BUSH)))
		if _is_world_position_blocked(pending_world, _resource_radius_for_kind(kind), false):
			_pending_resource_spawns.erase(key)


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
