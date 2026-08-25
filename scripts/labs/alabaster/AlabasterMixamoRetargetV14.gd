extends RefCounted
class_name AlabasterMixamoRetargetV14

# Mixamo -> Juno V14 lower-limb temporal stabilization.
#
# The bone-overlay capture finally separated the remaining defect from the old
# sprite-presentation hypothesis: near the end of a backward foot stroke, the
# actual Juno lower-limb chain accelerates inward and then snaps into the next
# cycle. V13 only relaxed/smoothed foot/toe pitch+roll and appended a closure key;
# it never preconditioned the LEG/FOOT/TOE bone rotations that lead into that
# closure.
#
# V14 deliberately leaves the solved body/arms/forward calibration untouched.
# For LOOPING clips only, it eases the final ~150 ms of both lower-limb chains
# toward the already-correct loop-start pose. The correction is applied to real
# nodeXfm rotations, not Sprite2D positions, so the debug bones, sprite hierarchy
# and gameplay attachments all see the same motion. Circular angle unwrapping
# prevents 360-degree aliases from being mistaken for real motion.
#
# This is a generic loop-continuity rule for the Mixamo -> Juno characterization,
# not a Walking frame hack. Non-loop clips remain byte-identical to V13.

const V13 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV13.gd")

const PROFILE_NAME := "MIXAMO_JUNO_V13_LOWER_LIMB_CONTINUITY_V14"
const DEFAULT_BLEND_FRAMES := 10
const DEFAULT_MAX_AXIS_CORRECTION_DEG := 45.0
const DEFAULT_MIN_SEAM_DELTA_DEG := 0.35

