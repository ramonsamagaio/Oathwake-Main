extends CharacterBody2D

const CombatCalculatorScript := preload("res://scripts/systems/CombatCalculator.gd")
const FloatingCombatTextSpawner := preload("res://scripts/ui/FloatingCombatTextSpawner.gd")
const OverheadNameplateScene := preload("res://scenes/ui/OverheadNameplate.tscn")
const MonsterAnimatorScript := preload("res://scripts/enemies/MonsterAnimator.gd")
const MonsterLocomotionScript := preload("res://scripts/enemies/MonsterLocomotion.gd")
const WorldItemSpawner := preload("res://scripts/systems/WorldItemSpawner.gd")

signal attack_started
signal attack_hit_frame
signal attack_finished

@export var monster_id: String = "slime"
@export var speed: float = 45.0
@export var damage: int = 10
@export var damage_cooldown: float = 1.0
@export var max_health: int = 30
@export var gel_drop_amount: int = 1
@export var show_nameplates := true
@export var show_floating_damage := true
@export var enable_hit_flash := true
@export var enable_knockback := true
@export var attack_windup_time: float = 0.08
@export var attack_hit_time: float = 0.04
@export var attack_recovery_time: float = 0.10

var player: CharacterBody2D
var player_in_contact := false
var damage_timer := 0.0
var health: int = 30
var is_dead := false
var forced_animation_time := 0.0
var separation_distance := 26.0
var contact_stop_distance := 27.0
var display_name := "Slime"
var behavior := "aggressive_contact_chaser"
var spawn_time_seconds := 20.0
var spawn_tiles := []
var loot_table := []
var nameplate: Node2D
var monster_data := {}
var movement_mode := "walk"
var direction_mode := "4dir"
var locomotion_data := {}
var animations_data := {}
var facing_direction := "down"
var combat_calculator := CombatCalculatorScript.new()
var original_scale := Vector2.ONE
var _attack_in_progress := false
var _motion_state := "idle"
var _monster_animator
var _monster_locomotion

@onready var damage_area: Area2D = $DamageArea


func _ready() -> void:
	add_to_group("enemy")
	original_scale = scale
	_load_monster_data()
	_setup_motion_systems()
	health = max_health
	_setup_nameplate()
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	damage_area.body_exited.connect(_on_damage_area_body_exited)
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_update_motion_animation(Vector2.ZERO, "idle")


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	var motion := _update_movement(delta)
	velocity = motion.get("velocity", Vector2.ZERO)
	facing_direction = str(motion.get("facing_direction", facing_direction))
	_motion_state = str(motion.get("state", _motion_state))
	forced_animation_time = maxf(forced_animation_time - delta, 0.0)
	if forced_animation_time <= 0.0:
		_update_motion_animation(motion.get("visual_offset", Vector2.ZERO), _motion_state)
	move_and_slide()
	_resolve_player_overlap()
	_update_damage(delta)


func _update_damage(delta: float) -> void:
	if damage_timer > 0.0:
		damage_timer -= delta

	if player_in_contact and damage_timer <= 0.0 and _can_damage_player() and not _attack_in_progress:
		_attack_player()
		damage_timer = damage_cooldown


func _attack_player() -> void:
	if _attack_in_progress:
		return

	_attack_in_progress = true
	_play_forced_animation("attack")
	attack_started.emit()
	_play_attack_tell()
	await _wait_attack_step(attack_windup_time)
	await _wait_attack_step(attack_hit_time)
	var target_data := {}
	if player.has_method("_get_combat_data"):
		target_data = player.call("_get_combat_data")

	var combat_result := combat_calculator.calculate_damage(get_combat_data(), target_data)
	attack_hit_frame.emit()
	if player.has_method("apply_combat_result"):
		player.call("apply_combat_result", combat_result)
	else:
		player.take_damage(int(combat_result.get("damage", damage)))
	await _wait_attack_step(attack_recovery_time)
	attack_finished.emit()
	_attack_in_progress = false


func take_damage(amount: int) -> void:
	if is_dead or amount <= 0:
		return

	health = max(health - amount, 0)
	_update_nameplate()
	_show_nameplate_after_damage()
	FloatingCombatTextSpawner.show_hit_impact(global_position + Vector2(0, -18), false)
	_play_hit_feedback(false)
	_play_forced_animation("hurt")
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), false, "enemy")

	if health == 0:
		_die()


func apply_combat_result(combat_result: Dictionary) -> void:
	if is_dead:
		return

	if bool(combat_result.get("miss", false)):
		if show_floating_damage:
			FloatingCombatTextSpawner.show_miss(global_position + Vector2(0, -28))
		return

	var amount := int(combat_result.get("damage", 0))
	if amount <= 0:
		return

	health = max(health - amount, 0)
	_update_nameplate()
	_show_nameplate_after_damage()
	var is_critical := bool(combat_result.get("is_critical", false))
	FloatingCombatTextSpawner.show_hit_impact(global_position + Vector2(0, -18), is_critical)
	_play_hit_feedback(is_critical)
	_play_forced_animation("hurt")
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), is_critical, "enemy")

	if health == 0:
		_die()


