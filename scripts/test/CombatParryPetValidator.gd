extends SceneTree

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const SKELETON_SCENE := preload("res://scenes/enemies/Skeleton.tscn")
const WORLD_ITEM_SCENE := preload("res://scenes/items/WorldItem.tscn")
const SMOKE_SCENE := preload("res://scenes/effects/SmokePuff.tscn")
const PARRY_SCENE := preload("res://scenes/effects/ParryEffect.tscn")
const EQUIPMENT_SYSTEM_SCRIPT := preload("res://scripts/systems/EquipmentSystem.gd")
const SPRITE_RESOLVER_SCRIPT := preload("res://scripts/systems/SpriteResolver.gd")

class TestMainNode:
	extends Node
	var equipment_system
	var inventory
	var collected_items: Array[Dictionary] = []

	func add_item_to_inventory(item_id: String, amount: int, metadata: Dictionary = {}) -> int:
		collected_items.append({
			"item_id": item_id,
			"amount": amount,
			"metadata": metadata.duplicate(true),
		})
		return 0

var failures: Array[String] = []
var test_main: TestMainNode
var player: CharacterBody2D
var enemy: CharacterBody2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_setup_runtime()
	await process_frame
	await physics_frame

	_validate_content_and_slots()
	_validate_sprite_placeholders()
	await _validate_player_attack_lock()
	await _validate_enemy_attack_lock()
	await _validate_stun_states()
	await _validate_parry_and_block()
	await _validate_butterfly_pet_pickup()
	await _finish()


func _setup_runtime() -> void:
	test_main = TestMainNode.new()
	test_main.name = "CombatParryPetTestMain"
	test_main.equipment_system = EQUIPMENT_SYSTEM_SCRIPT.new()
	root.add_child(test_main)
	test_main.add_to_group("main")

	player = PLAYER_SCENE.instantiate() as CharacterBody2D
	player.global_position = Vector2.ZERO
	root.add_child(player)

	enemy = SKELETON_SCENE.instantiate() as CharacterBody2D
	enemy.global_position = Vector2(24.0, 0.0)
	root.add_child(enemy)


func _validate_content_and_slots() -> void:
	var content_db := root.get_node_or_null("ContentDB")
	if content_db == null or not content_db.has_method("has_item"):
		failures.append("ContentDB was unavailable during combat/pet validation.")
		return
	if not content_db.has_item("butterfly_pet_trinket"):
		failures.append("Butterfly pet trinket was not merged into item content.")
		return
	var item_data: Dictionary = content_db.get_item("butterfly_pet_trinket")
	if str(item_data.get("equipment_slot", "")) != "trinket":
		failures.append("Butterfly item is not authored for the trinket slot.")
	if str(item_data.get("pet_id", "")) != "butterfly_pickup":
		failures.append("Butterfly item is missing its pickup pet id.")

	var valid_slot := str(test_main.equipment_system.get_valid_slot_for_item("butterfly_pet_trinket"))
	if valid_slot != "back":
		failures.append("Provisional trinket alias did not resolve to the visible back slot; got %s." % valid_slot)

	var resolver := SPRITE_RESOLVER_SCRIPT.new()
	var texture: Texture2D = resolver.get_texture_for_item("butterfly_pet_trinket")
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		failures.append("Butterfly trinket did not resolve its direct placeholder sprite.")


func _validate_sprite_placeholders() -> void:
	var smoke := SMOKE_SCENE.instantiate()
	root.add_child(smoke)
	var smoke_sprite := smoke.get_node_or_null("Sprite2D") as Sprite2D
	if smoke_sprite == null or smoke_sprite.texture == null:
		failures.append("Dash smoke is not backed by a replaceable Sprite2D texture.")
	if smoke.get_node_or_null("PuffA") != null:
		failures.append("Dash smoke still contains the obsolete procedural polygon puffs.")
	smoke.queue_free()

	var parry := PARRY_SCENE.instantiate()
	root.add_child(parry)
	var parry_sprite := parry.get_node_or_null("Sprite2D") as Sprite2D
	if parry_sprite == null or parry_sprite.texture == null:
		failures.append("Parry effect is not backed by a replaceable Sprite2D texture.")
	parry.queue_free()


func _validate_player_attack_lock() -> void:
	if not player.has_method("is_combat_movement_locked"):
		failures.append("Player does not expose the combat movement lock contract.")
		return
	player.call("_start_attack_cycle")
	player.set("attack_total_time", 1.0)
	player.set("velocity", Vector2(140.0, 60.0))
	await physics_frame
	var velocity: Vector2 = player.get("velocity")
	if velocity.length() > 0.01:
		failures.append("Player retained locomotion velocity while attacking: %s." % velocity)
	if not bool(player.call("is_combat_movement_locked")):
		failures.append("Player did not report combat movement locked during attack.")
	player.call("_finish_attack_cycle")


