extends RefCounted
class_name AlabasterMixamoRetargetV12

# Mixamo -> Juno V12 presentation calibration.
#
# V10/V11 already solved the dangerous structural problems: forward handedness,
# foot direction and upper-arm instability. V12 therefore does NOT re-solve the
# skeleton. It applies three tiny target-specific 2D presentation corrections on
# top of the proven V11 result:
#   1. a very small backward torso bias, because Juno's billboard torso reads a
#      little more forward-leaning than the same Mixamo pose in 3D;
#   2. toe/foot pitch and roll are eased toward Juno REST so the shoe reads more
#      parallel to the floor in profile instead of looking permanently tip-toed;
#   3. only absurd toe angular spikes are velocity-limited, preventing the little
#      end-of-stride heel kick without sanding away normal gait motion.
#
# These are CHARACTERIZATION constants for Mixamo -> Juno, not Walking-specific
# keys. Any Mixamo clip routed through this profile gets the same REST-relative
# projection policy. All bones except top/toeL/toeR must remain byte-equivalent
# to the V11 baseline or the whole V12 patch is rejected.

const V11 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV11.gd")

const PROFILE_NAME := "MIXAMO_JUNO_V11_2D_PRESENTATION_V12"
const DEFAULT_TORSO_BACK_BIAS_DEG := 1.5
const DEFAULT_TOE_PITCH_KEEP := 0.75
const DEFAULT_TOE_ROLL_KEEP := 0.88
const DEFAULT_TOE_MAX_DEG_PER_SECOND := 540.0
const DEFAULT_LOOP_SEAM_MULTIPLIER := 1.35
const LOOP_SEAM_BLEND_FRAMES := 4

