extends Node
class_name AlabasterBoneStudioDepthPolish

# Bone Bridge uses the transient animation name `__bone_bridge_preview`. The
# production DEFAULT rig intentionally limits some locomotion depth policies to
# canonical names such as walk/run, so those policies were silently skipped in
# the comparison tab even though the same pose data was correct. This controller
# runs AFTER the rig pose and reapplies only visual z-order rules while a Bone
# Bridge preview is active. It never changes animation transforms or source data.

var rig: Object = null
var _last_debug: Dictionary = {}


func setup(target_rig: Object) -> void:
	rig = target_rig
	process_priority = 100
	set_process(true)
	call_deferred("apply_now")


func _process(_delta: float) -> void:
	apply_now()


func apply_now() -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var animation_name := str(rig.get("current_animation"))
	if not animation_name.begins_with("__bone_bridge_"):
		_last_debug = {"active": false, "animation": animation_name}
		return

	# This is the exact arm-vs-torso policy used by canonical DEFAULT locomotion.
	# Bone Bridge's transient animation name was the only reason it did not run.
	if rig.has_method("_apply_humanoid_arm_torso_depth"):
		rig.call("_apply_humanoid_arm_torso_depth")

	# DEFAULT also guards its front-pelvis rule by canonical motion name. Recreate
	# that tiny visual contract here without changing DEFAULT's runtime behavior.
	_apply_front_pelvis_over_thighs()

	# Final profile safety: the anatomically near arm must paint above the complete
	# lower-body silhouette. This closes the remaining case where the pelvis or a
	# foot/thigh authored z-layer can still cross over the near arm during a walk.
	var front_suffix := _resolve_front_arm_suffix()
	if not front_suffix.is_empty():
		_force_front_arm_over_lower_body(front_suffix)

	# The safety pass above deliberately raises the near hand. Reassert the head
	# ceiling from the same live sprite records instead of relying on a profile's
	# inherited helper: Bone Bridge can run on Juno/DEFAULT/Dummy subclasses with
	# different override chains, but the visual rule itself is universal.
	_force_head_over_arms()
	_last_debug = _build_debug(front_suffix)


func get_last_debug() -> Dictionary:
	return _last_debug.duplicate(true)


func _apply_front_pelvis_over_thighs() -> void:
	var thigh_bounds := _visible_z_bounds(["legL", "legR"])
	if not bool(thigh_bounds.get("found", false)):
		return
	var layer_step := _layer_step()
	var required_pelvis_z := int(thigh_bounds.get("max", 0)) + layer_step
	for record in _sprite_records():
		if str(record.get("node", "")) != "bottom" or int(record.get("gfx_index", -1)) != 0:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		if sprite.z_index < required_pelvis_z:
			sprite.z_index = clampi(required_pelvis_z, -4096, 4096)
			sprite.set_meta("alabaster_bone_bridge_depth_reason", "pelvis_over_thighs")


func _resolve_front_arm_suffix() -> String:
	if rig.has_method("_side_front_state"):
		var left_state := int(rig.call("_side_front_state", "shoulderL", "shoulderR", "L"))
		if left_state != 0:
			return "L" if left_state == 1 else "R"

	# Exact cardinal views can collapse the shoulder anchors to the same depth.
	# In that case use the animated whole arm chain, which still carries the walk
	# swing and therefore tells us which side is actually nearer to the camera.
	if rig.has_method("_chain_camera_depth"):
		var left_depth := float(rig.call("_chain_camera_depth", ["armL", "handL", "fingerL"]))
		var right_depth := float(rig.call("_chain_camera_depth", ["armR", "handR", "fingerR"]))
		if not is_nan(left_depth) and not is_nan(right_depth) and absf(left_depth - right_depth) > 0.005:
			return "L" if left_depth > right_depth else "R"
	return ""


func _force_front_arm_over_lower_body(front_suffix: String) -> void:
	var lower_bounds := _visible_z_bounds([
		"bottom",
		"legL", "footL", "toeL",
		"legR", "footR", "toeR",
	])
	if not bool(lower_bounds.get("found", false)):
		return
	var front_nodes := ["arm" + front_suffix, "hand" + front_suffix, "finger" + front_suffix]
	var front_bounds := _visible_z_bounds(front_nodes)
	if not bool(front_bounds.get("found", false)):
		return
	var required_min := int(lower_bounds.get("max", 0)) + _layer_step()
	var current_min := int(front_bounds.get("min", required_min))
	if current_min >= required_min:
		return
	var shift := required_min - current_min
	for record in _sprite_records():
		if str(record.get("node", "")) not in front_nodes:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		sprite.z_index = clampi(sprite.z_index + shift, -4096, 4096)
		sprite.set_meta("alabaster_bone_bridge_depth_reason", "near_arm_over_lower_body")
		sprite.set_meta("alabaster_bone_bridge_depth_shift", shift)


func _force_head_over_arms() -> void:
	var arm_bounds := _visible_z_bounds([
		"armL", "handL", "fingerL",
		"armR", "handR", "fingerR",
	])
	var head_bounds := _visible_z_bounds(["head"])
	if not bool(arm_bounds.get("found", false)) or not bool(head_bounds.get("found", false)):
		return
	var required_min := int(arm_bounds.get("max", 0)) + _layer_step()
	var head_min := int(head_bounds.get("min", required_min))
	if head_min >= required_min:
		return
	var shift := required_min - head_min
	for record in _sprite_records():
		if str(record.get("node", "")) != "head":
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		sprite.z_index = clampi(sprite.z_index + shift, -4096, 4096)
		sprite.set_meta("alabaster_bone_bridge_depth_reason", "head_over_arms")
		sprite.set_meta("alabaster_bone_bridge_depth_shift", shift)


func _build_debug(front_suffix: String) -> Dictionary:
	var lower_bounds := _visible_z_bounds([
		"bottom",
		"legL", "footL", "toeL",
		"legR", "footR", "toeR",
	])
	var front_bounds := _visible_z_bounds([
		"arm" + front_suffix, "hand" + front_suffix, "finger" + front_suffix,
	]) if not front_suffix.is_empty() else {"found": false}
	var head_bounds := _visible_z_bounds(["head"])
	return {
		"active": true,
		"animation": str(rig.get("current_animation")),
		"front_suffix": front_suffix,
		"lower_body_found": bool(lower_bounds.get("found", false)),
		"lower_body_max": int(lower_bounds.get("max", -4096)),
		"front_arm_found": bool(front_bounds.get("found", false)),
		"front_arm_min": int(front_bounds.get("min", 4096)),
		"front_arm_max": int(front_bounds.get("max", -4096)),
		"head_found": bool(head_bounds.get("found", false)),
		"head_min": int(head_bounds.get("min", 4096)),
	}


func _visible_z_bounds(node_names: Array) -> Dictionary:
	var found := false
	var min_z := 4096
	var max_z := -4096
	for record in _sprite_records():
		if str(record.get("node", "")) not in node_names:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		found = true
		min_z = mini(min_z, sprite.z_index)
		max_z = maxi(max_z, sprite.z_index)
	return {"found": found, "min": min_z, "max": max_z}


func _sprite_records() -> Array:
	if rig == null:
		return []
	var records_value: Variant = rig.get("_sprite_records")
	if not records_value is Array:
		return []
	var result: Array = []
	for record_value in records_value as Array:
		if record_value is Dictionary:
			result.append(record_value as Dictionary)
	return result


func _layer_step() -> int:
	if rig == null:
		return 16
	return 1 if bool(rig.get("_embedded_world_mode")) else 16
