extends RefCounted
class_name AlabasterMixamoRestSpaceConverter

# Mixamo -> Alabaster retarget using the imported Skeleton3D itself as the
# authority for rest axes. This deliberately does NOT copy FBX local Euler
# rotations into Alabaster bones. Godot 4 animation bone transforms include the
# imported rest orientation, so raw track rotations are not portable between
# skeletons with different Bone Rest axes.
#
# Strategy per sample:
#   1. Seek the real imported Mixamo AnimationPlayer.
#   2. Read each semantic source bone's GLOBAL animated pose and GLOBAL rest.
#   3. Compute a global motion delta: pose * inverse(rest).
#   4. Convert Godot Y-up coordinates to Alabaster Z-up coordinates.
#   5. Re-parent those global motion deltas onto the much smaller Alabaster
#      hierarchy. Collapsed Mixamo chains therefore become ONE local Alabaster
#      motion instead of multiple tracks overwriting/doubling the same bone.
#
# The Alabaster source runtime applies animation rotations as motion deltas in a
# shared figure coordinate system. Node `dir` is a visual/rest-facing hint and
# is not multiplied into child animation motion, so the canonical retarget here
# intentionally works with motion deltas, not target Bone Rest quaternions.

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_REST_SPACE_V2"

# Source anchor whose global rest-space motion drives each Alabaster bone.
# Reusing Hips for root + bottom is intentional: after re-parenting, bottom gets
# identity relative motion and follows root, which matches the Alabaster tree.
const TARGET_SOURCE_ANCHOR := {
	"root": "hips",
	"bottom": "hips",
	"top": "spine2",
	"head": "head",
	"shoulderL": "leftarm",
	"armL": "leftforearm",
	"handL": "lefthand",
	"fingerL": "lefthand",
	"shoulderR": "rightarm",
	"armR": "rightforearm",
	"handR": "righthand",
	"fingerR": "righthand",
	"hipL": "leftupleg",
	"legL": "leftleg",
	"footL": "leftfoot",
	"toeL": "lefttoebase",
	"hipR": "rightupleg",
	"legR": "rightleg",
	"footR": "rightfoot",
	"toeR": "righttoebase",
}

const TARGET_PARENT := {
	"root": "",
	"bottom": "root",
	"top": "root",
	"head": "top",
	"shoulderL": "top",
	"armL": "shoulderL",
	"handL": "armL",
	"fingerL": "handL",
	"shoulderR": "top",
	"armR": "shoulderR",
	"handR": "armR",
	"fingerR": "handR",
	"hipL": "bottom",
	"legL": "hipL",
	"footL": "legL",
	"toeL": "footL",
	"hipR": "bottom",
	"legR": "hipR",
	"footR": "legR",
	"toeR": "footR",
}

const TARGET_ORDER := [
	"root", "bottom", "top", "head",
	"shoulderL", "armL", "handL", "fingerL",
	"shoulderR", "armR", "handR", "fingerR",
	"hipL", "legL", "footL", "toeL",
	"hipR", "legR", "footR", "toeR",
]

# Coordinate-system rotation from Godot imported 3D (X right, Y up, -Z forward)
# to the Alabaster figure space (X right, Y depth, Z up).
# Source X -> Alabaster X
# Source Y -> Alabaster Z
# Source Z -> Alabaster -Y
static var _source_to_alabaster := Basis(
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, -1.0, 0.0)
)


