extends RefCounted
class_name AlabasterMixamoRestSpaceConverter

# Mixamo -> Alabaster retarget using the imported Skeleton3D as the authority for
# Bone Rest axes. This deliberately does NOT copy FBX local Euler rotations into
# Alabaster bones.
#
# Godot 4 bone animation Transform tracks are imported in the Skeleton3D bone
# pose space, whose neutral/default value is the Bone Rest. Therefore we can
# reconstruct every source bone's animated GLOBAL rotation deterministically
# from Animation tracks + Skeleton3D rests, without relying on an AnimationPlayer
# processing tick.
#
# Per sample:
#   source global pose / source global rest -> global motion delta
#   Godot Y-up -> Alabaster Z-up coordinate conversion
#   global motion is re-parented onto Alabaster's reduced hierarchy
#
# This solves three separate mismatches at once:
#   * Mixamo FBX bone/pre-rotation axes != Alabaster axes
#   * Mixamo has many more intermediate bones
#   * Mixamo Hips is parent of BOTH spine and legs while Alabaster top/bottom are
#     siblings below root.

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_REST_SPACE_V2"

# Global source-motion anchor for each target semantic bone.
# `bottom` intentionally uses the same Hips motion as `root`; after re-parenting
# bottom relative to root its animation delta becomes identity, so the pelvis
# graphic follows root instead of receiving Hips rotation twice.
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

# Proper right-handed coordinate rotation:
# Godot X right  -> Alabaster X right
# Godot Y up     -> Alabaster Z up
# Godot Z back   -> Alabaster -Y (Alabaster depth/forward axis)
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

	var rotation_tracks := {}
	var position_tracks := {}
	_build_track_maps(animation, rotation_tracks, position_tracks)
	if rotation_tracks.is_empty():
		push_warning("Mixamo Rest-Space: animation has no Skeleton3D rotation tracks.")
		return {}

	var rest_global_basis := {}
	for semantic_value in bone_indices.keys():
		var semantic := str(semantic_value)
		var bone_index := int(bone_indices[semantic_value])
		rest_global_basis[semantic] = skeleton.get_bone_global_rest(bone_index).basis.orthonormalized()

	var fps := maxf(sample_fps, 1.0)
	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	# Alabaster looping frameCnt is an exclusive boundary. Do not author a hidden
	# terminal loop frame; it would contaminate interpolation before the wrap.
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var max_angle_deg := 0.0
	var max_root_translation := 0.0

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var source_pose_global := _sample_source_global_rotations(animation, skeleton, rotation_tracks, time)
		if source_pose_global.is_empty():
			return {}

		var source_global_motion := {}
		for semantic_value in bone_indices.keys():
			var semantic := str(semantic_value)
			var bone_index := int(bone_indices[semantic_value])
			if not source_pose_global.has(bone_index) or not rest_global_basis.has(semantic):
				continue
			var pose_basis: Basis = source_pose_global[bone_index]
			var rest_basis: Basis = rest_global_basis[semantic]
			# Pre-multiplied global rest-space delta: the rotation which moves the
			# imported rest frame into the current animated frame.
			var motion_basis := (pose_basis * rest_basis.inverse()).orthonormalized()
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
			max_angle_deg = maxf(max_angle_deg, absf(rad_to_deg(q.get_angle())))
			var angles := _quaternion_to_alabaster_angles(q, settings)
			var xfm := {"rot": angles, "trans": [0.0, 0.0, 0.0], "scale": 1.0}

			if target == "root" and not is_zero_approx(translation_scale):
				var root_delta := _sample_root_translation(animation, skeleton, position_tracks, bone_indices, time)
				var converted_delta := _convert_vector(root_delta) * translation_scale
				max_root_translation = maxf(max_root_translation, converted_delta.length())
				xfm["trans"] = [converted_delta.x, converted_delta.y, converted_delta.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	print("ALABASTER_MIXAMO_RESTSPACE_OK clip=%s frames=%d source_bones=%d rot_tracks=%d max_angle=%.2f root_translation=%.4f axis=X,-Z,Y" % [
		clip_name,
		sample_count,
		bone_indices.size(),
		rotation_tracks.size(),
		max_angle_deg,
		max_root_translation,
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
			"source_rest": "Skeleton3D Bone Rest",
			"source_pose": "Animation bone tracks reconstructed through Skeleton3D hierarchy",
			"axis_conversion": "godot(X,Y,Z)->alabaster(X,-Z,Y)",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _build_track_maps(animation: Animation, rotation_tracks: Dictionary, position_tracks: Dictionary) -> void:
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_POSITION_3D:
			continue
		var semantic := normalize(_bone_name_from_track_path(animation.track_get_path(track_index)))
		if semantic.is_empty():
			continue
		if track_type == Animation.TYPE_ROTATION_3D:
			rotation_tracks[semantic] = track_index
		else:
			position_tracks[semantic] = track_index


static func _sample_source_global_rotations(animation: Animation, skeleton: Skeleton3D, rotation_tracks: Dictionary, time: float) -> Dictionary:
	var result := {}
	# Skeleton3D guarantees a parent index lower than its child index, so this
	# single pass builds the complete global hierarchy deterministically.
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		var rest_local := skeleton.get_bone_rest(bone_index).basis.orthonormalized()
		var local_basis := rest_local
		if rotation_tracks.has(semantic):
			var track_index := int(rotation_tracks[semantic])
			var q := animation.rotation_track_interpolate(track_index, time).normalized()
			local_basis = Basis(q).orthonormalized()
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index >= 0 and result.has(parent_index):
			var parent_global: Basis = result[parent_index]
			result[bone_index] = (parent_global * local_basis).orthonormalized()
		else:
			result[bone_index] = local_basis
	return result


static func _sample_root_translation(animation: Animation, skeleton: Skeleton3D, position_tracks: Dictionary, bone_indices: Dictionary, time: float) -> Vector3:
	if not bone_indices.has("hips"):
		return Vector3.ZERO
	var hips_index := int(bone_indices["hips"])
	var rest_position := skeleton.get_bone_rest(hips_index).origin
	if not position_tracks.has("hips"):
		return Vector3.ZERO
	var track_index := int(position_tracks["hips"])
	var pose_position := animation.position_track_interpolate(track_index, time)
	return pose_position - rest_position


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


static func _bone_name_from_track_path(path: NodePath) -> String:
	var text := str(path)
	var separator := text.rfind(":")
	return text.substr(separator + 1) if separator >= 0 else text.get_file()


static func _convert_basis(source_basis: Basis) -> Basis:
	var c := _source_to_alabaster
	return (c * source_basis * c.inverse()).orthonormalized()


static func _convert_vector(source_vector: Vector3) -> Vector3:
	return _source_to_alabaster * source_vector


static func _quaternion_to_alabaster_angles(q: Quaternion, settings: Dictionary) -> Array:
	# Alabaster Quaternion.setAngles(yaw,pitch,roll) rebuilds from
	# Euler(pitch, roll, yaw), so encode Godot Quaternion Euler X/Y/Z as [Z,X,Y].
	# Coordinate axes were already converted before this serialization step.
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
