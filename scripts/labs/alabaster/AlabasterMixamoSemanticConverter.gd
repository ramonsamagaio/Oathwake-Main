extends RefCounted
class_name AlabasterMixamoSemanticConverter

# Mixamo -> Alabaster V5.
#
# V4 revealed two separate facts:
#   * the corrected Default bone semantics were right;
#   * driving a transient, detached FBX AnimationPlayer and then reading the
#     Skeleton3D did NOT reliably advance the source skeleton. The result was a
#     perfectly static Mixamo T-pose being sampled over and over.
#
# V5 keeps the corrected semantic chain, but evaluates the imported Animation
# tracks directly into Skeleton3D bone POSE properties. Skeleton3D therefore
# still owns Bone Rest / hierarchy / global-pose math, while we no longer depend
# on AnimationPlayer scene-tree processing for an offline tool.
#
# The other important correction is retarget-pose handling: we transfer the
# REST->POSE motion delta of each anatomical segment, never the absolute Mixamo
# T-pose direction. Therefore a horizontal Mixamo rest arm does not force the
# Default character into a T-pose. The delta is applied over Default's own rest
# pose (arms down, compact legs).

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_REST_DELTA_CHAIN_V5"
const EPS := 0.000001

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

# Default/Dummy attachment nodes shoulder*/hip* are pivots. The visible motion
# starts one node lower than the equivalent Mixamo anatomical chain.
const SOURCE_SEGMENT := {
	"armL": ["leftarm", "leftforearm"],
	"handL": ["leftforearm", "lefthand"],
	"fingerL": ["lefthand", "lefthandindex1"],
	"armR": ["rightarm", "rightforearm"],
	"handR": ["rightforearm", "righthand"],
	"fingerR": ["righthand", "righthandindex1"],
	"legL": ["leftupleg", "leftleg"],
	"footL": ["leftleg", "leftfoot"],
	"toeL": ["leftfoot", "lefttoebase"],
	"legR": ["rightupleg", "rightleg"],
	"footR": ["rightleg", "rightfoot"],
	"toeR": ["rightfoot", "righttoebase"],
}

# Default anatomical basis. Basis columns are target anatomical X/Y/Z:
# right = -X, up = +Z, forward = +Y. This is right-handed.
const TARGET_ANATOMICAL_RIGHT := Vector3(-1.0, 0.0, 0.0)
const TARGET_ANATOMICAL_UP := Vector3(0.0, 0.0, 1.0)
const TARGET_ANATOMICAL_FORWARD := Vector3(0.0, 1.0, 0.0)


