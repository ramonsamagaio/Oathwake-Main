extends SceneTree

const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")
const FloatingCombatTextScript := preload("res://scripts/ui/FloatingCombatText.gd")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const TREE_SCENE := preload("res://scenes/Tree.tscn")
const SLIME_SCENE := preload("res://scenes/enemies/Slime.tscn")
const RESOURCE_BASE_SCENE := preload("res://scenes/resources/ResourceNodeBase.tscn")
const START_AREA_SCENE := preload("res://scenes/maps/StartArea.tscn")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_screen_space_hit_motion()
	_validate_attack_content()
	await _validate_depth_and_directional_shadows()
	await _validate_layered_tree_backend()
	await _validate_authored_prop_presentation()

	if failures.is_empty():
		print("WORLD_PRESENTATION_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("WORLD_PRESENTATION_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_screen_space_hit_motion() -> void:
	var canvas_transform: Transform2D = Transform2D.IDENTITY.scaled(Vector2(2.0, 2.0)).translated(Vector2(120.0, 80.0))
	for start_value in [Vector2(-140.0, -220.0), Vector2(420.0, 680.0)]:
		var start: Vector2 = start_value
		var target: Vector2 = FloatingCombatTextScript.calculate_world_target_for_screen_rise(start, canvas_transform, 30.0)
		var screen_start: Vector2 = canvas_transform * start
		var screen_target: Vector2 = canvas_transform * target
		if screen_target.y >= screen_start.y:
			failures.append("Floating hit text does not move upward in screen space from %s." % start)


func _validate_attack_content() -> void:
	var content_db := root.get_node_or_null("ContentDB")
	if content_db == null or not content_db.has_method("get_character"):
		failures.append("ContentDB is unavailable for attack variation validation.")
		return
	var character: Dictionary = content_db.get_character("test_template_player")
	var variants_value: Variant = character.get("attack_animation_variants", [])
	if not (variants_value is Array) or (variants_value as Array).size() < 3:
		failures.append("Test player needs at least three configured attack animation variants.")
		return
	var animation_set: Dictionary = content_db.get_animation_set(str(character.get("animation_set_id", "")))
	var animations_value: Variant = animation_set.get("animations", {})
	if not (animations_value is Dictionary):
		failures.append("Test player Animation Set is missing its animations dictionary.")
		return
	var animations := animations_value as Dictionary
	for raw_variant in variants_value as Array:
		var variant := str(raw_variant)
		if variant.contains("{direction}"):
			for direction in ["down", "up", "left", "right"]:
				var resolved := variant.replace("{direction}", direction)
				if not animations.has(resolved):
					failures.append("Configured directional attack animation is missing: %s." % resolved)
		elif not animations.has(variant):
			failures.append("Configured attack animation is missing: %s." % variant)


func _validate_depth_and_directional_shadows() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	var tree_resource := TREE_SCENE.instantiate() as Area2D
	var slime := SLIME_SCENE.instantiate() as CharacterBody2D
	root.add_child(tree_resource)
	root.add_child(player)
	root.add_child(slime)
	tree_resource.global_position = Vector2(100.0, 240.0)
	player.global_position = Vector2(100.0, 100.0)
	slime.global_position = Vector2(180.0, 240.0)
	await process_frame
	await physics_frame

	if not tree_resource.has_meta("world_depth_y"):
		failures.append("Resource did not publish a world depth line.")
	else:
		var resource_depth_y := float(tree_resource.get_meta("world_depth_y"))
		player.global_position.y = resource_depth_y - 1.0
		await physics_frame
		var behind_z := player.z_index
		player.global_position.y = resource_depth_y + 1.0
		await physics_frame
		var front_z := player.z_index
		if behind_z >= tree_resource.z_index:
			failures.append("Player should remain behind a resource before crossing its configured depth line.")
		if front_z <= tree_resource.z_index:
			failures.append("Player should move in front only after crossing the resource depth line.")

	_validate_directional_shadow(player, "Player")
	_validate_directional_shadow(slime, "Slime")
	_validate_directional_shadow(tree_resource, "Tree resource")

	var observed_attacks: Dictionary = {}
	player.set("last_direction", "right")
	for _index in range(12):
		player.call("_play_attack_animation")
		var sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite != null:
			observed_attacks[str(sprite.animation)] = true
	if observed_attacks.size() < 3:
		failures.append("Player attack shuffle produced only %d unique animations." % observed_attacks.size())

	player.queue_free()
	tree_resource.queue_free()
	slime.queue_free()
	await process_frame


func _validate_directional_shadow(target: Node2D, label: String) -> void:
	var shadow := target.get_node_or_null("GroundShadow") as Polygon2D
	if shadow == null or not shadow.visible:
		failures.append("%s has no visible directional shadow." % label)
		return
	if not bool(shadow.get_meta("directional_shadow", false)):
		failures.append("%s shadow is still a contact ellipse instead of the directional runtime." % label)
		return
	var direction: Vector2 = shadow.get_meta("shadow_direction", Vector2.ZERO)
	if direction.x >= 0.0 or direction.y <= 0.0:
		failures.append("%s shadow does not point southwest." % label)
	if shadow.vertex_colors.size() != shadow.polygon.size() or shadow.vertex_colors.size() < 6:
		failures.append("%s shadow has no complete vertex fade." % label)
		return
	if shadow.vertex_colors[3].a > 0.001 or shadow.vertex_colors[4].a > 0.001:
		failures.append("%s shadow tail does not fade to transparent." % label)


func _validate_layered_tree_backend() -> void:
	var resource := RESOURCE_BASE_SCENE.instantiate()
	resource.set("resource_type_id", "tree")
	resource.set("resource_id", "layered_tree_validator")
	root.add_child(resource)
	await process_frame
	resource.set("resource_data", {
		"id": "layered_tree_validator",
		"sprite_id": "tree0",
		"layered_visual": {
			"enabled": true,
			"trunk_sprite_id": "tree0",
			"canopy_sprite_id": "node_fiber",
			"trunk_offset": {"x": 0.0, "y": 0.0},
			"canopy_offset": {"x": 0.0, "y": -18.0},
			"canopy_z_offset": 3,
			"canopy_wind_enabled": true,
		},
	})
	resource.call("_apply_resource_sprite")
	resource.call("_refresh_world_presentation")
	var trunk := resource.get_node_or_null("VisualRoot/ContentSpriteTarget/LayeredVisualRoot/TrunkSprite") as Sprite2D
	var canopy := resource.get_node_or_null("VisualRoot/ContentSpriteTarget/LayeredVisualRoot/CanopySprite") as Sprite2D
	if trunk == null or trunk.texture == null:
		failures.append("Layered tree backend did not create a trunk sprite.")
	if canopy == null or canopy.texture == null:
		failures.append("Layered tree backend did not create a canopy sprite.")
	elif trunk != null and canopy.z_index <= trunk.z_index:
		failures.append("Layered tree canopy does not render above its trunk.")
	var resources: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/resources.json"))
	for key in resources.keys():
		var record: Variant = resources[key]
		if not (record is Dictionary):
			continue
		var layered_value: Variant = (record as Dictionary).get("layered_visual", {})
		if layered_value is Dictionary and bool((layered_value as Dictionary).get("enabled", false)):
			failures.append("Current resource %s enables layered trees; backend should remain unapplied for now." % key)
	resource.queue_free()
	await process_frame


func _validate_authored_prop_presentation() -> void:
	var map := START_AREA_SCENE.instantiate()
	root.add_child(map)
	await process_frame
	await process_frame
	var authored_tree := map.find_child("Tree01", true, false) as Sprite2D
	if authored_tree == null:
		failures.append("Could not find authored Tree01 prop for presentation validation.")
	else:
		if not authored_tree.has_meta("world_depth_y") or authored_tree.z_as_relative:
			failures.append("Authored props are not participating in absolute world depth sorting.")
		_validate_directional_shadow(authored_tree, "Authored Tree01")
	map.queue_free()
	await process_frame
