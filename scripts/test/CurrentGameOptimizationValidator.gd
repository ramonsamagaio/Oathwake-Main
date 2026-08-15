extends SceneTree

const GAME_SCENE := preload("res://scenes/game/Game.tscn")
const BUTTERFLY_MONSTER_SCENE := preload("res://scenes/enemies/ButterflyMonster.tscn")
const BUTTERFLY_PET_SCENE := preload("res://scenes/pets/ButterflyPet.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := root.get_node_or_null("GameSession")
	if session != null:
		session.start_new_session("optimization_validator_%d" % Time.get_ticks_usec(), "Validator", "Optimization")
	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	for _frame in range(12):
		await process_frame

	var player := game.player as Node
	_check(player.get_node_or_null("NightLight") == null, "player has no emitted light")
	_check(not bool(player.call("is_player_night_readability_enabled")), "player has no unshaded readability override")
	_check(game.get_node("Systems/DayNightCycle").get("cycle_paused") == true, "day cycle starts locked")
	_check(is_equal_approx(float(game.day_night_cycle.time_of_day), 10.0 / 24.0), "default clock is locked at 16:00")
	_check(str(game.alabaster_weather.target_weather) == "clear" and not bool(game.alabaster_weather.auto_cycle), "weather starts clear and locked")
	_check(game.get_node_or_null("UI/WeatherButton") != null and game.get_node_or_null("UI/WeatherControlPanel") != null, "weather controls are next to the editor controls")
	_check(game.get_node_or_null("UI/FpsMeterBackdrop/FpsMeter") != null, "rolling FPS and frame-peak meter is visible")

	game.inventory.set_slot(0, "adamantite_axe", 1, {"current_durability": 10})
	game.hotbar_ui.assign_shortcut_from_inventory_slot(0, 0, true)
	for _use in range(4):
		player.call("_reduce_current_hotbar_item_durability")
	_check(int(game.inventory.get_slot(0).get("metadata", {}).get("current_durability", -1)) == 10, "four uses cause no whole durability loss")
	player.call("_reduce_current_hotbar_item_durability")
	_check(int(game.inventory.get_slot(0).get("metadata", {}).get("current_durability", -1)) == 9, "five uses cost one durability")

	_check(_json_scale("res://data/player_tuning.json", "default") == 1.0, "Juno uses 1:1 source-pixel scale")
	_check(_json_scale("res://data/monsters.json", "slime") == 1.0, "slime uses 1:1 source-pixel scale")
	var slime_record := _json_record("res://data/monsters.json", "slime")
	var slime_glow: Variant = slime_record.get("glow", {})
	_check(slime_glow is Dictionary and not bool((slime_glow as Dictionary).get("enabled", true)), "slime glow is disabled")
	for butterfly_id in ["butterfly_blue", "butterfly_grey", "butterfly_pink", "butterfly_red", "butterfly_white", "butterfly_yellow"]:
		_check(_json_scale("res://data/butterfly_monsters.json", butterfly_id) == 1.0, "%s uses 1:1 source-pixel scale" % butterfly_id)

	var resources: Node = game.current_map.get_resources_root()
	var player_shadow := player.get_node_or_null("RomesteadPlayerShadow")
	_check(player_shadow is CanvasGroup and player_shadow.get_child_count() > 0, "player shadow is flattened before opacity is applied")
	var shadow_parts_are_opaque := player_shadow != null
	if player_shadow != null:
		for part in player_shadow.get_children():
			if part is Sprite2D and not is_equal_approx((part as Sprite2D).modulate.a, 1.0):
				shadow_parts_are_opaque = false
	_check(shadow_parts_are_opaque, "player shadow parts cannot create overlapping alpha seams")
	var ambient := game.get_node_or_null("RomesteadAmbientParticles")
	_check(ambient != null and ambient.has_method("get_particle_world_positions") and (ambient.call("get_particle_world_positions") as Array).size() > 0, "firefly, leaf and dust field is active")
	var type_to_sprite := {}
	var instance_ids := {}
	var wind_tree: Node = null
	var depth_tree: Node2D = null
	var projected_shadow: Sprite2D = null
	for resource in resources.get_children():
		var type_id := str(resource.get("resource_type_id"))
		var instance_id := str(resource.get("resource_id"))
		instance_ids[instance_id] = true
		if not type_to_sprite.has(type_id):
			type_to_sprite[type_id] = str(resource.get("sprite_id"))
		if resource.visible and wind_tree == null and type_id.begins_with("tree") and resource.has_method("uses_romestead_wind") and bool(resource.call("uses_romestead_wind")) and resource.find_child("CanopyWindPivot", true, false) != null:
			wind_tree = resource
		if resource.visible and depth_tree == null and type_id.begins_with("tree"):
			depth_tree = resource as Node2D
		if resource.visible and projected_shadow == null:
			projected_shadow = resource.get_node_or_null("RomesteadShadow") as Sprite2D
	_check(instance_ids.size() == resources.get_child_count(), "spawn ids are unique without creating new content models")
	_check(type_to_sprite.size() < resources.get_child_count(), "tree/rock models are reused across repeated spawns")
	_check(projected_shadow != null and absf(projected_shadow.transform.y.x) > 0.05, "resource shadows use the visible diagonal Romestead projection")
	if depth_tree != null:
		_check(absf(float(depth_tree.get_meta("world_depth_y", INF)) - depth_tree.global_position.y) < 0.01, "trees sort from their authored ground contact")
		var original_player_position: Vector2 = (player as Node2D).global_position
		(player as Node2D).global_position = depth_tree.global_position + Vector2(0.0, -12.0)
		player.call("_update_world_depth")
		var tree_covers_player := depth_tree.z_index > (player as CanvasItem).z_index
		(player as Node2D).global_position = depth_tree.global_position + Vector2(0.0, 12.0)
		player.call("_update_world_depth")
		var player_covers_tree := (player as CanvasItem).z_index > depth_tree.z_index
		(player as Node2D).global_position = original_player_position
		player.call("_update_world_depth")
		_check(tree_covers_player and player_covers_tree, "tree/player ordering changes correctly across the trunk")
		depth_tree.call("tick_player_occlusion", depth_tree.global_position + Vector2(0.0, -20.0), 1.0)
		var tree_visual := depth_tree.get_node_or_null("VisualRoot") as CanvasItem
		var occluded_alpha := tree_visual.modulate.a if tree_visual != null else -1.0
		depth_tree.call("tick_player_occlusion", depth_tree.global_position + Vector2(200.0, 0.0), 1.0)
		var restored_alpha := tree_visual.modulate.a if tree_visual != null else -1.0
		_check(is_equal_approx(occluded_alpha, 0.70) and is_equal_approx(restored_alpha, 1.0), "resource occlusion removes only thirty percent opacity")
		var canopy_sprite := depth_tree.find_child("CanopySprite", true, false) as Sprite2D
		_check(canopy_sprite != null and canopy_sprite.position.y <= -7.9, "tree crown leaves the grounded trunk visible")
		var original_tree_position := depth_tree.global_position
		depth_tree.call("set_collected", true, 60.0)
		var procedural_world: Node = game.current_map.find_child("RomesteadProceduralGameWorld", true, false)
		var respawn_candidate: Vector2 = procedural_world.call("get_random_respawn_position", str(depth_tree.get("resource_type_id")), original_tree_position)
		var respawn_has_spacing := true
		for other in resources.get_children():
			if not other is Node2D or not other.visible or not str(other.get("resource_type_id")).begins_with("tree"):
				continue
			if (other as Node2D).global_position.distance_to(respawn_candidate) < 63.9:
				respawn_has_spacing = false
				break
		depth_tree.call("set_collected", false)
		_check(respawn_has_spacing, "tree respawn keeps at least 64 pixels from other trees")
	else:
		_check(false, "trees sort from their authored ground contact")
		_check(false, "tree/player ordering changes correctly across the trunk")
		_check(false, "resource occlusion removes only thirty percent opacity")
		_check(false, "tree crown leaves the grounded trunk visible")
		_check(false, "tree respawn keeps at least 64 pixels from other trees")
	if wind_tree != null:
		var pivot := wind_tree.find_child("CanopyWindPivot", true, false) as Node2D
		var initial_rotation := pivot.rotation if pivot != null else 0.0
		var moved := false
		for _frame in range(45):
			await process_frame
			if pivot != null and absf(pivot.rotation - initial_rotation) > 0.0001:
				moved = true
		_check(moved, "default clear-weather wind moves the tree canopy")
	else:
		_check(false, "default clear-weather wind moves the tree canopy")

	var processing_resources := 0
	for resource in resources.get_children():
		if resource.is_processing() and not bool(resource.call("is_collected")):
			processing_resources += 1
	_check(processing_resources == 0, "active procedural resources have no individual idle process")

	var butterfly := BUTTERFLY_MONSTER_SCENE.instantiate() as CharacterBody2D
	butterfly.set("monster_id", "butterfly_blue")
	game.current_map.get_enemies_root().add_child(butterfly)
	var pet := BUTTERFLY_PET_SCENE.instantiate() as Node2D
	game.get_node("RuntimeEntities").add_child(pet)
	pet.call("setup", player, {})
	game.day_night_cycle.set_night()
	for _frame in range(3):
		await process_frame
	var butterfly_shadow := butterfly.get_node_or_null("GroundShadow") as Polygon2D
	var pet_shadow := pet.get_node_or_null("GroundShadow") as Polygon2D
	var compact_contact := butterfly_shadow != null and bool(butterfly_shadow.get_meta("contact_shadow", false))
	if butterfly_shadow != null and not butterfly_shadow.polygon.is_empty():
		var min_y := butterfly_shadow.polygon[0].y
		var max_y := min_y
		for point in butterfly_shadow.polygon:
			min_y = minf(min_y, point.y)
			max_y = maxf(max_y, point.y)
		compact_contact = compact_contact and max_y - min_y <= 4.0
	_check(compact_contact, "flying monster uses a compact contact shadow")
	_check(projected_shadow != null and projected_shadow.modulate.a > 0.01, "resource shadows remain subtly visible at night")
	_check(player_shadow != null and player_shadow.self_modulate.a > 0.01, "player shadow remains subtly visible at night")
	_check(pet_shadow != null and pet_shadow.color.a > 0.01 and pet_shadow.color.a < 0.10, "pet butterfly shadow follows night strength")

	var wrong_tool_targets: Array[Node] = []
	for resource in resources.get_children():
		if resource.visible and str(resource.get("resource_type_id")).begins_with("rock"):
			wrong_tool_targets.append(resource)
			if wrong_tool_targets.size() == 2:
				break
	var durability_before := int(game.inventory.get_slot(0).get("metadata", {}).get("current_durability", -1))
	var held_item: Dictionary = player.call("_get_current_held_item_data") as Dictionary
	var actor_data: Dictionary = player.player_stats_resolver.get_total_player_data(player, player.call("_get_equipment_system"))
	var both_rejected := wrong_tool_targets.size() == 2
	for index in range(wrong_tool_targets.size()):
		var blocked_result: Dictionary = player.call("_attack_resource_with_context", wrong_tool_targets[index], held_item, actor_data, index == 0) as Dictionary
		both_rejected = both_rejected and not bool(blocked_result.get("can_damage", true))
	var durability_after := int(game.inventory.get_slot(0).get("metadata", {}).get("current_durability", -1))
	_check(both_rejected and durability_after == durability_before, "two wrong-tool hits cause no durability/UI writes")

	var resource_count: int = resources.get_child_count()
	var model_count: int = type_to_sprite.size()
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("CURRENT_GAME_OPTIMIZATION_VALIDATION: PASS resources=%d models=%d" % [resource_count, model_count])
		quit(0)
	else:
		push_error("CURRENT_GAME_OPTIMIZATION_VALIDATION failures: %s" % "; ".join(failures))
		quit(1)


func _json_scale(path: String, record_id: String) -> float:
	return float(_json_record(path, record_id).get("visual_scale", -1.0))


func _json_record(path: String, record_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	var record: Variant = (parsed as Dictionary).get(record_id, {})
	return (record as Dictionary) if record is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)