func _validate_enemy_attack_lock() -> void:
	enemy.set("_attack_in_progress", true)
	enemy.set("velocity", Vector2(90.0, 20.0))
	await physics_frame
	var velocity: Vector2 = enemy.get("velocity")
	if velocity.length() > 0.01:
		failures.append("Monster retained locomotion velocity while attacking: %s." % velocity)
	if not bool(enemy.call("is_combat_movement_locked")):
		failures.append("Monster did not report combat movement locked during attack.")
	enemy.set("_attack_in_progress", false)


func _validate_stun_states() -> void:
	player.call("apply_stun", 0.20, enemy)
	if not bool(player.call("is_stunned")):
		failures.append("Player stun did not become active.")
	player.set("velocity", Vector2(100.0, 0.0))
	await physics_frame
	var player_stun_velocity: Vector2 = player.get("velocity")
	if player_stun_velocity.length() > 0.01:
		failures.append("Player moved during stun.")
	await create_timer(0.24).timeout
	await physics_frame
	if bool(player.call("is_stunned")):
		failures.append("Player stun did not expire after its duration.")

	enemy.call("apply_stun", 0.20, player)
	if not bool(enemy.call("is_stunned")):
		failures.append("Monster stun did not become active.")
	enemy.set("velocity", Vector2(100.0, 0.0))
	await physics_frame
	var enemy_stun_velocity: Vector2 = enemy.get("velocity")
	if enemy_stun_velocity.length() > 0.01:
		failures.append("Monster moved during stun.")
	await create_timer(0.24).timeout
	await physics_frame
	if bool(enemy.call("is_stunned")):
		failures.append("Monster stun did not expire after its duration.")


func _validate_parry_and_block() -> void:
	player.set("invulnerability_time_left", 0.0)
	var health_before := int(player.get("health"))
	if not bool(player.call("start_block")):
		failures.append("Player could not enter block state while free.")
		return
	player.call("apply_combat_result", {
		"damage": 20.0,
		"damage_type": "physical",
		"source": enemy,
	})
	await process_frame
	if int(player.get("health")) != health_before:
		failures.append("Successful parry allowed incoming damage through.")
	if not bool(enemy.call("is_stunned")):
		failures.append("Successful parry did not stun the attacking monster.")
	if float(enemy.call("get_stun_time_left")) < 0.85:
		failures.append("Parry stun duration was shorter than the required one second window.")
	if int(player.get_meta("last_parry_success_msec", 0)) <= 0:
		failures.append("Successful parry did not publish its runtime marker.")

	player.call("stop_block")
	player.set("invulnerability_time_left", 0.0)
	await create_timer(1.05).timeout
	await physics_frame
	if not bool(player.call("start_block")):
		failures.append("Player could not re-enter block after parry.")
		return
	await create_timer(float(player.get("parry_window_seconds")) + 0.04).timeout
	var blocked_health_before := int(player.get("health"))
	player.call("apply_combat_result", {
		"damage": 20.0,
		"damage_type": "physical",
		"source": enemy,
	})
	await process_frame
	var blocked_damage := blocked_health_before - int(player.get("health"))
	if blocked_damage <= 0:
		failures.append("Normal block prevented all damage instead of reducing it.")
	elif blocked_damage >= 20:
		failures.append("Normal block did not reduce incoming damage; received %d." % blocked_damage)


func _validate_butterfly_pet_pickup() -> void:
	# Let any hurt animation from the normal block finish before testing pet flow.
	await create_timer(0.50).timeout
	test_main.equipment_system.set_equipped_slot("trinket", {
		"item_id": "butterfly_pet_trinket",
		"amount": 1,
		"metadata": {},
	})
	player.call("refresh_equipped_pet")
	await process_frame
	var pet := player.call("get_active_pet") as Node2D
	if pet == null or not is_instance_valid(pet):
		failures.append("Equipping the butterfly trinket did not summon a pet.")
		return
	if str(pet.get_meta("pet_id", "")) != "butterfly_pickup":
		failures.append("Summoned pet did not expose the butterfly pickup id.")

	var world_item := WORLD_ITEM_SCENE.instantiate() as Area2D
	world_item.set("spawn_jump_enabled", false)
	world_item.call("setup", "wood", 1, {})
	world_item.global_position = player.global_position + Vector2(110.0, 0.0)
	root.add_child(world_item)
	await process_frame

	var deadline := Time.get_ticks_msec() + 2600
	while is_instance_valid(world_item) and Time.get_ticks_msec() < deadline:
		await process_frame
	if is_instance_valid(world_item):
		failures.append("Butterfly pet did not fetch and collect a nearby world item.")
	elif test_main.collected_items.is_empty():
		failures.append("Butterfly removed the drop without using the normal inventory collection path.")
	else:
		var collected: Dictionary = test_main.collected_items.back()
		if str(collected.get("item_id", "")) != "wood":
			failures.append("Butterfly collected the wrong item id.")


func _finish() -> void:
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(test_main):
		test_main.queue_free()
	await process_frame
	if failures.is_empty():
		print("COMBAT_PARRY_PET_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("COMBAT_PARRY_PET_VALIDATION_FAILURE: %s" % failure)
	quit(1)
