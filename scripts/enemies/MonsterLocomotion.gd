extends Node

const HOP_PHASES := ["pause", "prepare", "air", "land", "recover"]
const STEERING_ANGLES := [0.0, 28.0, -28.0, 52.0, -52.0, 78.0, -78.0, 110.0, -110.0]

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
var contact_stop_distance := 27.0
var facing_direction := "down"
var state := "idle"

var obstacle_probe_distance := 42.0
var hazard_probe_distance := 68.0
var steering_strength := 1.25
var body_clearance := 14.0
var stuck_threshold := 0.48
var detour_duration := 0.8

var _phase := "pause"
var _phase_time_left := 0.0
var _hop_direction := Vector2.RIGHT
var _last_owner_position := Vector2(INF, INF)
var _stuck_time := 0.0
var _detour_time_left := 0.0
var _detour_sign := 1.0


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
	contact_stop_distance = maxf(float(locomotion_data.get("contact_stop_distance", 27.0)), 1.0)
	obstacle_probe_distance = maxf(float(locomotion_data.get("obstacle_probe_distance", 42.0)), 12.0)
	hazard_probe_distance = maxf(float(locomotion_data.get("hazard_probe_distance", 68.0)), obstacle_probe_distance)
	steering_strength = clampf(float(locomotion_data.get("steering_strength", 1.25)), 0.1, 4.0)
	body_clearance = maxf(float(locomotion_data.get("body_clearance", 14.0)), 2.0)
	stuck_threshold = maxf(float(locomotion_data.get("stuck_threshold", 0.48)), 0.1)
	detour_duration = maxf(float(locomotion_data.get("detour_duration", 0.8)), 0.1)

	_reset_hop_cycle()
	_last_owner_position = Vector2(INF, INF)
	_stuck_time = 0.0
	_detour_time_left = 0.0


func update(delta: float, owner: CharacterBody2D, target: CharacterBody2D) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return _make_result(Vector2.ZERO, "idle", facing_direction, Vector2.ZERO)

	_update_stuck_state(delta, owner)
	if movement_mode == "stationary" or target == null or not is_instance_valid(target):
		state = "idle"
		return _make_result(Vector2.ZERO, state, facing_direction, Vector2.ZERO)

	if movement_mode == "hop":
		return _update_hop(delta, owner, target)

	return _update_walk(owner, target)


func _update_walk(owner: CharacterBody2D, target: CharacterBody2D) -> Dictionary:
	if owner.global_position.distance_to(target.global_position) <= contact_stop_distance:
		state = "idle"
		return _make_result(Vector2.ZERO, state, facing_direction, Vector2.ZERO)
	var desired_direction := owner.global_position.direction_to(target.global_position)
	if desired_direction.length() <= 0.001:
		state = "idle"
		return _make_result(Vector2.ZERO, state, facing_direction, Vector2.ZERO)

	var direction := _get_steered_direction(owner, target, desired_direction.normalized())
	facing_direction = _vector_to_direction_name(direction, facing_direction)
	state = "walk"
	return _make_result(direction * move_speed, state, facing_direction, Vector2.ZERO)


func _update_hop(delta: float, owner: CharacterBody2D, target: CharacterBody2D) -> Dictionary:
	if owner.global_position.distance_to(target.global_position) <= contact_stop_distance and _phase != "air":
		state = "idle"
		return _make_result(Vector2.ZERO, state, facing_direction, Vector2.ZERO)
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

	var desired_direction := owner.global_position.direction_to(target.global_position)
	if desired_direction.length() <= 0.001:
		_hop_direction = Vector2.RIGHT
	else:
		_hop_direction = _get_steered_direction(owner, target, desired_direction.normalized())
	facing_direction = _vector_to_direction_name(_hop_direction, facing_direction)


func _get_steered_direction(owner: CharacterBody2D, target: CharacterBody2D, desired_direction: Vector2) -> Vector2:
	var hazard_repulsion := _get_hazard_repulsion(owner)
	var blended := (desired_direction + hazard_repulsion * steering_strength).normalized()
	if blended.length() <= 0.001:
		blended = desired_direction

	var best_direction := blended
	var best_score := -INF
	for angle_degrees in STEERING_ANGLES:
		var signed_angle := float(angle_degrees)
		if _detour_time_left > 0.0 and not is_zero_approx(signed_angle):
			signed_angle = absf(signed_angle) * _detour_sign
		var candidate := blended.rotated(deg_to_rad(signed_angle)).normalized()
		var score := _score_direction(owner, target, desired_direction, candidate)
		if score > best_score:
			best_score = score
			best_direction = candidate
	return best_direction.normalized()