func _die() -> void:
	is_dead = true
	_show_xp_reward()
	_drop_loot()
	damage_area.monitoring = false
	set_physics_process(false)
	var death_duration := _play_forced_animation("death")
	if death_duration > 0.0:
		await get_tree().create_timer(death_duration).timeout
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_property(self, "scale", original_scale * 0.75, 0.18)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func _drop_loot() -> void:
	if loot_table.is_empty():
		WorldItemSpawner.spawn_item("gel", gel_drop_amount, global_position)
		print("%s dropped %d gel" % [display_name, gel_drop_amount])
		return

	for loot_entry in loot_table:
		if not loot_entry is Dictionary:
			continue

		var chance := float(loot_entry.get("chance", 1.0))
		if randf() > chance:
			continue

		var item_id := str(loot_entry.get("item_id", ""))
		var min_amount := int(loot_entry.get("min_amount", 1))
		var max_amount := int(loot_entry.get("max_amount", min_amount))
		var amount := min_amount
		if max_amount > min_amount:
			amount += int(randi() % (max_amount - min_amount + 1))

		if not item_id.is_empty() and amount > 0:
			WorldItemSpawner.spawn_item(item_id, amount, global_position)
			print("%s dropped %d %s" % [display_name, amount, item_id])


func _on_damage_area_body_entered(body: Node2D) -> void:
	if _is_player_body(body):
		player = body as CharacterBody2D
		player_in_contact = true


func _on_damage_area_body_exited(body: Node2D) -> void:
	if _is_player_body(body):
		player_in_contact = false


func _can_damage_player() -> bool:
	return player != null and is_instance_valid(player) and player.is_in_group("player")


func _is_player_body(body: Node2D) -> bool:
	return body != null and body.is_in_group("player")


func _load_monster_data() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return

	monster_data = content_db.get_monster(monster_id)
	if monster_data.is_empty():
		push_error("EnemyBase could not load monster_id: %s" % monster_id)
		return

	display_name = str(monster_data.get("display_name", display_name))
	behavior = str(monster_data.get("behavior", behavior))
	max_health = int(monster_data.get("max_health", max_health))
	movement_mode = str(monster_data.get("movement_mode", movement_mode))
	direction_mode = str(monster_data.get("direction_mode", direction_mode))
	var loaded_locomotion = monster_data.get("locomotion", locomotion_data)
	if loaded_locomotion is Dictionary:
		locomotion_data = loaded_locomotion.duplicate(true)
	separation_distance = float(locomotion_data.get("separation_distance", separation_distance))
	contact_stop_distance = float(locomotion_data.get("contact_stop_distance", contact_stop_distance))
	if locomotion_data.has("move_speed"):
		speed = float(locomotion_data.get("move_speed", speed))
	elif monster_data.has("move_speed"):
		speed = float(monster_data.get("move_speed", speed))
	animations_data = monster_data.get("animations", animations_data) if monster_data.get("animations", null) is Dictionary else {}
	if locomotion_data.is_empty() and monster_data.has("locomotion") and monster_data.get("locomotion") is Dictionary:
		locomotion_data = monster_data.get("locomotion", {}).duplicate(true)
	damage = int(monster_data.get("damage", damage))
	damage_cooldown = float(monster_data.get("attack_cooldown", damage_cooldown))
	attack_windup_time = float(monster_data.get("attack_windup_time", attack_windup_time))
	attack_hit_time = float(monster_data.get("attack_hit_time", attack_hit_time))
	attack_recovery_time = float(monster_data.get("attack_recovery_time", attack_recovery_time))
	spawn_time_seconds = float(monster_data.get("spawn_time_seconds", spawn_time_seconds))

	var loaded_spawn_tiles = monster_data.get("spawn_tiles", spawn_tiles)
	if loaded_spawn_tiles is Array:
		spawn_tiles = loaded_spawn_tiles

	var loaded_loot_table = monster_data.get("loot_table", loot_table)
	if loaded_loot_table is Array:
		loot_table = loaded_loot_table

	print("%s loaded monster data from ContentDB" % display_name)


func can_chase_player() -> bool:
	return movement_mode != "stationary"


func is_stationary_behavior() -> bool:
	return movement_mode == "stationary"


func _setup_motion_systems() -> void:
	_monster_locomotion = MonsterLocomotionScript.new()
	_monster_locomotion.name = "MonsterLocomotion"
	add_child(_monster_locomotion)
	_monster_locomotion.configure(monster_data, movement_mode, direction_mode, locomotion_data, speed)

	var fallback_nodes := _get_fallback_visual_nodes()
	_monster_animator = MonsterAnimatorScript.new()
	_monster_animator.name = "MonsterAnimator"
	add_child(_monster_animator)
	_monster_animator.configure(self, monster_data, animations_data, direction_mode, fallback_nodes)


