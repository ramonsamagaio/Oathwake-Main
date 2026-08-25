extends RefCounted
class_name AlabasterMixamoRetargetV15

# Mixamo -> Juno V15 lower-foot temporal filter.
#
# V14 solved the loop seam but the user's bone-overlay capture exposed a second,
# independent defect: the ankle/foot chain can carry a localized change in angular
# velocity into the contact/recovery phase. In Alabaster a node's accumulated
# rotation also rotates that node's authored REST position, so this is not merely
# a Sprite2D orientation flick. A sharp local rotation curvature physically moves
# the next joint and reads as the recurring little "kick" in a front view.
#
# V15 deliberately keeps V10 handedness/REST characterization, V11 arms,
# V12/V13 presentation calibration and V14 seam closure intact. For LOOPING
# target-rest clips only, it applies an adaptive circular quaternion filter to the
# FOOT/TOE nodes. Constant angular velocity is mathematically left alone: only a
# sample that deviates from the quaternion midpoint of its temporal neighbours is
# blended toward that midpoint. This makes the rule reusable across Mixamo loops
# rather than special-casing Walking or a particular frame number.

const V14 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV14.gd")
const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")

const PROFILE_NAME := "MIXAMO_JUNO_V14_ADAPTIVE_FOOT_CONTINUITY_V15"
const FILTER_BONES := ["footL", "toeL", "footR", "toeR"]
const DEFAULT_FILTER_PASSES := 2
const DEFAULT_DEVIATION_START_DEG := 0.18
const DEFAULT_DEVIATION_FULL_DEG := 1.60
const DEFAULT_FOOT_STRENGTH := 0.82
const DEFAULT_TOE_STRENGTH := 0.90
const EPS := 0.000001


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	var baseline: Dictionary = V14.convert_scene(
		player,
		skeleton,
		clip_name,
		sample_fps,
		loop,
		translation_scale,
		settings
	)
	if baseline.is_empty():
		return baseline

	var mode: String = str(settings.get("retarget_limb_mode", "target_rest_swing"))
	if mode == "full_global_delta" or mode == "segment_swing" or not loop:
		return baseline

	var result: Dictionary = baseline.duplicate(true)
	var patch: Dictionary = _filter_lower_foot_acceleration(result, settings)
	if not bool(patch.get("ok", false)):
		push_warning("Mixamo -> Juno V15: lower-foot acceleration filter failed; preserving V14. %s" % str(patch.get("reason", "")))
		return baseline
	if not V14._non_lower_targets_match(baseline, result):
		push_warning("Mixamo -> Juno V15: a non-lower-limb target changed; preserving V14 byte-for-byte.")
		return baseline

	var meta_value: Variant = result.get("import_meta", {})
	var meta: Dictionary = (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	meta["bridge"] = "mixamo_juno_v14_plus_adaptive_foot_continuity_v15"
	meta["retarget_profile"] = PROFILE_NAME
	meta["lower_foot_acceleration_filter_version"] = 15
	meta["lower_foot_acceleration_filter_passes"] = int(patch.get("passes", 0))
	meta["lower_foot_acceleration_filter_patch_count"] = int(patch.get("patch_count", 0))
	meta["lower_foot_acceleration_filter_max_midpoint_before_deg"] = float(patch.get("max_before", 0.0))
	meta["lower_foot_acceleration_filter_max_midpoint_after_deg"] = float(patch.get("max_after", 0.0))
	meta["lower_foot_acceleration_filter_policy"] = "circular quaternion neighbour-midpoint; adaptive curvature gate; no clip/frame names"
	result["import_meta"] = meta

	print("ALABASTER_MIXAMO_V15_FOOT_CONTINUITY_OK clip=%s passes=%d patches=%d midpoint=%.3f->%.3f" % [
		clip_name,
		int(meta.get("lower_foot_acceleration_filter_passes", 0)),
		int(meta.get("lower_foot_acceleration_filter_patch_count", 0)),
		float(meta.get("lower_foot_acceleration_filter_max_midpoint_before_deg", 0.0)),
		float(meta.get("lower_foot_acceleration_filter_max_midpoint_after_deg", 0.0)),
	])
	return result


static func _filter_lower_foot_acceleration(result: Dictionary, settings: Dictionary) -> Dictionary:
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array or (transforms_value as Array).is_empty():
		return {"ok": false, "reason": "retarget result contains no transforms"}

	var transforms: Array = (transforms_value as Array).duplicate(true)
	var frame_count: int = int(result.get("frameCnt", 0))
	if frame_count < 5:
		return {"ok": false, "reason": "loop is too short for circular foot filtering"}

	var visible_indices: Array[int] = _visible_transform_indices(transforms, frame_count)
	if visible_indices.size() < 5:
		return {"ok": false, "reason": "not enough visible keys for circular foot filtering"}

	var passes: int = clampi(int(settings.get("juno_2d_foot_accel_filter_passes", DEFAULT_FILTER_PASSES)), 1, 4)
	var start_deg: float = maxf(float(settings.get("juno_2d_foot_accel_filter_start_degrees", DEFAULT_DEVIATION_START_DEG)), 0.0)
	var full_deg: float = maxf(float(settings.get("juno_2d_foot_accel_filter_full_degrees", DEFAULT_DEVIATION_FULL_DEG)), start_deg + 0.001)
	var foot_strength: float = clampf(float(settings.get("juno_2d_foot_accel_filter_strength", DEFAULT_FOOT_STRENGTH)), 0.0, 1.0)
	var toe_strength: float = clampf(float(settings.get("juno_2d_toe_accel_filter_strength", DEFAULT_TOE_STRENGTH)), 0.0, 1.0)

	var max_before: float = _max_midpoint_deviation(transforms, visible_indices)
	var patch_count: int = 0
	for _pass_index in range(passes):
		for bone_value in FILTER_BONES:
			var bone_name: String = str(bone_value)
			var strength: float = toe_strength if bone_name.begins_with("toe") else foot_strength
			patch_count += _filter_bone_pass(
				transforms,
				visible_indices,
				bone_name,
				start_deg,
				full_deg,
				strength
			)

	var loop_start: int = int(result.get("loopStart", result.get("animStart", 0)))
	var closure_ok: bool = _refresh_exclusive_loop_closure(transforms, frame_count, loop_start)
	if not closure_ok:
		return {"ok": false, "reason": "could not refresh exclusive loop closure after filtering"}

	var max_after: float = _max_midpoint_deviation(transforms, visible_indices)
	result["transforms"] = transforms
	return {
		"ok": true,
		"passes": passes,
		"patch_count": patch_count,
		"max_before": max_before,
		"max_after": max_after,
		"start_degrees": start_deg,
		"full_degrees": full_deg,
		"foot_strength": foot_strength,
		"toe_strength": toe_strength,
	}


static func _visible_transform_indices(transforms: Array, frame_count: int) -> Array[int]:
	var indices: Array[int] = []
	for index in range(transforms.size()):
		var frame_value: Variant = transforms[index]
		if not frame_value is Dictionary:
			continue
		var frame_number: int = int((frame_value as Dictionary).get("frame", -1))
		if frame_number >= 0 and frame_number < frame_count:
			indices.append(index)
	indices.sort_custom(func(a: int, b: int) -> bool:
		return int((transforms[a] as Dictionary).get("frame", 0)) < int((transforms[b] as Dictionary).get("frame", 0))
	)
	return indices


static func _filter_bone_pass(
	transforms: Array,
	visible_indices: Array[int],
	bone_name: String,
	start_deg: float,
	full_deg: float,
	strength: float
) -> int:
	if strength <= EPS:
		return 0
	var count: int = visible_indices.size()
	var source_quats: Array[Variant] = []
	var source_angles: Array[Variant] = []
	for local_index in range(count):
		var transform_index: int = visible_indices[local_index]
		var angles_value: Variant = _read_rotation(transforms, transform_index, bone_name)
		if not angles_value is Array:
			source_angles.append(null)
			source_quats.append(null)
			continue
		var angles: Array = (angles_value as Array).duplicate()
		source_angles.append(angles)
		source_quats.append(_source_quat(angles))

	var pending: Array[Variant] = []
	pending.resize(count)
	var patch_count: int = 0
	for local_index in range(count):
		var center_value: Variant = source_quats[local_index]
		if not center_value is Quaternion:
			continue
		var prev_index: int = (local_index - 1 + count) % count
		var next_index: int = (local_index + 1) % count
		var prev_value: Variant = source_quats[prev_index]
		var next_value: Variant = source_quats[next_index]
		if not prev_value is Quaternion or not next_value is Quaternion:
			continue

		var center: Quaternion = center_value as Quaternion
		var previous: Quaternion = _same_hemisphere(prev_value as Quaternion, center)
		var following: Quaternion = _same_hemisphere(next_value as Quaternion, center)
		var midpoint: Quaternion = previous.slerp(following, 0.5).normalized()
		midpoint = _same_hemisphere(midpoint, center)
		var deviation_deg: float = _quaternion_distance_degrees(center, midpoint)
		if deviation_deg <= start_deg:
			continue

		var normalized_gate: float = clampf((deviation_deg - start_deg) / maxf(full_deg - start_deg, 0.001), 0.0, 1.0)
		var gate: float = normalized_gate * normalized_gate * (3.0 - 2.0 * normalized_gate)
		var weight: float = clampf(strength * gate, 0.0, 1.0)
		if weight <= EPS:
			continue
		var filtered: Quaternion = center.slerp(midpoint, weight).normalized()
		pending[local_index] = filtered

	for local_index in range(count):
		var filtered_value: Variant = pending[local_index]
		if not filtered_value is Quaternion:
			continue
		var original_value: Variant = source_angles[local_index]
		if not original_value is Array:
			continue
		var original: Array = original_value as Array
		var filtered_angles: Array = V9._quaternion_to_alabaster_angles(filtered_value as Quaternion, {})
		filtered_angles = _unwrap_angles_near(filtered_angles, original)
		if _set_rotation(transforms, visible_indices[local_index], bone_name, filtered_angles):
			patch_count += 1
	return patch_count


static func _max_midpoint_deviation(transforms: Array, visible_indices: Array[int]) -> float:
	var maximum: float = 0.0
	var count: int = visible_indices.size()
	if count < 3:
		return maximum
	for bone_value in FILTER_BONES:
		var bone_name: String = str(bone_value)
		var quats: Array[Variant] = []
		for local_index in range(count):
			var angles_value: Variant = _read_rotation(transforms, visible_indices[local_index], bone_name)
			quats.append(_source_quat(angles_value as Array) if angles_value is Array else null)
		for local_index in range(count):
			var center_value: Variant = quats[local_index]
			if not center_value is Quaternion:
				continue
			var prev_value: Variant = quats[(local_index - 1 + count) % count]
			var next_value: Variant = quats[(local_index + 1) % count]
			if not prev_value is Quaternion or not next_value is Quaternion:
				continue
			var center: Quaternion = center_value as Quaternion
			var previous: Quaternion = _same_hemisphere(prev_value as Quaternion, center)
			var following: Quaternion = _same_hemisphere(next_value as Quaternion, center)
			var midpoint: Quaternion = _same_hemisphere(previous.slerp(following, 0.5).normalized(), center)
			maximum = maxf(maximum, _quaternion_distance_degrees(center, midpoint))
	return maximum


static func _refresh_exclusive_loop_closure(transforms: Array, frame_count: int, loop_start: int) -> bool:
	var source_index: int = -1
	var closure_index: int = -1
	for index in range(transforms.size()):
		var frame_value: Variant = transforms[index]
		if not frame_value is Dictionary:
			continue
		var frame_number: int = int((frame_value as Dictionary).get("frame", -1))
		if frame_number == loop_start:
			source_index = index
		elif frame_number == frame_count:
			closure_index = index
	if source_index < 0 or not transforms[source_index] is Dictionary:
		return false
	var closure: Dictionary = (transforms[source_index] as Dictionary).duplicate(true)
	closure["frame"] = frame_count
	closure["spline"] = "LINEAR"
	closure["v15_exclusive_loop_closure"] = true
	if closure_index >= 0:
		transforms[closure_index] = closure
	else:
		transforms.append(closure)
	return true


static func _read_rotation(transforms: Array, frame_index: int, bone_name: String) -> Variant:
	if frame_index < 0 or frame_index >= transforms.size():
		return null
	var frame_value: Variant = transforms[frame_index]
	if not frame_value is Dictionary:
		return null
	var nodes_value: Variant = (frame_value as Dictionary).get("nodeXfm", {})
	if not nodes_value is Dictionary:
		return null
	var xfm_value: Variant = (nodes_value as Dictionary).get(bone_name, {})
	if not xfm_value is Dictionary:
		return null
	var rot_value: Variant = (xfm_value as Dictionary).get("rot", [0.0, 0.0, 0.0])
	if not rot_value is Array:
		return null
	var source: Array = rot_value as Array
	return [
		float(source[0]) if source.size() > 0 else 0.0,
		float(source[1]) if source.size() > 1 else 0.0,
		float(source[2]) if source.size() > 2 else 0.0,
	]


static func _set_rotation(transforms: Array, frame_index: int, bone_name: String, angles: Array) -> bool:
	if frame_index < 0 or frame_index >= transforms.size():
		return false
	var frame_value: Variant = transforms[frame_index]
	if not frame_value is Dictionary:
		return false
	var frame: Dictionary = (frame_value as Dictionary).duplicate(true)
	var nodes_value: Variant = frame.get("nodeXfm", {})
	if not nodes_value is Dictionary:
		return false
	var nodes: Dictionary = (nodes_value as Dictionary).duplicate(true)
	var xfm_value: Variant = nodes.get(bone_name, {})
	if not xfm_value is Dictionary:
		return false
	var xfm: Dictionary = (xfm_value as Dictionary).duplicate(true)
	xfm["rot"] = [float(angles[0]), float(angles[1]), float(angles[2])]
	nodes[bone_name] = xfm
	frame["nodeXfm"] = nodes
	transforms[frame_index] = frame
	return true


static func _source_quat(angles: Array) -> Quaternion:
	# Exact inverse consumer used by AlabasterRigRuntimeSource._source_quat.
	var yaw: float = float(angles[0]) if angles.size() > 0 else 0.0
	var pitch: float = float(angles[1]) if angles.size() > 1 else 0.0
	var roll: float = float(angles[2]) if angles.size() > 2 else 0.0
	var x: float = deg_to_rad(pitch) * 0.5
	var y: float = deg_to_rad(roll) * 0.5
	var z: float = deg_to_rad(yaw) * 0.5
	var sx: float = sin(x)
	var cx: float = cos(x)
	var sy: float = sin(y)
	var cy: float = cos(y)
	var sz: float = sin(z)
	var cz: float = cos(z)
	return Quaternion(
		sx * cy * cz - cx * sy * sz,
		cx * sy * cz + sx * cy * sz,
		cx * cy * sz - sx * sy * cz,
		cx * cy * cz + sx * sy * sz
	).normalized()


static func _same_hemisphere(value: Quaternion, reference: Quaternion) -> Quaternion:
	var q: Quaternion = value.normalized()
	if q.dot(reference) < 0.0:
		return Quaternion(-q.x, -q.y, -q.z, -q.w)
	return q


static func _quaternion_distance_degrees(a: Quaternion, b: Quaternion) -> float:
	var dot_value: float = clampf(absf(a.normalized().dot(b.normalized())), 0.0, 1.0)
	return rad_to_deg(2.0 * acos(dot_value))


static func _unwrap_angles_near(current: Array, reference: Array) -> Array:
	var result: Array = current.duplicate()
	for axis in range(mini(result.size(), reference.size())):
		var value: float = float(result[axis])
		var target: float = float(reference[axis])
		while value - target > 180.0:
			value -= 360.0
		while value - target < -180.0:
			value += 360.0
		result[axis] = value
	return result