func _score_direction(owner: CharacterBody2D, target: CharacterBody2D, desired_direction: Vector2, candidate: Vector2) -> float:
	if _is_obstacle_ahead(owner, target, candidate):
		return -1000.0
	var alignment := candidate.dot(desired_direction) * 5.0
	var hazard_penalty := _get_hazard_penalty(owner, candidate) * 8.0
	var detour_bonus := 0.0
	if _detour_time_left > 0.0:
		var cross := desired_direction.cross(candidate)
		detour_bonus = 1.5 if signf(cross) == signf(_detour_sign) else -0.5
	return alignment + detour_bonus - hazard_penalty


func _is_obstacle_ahead(owner: CharacterBody2D, target: CharacterBody2D, direction: Vector2) -> bool:
	var world := owner.get_world_2d()
	if world == null:
		return false
	var exclude: Array[RID] = [owner.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	var from := owner.global_position
	var to := from + direction.normalized() * obstacle_probe_distance
	var query := PhysicsRayQueryParameters2D.create(from, to, 0xFFFFFFFF, exclude)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not world.direct_space_state.intersect_ray(query).is_empty()


func _get_hazard_repulsion(owner: CharacterBody2D) -> Vector2:
	var repulsion := Vector2.ZERO
	for hazard in owner.get_tree().get_nodes_in_group("environmental_hazard"):
		if hazard == null or not is_instance_valid(hazard):
			continue
		if hazard.has_method("is_dangerous_to") and not bool(hazard.call("is_dangerous_to", owner)):
			continue
		if not hazard.has_method("get_avoidance_center") or not hazard.has_method("get_avoidance_radius"):
			continue
		var center: Vector2 = hazard.call("get_avoidance_center")
		var radius := float(hazard.call("get_avoidance_radius")) + body_clearance
		var offset := owner.global_position - center
		var distance := offset.length()
		if distance >= radius + hazard_probe_distance:
			continue
		var away := offset.normalized() if distance > 0.001 else Vector2.RIGHT * _detour_sign
		var pressure := 1.0 - clampf((distance - radius) / maxf(hazard_probe_distance, 1.0), 0.0, 1.0)
		repulsion += away * pressure * maxf(float(hazard.call("get_avoidance_cost")) if hazard.has_method("get_avoidance_cost") else 1.0, 0.1)
	return repulsion


func _get_hazard_penalty(owner: CharacterBody2D, direction: Vector2) -> float:
	var start := owner.global_position
	var finish := start + direction.normalized() * hazard_probe_distance
	var penalty := 0.0
	for hazard in owner.get_tree().get_nodes_in_group("environmental_hazard"):
		if hazard == null or not is_instance_valid(hazard):
			continue
		if hazard.has_method("is_dangerous_to") and not bool(hazard.call("is_dangerous_to", owner)):
			continue
		if not hazard.has_method("get_avoidance_center") or not hazard.has_method("get_avoidance_radius"):
			continue
		var center: Vector2 = hazard.call("get_avoidance_center")
		var radius := float(hazard.call("get_avoidance_radius")) + body_clearance
		var distance := _distance_to_segment(center, start, finish)
		if distance < radius:
			var cost := float(hazard.call("get_avoidance_cost")) if hazard.has_method("get_avoidance_cost") else 1.0
			penalty += (1.0 - distance / maxf(radius, 0.01)) * maxf(cost, 0.1)
	return penalty


func _distance_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(segment_start)
	var t := clampf((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * t)


func _update_stuck_state(delta: float, owner: CharacterBody2D) -> void:
	_detour_time_left = maxf(_detour_time_left - delta, 0.0)
	if is_inf(_last_owner_position.x):
		_last_owner_position = owner.global_position
		return
	var moved_distance := owner.global_position.distance_to(_last_owner_position)
	if state != "idle" and moved_distance < 0.45:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
	if _stuck_time >= stuck_threshold:
		_stuck_time = 0.0
		_detour_time_left = detour_duration
		_detour_sign = -_detour_sign
	_last_owner_position = owner.global_position


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
