extends SceneTree

const GameScene := preload("res://scenes/game/Game.tscn")
const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var editor_data = ContentEditorData.new()
	_check(editor_data.load_all().is_empty(), "Content Editor loads the expanded catalogs")
	var expected_ids: Array[String] = []
	for index in range(2, 41):
		expected_ids.append("tree%d" % index)
	for index in range(1, 11):
		expected_ids.append("rock%d" % index)
	for index in range(1, 9):
		expected_ids.append("stone%d" % index)
	for index in range(1, 25):
		expected_ids.append("wheat%d" % index)
	for index in range(1, 22):
		expected_ids.append("bush%d" % index)
	for resource_id in expected_ids:
		var record := editor_data.get_record(ContentEditorData.SECTION_RESOURCES, resource_id)
		_check(not record.is_empty(), "Content Editor lists %s" % resource_id)
		_check(editor_data.validate_resource(resource_id, resource_id, record).is_empty(), "%s passes resource validation" % resource_id)

	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var map := game.current_map as MapRoot
	var world := map.find_child("RomesteadProceduralGameWorld", true, false) as RomesteadProceduralGameWorld
	var resources := map.get_resources_root()
	_check(world != null, "GAME uses the Romestead procedural world")
	_check(resources.get_child_count() > 40, "Procedural world created functional resources")
	_check(game.romestead_environment != null and game.alabaster_weather != null, "Romestead lighting and Alabaster weather are active")
	_check(game.day_night_cycle.external_visual_control, "Romestead lighting has visual priority")

	var tree_node: Node = null
	var rock_node: Node = null
	for node in resources.get_children():
		var type_id := str(node.get("resource_type_id"))
		if tree_node == null and type_id.begins_with("tree"):
			tree_node = node
		if rock_node == null and type_id.begins_with("rock"):
			rock_node = node
	_check(tree_node != null and rock_node != null, "Trees and breakable rocks spawn as Oathwake resources")
	if tree_node != null:
		var canopy_pivot := tree_node.find_child("CanopyWindPivot", true, false) as Node2D
		var trunk := tree_node.find_child("TrunkSprite", true, false) as Sprite2D
		var canopy := tree_node.find_child("CanopySprite", true, false) as Sprite2D
		_check(canopy_pivot != null and trunk != null and canopy != null, "Tree is split into static trunk and moving canopy")
		var trunk_rotation := trunk.rotation
		tree_node.call("set_romestead_environment", 0.0, 0.0, 0.82, 2.2, Vector2(1.0, 0.2), 16.0, 1.0)
		tree_node.call("tick_romestead_motion", 0.7)
		_check(not is_zero_approx(canopy_pivot.rotation) and is_equal_approx(trunk.rotation, trunk_rotation), "Wind moves only the grounded canopy")
		tree_node.call("take_damage", 1)
		tree_node.call("_process", 0.08)
		_check(absf(canopy_pivot.rotation) > 0.0001, "Tree reacts to a successful axe hit")

	if rock_node != null:
		var body_shape := rock_node.get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
		_check(body_shape != null and body_shape.shape is CircleShape2D, "Breakable rock has gameplay collision")

	var respawn_node := tree_node
	if respawn_node != null:
		var old_position := (respawn_node as Node2D).global_position
		respawn_node.call("set_collected", true, 0.0)
		respawn_node.call("_process", 0.01)
		var new_position := (respawn_node as Node2D).global_position
		var record: Dictionary = editor_data.get_record(ContentEditorData.SECTION_RESOURCES, str(respawn_node.get("resource_type_id")))
		_check(not new_position.is_equal_approx(old_position), "Destroyed resource respawns at a new procedural location")
		_check((record.get("biomes", []) as Array).has(world.get_biome_id_at_world(new_position)), "Respawn remains inside an allowed biome")

	var generated_resource_count := resources.get_child_count()
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("ROMESTEAD_GAME_INTEGRATION_VALIDATION: PASS resources=%d catalog=%d" % [generated_resource_count, expected_ids.size()])
		quit(0)
	else:
		push_error("ROMESTEAD_GAME_INTEGRATION_VALIDATION failures: %s" % "; ".join(failures))
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)