static func convert_scene(player: AnimationPlayer, skeleton: Skeleton3D, clip_name: String, sample_fps: float, loop: bool, translation_scale: float, settings: Dictionary) -> Dictionary:
	if player == null or skeleton == null or clip_name.is_empty() or not player.has_animation(clip_name):
		return {}
	var animation := player.get_animation(clip_name)
	if animation == null:
		return {}

	var indices := _build_bone_index(skeleton)
	var missing := _required_missing(indices)
	if not missing.is_empty():
		push_warning("Mixamo Rest-Delta V5: source skeleton is missing %s" % str(missing))
		return {}

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	_build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)
	if rotation_tracks.is_empty():
		push_warning("Mixamo Rest-Delta V5: no Skeleton3D rotation tracks were found.")
		return {}

	var rest_global := {}
	for semantic_value in indices.keys():
		var semantic := str(semantic_value)
		var bone_index := int(indices[semantic_value])
		rest_global[semantic] = skeleton.get_bone_global_rest(bone_index)

	var rest_pelvis_value: Variant = _body_frame(rest_global, "hips", "leftupleg", "rightupleg", "spine")
	var rest_torso_value: Variant = _body_frame(rest_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	if rest_pelvis_value == null or rest_torso_value == null:
		push_warning("Mixamo Rest-Delta V5: could not construct source rest anatomical frames.")
		return {}
	var rest_pelvis: Basis = rest_pelvis_value
	var rest_torso: Basis = rest_torso_value

	var target_anatomical := Basis(TARGET_ANATOMICAL_RIGHT, TARGET_ANATOMICAL_UP, TARGET_ANATOMICAL_FORWARD).orthonormalized()
	var source_to_target := (target_anatomical * rest_pelvis.inverse()).orthonormalized()

	var fps := maxf(sample_fps, 1.0)
	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var max_angles := {}
	var motion_span := {}
	var first_local_q := {}
	var previous_angles := {}
	var max_root_translation := 0.0

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var pose_global := _evaluate_source_pose_from_tracks(
			animation,
			skeleton,
			indices,
			rotation_tracks,
			position_tracks,
			scale_tracks,
			time
		)
		if pose_global.is_empty():
			return {}

		var target_global := _build_target_global_delta(rest_global, pose_global, rest_pelvis, rest_torso, source_to_target)
		if target_global.is_empty():
			return {}

		var node_xfm := {}
		for target_value in TARGET_ORDER:
			var target := str(target_value)
			if not target_global.has(target):
				continue
			var global_basis: Basis = target_global[target]
			var local_basis := global_basis
			var parent := str(TARGET_PARENT.get(target, ""))
			if not parent.is_empty() and target_global.has(parent):
				var parent_basis: Basis = target_global[parent]
				local_basis = (parent_basis.inverse() * global_basis).orthonormalized()

			var q := _canonical_quaternion(local_basis.get_rotation_quaternion())
			var angle_deg := absf(rad_to_deg(q.get_angle()))
			max_angles[target] = maxf(float(max_angles.get(target, 0.0)), angle_deg)
			if not first_local_q.has(target):
				first_local_q[target] = q
				motion_span[target] = 0.0
			else:
				var first_q: Quaternion = first_local_q[target]
				var dot_value := clampf(absf(first_q.dot(q)), 0.0, 1.0)
				var span_deg := rad_to_deg(2.0 * acos(dot_value))
				motion_span[target] = maxf(float(motion_span.get(target, 0.0)), span_deg)

			var angles := _quaternion_to_alabaster_angles(q, settings)
			if previous_angles.has(target):
				angles = _unwrap_angles(angles, previous_angles[target])
			previous_angles[target] = angles.duplicate()

			var xfm := {
				"rot": angles,
				"trans": [0.0, 0.0, 0.0],
				"scale": 1.0,
			}

			if target == "root" and not is_zero_approx(translation_scale):
				var source_delta := _hips_translation_delta(rest_global, pose_global)
				var converted := source_to_target * source_delta * translation_scale
				max_root_translation = maxf(max_root_translation, converted.length())
				xfm["trans"] = [converted.x, converted.y, converted.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	# Leave the transient skeleton clean for subsequent previews.
	skeleton.reset_bone_poses()

	print("ALABASTER_MIXAMO_REST_DELTA_OK clip=%s frames=%d bones=%d rot_tracks=%d root_trans=%.4f max=%s span=%s" % [
		clip_name, sample_count, indices.size(), rotation_tracks.size(), max_root_translation, str(max_angles), str(motion_span),
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
			"bridge": "mixamo_skeleton_pose_tracks_rest_delta_to_default",
			"retarget_profile": PROFILE_NAME,
			"sample_fps": fps,
			"source_rest": "Skeleton3D Bone Rest",
			"source_pose": "Animation tracks written into Skeleton3D bone pose, then global pose read back",
			"limb_transfer": "source rest-to-pose anatomical segment swing",
			"target_chain": "Default shoulder/hip pivots + arm/hand and leg/foot segment deltas",
			"axis_conversion": "derived from source rest pelvis anatomical frame",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _evaluate_source_pose_from_tracks(animation: Animation, skeleton: Skeleton3D, indices: Dictionary, rotation_tracks: Dictionary, position_tracks: Dictionary, scale_tracks: Dictionary, time: float) -> Dictionary:
	# The raw FBX scene is detached from the main SceneTree inside Bone Studio.
	# AnimationPlayer.seek() can therefore leave the Skeleton in its imported rest
	# pose. Apply exactly the same interpolated transform-track values directly to
	# Skeleton3D's pose API; Skeleton3D then resolves Bone Rest and hierarchy.
	skeleton.reset_bone_poses()

	for semantic_value in rotation_tracks.keys():
		var semantic := str(semantic_value)
		if not indices.has(semantic):
			continue
		var q := animation.rotation_track_interpolate(int(rotation_tracks[semantic_value]), time)
		if q is Quaternion:
			skeleton.set_bone_pose_rotation(int(indices[semantic]), (q as Quaternion).normalized())

	for semantic_value in position_tracks.keys():
		var semantic := str(semantic_value)
		if not indices.has(semantic):
			continue
		var p := animation.position_track_interpolate(int(position_tracks[semantic_value]), time)
		if p is Vector3:
			skeleton.set_bone_pose_position(int(indices[semantic]), p)

	for semantic_value in scale_tracks.keys():
		var semantic := str(semantic_value)
		if not indices.has(semantic):
			continue
		var s := animation.scale_track_interpolate(int(scale_tracks[semantic_value]), time)
		if s is Vector3:
			skeleton.set_bone_pose_scale(int(indices[semantic]), s)

	var result := {}
	for semantic_value in indices.keys():
		var semantic := str(semantic_value)
		result[semantic] = skeleton.get_bone_global_pose(int(indices[semantic_value]))
	return result


static func _build_target_global_delta(rest_global: Dictionary, pose_global: Dictionary, rest_pelvis: Basis, rest_torso: Basis, source_to_target: Basis) -> Dictionary:
	var result := {}

	var pose_pelvis_value: Variant = _body_frame(pose_global, "hips", "leftupleg", "rightupleg", "spine")
	var pose_torso_value: Variant = _body_frame(pose_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	if pose_pelvis_value == null or pose_torso_value == null:
		return {}
	var pose_pelvis: Basis = pose_pelvis_value
	var pose_torso: Basis = pose_torso_value

	var source_root_delta := (pose_pelvis * rest_pelvis.inverse()).orthonormalized()
	var source_top_delta := (pose_torso * rest_torso.inverse()).orthonormalized()
	result["root"] = _map_motion_basis(source_root_delta, source_to_target)
	result["bottom"] = result["root"]
	result["top"] = _map_motion_basis(source_top_delta, source_to_target)

	var head_delta_value: Variant = _global_basis_motion(rest_global, pose_global, "head")
	result["head"] = _map_motion_basis(head_delta_value, source_to_target) if head_delta_value != null else result["top"]

	# Attachment pivots inherit their parent. Visible limb motion begins in arm*/leg*.
	result["shoulderL"] = result["top"]
	result["shoulderR"] = result["top"]
	result["hipL"] = result["bottom"]
	result["hipR"] = result["bottom"]

	for target in ["armL", "handL", "fingerL", "armR", "handR", "fingerR", "legL", "footL", "toeL", "legR", "footR", "toeR"]:
		var pair: Array = SOURCE_SEGMENT[target]
		var swing: Variant = _segment_rest_delta(
			rest_global,
			pose_global,
			str(pair[0]),
			str(pair[1]),
			source_to_target
		)
		if swing == null:
			var parent := str(TARGET_PARENT[target])
			result[target] = result[parent] if result.has(parent) else Basis.IDENTITY
		else:
			result[target] = swing

	return result


static func _segment_rest_delta(rest_global: Dictionary, pose_global: Dictionary, source_start: String, source_end: String, source_to_target: Basis) -> Variant:
	if not rest_global.has(source_start) or not rest_global.has(source_end) or not pose_global.has(source_start) or not pose_global.has(source_end):
		return null
	var rest_a: Transform3D = rest_global[source_start]
	var rest_b: Transform3D = rest_global[source_end]
	var pose_a: Transform3D = pose_global[source_start]
	var pose_b: Transform3D = pose_global[source_end]
	var rest_dir := source_to_target * (rest_b.origin - rest_a.origin)
	var pose_dir := source_to_target * (pose_b.origin - pose_a.origin)
	if rest_dir.length_squared() <= EPS or pose_dir.length_squared() <= EPS:
		return null
	rest_dir = rest_dir.normalized()
	pose_dir = pose_dir.normalized()
	return Basis(_canonical_quaternion(Quaternion(rest_dir, pose_dir))).orthonormalized()


static func _body_frame(data: Dictionary, origin_name: String, left_name: String, right_name: String, up_name: String) -> Variant:
	for name in [origin_name, left_name, right_name, up_name]:
		if not data.has(name):
			return null
	var origin: Vector3 = (data[origin_name] as Transform3D).origin
	var left: Vector3 = (data[left_name] as Transform3D).origin
	var right: Vector3 = (data[right_name] as Transform3D).origin
	var up_point: Vector3 = (data[up_name] as Transform3D).origin
	var anatomical_right := right - left
	var anatomical_up := up_point - origin
	if anatomical_right.length_squared() <= EPS or anatomical_up.length_squared() <= EPS:
		return null
	anatomical_right = anatomical_right.normalized()
	anatomical_up = anatomical_up - anatomical_right * anatomical_up.dot(anatomical_right)
	if anatomical_up.length_squared() <= EPS:
		return null
	anatomical_up = anatomical_up.normalized()
	var anatomical_forward := anatomical_right.cross(anatomical_up)
	if anatomical_forward.length_squared() <= EPS:
		return null
	anatomical_forward = anatomical_forward.normalized()
	anatomical_up = anatomical_forward.cross(anatomical_right).normalized()
	return Basis(anatomical_right, anatomical_up, anatomical_forward).orthonormalized()


static func _map_motion_basis(source_motion_value: Variant, source_to_target: Basis) -> Basis:
	var source_motion: Basis = source_motion_value
	return (source_to_target * source_motion * source_to_target.inverse()).orthonormalized()


static func _global_basis_motion(rest_global: Dictionary, pose_global: Dictionary, bone_name: String) -> Variant:
	if not rest_global.has(bone_name) or not pose_global.has(bone_name):
		return null
	var rest_xfm: Transform3D = rest_global[bone_name]
	var pose_xfm: Transform3D = pose_global[bone_name]
	return (pose_xfm.basis.orthonormalized() * rest_xfm.basis.orthonormalized().inverse()).orthonormalized()


static func _hips_translation_delta(rest_global: Dictionary, pose_global: Dictionary) -> Vector3:
	if not rest_global.has("hips") or not pose_global.has("hips"):
		return Vector3.ZERO
	return (pose_global["hips"] as Transform3D).origin - (rest_global["hips"] as Transform3D).origin


static func _build_track_maps(animation: Animation, rotation_tracks: Dictionary, position_tracks: Dictionary, scale_tracks: Dictionary) -> void:
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_SCALE_3D:
			continue
		var semantic := normalize(_bone_name_from_track_path(animation.track_get_path(track_index)))
		if semantic.is_empty():
			continue
		match track_type:
			Animation.TYPE_ROTATION_3D:
				rotation_tracks[semantic] = track_index
			Animation.TYPE_POSITION_3D:
				position_tracks[semantic] = track_index
			Animation.TYPE_SCALE_3D:
				scale_tracks[semantic] = track_index


static func _build_bone_index(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		if not semantic.is_empty():
			result[semantic] = bone_index
	return result


static func _required_missing(indices: Dictionary) -> Array[String]:
	var required := [
		"hips", "spine", "spine2", "neck", "head",
		"leftshoulder", "leftarm", "leftforearm", "lefthand",
		"rightshoulder", "rightarm", "rightforearm", "righthand",
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


static func _canonical_quaternion(q: Quaternion) -> Quaternion:
	var n := q.normalized()
	if n.w < 0.0:
		return Quaternion(-n.x, -n.y, -n.z, -n.w)
	return n


static func _unwrap_angles(current: Array, previous: Array) -> Array:
	var result := current.duplicate()
	for i in range(mini(result.size(), previous.size())):
		var value := float(result[i])
		var prev := float(previous[i])
		while value - prev > 180.0:
			value -= 360.0
		while value - prev < -180.0:
			value += 360.0
		result[i] = value
	return result


static func _quaternion_to_alabaster_angles(q: Quaternion, settings: Dictionary) -> Array:
	# Alabaster Quaternion.setAngles(yaw,pitch,roll) rebuilds from
	# Euler(pitch, roll, yaw), so encode Godot Quaternion Euler X/Y/Z as [Z,X,Y].
	var e := _canonical_quaternion(q).get_euler()
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
