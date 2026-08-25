extends RefCounted
class_name AlabasterMixamoRetargetV13

# Mixamo -> Juno V13 visual locomotion polish.
#
# The user's close profile capture exposed two things V12 could not diagnose from
# angle velocity alone:
#   1. Juno still reads several degrees too far forward because the billboard
#      torso exaggerates the source pose in profile;
#   2. the end-of-stride "kick" is partly a loop-sampling problem. V10/V12 emit
#      loop frames [0 .. frameCnt-1]. BonesSystem can interpolate a smooth seam
#      only when it sees an EXCLUSIVE frameCnt key, otherwise the final visible
#      frame is held and the clock snaps straight back to frame 0.
#
# V13 keeps every structural V10/V11 solve intact. It adds only target-side
# presentation changes: a stronger but still small torso correction, gentle
# foot/toe relaxation toward authored REST, one 1-2-1 lower-foot smoothing pass,
# and an exclusive loop closure key that exists only to give the runtime a proper
# interpolation target. Yaw is never touched, so forward/handedness cannot regress.

const V12 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV12.gd")

const PROFILE_NAME := "MIXAMO_JUNO_V12_PROFILE_POLISH_V13"
const EXTRA_TORSO_BACK_BIAS_DEG := 3.5
const FOOT_PITCH_KEEP := 0.78
const FOOT_ROLL_KEEP := 0.90
const TOE_EXTRA_PITCH_KEEP := 0.72
const TOE_EXTRA_ROLL_KEEP := 0.86

