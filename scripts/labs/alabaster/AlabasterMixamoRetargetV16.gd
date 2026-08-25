extends RefCounted
class_name AlabasterMixamoRetargetV16

# Mixamo -> Juno V16 runtime rotation codec correction.
#
# V14 already contains the anatomical/rest calibration and presentation work.
# The remaining pipeline defect lived at the serialization boundary: the solver
# converted a Quaternion with Godot's get_euler() convention, while Juno's real
# Alabaster runtime reconstructs [yaw, pitch, roll] as:
#
#     Q = Qz(yaw) * Qy(roll) * Qx(pitch)
#
# Those two operations are not inverse conventions. A mathematically correct
# local bone Quaternion could therefore become a substantially different
# Quaternion after being written to nodeXfm.rot and read by the runtime.
#
# V16 preserves V14's solved motion byte-for-byte except for nodeXfm.rot. It
# recovers the Quaternion represented by the legacy Godot Euler tuple, then
# serializes that Quaternion with the exact inverse of the runtime formula.

const V14 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV14.gd")

const PROFILE_NAME := "MIXAMO_JUNO_V13_V14_RUNTIME_CODEC_V16"
const CODEC_NAME := "Qz(yaw)*Qy(roll)*Qx(pitch) exact inverse"
const EPS := 0.000001
const SELF_TEST_MAX_ERROR_DEG := 0.02


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	var self_test := run_self_test()
	if not bool(self_test.get("ok", false)):
		push_warning("Mixamo -> Juno V16: runtime rotation codec self-test failed: %s" % str(self_test))
		return {}

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

	# Old debug solvers are intentionally left untouched for A/B diagnosis. V16
	# is the production target-rest path only.
	var mode := str(settings.get("retarget_limb_mode", "target_rest_swing"))
	if mode == "full_global_delta" or mode == "segment_swing":
		return baseline

	var result := baseline.duplicate(true)
	var conversion := _transcode_result_rotations(result)
	if not bool(conversion.get("ok", false)):
		push_warning("Mixamo -> Juno V16: rotation transcode failed; preserving V14. %s" % str(conversion.get("reason", "")))
		return baseline

	var meta_value: Variant = result.get("import_meta", {})
	var meta: Dictionary = (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	meta["bridge"] = "mixamo_juno_v14_plus_runtime_rotation_codec_v16"
	meta["retarget_profile"] = PROFILE_NAME
	meta["rotation_codec_version"] = 16
	meta["rotation_codec"] = CODEC_NAME
	meta["rotation_codec_transcoded_keys"] = int(conversion.get("key_count", 0))
	meta["rotation_codec_max_self_test_error_degrees"] = float(self_test.get("max_runtime_error_degrees", 999.0))
	meta["rotation_codec_legacy_recovery_error_degrees"] = float(self_test.get("max_legacy_recovery_error_degrees", 999.0))
	result["import_meta"] = meta

	print("ALABASTER_MIXAMO_V16_CODEC_OK clip=%s keys=%d legacy_err=%.6f runtime_err=%.6f" % [
		clip_name,
		int(meta.get("rotation_codec_transcoded_keys", 0)),
		float(meta.get("rotation_codec_legacy_recovery_error_degrees", 0.0)),
		float(meta.get("rotation_codec_max_self_test_error_degrees", 0.0)),
	])
	return result


static func run_self_test() -> Dictionary:
	var samples: Array[Quaternion] = [
		Quaternion.IDENTITY,
		Quaternion(Vector3.RIGHT, deg_to_rad(37.0)),
		Quaternion(Vector3.UP, deg_to_rad(-52.0)),
		Quaternion(Vector3.FORWARD, deg_to_rad(83.0)),
		(Quaternion(Vector3.UP, deg_to_rad(31.0)) * Quaternion(Vector3.RIGHT, deg_to_rad(-48.0))).normalized(),
		(Quaternion(Vector3.FORWARD, deg_to_rad(-71.0)) * Quaternion(Vector3.UP, deg_to_rad(24.0)) * Quaternion(Vector3.RIGHT, deg_to_rad(63.0))).normalized(),
		Quaternion(Vector3(0.37, 0.81, -0.45).normalized(), deg_to_rad(128.0)),
	]
	var max_legacy_error := 0.0
	var max_runtime_error := 0.0
	for source_q in samples:
		# Recreate the exact legacy V9/V10 serialization path:
		# get_euler() -> [e.z, e.x, e.y].
		var legacy_euler := source_q.normalized().get_euler()
		var legacy_angles: Array = [
			rad_to_deg(legacy_euler.z),
			rad_to_deg(legacy_euler.x),
			rad_to_deg(legacy_euler.y),
		]
		var recovered := _legacy_angles_to_quaternion(legacy_angles)
		max_legacy_error = maxf(max_legacy_error, _quaternion_error_degrees(source_q, recovered))

		var runtime_angles := _quaternion_to_runtime_angles(recovered)
		var runtime_q := _runtime_angles_to_quaternion(runtime_angles)
		max_runtime_error = maxf(max_runtime_error, _quaternion_error_degrees(recovered, runtime_q))

	return {
		"ok": max_legacy_error <= SELF_TEST_MAX_ERROR_DEG and max_runtime_error <= SELF_TEST_MAX_ERROR_DEG,
		"max_legacy_recovery_error_degrees": max_legacy_error,
		"max_runtime_error_degrees": max_runtime_error,
		"sample_count": samples.size(),
	}


static func _transcode_result_rotations(result: Dictionary) -> Dictionary:
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array:
		return {"ok": false, "reason": "retarget result has no transforms array"}
	var transforms: Array = (transforms_value as Array).duplicate(true)
	var previous_angles := {}
	var key_count := 0

	for frame_index in range(transforms.size()):
		var frame_value: Variant = transforms[frame_index]
		if not frame_value is Dictionary:
			continue
		var frame := (frame_value as Dictionary).duplicate(true)
		var nodes_value: Variant = frame.get("nodeXfm", {})
		if not nodes_value is Dictionary:
			continue
		var nodes := (nodes_value as Dictionary).duplicate(true)

		for bone_value in nodes.keys():
			var bone_name := str(bone_value)
			var xfm_value: Variant = nodes[bone_value]
			if not xfm_value is Dictionary:
				continue
			var xfm := (xfm_value as Dictionary).duplicate(true)
			var rot := _rotation_array(xfm.get("rot", [0.0, 0.0, 0.0]))
			var intended_q := _legacy_angles_to_quaternion(rot)
			var encoded := _quaternion_to_runtime_angles(intended_q)
			if previous_angles.has(bone_name):
				encoded = _unwrap_angles(encoded, previous_angles[bone_name] as Array)
			previous_angles[bone_name] = encoded.duplicate()
			xfm["rot"] = encoded
			nodes[bone_value] = xfm
			key_count += 1

		frame["nodeXfm"] = nodes
		transforms[frame_index] = frame

	result["transforms"] = transforms
	return {"ok": true, "key_count": key_count}


static func _legacy_angles_to_quaternion(angles: Array) -> Quaternion:
	var yaw := float(angles[0]) if angles.size() > 0 else 0.0
	var pitch := float(angles[1]) if angles.size() > 1 else 0.0
	var roll := float(angles[2]) if angles.size() > 2 else 0.0
	# Legacy serializer stored [e.z, e.x, e.y] from Quaternion.get_euler().
	# Basis.from_euler() uses the same Godot default YXZ convention, recovering
	# the Quaternion that the anatomical solver intended before serialization.
	var euler := Vector3(deg_to_rad(pitch), deg_to_rad(roll), deg_to_rad(yaw))
	return Basis.from_euler(euler).get_rotation_quaternion().normalized()


static func _quaternion_to_runtime_angles(q_value: Quaternion) -> Array:
	var q := q_value.normalized()
	# Exact inverse for the runtime's Qz(yaw) * Qy(roll) * Qx(pitch).
	var pitch := atan2(
		2.0 * (q.w * q.x + q.y * q.z),
		1.0 - 2.0 * (q.x * q.x + q.y * q.y)
	)
	var roll_sin := clampf(2.0 * (q.w * q.y - q.z * q.x), -1.0, 1.0)
	var roll := asin(roll_sin)
	var yaw := atan2(
		2.0 * (q.w * q.z + q.x * q.y),
		1.0 - 2.0 * (q.y * q.y + q.z * q.z)
	)
	return [rad_to_deg(yaw), rad_to_deg(pitch), rad_to_deg(roll)]


static func _runtime_angles_to_quaternion(angles: Array) -> Quaternion:
	var yaw := float(angles[0]) if angles.size() > 0 else 0.0
	var pitch := float(angles[1]) if angles.size() > 1 else 0.0
	var roll := float(angles[2]) if angles.size() > 2 else 0.0
	# Kept deliberately identical to AlabasterRigRuntimeSource._source_quat().
	var x := deg_to_rad(pitch) * 0.5
	var y := deg_to_rad(roll) * 0.5
	var z := deg_to_rad(yaw) * 0.5
	var sx := sin(x)
	var cx := cos(x)
	var sy := sin(y)
	var cy := cos(y)
	var sz := sin(z)
	var cz := cos(z)
	return Quaternion(
		sx * cy * cz - cx * sy * sz,
		cx * sy * cz + sx * cy * sz,
		cx * cy * sz - sx * sy * cz,
		cx * cy * cz + sx * sy * sz
	).normalized()


static func _rotation_array(value: Variant) -> Array:
	var result: Array = [0.0, 0.0, 0.0]
	if value is Array:
		var source := value as Array
		for index in range(mini(source.size(), 3)):
			result[index] = float(source[index])
	return result


static func _unwrap_angles(current: Array, previous: Array) -> Array:
	var result := current.duplicate()
	for index in range(mini(result.size(), previous.size())):
		var value := float(result[index])
		var reference := float(previous[index])
		while value - reference > 180.0:
			value -= 360.0
		while value - reference < -180.0:
			value += 360.0
		result[index] = value
	return result


static func _quaternion_error_degrees(a_value: Quaternion, b_value: Quaternion) -> float:
	var a := a_value.normalized()
	var b := b_value.normalized()
	var dot_value := clampf(absf(a.dot(b)), 0.0, 1.0)
	return rad_to_deg(2.0 * acos(dot_value))
