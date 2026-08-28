extends "res://scripts/labs/alabaster/AlabasterRigRuntimeTunable.gd"
class_name AlabasterRigRuntimeLayerGuard

# Final visual hierarchy pass for every production humanoid using BonesSystem.
#
# The source renderer establishes authored zOrder first. Production then applies
# direction-aware arm/leg rules, and skin subclasses may add their own clothing
# or pelvis rules. The old architecture had one subtle hole: a subclass could
# legitimately raise the pelvis AFTER the production near-arm rule, putting the
# pelvis/feet back in front of the anatomically near arm. Bone Studio carried a
# private post-pass that hid this while previewing, but gameplay did not.
#
# This class is intentionally between Tunable and BonesSystem so it runs after
# the complete virtual _apply_profile_front_arm_over_legs() chain for Juno,
# DEFAULT, Dummy and Male. It changes CanvasItem depth only. Bone transforms,
# animation tracks, authored sprite cells and retarget data remain untouched.

const FINAL_PROFILE_EPSILON := 11.26

var _final_layer_guard_debug: Dictionary = {}


func _apply_pose() -> void:
	super._apply_pose()
	_apply_final_profile_hierarchy_guard()


func get_final_layer_guard_debug() -> Dictionary:
	return _final_layer_guard_debug.duplicate(true)


func _apply_final_profile_hierarchy_guard() -> void:
	_final_layer_guard_debug = {
		"active": false,
		"animation": current_animation,
		"facing": facing_degrees,
	}
	var is_east := _angular_distance(facing_degrees, 90.0) <= FINAL_PROFILE_EPSILON
	var is_west := _angular_distance(facing_degrees, 270.0) <= FINAL_PROFILE_EPSILON
	if not is_east and not is_west:
		return

	var front_suffix := _resolve_final_front_arm_suffix()
	if front_suffix.is_empty():
		return

	var layer_step := 1 if _embedded_world_mode else 16
	var lower_nodes := [
		"bottom",
		"legL", "footL", "toeL",
		"legR", "footR", "toeR",
	]
	var front_nodes := ["arm" + front_suffix, "hand" + front_suffix, "finger" + front_suffix]
	var all_arm_nodes := ["armL", "handL", "fingerL", "armR", "handR", "fingerR"]

	var lower_before := _guard_visible_z_bounds(lower_nodes)
	var front_before := _guard_visible_z_bounds(front_nodes)
	var front_shift := 0
	if bool(lower_before.get("found", false)) and bool(front_before.get("found", false)):
		var required_front_min := int(lower_before.get("max", 0)) + layer_step
		var current_front_min := int(front_before.get("min", required_front_min))
		if current_front_min < required_front_min:
			front_shift = required_front_min - current_front_min
			_guard_shift_visible_nodes(front_nodes, front_shift, "near_arm_over_complete_lower_body")

	# Raising a hand/forearm can make it overtake the skull. Reassert the head as
	# the body ceiling after every subclass-specific and final arm adjustment.
	var arms_after := _guard_visible_z_bounds(all_arm_nodes)
	var head_before := _guard_visible_z_bounds(["head"])
	var head_shift := 0
	if bool(arms_after.get("found", false)) and bool(head_before.get("found", false)):
		var required_head_min := int(arms_after.get("max", 0)) + layer_step
		var current_head_min := int(head_before.get("min", required_head_min))
		if current_head_min < required_head_min:
			head_shift = required_head_min - current_head_min
			_guard_shift_visible_nodes(["head"], head_shift, "head_over_all_arms")

	var lower_after := _guard_visible_z_bounds(lower_nodes)
	var front_after := _guard_visible_z_bounds(front_nodes)
	var arms_final := _guard_visible_z_bounds(all_arm_nodes)
	var head_after := _guard_visible_z_bounds(["head"])
	_final_layer_guard_debug = {
		"active": true,
		"animation": current_animation,
		"facing": facing_degrees,
		"view": "east" if is_east else "west",
		"front_suffix": front_suffix,
		"lower_body_found": bool(lower_after.get("found", false)),
		"lower_body_max": int(lower_after.get("max", -4096)),
		"front_arm_found": bool(front_after.get("found", false)),
		"front_arm_min": int(front_after.get("min", 4096)),
		"front_arm_max": int(front_after.get("max", -4096)),
		"all_arms_found": bool(arms_final.get("found", false)),
		"all_arms_max": int(arms_final.get("max", -4096)),
		"head_found": bool(head_after.get("found", false)),
		"head_min": int(head_after.get("min", 4096)),
		"front_arm_shift": front_shift,
		"head_shift": head_shift,
	}


func _resolve_final_front_arm_suffix() -> String:
	var left_state := _side_front_state("shoulderL", "shoulderR", "L")
	if left_state != 0:
		return "L" if left_state == 1 else "R"

	# Some rigs expose a camera-space chain scorer for the rare frame where both
	# shoulder anchors quantize to equal depth. Reuse it when available instead of
	# guessing a side from the animation name.
	if has_method("_chain_camera_depth"):
		var left_depth := float(call("_chain_camera_depth", ["armL", "handL", "fingerL"]))
		var right_depth := float(call("_chain_camera_depth", ["armR", "handR", "fingerR"]))
		if not is_nan(left_depth) and not is_nan(right_depth) and absf(left_depth - right_depth) > 0.005:
			return "L" if left_depth > right_depth else "R"
	return ""


func _guard_visible_z_bounds(node_names: Array) -> Dictionary:
	var found := false
	var min_z := 4096
	var max_z := -4096
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		if str(record.get("node", "")) not in node_names:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		found = true
		min_z = mini(min_z, sprite.z_index)
		max_z = maxi(max_z, sprite.z_index)
	return {"found": found, "min": min_z, "max": max_z}


func _guard_shift_visible_nodes(node_names: Array, delta_z: int, reason: String) -> void:
	if delta_z == 0:
		return
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		if str(record.get("node", "")) not in node_names:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		sprite.z_index = clampi(sprite.z_index + delta_z, -4096, 4096)
		sprite.set_meta("alabaster_final_depth_reason", reason)
		sprite.set_meta("alabaster_final_depth_shift", delta_z)
