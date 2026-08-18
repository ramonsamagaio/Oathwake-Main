class_name RomesteadWildlife
extends "res://scripts/enemies/GenericMonster.gd"

var _rng := RandomNumberGenerator.new()
var _state_timer := 0.0
var _panic_timer := 0.0
var _deer_alert_timer := 0.0
var _deer_has_alerted := false
var _wild_wander_direction := Vector2.ZERO
var _wildlife_config: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("romestead_wildlife")
	show_nameplates = false
	if damage_area != null:
		damage_area.monitoring = false
		for connection in damage_area.body_entered.get_connections():
			damage_area.body_entered.disconnect(connection.callable)
	_rng.seed = int(global_position.x * 92821.0) ^ int(global_position.y * 68917.0) ^ monster_id.hash()
	_wildlife_config = monster_data.get("wildlife", {}) as Dictionary
	_choose_idle_state()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_state_timer -= delta
	_panic_timer = maxf(_panic_timer - delta, 0.0)
	_deer_alert_timer = maxf(_deer_alert_timer - delta, 0.0)

	var threat_radius := float(_wildlife_config.get("threat_radius", 128.0))
	var threat_distance := global_position.distance_to(player.global_position) if player != null else INF
	var threat_close := threat_distance <= threat_radius
	if monster_id == "deer_female" and not threat_close and _panic_timer <= 0.0:
		_deer_has_alerted = false
	if monster_id == "deer_female" and threat_close and not _deer_has_alerted and _panic_timer <= 0.0 and _deer_alert_timer <= 0.0:
		_deer_alert_timer = float(_wildlife_config.get("minimum_alert_seconds", 0.7))
		_deer_has_alerted = true
	elif threat_close and monster_id != "deer_female":
		_panic_timer = maxf(_panic_timer, float(_wildlife_config.get("lost_threat_delay", 0.7)))
	if monster_id == "deer_female" and _deer_alert_timer <= 0.0 and threat_distance <= float(_wildlife_config.get("flee_radius", 144.0)):
		_panic_timer = maxf(_panic_timer, float(_wildlife_config.get("lost_threat_delay", 0.7)))

	var state := "idle"
	var direction := Vector2.ZERO
	if monster_id == "deer_female" and _deer_alert_timer > 0.0:
		state = "alert" if _deer_alert_timer > float(_wildlife_config.get("minimum_alert_seconds", 0.7)) - 0.192 else "alert_loop"
		direction = Vector2.ZERO
		_wild_wander_direction = Vector2.ZERO
	elif _panic_timer > 0.0 and player != null:
		direction = player.global_position.direction_to(global_position)
		state = "fly" if monster_id == "bird" else "run"
		_state_timer = maxf(_state_timer, 0.12)
	elif _state_timer <= 0.0:
		_choose_next_wander_state()

	if direction == Vector2.ZERO:
		direction = _wild_wander_direction
		if direction != Vector2.ZERO:
			state = "hop" if monster_id == "bird" else ("walk" if monster_id == "deer_female" else "run")
		elif monster_id == "bird" and _rng.randf() < 0.35:
			state = "peck"
		elif monster_id == "squirrel" and _rng.randf() < 0.30:
			state = "feeding"

	var walk_scale := float(_wildlife_config.get("walk_speed_scale", 0.3))
	var run_scale := float(_wildlife_config.get("run_speed_scale", 1.0))
	var speed_scale := run_scale if _panic_timer > 0.0 else walk_scale
	velocity = direction.normalized() * speed * speed_scale
	if direction != Vector2.ZERO:
		facing_direction = _wild_direction_name(direction)
	move_and_slide()
	WorldDepthRuntime.apply_node_depth(self)
	if _monster_animator != null:
		_monster_animator.play_state(state, facing_direction)


func take_damage(amount: int) -> void:
	_panic_timer = maxf(_panic_timer, 2.5)
	super.take_damage(amount)


func apply_combat_result(combat_result: Dictionary) -> void:
	_panic_timer = maxf(_panic_timer, 2.5)
	super.apply_combat_result(combat_result)


func set_runtime_active(active: bool) -> void:
	visible = active
	set_physics_process(active)
	if _elemental_conditions != null:
		_elemental_conditions.set_process(active)
	var ground_shadow := get_node_or_null("GroundShadow")
	if ground_shadow != null:
		ground_shadow.set_process(active)
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _choose_next_wander_state() -> void:
	if _rng.randf() < 0.48:
		_choose_idle_state()
		return
	_wild_wander_direction = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	var distance := _rng.randf_range(
		float(_wildlife_config.get("wander_min_distance", 32.0)),
		float(_wildlife_config.get("wander_max_distance", 160.0))
	)
	_state_timer = distance / maxf(speed * float(_wildlife_config.get("walk_speed_scale", 0.3)), 1.0)


func _choose_idle_state() -> void:
	_wild_wander_direction = Vector2.ZERO
	_state_timer = _rng.randf_range(
		float(_wildlife_config.get("idle_min_seconds", 0.5)),
		float(_wildlife_config.get("idle_max_seconds", 2.0))
	)


func _wild_direction_name(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "right" if direction.x >= 0.0 else "left"
	return "down" if direction.y >= 0.0 else "up"
