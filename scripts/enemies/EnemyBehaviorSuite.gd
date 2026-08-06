extends "res://scripts/enemies/EnemyScreenCombatSuite.gd"

const StunEffectScene := preload("res://scenes/effects/StunEffect.tscn")

var peaceful := false
var fearful := false
var fear_radius := 140.0
var flying := false
var _wander_direction := Vector2.RIGHT
var _wander_time_left := 0.0
var _wander_pause_left := 0.0
var _flight_phase := 0.0
var _stun_effect: Node2D
var _behavior_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_behavior_rng.randomize()
	super._ready()


func _load_monster_data() -> void:
	super._load_monster_data()
	peaceful = bool(monster_data.get("peaceful", false))
	fearful = bool(monster_data.get("fearful", false))
	fear_radius = maxf(float(monster_data.get("fear_radius", 140.0)), 1.0)
	flying = bool(monster_data.get("flying", false))
	set_meta("peaceful", peaceful)
	set_meta("fearful", fearful)
	set_meta("flying", flying)


func _physics_process(delta: float) -> void:
	_flight_phase += delta * 5.0
	super._physics_process(delta)
	_sync_stun_effect()


func _update_damage(delta: float) -> void:
	if peaceful:
		damage_timer = maxf(damage_timer - delta, 0.0)
		return
	super._update_damage(delta)


func _can_damage_player() -> bool:
	return not peaceful and super._can_damage_player()


func _update_movement(delta: float) -> Dictionary:
	if not is_visible_for_activation():
		_cancel_active_attack()
		return _idle_behavior_result()
	if is_stunned() or _attack_in_progress:
		return _idle_behavior_result()
	if not peaceful and behavior != "passive_wanderer":
		return super._update_movement(delta)
	return _update_passive_movement(delta)


func _update_passive_movement(delta: float) -> Dictionary:
	var movement_direction := Vector2.ZERO
	var state_name := "idle"
	if fearful and player != null and is_instance_valid(player):
		var player_distance := global_position.distance_to(player.global_position)
		if player_distance < fear_radius:
			var away := player.global_position.direction_to(global_position)
			if away.length_squared() <= 0.001:
				away = Vector2.RIGHT.rotated(_behavior_rng.randf_range(0.0, TAU))
			var tangent := Vector2(-away.y, away.x) * sin(_flight_phase * 1.7) * 0.38
			movement_direction = (away + tangent).normalized()
			state_name = "walk"

	if movement_direction == Vector2.ZERO:
		_update_wander_clock(delta)
		if _wander_pause_left <= 0.0:
			movement_direction = _wander_direction
			state_name = "walk"

	var visual_offset := Vector2.ZERO
	if flying:
		var bob_height := float(locomotion_data.get("flight_bob_height", 5.0))
		visual_offset.y = sin(_flight_phase) * bob_height
		if movement_direction != Vector2.ZERO:
			var flutter := float(locomotion_data.get("flutter_strength", 0.42))
			var perpendicular := Vector2(-movement_direction.y, movement_direction.x)
			movement_direction = (movement_direction + perpendicular * sin(_flight_phase * 2.3) * flutter).normalized()

	if movement_direction != Vector2.ZERO:
		facing_direction = _direction_name(movement_direction, facing_direction)
	return {
		"velocity": movement_direction * speed,
		"state": state_name,
		"facing_direction": facing_direction,
		"visual_offset": visual_offset,
	}


func _update_wander_clock(delta: float) -> void:
	_wander_time_left = maxf(_wander_time_left - delta, 0.0)
	_wander_pause_left = maxf(_wander_pause_left - delta, 0.0)
	if _wander_time_left > 0.0 or _wander_pause_left > 0.0:
		return
	if _behavior_rng.randf() < 0.22:
		_wander_pause_left = _behavior_rng.randf_range(0.18, 0.60)
		return
	_wander_direction = Vector2.RIGHT.rotated(_behavior_rng.randf_range(0.0, TAU))
	var minimum := float(locomotion_data.get("wander_change_min", 0.75))
	var maximum := maxf(float(locomotion_data.get("wander_change_max", 1.8)), minimum)
	_wander_time_left = _behavior_rng.randf_range(minimum, maximum)


func _idle_behavior_result() -> Dictionary:
	var visual_offset := Vector2.ZERO
	if flying:
		visual_offset.y = sin(_flight_phase) * float(locomotion_data.get("flight_bob_height", 5.0))
	return {
		"velocity": Vector2.ZERO,
		"state": "idle",
		"facing_direction": facing_direction,
		"visual_offset": visual_offset,
	}


func _direction_name(direction: Vector2, fallback: String) -> String:
	if direction.length_squared() <= 0.001:
		return fallback
	if absf(direction.x) > absf(direction.y):
		return "right" if direction.x >= 0.0 else "left"
	return "down" if direction.y >= 0.0 else "up"


func apply_stun(duration := -1.0, source: Node = null) -> void:
	super.apply_stun(duration, source)
	_ensure_stun_effect()


func _sync_stun_effect() -> void:
	if is_stunned():
		_ensure_stun_effect()
	elif _stun_effect != null and is_instance_valid(_stun_effect):
		_stun_effect.queue_free()
		_stun_effect = null


func _ensure_stun_effect() -> void:
	if _stun_effect != null and is_instance_valid(_stun_effect):
		return
	_stun_effect = StunEffectScene.instantiate() as Node2D
	add_child(_stun_effect)
	_stun_effect.position = Vector2(0.0, -34.0 if flying else -42.0)
	_stun_effect.z_index = 20