func _update_movement(delta: float) -> Dictionary:
	if _monster_locomotion == null:
		return {
			"velocity": Vector2.ZERO,
			"state": "idle",
			"facing_direction": facing_direction,
			"visual_offset": Vector2.ZERO,
		}
	return _monster_locomotion.update(delta, self, player)


func _update_motion_animation(visual_offset: Vector2, motion_state: String) -> void:
	if _monster_animator == null:
		return
	_monster_animator.set_visual_offset(visual_offset)
	_monster_animator.play_state(motion_state, facing_direction)


func _get_fallback_visual_nodes() -> Array:
	var fallback_nodes: Array = []
	for child in get_children():
		if child == null:
			continue
		if child == damage_area or child == nameplate:
			continue
		if child.name == "MonsterAnimator" or child.name == "MonsterLocomotion":
			continue
		if child is CanvasItem:
			fallback_nodes.append(child)
	return fallback_nodes


func _setup_nameplate() -> void:
	if not show_nameplates:
		return

	nameplate = OverheadNameplateScene.instantiate()
	add_child(nameplate)
	nameplate.setup(display_name, health, max_health)


func _update_nameplate() -> void:
	if nameplate == null or not is_instance_valid(nameplate):
		return

	nameplate.set_health(health, max_health)


func _show_nameplate_after_damage() -> void:
	if nameplate == null or not is_instance_valid(nameplate):
		return
	if nameplate.has_method("show_after_damage"):
		nameplate.call("show_after_damage")


func _play_hit_feedback(is_critical: bool) -> void:
	if not enable_hit_flash:
		return

	var vfx_profile := _get_vfx_profile()
	var hit_flash_duration := float(vfx_profile.get("hit_flash_duration", 0.10))
	var critical_hit_flash_duration := float(vfx_profile.get("critical_hit_flash_duration", 0.14))
	var hit_bump_scale := float(vfx_profile.get("hit_bump_scale", 1.04))
	var critical_bump_scale := float(vfx_profile.get("critical_bump_scale", 1.08))
	var flash_color := Color(1.0, 0.65, 0.55, 1.0) if is_critical else Color(1.0, 0.35, 0.35, 1.0)
	for child in get_children():
		if not child is CanvasItem:
			continue
		if child == nameplate:
			continue

		var canvas_item := child as CanvasItem
		var original_color := canvas_item.modulate
		canvas_item.modulate = flash_color
		var tween := create_tween()
		tween.tween_property(canvas_item, "modulate", original_color, critical_hit_flash_duration if is_critical else hit_flash_duration)

	if enable_knockback:
		var bump_scale := original_scale * (critical_bump_scale if is_critical else hit_bump_scale)
		var scale_tween := create_tween()
		scale_tween.tween_property(self, "scale", bump_scale, 0.04)
		scale_tween.tween_property(self, "scale", original_scale, 0.08)


func _play_attack_tell() -> void:
	var tell_tween := create_tween()
	tell_tween.tween_property(self, "scale", original_scale * Vector2(1.05, 0.95), 0.05)
	tell_tween.tween_property(self, "scale", original_scale, 0.06)
	tell_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.01)


func _play_forced_animation(state_name: String) -> float:
	if _monster_animator == null:
		return 0.0
	var animation_name := "%s_%s" % [state_name, facing_direction]
	if not _monster_animator.has_animation(animation_name):
		animation_name = state_name
	if not _monster_animator.has_animation(animation_name):
		return 0.0
	var duration := _monster_animator.get_animation_duration(animation_name)
	forced_animation_time = maxf(forced_animation_time, duration)
	_monster_animator.play_state(state_name, facing_direction)
	return duration

func _resolve_player_overlap() -> void:
	if player == null or not is_instance_valid(player):
		return
	var delta := global_position - player.global_position
	var distance := delta.length()
	if distance >= separation_distance:
		return
	var direction := delta.normalized() if distance > 0.001 else Vector2.RIGHT.rotated(randf() * TAU)
	global_position += direction * (separation_distance - distance + 0.5)
	velocity = velocity.slide(direction)

func get_combat_data() -> Dictionary:
	var combat_data: Dictionary = monster_data.duplicate(true) if monster_data is Dictionary else {}
	combat_data["max_health"] = max_health
	combat_data["damage"] = damage
	if not combat_data.has("base_combat"):
		combat_data["base_combat"] = {
			"base_attack": damage,
			"attack_cooldown": damage_cooldown,
		}
	return combat_data


func _show_xp_reward() -> void:
	var xp_reward := int(monster_data.get("xp_reward", 0))
	if xp_reward <= 0:
		return

	FloatingCombatTextSpawner.show_xp(xp_reward, global_position + Vector2(0, -30))
	if player != null and is_instance_valid(player) and player.has_method("gain_xp"):
		player.call("gain_xp", xp_reward)


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}


func _wait_attack_step(duration: float) -> void:
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout
