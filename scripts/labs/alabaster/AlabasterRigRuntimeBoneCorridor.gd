extends "res://scripts/labs/alabaster/AlabasterRigRuntimeSourceLive.gd"
class_name AlabasterRigRuntimeBoneCorridor

# Anatomical cardinal-view guard applied to the live BONE state before the
# Production presentation layer runs. The previous implementation in
# AlabasterRigRuntimeProduction moved only Sprite2D pieces after the skeleton had
# already been solved. That hid part of the crossing but left the debug bones,
# attachments and the next-joint trajectory on the original inward path.
#
# This layer keeps the imported rotations untouched. It moves the already-solved
# lower-chain anchors only when a looping locomotion pose collapses a foot through
# the sagittal corridor defined by the live hip span. leg receives a partial
# correction, foot/toe receive the full correction, so the toe segment stays
# rigid while the knee/ankle share the lateral adjustment. Because the correction
# is expressed from the target rig's own hip/foot anchors, there are no clip names
# or frame-number hacks for imported Bone Bridge motion.

const BONE_CORRIDOR_FACING_EPSILON := 11.26
const BONE_CORRIDOR_MIN_HALF_HIP_RATIO := 0.78
const BONE_CORRIDOR_MIN_PX := 2.35
const BONE_CORRIDOR_MAX_SHIFT_PX := 10.0
const BONE_CORRIDOR_MAX_SHIFT_HIP_RATIO := 1.20
const BONE_CORRIDOR_LEG_WEIGHT := 0.68
const BONE_CORRIDOR_EPSILON := 0.001

var _bone_corridor_debug: Dictionary = {}


func _apply_pose() -> void:
	super._apply_pose()
	_apply_cardinal_bone_corridor()


func get_bone_corridor_debug() -> Dictionary:
	return _bone_corridor_debug.duplicate(true)


func _apply_cardinal_bone_corridor() -> void:
	_bone_corridor_debug = {
		"active": false,
		"animation": current_animation,
		"facing": facing_degrees,
		"correction_space": "bone_state",
	}
	if not _bone_corridor_enabled():
		return

	var is_north := _angular_distance(facing_degrees, 0.0) <= BONE_CORRIDOR_FACING_EPSILON
	var is_south := _angular_distance(facing_degrees, 180.0) <= BONE_CORRIDOR_FACING_EPSILON
	if not is_north and not is_south:
		return
	for required_node in ["hipL", "hipR", "legL", "footL", "toeL", "legR", "footR", "toeR"]:
		if not _states.has(required_node):
			return

	var hip_l := _bone_screen_anchor("hipL")
	var hip_r := _bone_screen_anchor("hipR")
	var foot_l := _bone_screen_anchor("footL")
	var foot_r := _bone_screen_anchor("footR")
	var center_x := (hip_l.x + hip_r.x) * 0.5
	var half_hip_span := absf(hip_l.x - hip_r.x) * 0.5
	if half_hip_span <= 0.25:
		return

	var min_half_stance := maxf(half_hip_span * BONE_CORRIDOR_MIN_HALF_HIP_RATIO, BONE_CORRIDOR_MIN_PX)
	var max_shift := minf(BONE_CORRIDOR_MAX_SHIFT_PX, half_hip_span * BONE_CORRIDOR_MAX_SHIFT_HIP_RATIO)
	var left_sign := signf(hip_l.x - center_x)
	var right_sign := signf(hip_r.x - center_x)
	if is_zero_approx(left_sign) or is_zero_approx(right_sign) or left_sign == right_sign:
		return

	var left_raw_lateral := (foot_l.x - center_x) * left_sign
	var right_raw_lateral := (foot_r.x - center_x) * right_sign
	var left_shift_mag := clampf(min_half_stance - left_raw_lateral, 0.0, max_shift)
	var right_shift_mag := clampf(min_half_stance - right_raw_lateral, 0.0, max_shift)
	var left_shift := left_shift_mag * left_sign
	var right_shift := right_shift_mag * right_sign

	var original_world := _snapshot_state_world_positions()
	var left_applied := _shift_bone_chain_screen_x("L", left_shift)
	var right_applied := _shift_bone_chain_screen_x("R", right_shift)
	_repair_shifted_chain_origins(original_world)
	_shift_lower_chain_sprites("L", left_applied)
	_shift_lower_chain_sprites("R", right_applied)

	var corrected_l := _bone_screen_anchor("footL")
	var corrected_r := _bone_screen_anchor("footR")
	var left_corrected_lateral := (corrected_l.x - center_x) * left_sign
	var right_corrected_lateral := (corrected_r.x - center_x) * right_sign

	_bone_corridor_debug = {
		"active": true,
		"animation": current_animation,
		"facing": facing_degrees,
		"view": "north" if is_north else "south",
		"correction_space": "bone_state",
		"center_x": center_x,
		"hip_span": half_hip_span * 2.0,
		"min_half_stance": min_half_stance,
		"max_shift": max_shift,
		"left_raw_lateral": left_raw_lateral,
		"right_raw_lateral": right_raw_lateral,
		"left_requested_shift": left_shift,
		"right_requested_shift": right_shift,
		"left_shift": float(left_applied.get("foot", 0.0)),
		"right_shift": float(right_applied.get("foot", 0.0)),
		"left_leg_shift": float(left_applied.get("leg", 0.0)),
		"right_leg_shift": float(right_applied.get("leg", 0.0)),
		"left_corrected_lateral": left_corrected_lateral,
		"right_corrected_lateral": right_corrected_lateral,
	}


func _bone_corridor_enabled() -> bool:
	if current_animation.begins_with("__bone_bridge_"):
		var anim_value: Variant = _anims.get(current_animation, {})
		if not anim_value is Dictionary:
			return false
		var anim := anim_value as Dictionary
		var meta_value: Variant = anim.get("import_meta", {})
		if not meta_value is Dictionary:
			return false
		var meta := meta_value as Dictionary
		return int(meta.get("presentation_calibration_version", 0)) >= 13 \
			and bool(meta.get("runtime_loop_closure_key", false)) \
			and bool(anim.get("repeat", false))

	# Native/player locomotion also uses the same target-side anatomical guard.
	# Imported clips deliberately do not need to be named Walking.
	return current_animation == "walk" or current_animation == "juno_walk_retarget"


func _snapshot_state_world_positions() -> Dictionary:
	var result := {}
	for node_value in _states.keys():
		var node_name := str(node_value)
		var state_value: Variant = _states[node_value]
		if state_value is Dictionary:
			result[node_name] = (state_value as Dictionary).get("g_self", Vector3.ZERO)
	return result


func _shift_bone_chain_screen_x(suffix: String, requested_screen_shift: float) -> Dictionary:
	var result := {"leg": 0.0, "foot": 0.0, "toe": 0.0}
	if absf(requested_screen_shift) <= BONE_CORRIDOR_EPSILON:
		return result
	var targets := [
		{"role": "leg", "name": "leg" + suffix, "weight": BONE_CORRIDOR_LEG_WEIGHT},
		{"role": "foot", "name": "foot" + suffix, "weight": 1.0},
		{"role": "toe", "name": "toe" + suffix, "weight": 1.0},
	]
	for target_value in targets:
		var target := target_value as Dictionary
		var node_name := str(target.get("name", ""))
		if not _states.has(node_name):
			continue
		var state_value: Variant = _states[node_name]
		if not state_value is Dictionary:
			continue
		var state := (state_value as Dictionary).duplicate(true)
		var world_value: Variant = state.get("g_self", Vector3.ZERO)
		if not world_value is Vector3:
			continue
		var world := world_value as Vector3
		var before_x := _project_world(world).x
		var probe_x := _project_world(world + Vector3(1.0, 0.0, 0.0)).x
		var screen_per_world_x := probe_x - before_x
		if absf(screen_per_world_x) <= 0.00001:
			continue
		var desired_screen_shift := requested_screen_shift * float(target.get("weight", 1.0))
		world.x += desired_screen_shift / screen_per_world_x
		var after_x := _project_world(world).x
		var actual_screen_shift := after_x - before_x
		state["g_self"] = world
		state["alabaster_bone_corridor_shift_px"] = actual_screen_shift
		state["alabaster_bone_corridor_side"] = suffix
		_states[node_name] = state
		result[str(target.get("role", ""))] = actual_screen_shift
	return result


func _repair_shifted_chain_origins(original_world: Dictionary) -> void:
	# g_self is an absolute endpoint. g_origin/parent_global must follow only the
	# parent's endpoint delta, otherwise the debug bone would visually detach from
	# its parent when the child receives a larger share of the IK-like correction.
	for node_name in ["legL", "footL", "toeL", "legR", "footR", "toeR"]:
		if not _states.has(node_name):
			continue
		var state_value: Variant = _states[node_name]
		if not state_value is Dictionary:
			continue
		var state := (state_value as Dictionary).duplicate(true)
		var parent_name := str(state.get("parent", ""))
		if parent_name.is_empty() or not _states.has(parent_name) or not original_world.has(parent_name):
			_states[node_name] = state
			continue
		var parent_state_value: Variant = _states[parent_name]
		if not parent_state_value is Dictionary:
			continue
		var parent_state := parent_state_value as Dictionary
		var new_parent_world: Vector3 = parent_state.get("g_self", Vector3.ZERO)
		var old_parent_world: Vector3 = original_world[parent_name]
		var parent_delta := new_parent_world - old_parent_world
		state["g_origin"] = (state.get("g_origin", Vector3.ZERO) as Vector3) + parent_delta
		state["parent_global"] = (state.get("parent_global", Vector3.ZERO) as Vector3) + parent_delta
		state["parent_state"] = parent_state
		_states[node_name] = state


func _shift_lower_chain_sprites(suffix: String, applied: Dictionary) -> void:
	var shifts := {
		"leg" + suffix: float(applied.get("leg", 0.0)),
		"foot" + suffix: float(applied.get("foot", 0.0)),
		"toe" + suffix: float(applied.get("toe", 0.0)),
	}
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var node_name := str(record.get("node", ""))
		if not shifts.has(node_name):
			continue
		var shift := float(shifts[node_name])
		if absf(shift) <= BONE_CORRIDOR_EPSILON:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		sprite.position.x += shift
		sprite.set_meta("alabaster_bone_corridor_shift", shift)
		sprite.set_meta("alabaster_bone_corridor_side", suffix)


func _bone_screen_anchor(node_name: String) -> Vector2:
	if not _states.has(node_name):
		return Vector2.ZERO
	var state_value: Variant = _states[node_name]
	if not state_value is Dictionary:
		return Vector2.ZERO
	return _project_world((state_value as Dictionary).get("g_self", Vector3.ZERO))
