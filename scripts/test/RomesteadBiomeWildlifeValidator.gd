extends SceneTree

const GameScene := preload("res://scenes/game/Game.tscn")
const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var editor := ContentEditorData.new()
	_check(editor.load_all().is_empty(), "Content Editor loads expanded Romestead catalogs")
	for resource_id in ["tree41", "tree42", "purple_bush1", "forest_bush1", "mushroom_red", "mushroom_brown", "mushroom_yellow", "bellflower1", "lily1", "copper_ore_node", "mossy_rock1"]:
		var resource := editor.get_record(ContentEditorData.SECTION_RESOURCES, resource_id)
		_check(not resource.is_empty(), "Content Editor lists %s" % resource_id)
		_check(editor.validate_resource(resource_id, resource_id, resource).is_empty(), "%s passes Content Editor validation" % resource_id)
	for monster_id in ["squirrel", "rabbit", "deer_female", "bird"]:
		var monster := editor.get_record(ContentEditorData.SECTION_MONSTERS, monster_id)
		_check(not monster.is_empty(), "Content Editor lists %s" % monster_id)
		_check(editor.validate_monster(monster_id, monster_id, monster).is_empty(), "%s passes Content Editor validation" % monster_id)
		_check((monster.get("animations", {}) as Dictionary).size() >= 3, "%s has native animations" % monster_id)
	for sprite_id in ["romestead_apple_canopy", "romestead_apple_stump", "romestead_stone_pine_canopy", "romestead_stone_pine_stump", "romestead_purple_bush", "romestead_forest_bush", "romestead_mushroom_red", "romestead_bellflower", "romestead_lily", "romestead_copper_ore", "romestead_mossy_boulder", "romestead_tiny_leaf", "romestead_tiny_flower"]:
		var sprite := editor.get_record(ContentEditorData.SECTION_SPRITES, sprite_id)
		_check(not sprite.is_empty(), "Content Editor lists sprite %s" % sprite_id)
		_check(editor.validate_sprite(sprite_id, sprite_id, sprite).is_empty(), "%s passes sprite validation" % sprite_id)

	for path in [
		"res://assets/world_lab/romestead_native_png/romestead_wildlife_native_atlas.png",
		"res://assets/sprites/world/procedural/terrain/forest_unbreakable_bushes_bottom_.png",
		"res://assets/sprites/world/procedural/terrain/forest_unbreakable_bushes_top_.png",
		"res://assets/sprites/world/procedural/terrain/tree_wall.png",
	]:
		_check(FileAccess.file_exists(path), "Editable native asset exists: %s" % path.get_file())

	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var world := game.find_child("RomesteadProceduralGameWorld", true, false)
	_check(world != null, "Expanded procedural world instantiated")
	if world != null:
		var biomes := world.get("_biomes") as Dictionary
		var forest_light_count := 0
		var forest_deep_count := 0
		for value in biomes.values():
			forest_light_count += 1 if int(value) == 6 else 0
			forest_deep_count += 1 if int(value) == 7 else 0
		_check(forest_light_count > 0, "World contains forest-light transition")
		_check(forest_deep_count > 0, "World contains closed forest")
		_check(_has_reachable_biome(world, 7), "Closed forest is reachable from the enlarged starting area")
		var barrier := world.get_node_or_null("ForestBarrierBottom") as TileMapLayer
		_check(barrier != null and barrier.get_used_cells().size() > 0, "Closed forest has authored barrier tiles")
		_check(barrier != null and barrier.tile_set != null and barrier.tile_set.get_physics_layers_count() == 1, "Closed forest barrier has collision")

	var wildlife := get_nodes_in_group("romestead_wildlife")
	_check(wildlife.size() == 36, "Procedural world spawns the four wildlife populations")
	var wildlife_ids := {}
	for animal in wildlife:
		wildlife_ids[str(animal.get("monster_id"))] = true
	for monster_id in ["squirrel", "rabbit", "deer_female", "bird"]:
		_check(wildlife_ids.has(monster_id), "%s is present in the generated world" % monster_id)

	var tree = _find_resource(game, "tree2")
	_check(tree != null, "A layered tree is available for fall validation")
	if tree != null:
		var player := game.get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			player.global_position = (tree as Node2D).global_position + Vector2(18, 0)
		tree.call("take_damage", 9999)
		_check(not bool(tree.call("is_collected")), "Tree does not drop before crown fall finishes")
		await create_timer(0.65).timeout
		_check(not bool(tree.call("is_collected")), "Tree still waits midway through the 1.2 second fall")
		await create_timer(0.65).timeout
		_check(bool(tree.call("is_collected")), "Tree drops only after the 1.2 second crown fall")
		var canopy := tree.get("layered_canopy_sprite") as Sprite2D
		var trunk := tree.get("layered_trunk_sprite") as Sprite2D
		_check(canopy != null and not canopy.visible, "Fallen crown is removed")
		_check(trunk != null and trunk.visible and tree.visible, "Cut trunk remains in the world")

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("ROMESTEAD_BIOME_WILDLIFE_VALIDATION: PASS wildlife=%d" % wildlife.size())
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ROMESTEAD_BIOME_WILDLIFE_VALIDATION: FAIL count=%d" % failures.size())
		quit(1)


func _find_resource(root_node: Node, type_id: String) -> Node:
	for node in root_node.get_tree().get_nodes_in_group("resource_node"):
		if str(node.call("get_resource_type_id")) == type_id and node.visible:
			return node
	return null


func _has_reachable_biome(world: Node, target_biome: int) -> bool:
	var biomes := world.get("_biomes") as Dictionary
	var blocked := (world.get("_forest_barriers") as Dictionary).duplicate()
	for cell in (world.get("_forest_tree_left") as Dictionary).keys():
		blocked[cell] = true
	for cell in (world.get("_forest_tree_right") as Dictionary).keys():
		blocked[cell] = true
	var size := world.get("world_size_tiles") as Vector2i
	var minimum := Vector2i(-size.x / 2, -size.y / 2)
	var maximum := minimum + size
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var visited := {Vector2i.ZERO: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if int(biomes.get(cell, -1)) == target_biome:
			return true
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next_cell: Vector2i = cell + offset
			if next_cell.x < minimum.x or next_cell.y < minimum.y or next_cell.x >= maximum.x or next_cell.y >= maximum.y:
				continue
			if visited.has(next_cell) or blocked.has(next_cell):
				continue
			visited[next_cell] = true
			queue.append(next_cell)
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