const ALLOWED_PATCH_TARGETS := {
	"top": true,
	"toeL": true,
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
	var baseline := V11.convert_scene(
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

	var result: Dictionary = baseline.duplicate(true)
	var patch_info := _apply_juno_2d_presentation(result, sample_fps, loop, settings)
	if not bool(patch_info.get("ok", false)):
		push_warning("Mixamo -> Juno V12: presentation patch failed; preserving V11. %s" % str(patch_info.get("reason", "")))
		return baseline

	if not _preserved_targets_match(baseline, result):
		push_warning("Mixamo -> Juno V12: a non-presentation bone changed; preserving V11 byte-for-byte.")
		return baseline

	var meta_value: Variant = result.get("import_meta", {})
	var meta: Dictionary = (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	meta["bridge"] = "mixamo_juno_v11_plus_2d_presentation_v12"
	meta["retarget_profile"] = PROFILE_NAME
	meta["presentation_calibration_version"] = 12
	meta["torso_back_bias_degrees"] = float(patch_info.get("torso_back_bias_degrees", 0.0))
	meta["toe_pitch_keep"] = float(patch_info.get("toe_pitch_keep", 1.0))
	meta["toe_roll_keep"] = float(patch_info.get("toe_roll_keep", 1.0))
	meta["toe_max_degrees_per_second"] = float(patch_info.get("toe_max_degrees_per_second", 0.0))
	meta["toe_velocity_clamp_count"] = int(patch_info.get("toe_velocity_clamp_count", 0))
	meta["toe_loop_seam_patch_count"] = int(patch_info.get("toe_loop_seam_patch_count", 0))
	meta["presentation_patch_targets"] = ["top", "toeL", "toeR"]
	meta["v11_non_presentation_bones_preserved"] = true
	result["import_meta"] = meta

	print("ALABASTER_MIXAMO_V12_2D_OK clip=%s frames=%d torso_bias=%.2f toe_keep=%.2f clamps=%d seam=%d v11_rest_preserved=true" % [
		clip_name,
		(result.get("transforms", []) as Array).size() if result.get("transforms", []) is Array else 0,
		float(patch_info.get("torso_back_bias_degrees", 0.0)),
		float(patch_info.get("toe_pitch_keep", 1.0)),
		int(patch_info.get("toe_velocity_clamp_count", 0)),
		int(patch_info.get("toe_loop_seam_patch_count", 0)),
	])
	return result


static func _apply_juno_2d_presentation(
	result: Dictionary,
	sample_fps: float,
	loop: bool,
	settings: Dictionary
) -> Dictionary:
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array or (transforms_value as Array).is_empty():
		return {"ok": false, "reason": "retarget result contains no transforms"}

	var transforms := transforms_value as Array
	var torso_bias := float(settings.get("juno_2d_torso_back_bias_degrees", DEFAULT_TORSO_BACK_BIAS_DEG))
	var toe_pitch_keep := clampf(float(settings.get("juno_2d_toe_pitch_keep", DEFAULT_TOE_PITCH_KEEP)), 0.0, 1.0)
	var toe_roll_keep := clampf(float(settings.get("juno_2d_toe_roll_keep", DEFAULT_TOE_ROLL_KEEP)), 0.0, 1.0)
	var max_speed := maxf(float(settings.get("juno_2d_toe_max_deg_per_second", DEFAULT_TOE_MAX_DEG_PER_SECOND)), 90.0)
	var fps := maxf(sample_fps, 1.0)
	var max_step := max_speed / fps
	var previous_toe := {}
	var clamp_count := 0

	for frame_index in range(transforms.size()):
		var frame_value: Variant = transforms[frame_index]
		if not frame_value is Dictionary:
			continue
		var frame_dict := (frame_value as Dictionary).duplicate(true)
		var node_value: Variant = frame_dict.get("nodeXfm", {})
		if not node_value is Dictionary:
			continue
		var node_xfm := (node_value as Dictionary).duplicate(true)

		# Positive Alabaster pitch tilts Juno's +Z-up torso very slightly toward
		# -Y, i.e. backward relative to the calibrated +Y forward direction.
		if node_xfm.has("top"):
			var top_value: Variant = node_xfm.get("top", {})
			if top_value is Dictionary:
				var top_xfm := (top_value as Dictionary).duplicate(true)
				var top_rot := _rotation_array(top_xfm)
				top_rot[1] = float(top_rot[1]) + torso_bias
				top_xfm["rot"] = top_rot
				node_xfm["top"] = top_xfm

		for toe_name in ["toeL", "toeR"]:
			if not node_xfm.has(toe_name):
				continue
			var toe_value: Variant = node_xfm.get(toe_name, {})
			if not toe_value is Dictionary:
				continue
			var toe_xfm := (toe_value as Dictionary).duplicate(true)
			var rot := _rotation_array(toe_xfm)
			# Yaw stays untouched so the fixed forward/handedness solution cannot
			# regress. Only the two floor-reading axes are relaxed toward REST.
			var pitch := _canonical_degrees(float(rot[1])) * toe_pitch_keep
			var roll := _canonical_degrees(float(rot[2])) * toe_roll_keep
			if previous_toe.has(toe_name):
				var previous: Vector2 = previous_toe[toe_name]
				var limited_pitch := _limit_angle_step(previous.x, pitch, max_step)
				var limited_roll := _limit_angle_step(previous.y, roll, max_step)
				if not is_equal_approx(limited_pitch, _unwrap_near(pitch, previous.x)):
					clamp_count += 1
				if not is_equal_approx(limited_roll, _unwrap_near(roll, previous.y)):
					clamp_count += 1
				pitch = limited_pitch
				roll = limited_roll
			previous_toe[toe_name] = Vector2(pitch, roll)
			rot[1] = pitch
			rot[2] = roll
			toe_xfm["rot"] = rot
			node_xfm[toe_name] = toe_xfm

		frame_dict["nodeXfm"] = node_xfm
		transforms[frame_index] = frame_dict

	var seam_count := 0
	if loop and transforms.size() >= 3:
		seam_count = _stabilize_toe_loop_seam(
			transforms,
			max_step * float(settings.get("juno_2d_loop_seam_multiplier", DEFAULT_LOOP_SEAM_MULTIPLIER))
		)

	result["transforms"] = transforms
	return {
		"ok": true,
		"torso_back_bias_degrees": torso_bias,
		"toe_pitch_keep": toe_pitch_keep,
		"toe_roll_keep": toe_roll_keep,
		"toe_max_degrees_per_second": max_speed,
		"toe_velocity_clamp_count": clamp_count,
		"toe_loop_seam_patch_count": seam_count,
	}


static func _stabilize_toe_loop_seam(transforms: Array, seam_limit: float) -> int:
	var patch_count := 0
	var blend_frames := mini(LOOP_SEAM_BLEND_FRAMES, transforms.size())
	for toe_name in ["toeL", "toeR"]:
		for axis in [1, 2]:
			var first_value := _read_rotation_axis(transforms, 0, toe_name, axis)
			var last_value := _read_rotation_axis(transforms, transforms.size() - 1, toe_name, axis)
			if first_value == null or last_value == null:
				continue
			var first_near_last := _unwrap_near(float(first_value), float(last_value))
			var seam_delta := first_near_last - float(last_value)
			if absf(seam_delta) <= seam_limit:
				continue
			var allowed_delta := clampf(seam_delta, -seam_limit, seam_limit)
			var desired_last := first_near_last - allowed_delta
			var correction := desired_last - float(last_value)
			for blend_index in range(blend_frames):
				var frame_index := transforms.size() - blend_frames + blend_index
				var weight := float(blend_index + 1) / float(blend_frames)
				if _offset_rotation_axis(transforms, frame_index, toe_name, axis, correction * weight):
					patch_count += 1
	return patch_count


static func _rotation_array(xfm: Dictionary) -> Array:
	var rot_value: Variant = xfm.get("rot", [0.0, 0.0, 0.0])
	var result := [0.0, 0.0, 0.0]
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
	if axis < 0 or axis >= rot.size():
		return null
	return float(rot[axis])


static func _offset_rotation_axis(transforms: Array, frame_index: int, bone_name: String, axis: int, amount: float) -> bool:
	if frame_index < 0 or frame_index >= transforms.size():
		return false
	var frame_value: Variant = transforms[frame_index]
	if not frame_value is Dictionary:
		return false
	var frame_dict := (frame_value as Dictionary).duplicate(true)
	var node_value: Variant = frame_dict.get("nodeXfm", {})
	if not node_value is Dictionary:
		return false
	var node_xfm := (node_value as Dictionary).duplicate(true)
	var xfm_value: Variant = node_xfm.get(bone_name, {})
	if not xfm_value is Dictionary:
		return false
	var xfm := (xfm_value as Dictionary).duplicate(true)
	var rot := _rotation_array(xfm)
	if axis < 0 or axis >= rot.size():
		return false
	rot[axis] = float(rot[axis]) + amount
	xfm["rot"] = rot
	node_xfm[bone_name] = xfm
	frame_dict["nodeXfm"] = node_xfm
	transforms[frame_index] = frame_dict
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


static func _limit_angle_step(previous: float, candidate: float, max_step: float) -> float:
	var resolved := _unwrap_near(candidate, previous)
	var delta := resolved - previous
	if absf(delta) <= max_step:
		return resolved
	return previous + clampf(delta, -max_step, max_step)


static func _preserved_targets_match(before: Dictionary, after: Dictionary) -> bool:
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
		var names := {}
		for name_value in before_nodes.keys():
			names[str(name_value)] = true
		for name_value in after_nodes.keys():
			names[str(name_value)] = true
		for name_value in names.keys():
			var bone_name := str(name_value)
			if ALLOWED_PATCH_TARGETS.has(bone_name):
				continue
			if before_nodes.get(bone_name, null) != after_nodes.get(bone_name, null):
				return false
	return true
