extends RefCounted
class_name AlabasterMixamoRetargetV7

# Mixamo -> Default retarget V7.
#
# V6 proved the imported Animation curves contain motion (raw_track_span > 0),
# while writing those curves through Skeleton3D's pose API still yielded a
# completely static global pose in this detached/offline FBX scene. V7 therefore
# removes that unreliable middleman entirely.
#
# The imported 3D transform tracks are sampled directly and composed through the
# ACTUAL Skeleton3D parent/rest hierarchy into source global transforms. This is
# the same deterministic approach that made the early prototype move, but now it
# uses the corrected Default semantics and transfers REST->POSE anatomical deltas
# instead of copying Mixamo's T/A-pose orientation.

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_TRACK_HIERARCHY_REST_DELTA_V7"
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

# Default/Dummy shoulder* and hip* are attachment pivots. Visible limb motion
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
		push_warning("Mixamo V7: source skeleton is missing %s" % str(missing))
		return {}

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	_build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)
	if rotation_tracks.is_empty():
		push_warning("Mixamo V7: no Skeleton3D rotation tracks were found.")
		return {}

	var raw_track_span := _measure_raw_rotation_track_span(animation, rotation_tracks, maxf(sample_fps, 1.0))
	var rest_global := _build_global_rest(skeleton)
	var rest_semantic := _index_transforms_by_semantic(rest_global, skeleton)

	var rest_pelvis_value: Variant = _body_frame(rest_semantic, "hips", "leftupleg", "rightupleg", "spine")
	var rest_torso_value: Variant = _body_frame(rest_semantic, "spine2", "leftshoulder", "rightshoulder", "neck")
	if rest_pelvis_value == null or rest_torso_value == null:
		push_warning("Mixamo V7: could not construct source rest anatomical frames.")
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
	var source_joint_span := {}
	var first_pose_semantic := {}

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var pose_indexed := _sample_global_transforms_manual(animation, skeleton, rotation_tracks, position_tracks, scale_tracks, time)
		var pose_semantic := _index_transforms_by_semantic(pose_indexed, skeleton)
		if pose_semantic.is_empty():
			return {}

		if first_pose_semantic.is_empty():
			first_pose_semantic = pose_semantic.duplicate(true)
		else:
			_measure_source_joint_span(first_pose_semantic, pose_semantic, source_joint_span)

		var target_global := _build_target_global_delta(rest_semantic, pose_semantic, rest_pelvis, rest_torso, source_to_target)
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
				motion_span[target] = maxf(float(motion_span.get(target, 0.0)), rad_to_deg(2.0 * acos(dot_value)))

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
				var source_delta := _hips_translation_delta(rest_semantic, pose_semantic)
				var converted := source_to_target * source_delta * translation_scale
				max_root_translation = maxf(max_root_translation, converted.length())
				xfm["trans"] = [converted.x, converted.y, converted.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	print("ALABASTER_MIXAMO_V7_OK clip=%s frames=%d bones=%d rot_tracks=%d raw_track_span=%s joint_span=%s root_trans=%.4f max=%s span=%s" % [
		clip_name, sample_count, indices.size(), rotation_tracks.size(), str(raw_track_span), str(source_joint_span), max_root_translation, str(max_angles), str(motion_span),
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
			"bridge": "mixamo_manual_track_hierarchy_rest_delta_to_default",
			"retarget_profile": PROFILE_NAME,
			"sample_fps": fps,
			"source_rest": "Skeleton3D local Bone Rest composed manually through parent hierarchy",
			"source_pose": "Animation 3D transform tracks composed manually through Skeleton3D parent hierarchy",
			"limb_transfer": "source rest-to-pose anatomical segment swing",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _build_global_rest(skeleton: Skeleton3D) -> Dictionary:
	var indexed := {}
	for bone_index in range(skeleton.get_bone_count()):
		var local := skeleton.get_bone_rest(bone_index)
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index >= 0 and indexed.has(parent_index):
			indexed[bone_index] = (indexed[parent_index] as Transform3D) * local
		else:
			indexed[bone_index] = local
	return indexed


static func _sample_global_transforms_manual(animation: Animation, skeleton: Skeleton3D, rotation_tracks: Dictionary, position_tracks: Dictionary, scale_tracks: Dictionary, time: float) -> Dictionary:
	var indexed := {}
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		var rest_local := skeleton.get_bone_rest(bone_index)
		var local_basis := rest_local.basis
		var local_origin := rest_local.origin

		if rotation_tracks.has(semantic):
			var q: Quaternion = animation.rotation_track_interpolate(int(rotation_tracks[semantic]), time)
			local_basis = Basis(q.normalized())
		if scale_tracks.has(semantic):
			var s: Vector3 = animation.scale_track_interpolate(int(scale_tracks[semantic]), time)
			local_basis = local_basis.scaled(s)
		if position_tracks.has(semantic):
			local_origin = animation.position_track_interpolate(int(position_tracks[semantic]), time)

		var local := Transform3D(local_basis, local_origin)
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index >= 0 and indexed.has(parent_index):
			indexed[bone_index] = (indexed[parent_index] as Transform3D) * local
		else:
			indexed[bone_index] = local
	return indexed


static func _measure_source_joint_span(first_pose: Dictionary, pose: Dictionary, out_span: Dictionary) -> void:
	for target in ["armL", "handL", "armR", "handR", "legL", "footL", "legR", "footR"]:
		var pair: Array = SOURCE_SEGMENT[target]
		var a := str(pair[0])
		var b := str(pair[1])
		if not first_pose.has(a) or not first_pose.has(b) or not pose.has(a) or not pose.has(b):
			continue
		var first_dir := ((first_pose[b] as Transform3D).origin - (first_pose[a] as Transform3D).origin).normalized()
		var current_dir := ((pose[b] as Transform3D).origin - (pose[a] as Transform3D).origin).normalized()
		if first_dir.length_squared() <= EPS or current_dir.length_squared() <= EPS:
			continue
		var angle := rad_to_deg(acos(clampf(first_dir.dot(current_dir), -1.0, 1.0)))
		out_span[target] = maxf(float(out_span.get(target, 0.0)), angle)


static func _measure_raw_rotation_track_span(animation: Animation, rotation_tracks: Dictionary, fps: float) -> Dictionary:
	var interesting := ["hips", "spine2", "leftarm", "leftforearm", "rightarm", "rightforearm", "leftupleg", "leftleg", "rightupleg", "rightleg"]
	var result := {}
	var sample_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 2)
	for semantic in interesting:
		if not rotation_tracks.has(semantic):
			continue
		var track := int(rotation_tracks[semantic])
		var q0: Quaternion = animation.rotation_track_interpolate(track, 0.0)
		var max_span := 0.0
		for i in range(sample_count):
			var t := minf(float(i) / fps, animation.length)
			var q: Quaternion = animation.rotation_track_interpolate(track, t)
			var d := clampf(absf(q0.normalized().dot(q.normalized())), 0.0, 1.0)
			max_span = maxf(max_span, rad_to_deg(2.0 * acos(d)))
		result[semantic] = snappedf(max_span, 0.01)
	return result


static func _build_target_global_delta(rest_global: Dictionary, pose_global: Dictionary, rest_pelvis: Basis, rest_torso: Basis, source_to_target: Basis) -> Dictionary:
	var result := {}
	var pose_pelvis_value: Variant = _body_frame(pose_global, "hips", "leftupleg", "rightupleg", "spine")
	var pose_torso_value: Variant = _body_frame(pose_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	if pose_pelvis_value == null or pose_torso_value == null:
		return {}
	var pose_pelvis: Basis = pose_pelvis_value
	var pose_torso: Basis = pose_torso_value
	result["root"] = _map_motion_basis((pose_pelvis * rest_pelvis.inverse()).orthonormalized(), source_to_target)
	result["bottom"] = result["root"]
	result["top"] = _map_motion_basis((pose_torso * rest_torso.inverse()).orthonormalized(), source_to_target)
	var head_delta: Variant = _global_basis_motion(rest_global, pose_global, "head")
	result["head"] = _map_motion_basis(head_delta, source_to_target) if head_delta != null else result["top"]

	result["shoulderL"] = result["top"]
	result["shoulderR"] = result["top"]
	result["hipL"] = result["bottom"]
	result["hipR"] = result["bottom"]

	for target in ["armL", "handL", "fingerL", "armR", "handR", "fingerR", "legL", "footL", "toeL", "legR", "footR", "toeR"]:
		var pair: Array = SOURCE_SEGMENT[target]
		var swing: Variant = _segment_rest_delta(rest_global, pose_global, str(pair[0]), str(pair[1]), source_to_target)
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
	return Basis(_canonical_quaternion(Quaternion(rest_dir.normalized(), pose_dir.normalized()))).orthonormalized()


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


static func _index_transforms_by_semantic(indexed: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index_value in indexed.keys():
		var bone_index := int(bone_index_value)
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		if not semantic.is_empty():
			result[semantic] = indexed[bone_index_value]
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