const ALLOWED_PATCH_TARGETS := {
	"top": true,
	"footL": true,
	"toeL": true,
	"footR": true,
	"toeR": true,
}


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	var baseline: Dictionary = V12.convert_scene(
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
	if mode == "full_global_delta" or mode == "segment_swing":
		return baseline

	var baseline_meta_value: Variant = baseline.get("import_meta", {})
	if not baseline_meta_value is Dictionary:
		return baseline
	var baseline_meta := baseline_meta_value as Dictionary
	if not str(baseline_meta.get("retarget_profile", "")).contains("V12"):
		return baseline

	var result := baseline.duplicate(true)
	var patch_info := _apply_profile_polish(result, loop, settings)
	if not bool(patch_info.get("ok", false)):
		push_warning("Mixamo -> Juno V13: profile polish failed; preserving V12. %s" % str(patch_info.get("reason", "")))
		return baseline
	if not _preserved_targets_match(baseline, result):
		push_warning("Mixamo -> Juno V13: a non-presentation bone changed; preserving V12 byte-for-byte.")
		return baseline

	var meta_value: Variant = result.get("import_meta", {})
	var meta: Dictionary = (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	var v12_torso_bias := float(meta.get("torso_back_bias_degrees", 1.5))
	var v12_toe_pitch_keep := float(meta.get("toe_pitch_keep", 1.0))
	var v12_toe_roll_keep := float(meta.get("toe_roll_keep", 1.0))
	var extra_torso_bias := float(patch_info.get("extra_torso_back_bias_degrees", EXTRA_TORSO_BACK_BIAS_DEG))
	var foot_pitch_keep := float(patch_info.get("foot_pitch_keep", FOOT_PITCH_KEEP))
	var foot_roll_keep := float(patch_info.get("foot_roll_keep", FOOT_ROLL_KEEP))
	var toe_extra_pitch_keep := float(patch_info.get("toe_extra_pitch_keep", TOE_EXTRA_PITCH_KEEP))
	var toe_extra_roll_keep := float(patch_info.get("toe_extra_roll_keep", TOE_EXTRA_ROLL_KEEP))

	meta["bridge"] = "mixamo_juno_v12_plus_profile_polish_v13"
	meta["retarget_profile"] = PROFILE_NAME
	meta["presentation_calibration_version"] = 13
	meta["v12_torso_back_bias_degrees"] = v12_torso_bias
	meta["torso_back_bias_degrees"] = v12_torso_bias + extra_torso_bias
	meta["foot_pitch_keep"] = foot_pitch_keep
	meta["foot_roll_keep"] = foot_roll_keep
	meta["toe_pitch_keep"] = v12_toe_pitch_keep * toe_extra_pitch_keep
	meta["toe_roll_keep"] = v12_toe_roll_keep * toe_extra_roll_keep
	meta["lower_foot_smoothing"] = "circular_1_2_1"
	meta["runtime_loop_closure_key"] = bool(patch_info.get("runtime_loop_closure_key", false))
	meta["presentation_patch_targets"] = ["top", "footL", "toeL", "footR", "toeR"]
	meta["v12_non_presentation_bones_preserved"] = true
	result["import_meta"] = meta

	var transforms_value: Variant = result.get("transforms", [])
	var frame_total := (transforms_value as Array).size() if transforms_value is Array else 0
	print("ALABASTER_MIXAMO_V13_2D_OK clip=%s keys=%d torso_bias=%.2f foot_keep=%.2f toe_keep=%.2f closure=%s" % [
		clip_name,
		frame_total,
		float(meta.get("torso_back_bias_degrees", 0.0)),
		foot_pitch_keep,
		float(meta.get("toe_pitch_keep", 1.0)),
		str(meta.get("runtime_loop_closure_key", false)),
	])
	return result


static func _apply_profile_polish(result: Dictionary, loop: bool, settings: Dictionary) -> Dictionary:
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array or (transforms_value as Array).is_empty():
		return {"ok": false, "reason": "retarget result contains no transforms"}

	var transforms: Array = (transforms_value as Array).duplicate(true)
	var frame_count := maxi(int(result.get("frameCnt", transforms.size())), 1)
	var loop_start := int(result.get("loopStart", result.get("animStart", 0)))
	var extra_torso_bias := float(settings.get("juno_2d_extra_torso_back_bias_degrees", EXTRA_TORSO_BACK_BIAS_DEG))
	var foot_pitch_keep := clampf(float(settings.get("juno_2d_foot_pitch_keep", FOOT_PITCH_KEEP)), 0.0, 1.0)
	var foot_roll_keep := clampf(float(settings.get("juno_2d_foot_roll_keep", FOOT_ROLL_KEEP)), 0.0, 1.0)
	var toe_extra_pitch_keep := clampf(float(settings.get("juno_2d_toe_extra_pitch_keep", TOE_EXTRA_PITCH_KEEP)), 0.0, 1.0)
	var toe_extra_roll_keep := clampf(float(settings.get("juno_2d_toe_extra_roll_keep", TOE_EXTRA_ROLL_KEEP)), 0.0, 1.0)

	# Remove any hidden/exclusive endpoint before presentation filtering. The final
	# closure is rebuilt from the corrected loop-start pose below.
	var visible_transforms: Array = []
	for frame_value in transforms:
		if not frame_value is Dictionary:
			continue
		if int((frame_value as Dictionary).get("frame", 0)) >= frame_count:
			continue
		visible_transforms.append((frame_value as Dictionary).duplicate(true))
	transforms = visible_transforms
	if transforms.is_empty():
		return {"ok": false, "reason": "no visible transform frames remain"}

	# V12 already contributes 1.5 degrees. The extra 3.5 brings the total visual
	# correction to ~5 degrees, which matches the profile capture without turning
	# the walk into an obvious backward lean.
	for frame_index in range(transforms.size()):
		var frame := transforms[frame_index] as Dictionary
		var node_value: Variant = frame.get("nodeXfm", {})
		if not node_value is Dictionary:
			continue
		var nodes := (node_value as Dictionary).duplicate(true)
		if nodes.has("top") and nodes["top"] is Dictionary:
			var top_xfm := (nodes["top"] as Dictionary).duplicate(true)
			var top_rot := _rotation_array(top_xfm)
			top_rot[1] = float(top_rot[1]) + extra_torso_bias
			top_xfm["rot"] = top_rot
			nodes["top"] = top_xfm
		frame["nodeXfm"] = nodes
		transforms[frame_index] = frame

	_relax_bone_axes(transforms, "footL", foot_pitch_keep, foot_roll_keep)
	_relax_bone_axes(transforms, "footR", foot_pitch_keep, foot_roll_keep)
	_relax_bone_axes(transforms, "toeL", toe_extra_pitch_keep, toe_extra_roll_keep)
	_relax_bone_axes(transforms, "toeR", toe_extra_pitch_keep, toe_extra_roll_keep)

	# A single centered 1-2-1 pass removes the short high-frequency ankle flick
	# visible as a "kick" while retaining the long stride arc. For looping clips,
	# neighbors wrap around the cycle so the filter itself cannot create a seam.
	for bone_name in ["footL", "footR", "toeL", "toeR"]:
		_smooth_axis_121(transforms, bone_name, 1, loop)
		_smooth_axis_121(transforms, bone_name, 2, loop)

	var closure_added := false
	if loop:
		closure_added = _append_exclusive_loop_closure(transforms, frame_count, loop_start)
	result["transforms"] = transforms
	return {
		"ok": true,
		"extra_torso_back_bias_degrees": extra_torso_bias,
		"foot_pitch_keep": foot_pitch_keep,
		"foot_roll_keep": foot_roll_keep,
		"toe_extra_pitch_keep": toe_extra_pitch_keep,
		"toe_extra_roll_keep": toe_extra_roll_keep,
		"runtime_loop_closure_key": closure_added,
	}


static func _relax_bone_axes(transforms: Array, bone_name: String, pitch_keep: float, roll_keep: float) -> void:
	var previous_pitch: Variant = null
	var previous_roll: Variant = null
	for frame_index in range(transforms.size()):
		var frame_value: Variant = transforms[frame_index]
		if not frame_value is Dictionary:
			continue
		var frame := (frame_value as Dictionary).duplicate(true)
		var node_value: Variant = frame.get("nodeXfm", {})
		if not node_value is Dictionary:
			continue
		var nodes := (node_value as Dictionary).duplicate(true)
		var xfm_value: Variant = nodes.get(bone_name, {})
		if not xfm_value is Dictionary:
			continue
		var xfm := (xfm_value as Dictionary).duplicate(true)
		var rot := _rotation_array(xfm)
		var pitch := _canonical_degrees(float(rot[1])) * pitch_keep
		var roll := _canonical_degrees(float(rot[2])) * roll_keep
		if previous_pitch != null:
			pitch = _unwrap_near(pitch, float(previous_pitch))
		if previous_roll != null:
			roll = _unwrap_near(roll, float(previous_roll))
		previous_pitch = pitch
		previous_roll = roll
		rot[1] = pitch
		rot[2] = roll
		xfm["rot"] = rot
		nodes[bone_name] = xfm
		frame["nodeXfm"] = nodes
		transforms[frame_index] = frame


static func _smooth_axis_121(transforms: Array, bone_name: String, axis: int, loop: bool) -> void:
	if transforms.size() < 3:
		return
	var source: Array[Variant] = []
	for frame_index in range(transforms.size()):
		source.append(_read_rotation_axis(transforms, frame_index, bone_name, axis))
	var filtered: Array[Variant] = source.duplicate()
	for index in range(source.size()):
		if source[index] == null:
			continue
		var center := float(source[index])
		var prev_index := index - 1
		var next_index := index + 1
		if loop:
			prev_index = (prev_index + source.size()) % source.size()
			next_index %= source.size()
		else:
			prev_index = maxi(prev_index, 0)
			next_index = mini(next_index, source.size() - 1)
		var prev_value: Variant = source[prev_index]
		var next_value: Variant = source[next_index]
		if prev_value == null or next_value == null:
			continue
		var prev_angle := _unwrap_near(float(prev_value), center)
		var next_angle := _unwrap_near(float(next_value), center)
		filtered[index] = (prev_angle + center * 2.0 + next_angle) * 0.25
	for index in range(filtered.size()):
		if filtered[index] != null:
			_set_rotation_axis(transforms, index, bone_name, axis, float(filtered[index]))


static func _append_exclusive_loop_closure(transforms: Array, frame_count: int, loop_start: int) -> bool:
	var source_index := -1
	for index in range(transforms.size()):
		var frame_value: Variant = transforms[index]
		if frame_value is Dictionary and int((frame_value as Dictionary).get("frame", -1)) == loop_start:
			source_index = index
			break
	if source_index < 0:
		source_index = 0
	if source_index >= transforms.size() or not transforms[source_index] is Dictionary:
		return false
	var closure := (transforms[source_index] as Dictionary).duplicate(true)
	closure["frame"] = frame_count
	closure["spline"] = "LINEAR"
	closure["v13_exclusive_loop_closure"] = true
	transforms.append(closure)
	return true


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


static func _set_rotation_axis(transforms: Array, frame_index: int, bone_name: String, axis: int, value: float) -> bool:
	if frame_index < 0 or frame_index >= transforms.size():
		return false
	var frame_value: Variant = transforms[frame_index]
	if not frame_value is Dictionary:
		return false
	var frame := (frame_value as Dictionary).duplicate(true)
	var node_value: Variant = frame.get("nodeXfm", {})
	if not node_value is Dictionary:
		return false
	var nodes := (node_value as Dictionary).duplicate(true)
	var xfm_value: Variant = nodes.get(bone_name, {})
	if not xfm_value is Dictionary:
		return false
	var xfm := (xfm_value as Dictionary).duplicate(true)
	var rot := _rotation_array(xfm)
	if axis < 0 or axis >= rot.size():
		return false
	rot[axis] = value
	xfm["rot"] = rot
	nodes[bone_name] = xfm
	frame["nodeXfm"] = nodes
	transforms[frame_index] = frame
	return true


static func _canonical_degrees(value: float) -> float:
	return wrapf(value + 180.0, 0.0, 360.0) - 180.0


static func _unwrap_near(value: float, reference: float) -> float:
	var result := value
	while result - reference > 180.0:
		result -= 360.0
	while result - reference < -180.0:
		result += 360.0
	return result


static func _preserved_targets_match(before: Dictionary, after: Dictionary) -> bool:
	var before_value: Variant = before.get("transforms", [])
	var after_value: Variant = after.get("transforms", [])
	if not before_value is Array or not after_value is Array:
		return false
	var before_frames := before_value as Array
	var after_frames := after_value as Array
	if after_frames.size() < before_frames.size() or after_frames.size() > before_frames.size() + 1:
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
			if ALLOWED_PATCH_TARGETS.has(target):
				continue
			if not after_nodes.has(target) or before_nodes[target_value] != after_nodes[target]:
				return false
	return true
