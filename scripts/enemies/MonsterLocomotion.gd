extends Node

const HOP_PHASES := ["pause", "prepare", "air", "land", "recover"]

var movement_mode := "walk"
var direction_mode := "4dir"
var locomotion_data: Dictionary = {}
var move_speed := 45.0
var arc_height := 0.0
var pause_time := 0.18
var prepare_time := 0.10
var air_time := 0.22
var land_time := 0.08
var recover_time := 0.10
var facing_direction := "down"
var state := "idle"

var _phase := "pause"
var _phase_time_left := 0.0
var _hop_direction := Vector2.RIGHT


func configure(monster_data: Dictionary, fallback_movement_mode := "walk", fallback_direction_mode := "4dir", fallback_locomotion: Dictionary = {}, fallback_move_speed := 45.0) -> void:
	movement_mode = str(monster_data.get("movement_mode", fallback_movement_mode))
	if movement_mode.is_empty():
		movement_mode = fallback_movement_mode

	direction_mode = str(monster_data.get("direction_mode", fallback_direction_mode))
	if direction_mode.is_empty():
		direction_mode = fallback_direction_mode

	locomotion_data = fallback_locomotion.duplicate(true) if fallback_locomotion is Dictionary else {}
	var loaded_locomotion: Variant = monster_data.get("locomotion", {})
	if loaded_locomotion is Dictionary:
		locomotion_data.merge(loaded_locomotion, true)

	move_speed = float(locomotion_data.get("move_speed", monster_data.get("move_speed", fallback_move_speed)))
	arc_height = float(locomotion_data.get("arc_height", 0.0))
	pause_time = float(locomotion_data.get("pause_time", 0.18))
	prepare_time = float(locomotion_data.get("prepare_time", 0.10))
	air_time = float(locomotion_data.get("air_time", 0.22))
	land_time = float(locomotion_data.get("land_time", 0.08))
	recover_time = float(locomotion_data.get("recover_time", 0.10))

	_reset_hop_cycle()


func update(delta: float, owner: CharacterBody2D, target: CharacterBody2D) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return _make_result(Vector2.ZERO, "idle", facing_direction, Vector2.ZERO)

	if movement_mode == "stationary" or target == null or not is_instance_valid(target):
		state = "idle"
		return _make_result(Vector2.ZERO, state, facing_direction, Vector2.ZERO)

	if movement_mode == "hop":
		return _update_hop(delta, owner, target)

	return _update_walk(owner, target)


func _update_walk(owner: CharacterBody2D, target: CharacterBody2D) -> Dictionary:
	var direction := owner.global_position.direction_to(target.global_position)
	if direction.length() <= 0.001:
		state = "idle"
		return _make_result(Vector2.ZERO, state, facing_direction, Vector2.ZERO)

	facing_direction = _vector_to_direction_name(direction, facing_direction)
	state = "walk"
	return _make_result(direction.normalized() * move_speed, state, facing_direction, Vector2.ZERO)


func _update_hop(delta: float, owner: CharacterBody2D, target: CharacterBody2D) -> Dictionary:
	if _phase_time_left <= 0.0:
		_advance_hop_phase(owner, target)

	_phase_time_left -= delta

	var velocity := Vector2.ZERO
	var visual_offset := Vector2.ZERO
	match _phase:
		"pause":
			state = "idle"
		"prepare":
			state = "hop_prepare"
		"air":
			state = "hop_air"
			velocity = _hop_direction.normalized() * move_speed
			var air_progress := 0.0
			if air_time > 0.0:
				air_progress = clampf(1.0 - (_phase_time_left / air_time), 0.0, 1.0)
			visual_offset.y = -sin(air_progress * PI) * arc_height
		"land":
			state = "hop_land"
		"recover":
			state = "idle"
		_:
			state = "idle"

	if _phase_time_left <= 0.0:
		_advance_hop_phase(owner, target)

	return _make_result(velocity, state, facing_direction, visual_offset)


func _advance_hop_phase(owner: CharacterBody2D, target: CharacterBody2D) -> void:
	match _phase:
		"pause":
			_phase = "prepare"
			_phase_time_left = maxf(prepare_time, 0.01)
			_update_hop_direction(owner, target)
		"prepare":
			_phase = "air"
			_phase_time_left = maxf(air_time, 0.01)
		"air":
			_phase = "land"
			_phase_time_left = maxf(land_time, 0.01)
		"land":
			_phase = "recover"
			_phase_time_left = maxf(recover_time, 0.01)
		"recover":
			_phase = "pause"
			_phase_time_left = maxf(pause_time, 0.01)
		_:
			_reset_hop_cycle()


func _reset_hop_cycle() -> void:
	_phase = "pause"
	_phase_time_left = maxf(pause_time, 0.01)
	state = "idle"


func _update_hop_direction(owner: CharacterBody2D, target: CharacterBody2D) -> void:
	if owner == null or target == null:
		_hop_direction = Vector2.RIGHT
		return

	var direction := owner.global_position.direction_to(target.global_position)
	if direction.length() <= 0.001:
		_hop_direction = Vector2.RIGHT
	else:
		_hop_direction = direction.normalized()
	facing_direction = _vector_to_direction_name(_hop_direction, facing_direction)


func _vector_to_direction_name(vector: Vector2, fallback: String) -> String:
	if vector.length() <= 0.001:
		return fallback
	if absf(vector.x) > absf(vector.y):
		return "right" if vector.x >= 0.0 else "left"
	return "down" if vector.y >= 0.0 else "up"


func _make_result(velocity: Vector2, motion_state: String, direction_name: String, visual_offset: Vector2) -> Dictionary:
	return {
		"velocity": velocity,
		"state": motion_state,
		"facing_direction": direction_name,
		"visual_offset": visual_offset,
	}
