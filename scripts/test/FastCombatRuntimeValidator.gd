extends SceneTree

const GameScene := preload("res://scenes/game/Game.tscn")
const WorldItemScene := preload("res://scenes/items/WorldItem.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var player = game.player
	_check(player != null, "Enhanced player exists")
	_check(player.has_method("get_current_attack_cooldown"), "Player exposes derived attack cooldown")
	_check(player.has_method("get_current_attack_speed"), "Player exposes attack speed substat")
	_check(player.has_method("get_current_invulnerability_duration"), "Player exposes invulnerability substat")
	_check(player.has_method("_try_dash"), "Player exposes dash action")

	if player != null:
		var cooldown := float(player.get_current_attack_cooldown())
		_check(cooldown > 0.0 and cooldown < 1.0, "Attack cooldown is derived and fast")
		player.call("_attack")
		_check(float(player.get("attack_cooldown_left")) > 0.0, "Attack starts its real cooldown")
		player.call("_attack")
		_check(float(player.get("attack_buffer_left")) > 0.0, "Repeated attack input is buffered")

		var health_before := int(player.health)
		player.take_damage(1)
		var health_after_first := int(player.health)
		player.take_damage(1)
		_check(health_after_first == health_before - 1, "First player hit applies damage")
		_check(int(player.health) == health_after_first, "Invulnerability blocks immediate repeated damage")
		_check(bool(player.is_invulnerable()), "Player reports active invulnerability")

		var position_before: Vector2 = player.global_position
		player.call("_start_dash", Vector2.RIGHT)
		await physics_frame
		await physics_frame
		_check(player.global_position.x > position_before.x, "Dash moves the player")

	var world_item := WorldItemScene.instantiate()
	root.add_child(world_item)
	world_item.setup("wood", 1)
	await process_frame
	_check(world_item.get_node_or_null("GroundShadow") != null, "World item creates a ground shadow")
	_check(world_item.has_method("_create_ground_shadow"), "World item uses hover enhancement")

	var sfx_manager := root.get_node_or_null("SFXManager")
	_check(sfx_manager != null, "SFXManager autoload exists")
	if sfx_manager != null:
		for profile_id in ["player_hit", "player_dash", "hit_slime", "hit_skeleton", "hit_stone", "hit_wood", "critical_hit"]:
			_check(bool(sfx_manager.has_profile(profile_id)), "SFX profile exists: %s" % profile_id)

	if failures.is_empty():
		print("FAST_COMBAT_RUNTIME_VALIDATION: PASS")
		quit(0)
	else:
		push_error("FAST_COMBAT_RUNTIME_VALIDATION failures: %s" % "; ".join(failures))
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)