const LOWER_CHAIN := [
	"legL", "footL", "toeL",
	"legR", "footR", "toeR",
]


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	var baseline: Dictionary = V13.convert_scene(
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

	var mode := str(settings.get("retarget_limb_mode", "target_rest_swing"))
	if mode == "full_global_delta" or mode == "segment_swing" or not loop:
		return baseline

	var result := baseline.duplicate(true)
	var patch := _stabilize_lower_limb_cycle(result, settings)
	if not bool(patch.get("ok", false)):
		push_warning("Mixamo -> Juno V14: lower-limb continuity pass failed; preserving V13. %s" % str(patch.get("reason", "")))
		return baseline
	if not _non_lower_targets_match(baseline, result):
		push_warning("Mixamo -> Juno V14: a non-lower-limb target changed; preserving V13 byte-for-byte.")
		return baseline

	var meta_value: Variant = result.get("import_meta", {})
	var meta: Dictionary = (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	meta["bridge"] = "mixamo_juno_v13_plus_lower_limb_continuity_v14"
	# Keep "V13" in the profile name for compatibility with existing regression
	# readers while advertising the new production layer explicitly.
	meta["retarget_profile"] = PROFILE_NAME
	meta["lower_limb_loop_stabilization_version"] = 14
	meta["lower_limb_loop_blend_frames"] = int(patch.get("blend_frames", 0))
	meta["lower_limb_loop_patch_count"] = int(patch.get("patch_count", 0))
	meta["lower_limb_loop_max_seam_before_deg"] = float(patch.get("max_before", 0.0))
	meta["lower_limb_loop_max_seam_after_deg"] = float(patch.get("max_after", 0.0))
	meta["lower_limb_loop_policy"] = "real nodeXfm continuity; smoothstep final-window blend to loopStart"
	result["import_meta"] = meta

	print("ALABASTER_MIXAMO_V14_LOWER_LIMB_OK clip=%s blend=%d patches=%d seam=%.2f->%.2f" % [
		clip_name,
		int(meta.get("lower_limb_loop_blend_frames", 0)),
		int(meta.get("lower_limb_loop_patch_count", 0)),
		float(meta.get("lower_limb_loop_max_seam_before_deg", 0.0)),
		float(meta.get("lower_limb_loop_max_seam_after_deg", 0.0)),
	])
	return result


static func _stabilize_lower_limb_cycle(result: Dictionary, settings: Dictionary) -> Dictionary:
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array or (transforms_value as Array).is_empty():
		return {"ok": false, "reason": "retarget result contains no transforms"}

	var transforms: Array = (transforms_value as Array).duplicate(true)
	var frame_count := int(result.get("frameCnt", 0))
	if frame_count < 4:
		return {"ok": false, "reason": "loop is too short for lower-limb stabilization"}

	# V13 appends one exclusive frameCnt key. Only visible [0..frameCnt-1] keys
	# are shaped here. The exclusive key already equals loopStart and remains the
	# exact interpolation target after this pass.
	var visible_indices: Array[int] = []
	for index in range(transforms.size()):
		var frame_value: Variant = transforms[index]
		if not frame_value is Dictionary:
			continue
		var frame_number := int((frame_value as Dictionary).get("frame", -1))
		if frame_number >= 0 and frame_number < frame_count:
			visible_indices.append(index)
	if visible_indices.size() < 4:
		return {"ok": false, "reason": "not enough visible loop keys"}

	visible_indices.sort_custom(func(a: int, b: int) -> bool:
		return int((transforms[a] as Dictionary).get("frame", 0)) < int((transforms[b] as Dictionary).get("frame", 0))
	)

	var loop_start_frame := int(result.get("loopStart", result.get("animStart", 0)))
	var start_pos := 0
	for i in range(visible_indices.size()):
		if int((transforms[visible_indices[i]] as Dictionary).get("frame", -1)) == loop_start_frame:
			start_pos = i
			break

	var requested_blend := maxi(int(settings.get("juno_2d_lower_limb_loop_blend_frames", DEFAULT_BLEND_FRAMES)), 3)
	var blend_frames := mini(requested_blend, maxi(visible_indices.size() / 3, 3))
	var max_correction := maxf(float(settings.get("juno_2d_lower_limb_max_axis_correction_degrees", DEFAULT_MAX_AXIS_CORRECTION_DEG)), 5.0)
	var min_delta := maxf(float(settings.get("juno_2d_lower_limb_min_seam_delta_degrees", DEFAULT_MIN_SEAM_DELTA_DEG)), 0.0)
	var patch_count := 0
	var max_before := 0.0

	var first_index := visible_indices[start_pos]
	var last_index := visible_indices[visible_indices.size() - 1]
	for bone_name in LOWER_CHAIN:
		for axis in range(3):
			var first_value := _read_rotation_axis(transforms, first_index, bone_name, axis)
			var last_value := _read_rotation_axis(transforms, last_index, bone_name, axis)
			if first_value == null or last_value == null:
				continue
			var first_near_last := _unwrap_near(float(first_value), float(last_value))
			var seam_delta := first_near_last - float(last_value)
			max_before = maxf(max_before, absf(seam_delta))
			if absf(seam_delta) <= min_delta:
				continue

			# Guard against a pathological source by limiting how much V14 may reshape
			# one local axis. Normal Walking deltas are far below this cap.
			var correction := clampf(seam_delta, -max_correction, max_correction)
			var window_start := maxi(visible_indices.size() - blend_frames, 0)
			for local_index in range(window_start, visible_indices.size()):
				var t := float(local_index - window_start + 1) / float(visible_indices.size() - window_start)
				# Smoothstep has zero-ish acceleration at both ends of the correction
				# window, avoiding the new mini-kick a linear ramp can introduce.
				var weight := t * t * (3.0 - 2.0 * t)
				var transform_index := visible_indices[local_index]
				if _offset_rotation_axis(transforms, transform_index, bone_name, axis, correction * weight):
					patch_count += 1

	# Recompute the actual residual seam after shaping. This is intentionally
	# measured on bone rotations, not sprite positions.
	var max_after := 0.0
	for bone_name in LOWER_CHAIN:
		for axis in range(3):
			var first_value := _read_rotation_axis(transforms, first_index, bone_name, axis)
			var last_value := _read_rotation_axis(transforms, last_index, bone_name, axis)
			if first_value == null or last_value == null:
				continue
			var first_near_last := _unwrap_near(float(first_value), float(last_value))
			max_after = maxf(max_after, absf(first_near_last - float(last_value)))

	result["transforms"] = transforms
	return {
		"ok": true,
		"blend_frames": blend_frames,
		"patch_count": patch_count,
		"max_before": max_before,
		"max_after": max_after,
	}


static func _rotation_array(xfm: Dictionary) -> Array:
	var rot_value: Variant = xfm.get("rot", [0.0, 0.0, 0.0])
	var result: Array = [0.0, 0.0, 0.0]
	if rot_value is Array:
		var source := rot_value as Array
		for index in range(mini(source.size(), 3)):
			result[index] = float(source[index])
	return result


static func _read_rotation_axis(transforms: Array, frame_index: int, bone_name: String, axis: int) -> Variant:
	if frame_index < 0 or frame_index >= transforms.size():
		return null
	var frame_value: Variant = transforms[frame_index]
	if not frame_value is Dictionary:
		return null
	var node_value: Variant = (frame_value as Dictionary).get("nodeXfm", {})
	if not node_value is Dictionary:
		return null
	var xfm_value: Variant = (node_value as Dictionary).get(bone_name, {})
	if not xfm_value is Dictionary:
		return null
	var rot := _rotation_array(xfm_value as Dictionary)
	return float(rot[axis]) if axis >= 0 and axis < rot.size() else null


static func _offset_rotation_axis(transforms: Array, frame_index: int, bone_name: String, axis: int, amount: float) -> bool:
	if absf(amount) <= 0.000001 or frame_index < 0 or frame_index >= transforms.size():
		return false
	var frame_value: Variant = transforms[frame_index]
	if not frame_value is Dictionary:
		return false
	var frame := (frame_value as Dictionary).duplicate(true)
	var nodes_value: Variant = frame.get("nodeXfm", {})
	if not nodes_value is Dictionary:
		return false
	var nodes := (nodes_value as Dictionary).duplicate(true)
	var xfm_value: Variant = nodes.get(bone_name, {})
	if not xfm_value is Dictionary:
		return false
	var xfm := (xfm_value as Dictionary).duplicate(true)
	var rot := _rotation_array(xfm)
	if axis < 0 or axis >= rot.size():
		return false
	rot[axis] = float(rot[axis]) + amount
	xfm["rot"] = rot
	nodes[bone_name] = xfm
	frame["nodeXfm"] = nodes
	transforms[frame_index] = frame
	return true


static func _unwrap_near(value: float, reference: float) -> float:
	var result := value
	while result - reference > 180.0:
		result -= 360.0
	while result - reference < -180.0:
		result += 360.0
	return result


static func _non_lower_targets_match(before: Dictionary, after: Dictionary) -> bool:
	var before_value: Variant = before.get("transforms", [])
	var after_value: Variant = after.get("transforms", [])
	if not before_value is Array or not after_value is Array:
		return false
	var before_frames := before_value as Array
	var after_frames := after_value as Array
	if before_frames.size() != after_frames.size():
		return false
	for frame_index in range(before_frames.size()):
		var before_frame_value: Variant = before_frames[frame_index]
		var after_frame_value: Variant = after_frames[frame_index]
		if not before_frame_value is Dictionary or not after_frame_value is Dictionary:
			continue
		var before_nodes_value: Variant = (before_frame_value as Dictionary).get("nodeXfm", {})
		var after_nodes_value: Variant = (after_frame_value as Dictionary).get("nodeXfm", {})
		if not before_nodes_value is Dictionary or not after_nodes_value is Dictionary:
			return false
		var before_nodes := before_nodes_value as Dictionary
		var after_nodes := after_nodes_value as Dictionary
		for target_value in before_nodes.keys():
			var target := str(target_value)
			if target in LOWER_CHAIN:
				continue
			if not after_nodes.has(target) or before_nodes[target_value] != after_nodes[target]:
				return false
	return true
