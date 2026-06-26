extends RefCounted

const WorldItemScene := preload("res://scenes/items/WorldItem.tscn")
const TILE_SIZE := 32.0
const ADJACENT_TILE_OFFSETS := [
	Vector2(-1, -1),
	Vector2(0, -1),
	Vector2(1, -1),
	Vector2(-1, 0),
	Vector2(1, 0),
	Vector2(-1, 1),
	Vector2(0, 1),
	Vector2(1, 1),
]


static func spawn_item(item_id: String, amount: int, world_position: Vector2) -> Node2D:
	if item_id.is_empty() or amount <= 0:
		return null

	var parent := _get_world_items_parent()
	if parent == null:
		return null

	var drop_position := _get_random_adjacent_drop_position(world_position)
	var world_item = WorldItemScene.instantiate()
	world_item.position = parent.to_local(drop_position)
	parent.add_child(world_item)
	world_item.setup(item_id, amount)
	return world_item


static func spawn_drops(drop_results: Array, world_position: Vector2) -> void:
	for drop_entry in drop_results:
		if not drop_entry is Dictionary:
			continue

		spawn_item(str(drop_entry.get("item_id", "")), int(drop_entry.get("amount", 0)), world_position)


static func _get_world_items_parent() -> Node2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null

	var existing := tree.current_scene.get_node_or_null("World/WorldItems") as Node2D
	if existing != null:
		return existing

	var world := tree.current_scene.get_node_or_null("World") as Node2D
	if world == null:
		return tree.current_scene as Node2D

	var world_items := Node2D.new()
	world_items.name = "WorldItems"
	world_items.y_sort_enabled = true
	world.add_child(world_items)
	return world_items


static func _get_random_adjacent_drop_position(world_position: Vector2) -> Vector2:
	var offset_index: int = randi_range(0, ADJACENT_TILE_OFFSETS.size() - 1)
	var tile_offset: Vector2 = ADJACENT_TILE_OFFSETS[offset_index]
	var jitter := Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	return world_position + (tile_offset * TILE_SIZE) + jitter
