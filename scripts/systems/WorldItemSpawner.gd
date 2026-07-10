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
static var _configured_world_items_root: Node2D


static func set_world_items_root(root: Node2D) -> void:
	_configured_world_items_root = root


static func spawn_item(item_id: String, amount: int, world_position: Vector2, metadata: Dictionary = {}) -> Node2D:
	return _spawn_item_at_position(item_id, amount, _get_random_adjacent_drop_position(world_position), true, metadata)


static func spawn_item_near_position(item_id: String, amount: int, world_position: Vector2, metadata: Dictionary = {}) -> Node2D:
	var offset := Vector2(randf_range(-22.0, 22.0), randf_range(-14.0, 14.0))
	return _spawn_item_at_position(item_id, amount, world_position + offset, true, metadata)


static func spawn_loaded_item(item_id: String, amount: int, world_position: Vector2, metadata: Dictionary = {}) -> Node2D:
	return _spawn_item_at_position(item_id, amount, world_position, false, metadata)


static func clear_world_items() -> void:
	var parent := _get_world_items_parent()
	if parent == null:
		return

	for child in parent.get_children():
		if child is Node:
			child.queue_free()


static func _spawn_item_at_position(item_id: String, amount: int, drop_position: Vector2, play_jump := true, metadata: Dictionary = {}) -> Node2D:
	if item_id.is_empty() or amount <= 0:
		return null

	var parent := _get_world_items_parent()
	if parent == null:
		return null

	var world_item: Node2D = WorldItemScene.instantiate()
	world_item.set("item_id", item_id)
	world_item.set("amount", amount)
	world_item.set("spawn_jump_enabled", play_jump)
	world_item.set("spawn_magnet_delay", 0.3 if play_jump else 0.0)
	world_item.position = parent.to_local(drop_position)
	parent.add_child(world_item)
	world_item.call("setup", item_id, amount, metadata)
	return world_item


static func spawn_drops(drop_results: Array, world_position: Vector2) -> void:
	for drop_entry in drop_results:
		if not drop_entry is Dictionary:
			continue

		spawn_item(str(drop_entry.get("item_id", "")), int(drop_entry.get("amount", 0)), world_position)


static func _get_world_items_parent() -> Node2D:
	if _configured_world_items_root != null and is_instance_valid(_configured_world_items_root):
		return _configured_world_items_root
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null

	var existing := tree.current_scene.get_node_or_null("World/WorldItems") as Node2D
	if existing != null:
		return existing
	var grouped_root := tree.get_first_node_in_group("world_items_root") as Node2D
	if grouped_root != null:
		return grouped_root

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