static func convert_scene(player: AnimationPlayer, skeleton: Skeleton3D, clip_name: String, sample_fps: float, loop: bool, translation_scale: float, settings: Dictionary) -> Dictionary:
	if player == null or skeleton == null or clip_name.is_empty():
		return {}
	if not player.has_animation(clip_name):
		push_warning("Mixamo Rest-Space: animation '%s' is not available on the AnimationPlayer." % clip_name)
		return {}
	var animation := player.get_animation(clip_name)
	if animation == null:
		return {}

	var bone_indices := _build_bone_index(skeleton)
	var missing := _required_missing(bone_indices)
	if not missing.is_empty():
		push_warning("Mixamo Rest-Space: source skeleton is missing semantic bones %s" % str(missing))
		return {}

	var fps := maxf(sample_fps, 1.0)
	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var max_angle_deg := 0.0
	var max_root_translation := 0.0

	# Rest is read once from the imported Skeleton3D. This is the key difference
	# from the previous converter, which treated animation-local quaternions as if
	# Mixamo and Alabaster shared identical bone axes.
	var rest_global := {}
	for semantic_value in bone_indices.keys():
		var semantic := str(semantic_value)
		var bone_index := int(bone_indices[semantic_value])
		rest_global[semantic] = skeleton.get_bone_global_rest(bone_index)

	var prior_animation := String(player.current_animation)
	var prior_position := float(player.current_animation_position)
	player.play(clip_name)
	player.seek(0.0, true, true)
	player.advance(0.0)

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		player.seek(time, true, true)
		player.advance(0.0)

		var source_global_motion := {}
		for semantic_value in bone_indices.keys():
			var semantic := str(semantic_value)
			var bone_index := int(bone_indices[semantic_value])
			var pose_global := skeleton.get_bone_global_pose(bone_index)
			var rest_xfm: Transform3D = rest_global[semantic]
			var motion_basis := (pose_global.basis * rest_xfm.basis.inverse()).orthonormalized()
			source_global_motion[semantic] = _convert_basis(motion_basis)

		var target_global_motion := {}
		var node_xfm := {}
		for target_value in TARGET_ORDER:
			var target := str(target_value)
			var anchor := str(TARGET_SOURCE_ANCHOR.get(target, ""))
			if anchor.is_empty() or not source_global_motion.has(anchor):
				continue
			var target_global: Basis = source_global_motion[anchor]
			target_global_motion[target] = target_global

			var parent := str(TARGET_PARENT.get(target, ""))
			var local_basis := target_global
			if not parent.is_empty() and target_global_motion.has(parent):
				var parent_global: Basis = target_global_motion[parent]
				local_basis = (parent_global.inverse() * target_global).orthonormalized()

			var q := local_basis.get_rotation_quaternion().normalized()
			var angle_deg := rad_to_deg(q.get_angle())
			max_angle_deg = maxf(max_angle_deg, absf(angle_deg))
			var angles := _quaternion_to_alabaster_angles(q, settings)
			var xfm := {"rot": angles, "trans": [0.0, 0.0, 0.0], "scale": 1.0}

			if target == "root" and not is_zero_approx(translation_scale):
				var hips_index := int(bone_indices["hips"])
				var hips_pose := skeleton.get_bone_global_pose(hips_index)
				var hips_rest: Transform3D = rest_global["hips"]
				var source_delta := hips_pose.origin - hips_rest.origin
				var converted_delta := _convert_vector(source_delta) * translation_scale
				max_root_translation = maxf(max_root_translation, converted_delta.length())
				xfm["trans"] = [converted_delta.x, converted_delta.y, converted_delta.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	# Restore the source preview as politely as possible.
	if not prior_animation.is_empty() and player.has_animation(prior_animation):
		player.play(prior_animation)
		player.seek(prior_position, true, true)
		player.advance(0.0)
	else:
		player.stop()

	print("ALABASTER_MIXAMO_RESTSPACE_OK clip=%s frames=%d bones=%d max_angle=%.2f root_translation=%.4f axis=X,-Z,Y" % [
		clip_name, sample_count, bone_indices.size(), max_angle_deg, max_root_translation,
	])

	return {
		"category": str(settings.get("category", "DEFAULT")),
		"frameCnt": frame_count,
		"frameRepeat": TICK_RATE / fps,
		"animStart": 0,
		"loopStart": 0,
		"repeat": loop,
		"transforms": transforms,
		"nodes": {},
		"import_meta": {
			"bridge": "mixamo_skeleton3d_global_rest_space_to_alabaster",
			"retarget_profile": PROFILE_NAME,
			"sample_fps": fps,
			"source_rest": "Skeleton3D.get_bone_global_rest",
			"source_pose": "Skeleton3D.get_bone_global_pose",
			"axis_conversion": "godot(X,Y,Z)->alabaster(X,-Z,Y)",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _build_bone_index(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		if not semantic.is_empty():
			result[semantic] = bone_index
	return result


static func _required_missing(indices: Dictionary) -> Array[String]:
	var required := [
		"hips", "spine2", "head",
		"leftarm", "leftforearm", "lefthand",
		"rightarm", "rightforearm", "righthand",
		"leftupleg", "leftleg", "leftfoot", "lefttoebase",
		"rightupleg", "rightleg", "rightfoot", "righttoebase",
	]
	var missing: Array[String] = []
	for name in required:
		if not indices.has(name):
			missing.append(name)
	return missing


static func normalize(value: String) -> String:
	return value.to_lower().replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "").replace(" ", "").replace("-", "").replace("_", "")


static func _convert_basis(source_basis: Basis) -> Basis:
	var c := _source_to_alabaster
	return (c * source_basis * c.inverse()).orthonormalized()


static func _convert_vector(source_vector: Vector3) -> Vector3:
	return _source_to_alabaster * source_vector


static func _quaternion_to_alabaster_angles(q: Quaternion, settings: Dictionary) -> Array:
	# Alabaster Quaternion.setAngles(yaw,pitch,roll) rebuilds a quaternion from
	# Euler(pitch, roll, yaw), so serialize Godot quaternion Euler X/Y/Z as
	# [Z, X, Y]. This is an encoding step only; axes were already converted above.
	var e := q.normalized().get_euler()
	var yaw := rad_to_deg(e.z)
	var pitch := rad_to_deg(e.x)
	var roll := rad_to_deg(e.y)
	yaw = yaw * float(settings.get("yaw_scale", 1.0)) + float(settings.get("yaw_correction_degrees", 0.0))
	pitch = pitch * float(settings.get("pitch_scale", 1.0)) + float(settings.get("pitch_correction_degrees", 0.0))
	roll = roll * float(settings.get("roll_scale", 1.0)) + float(settings.get("roll_correction_degrees", 0.0))
	if bool(settings.get("top_down_mode", true)):
		pitch = clampf(pitch, -170.0, 170.0)
		roll = clampf(roll, -170.0, 170.0)
	return [yaw, pitch, roll]
