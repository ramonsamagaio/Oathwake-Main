extends RefCounted
class_name AlabasterMixamoRetargetV9

# Mixamo -> Juno target-aware retarget V9.
#
# V8 correctly reconstructs the Mixamo FBX hierarchy and REST->POSE motion, but
# it still assumes that a source limb rotation can be applied directly to a Juno
# limb. That is not generally true: Juno's authored local rest vectors are not
# the same axes as Mixamo's T-pose bones. The visible symptom is exactly what a
# walking clip exposes: knees can bend backwards, feet can point through the
# body, and an arm can appear to swing on the wrong side even though bone names
# are correct.
#
# V9 keeps V8's authoritative source sampling, but characterizes the TARGET too.
# For every limb segment it asks a simpler, safer question:
#   "Where is this source segment pointing in the current pose?"
# and builds the Juno global rotation that points Juno's OWN authored rest vector
# in that direction. Parent motion is removed afterwards, producing the local
# animation rotation expected by the Alabaster runtime.

const V8 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV8.gd")

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_JUNO_TARGET_REST_SWING_V9"
const EPS := 0.000001

const CORE_TARGET_ORDER := [
	"root", "bottom", "top", "head",
	"armL", "handL", "fingerL",
	"armR", "handR", "fingerR",
	"legL", "footL", "toeL",
	"legR", "footR", "toeR",
]

const JUNO_PARENT_FALLBACK := {
	"root": "",
	"bottom": "root",
	"top": "root",
	"head": "top",
	"armL": "top",
	"handL": "armL",
	"fingerL": "handL",
	"armR": "top",
	"handR": "armR",
	"fingerR": "handR",
	"legL": "bottom",
	"footL": "legL",
	"toeL": "footL",
	"legR": "bottom",
	"footR": "legR",
	"toeR": "footR",
}

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

const REQUIRED_SOURCE := [
	"hips", "spine", "spine2", "neck", "head",
	"leftshoulder", "leftarm", "leftforearm", "lefthand",
	"rightshoulder", "rightarm", "rightforearm", "righthand",
	"leftupleg", "leftleg", "leftfoot",
	"rightupleg", "rightleg", "rightfoot",
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
	var mode := str(settings.get("retarget_limb_mode", "target_rest_swing"))
	# Keep the previous solvers available in RETARGET DEBUG for A/B comparisons.
	if mode == "full_global_delta" or mode == "segment_swing":
		return V8.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)

	if player == null or skeleton == null or clip_name.is_empty() or not player.has_animation(clip_name):
		return {}
	var animation := player.get_animation(clip_name)
	if animation == null:
		return {}

	var target_rest_local := _target_rest_local_positions(settings)
	var target_parent_map := _target_parent_map(settings)
	if target_rest_local.is_empty():
		push_warning("Mixamo -> Juno V9: target rest vectors unavailable; using V8 segment swing fallback.")
		var fallback_settings := settings.duplicate(true)
		fallback_settings["retarget_limb_mode"] = "segment_swing"
		return V8.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, fallback_settings)

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	_build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)
	if rotation_tracks.is_empty():
		return {}

	var rest_indexed := _build_global_rest(skeleton)
	var rest_semantic := _index_transforms_by_semantic(rest_indexed, skeleton)
	for required_name in REQUIRED_SOURCE:
		if not rest_semantic.has(required_name):
			push_warning("Mixamo -> Juno V9: missing required source bone '%s'." % required_name)
			return {}

	var rest_pelvis_value := _body_frame_transforms(rest_semantic, "hips", "leftupleg", "rightupleg", "spine")
	var rest_torso_value := _body_frame_transforms(rest_semantic, "spine2", "leftshoulder", "rightshoulder", "neck")
	if rest_pelvis_value == null or rest_torso_value == null:
		return {}
	var rest_pelvis: Basis = rest_pelvis_value
	var rest_torso: Basis = rest_torso_value

	# Characterize Juno from her actual authored node positions rather than a
	# hard-coded axis guess. This automatically establishes the target handedness
	# and therefore the correct forward/back direction for knees, feet and arms.
	var target_rest_global := _build_target_rest_global(target_rest_local, target_parent_map)
	var target_pelvis_value := _body_frame_points(target_rest_global, "bottom", "legL", "legR", "top")
	if target_pelvis_value == null:
		push_warning("Mixamo -> Juno V9: could not characterize target pelvis; using V8 fallback.")
		var fallback_settings := settings.duplicate(true)
		fallback_settings["retarget_limb_mode"] = "segment_swing"
		return V8.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, fallback_settings)
	var target_pelvis: Basis = target_pelvis_value
	var source_to_target := (target_pelvis * rest_pelvis.inverse()).orthonormalized()

	var target_bones := _target_bones(settings)
	var skip_nodes := _skip_nodes(settings)
	var fps := maxf(sample_fps, 1.0)
	if is_zero_approx(translation_scale):
		translation_scale = float(settings.get("root_translation_scale", 0.0))
	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var previous_angles := {}

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var pose_indexed := _sample_global_transforms(
			animation,
			skeleton,
			rotation_tracks,
			position_tracks,
			scale_tracks,
			time
		)
		var pose_semantic := _index_transforms_by_semantic(pose_indexed, skeleton)
		if pose_semantic.is_empty():
			return {}

		var pose_pelvis_value := _body_frame_transforms(pose_semantic, "hips", "leftupleg", "rightupleg", "spine")
		var pose_torso_value := _body_frame_transforms(pose_semantic, "spine2", "leftshoulder", "rightshoulder", "neck")
		if pose_pelvis_value == null or pose_torso_value == null:
			return {}
		var pose_pelvis: Basis = pose_pelvis_value
		var pose_torso: Basis = pose_torso_value
		var pelvis_delta := (pose_pelvis * rest_pelvis.inverse()).orthonormalized()
		var torso_delta := (pose_torso * rest_torso.inverse()).orthonormalized()

		var target_global := {}
		# Juno's gameplay facing owns root yaw. Pelvis/torso motion remains animated.
		target_global["root"] = Basis.IDENTITY
		target_global["bottom"] = _map_motion_basis(pelvis_delta, source_to_target)
		target_global["top"] = _map_motion_basis(torso_delta, source_to_target)

		var head_delta := _global_basis_motion(rest_semantic, pose_semantic, "head")
		target_global["head"] = _map_motion_basis(head_delta, source_to_target) if head_delta != null else target_global["top"]

		for target_value in SOURCE_SEGMENT.keys():
			var target := str(target_value)
			var pair: Array = SOURCE_SEGMENT[target]
			var desired_direction := _source_pose_direction(
				pose_semantic,
				str(pair[0]),
				str(pair[1]),
				source_to_target
			)
			var target_rest_direction := _target_segment_rest_direction(
				target,
				target_rest_local,
				target_rest_global,
				target_parent_map
			)
			if desired_direction.length_squared() <= EPS or target_rest_direction.length_squared() <= EPS:
				var parent_name := str(JUNO_PARENT_FALLBACK.get(target, ""))
				target_global[target] = target_global[parent_name] if target_global.has(parent_name) else Basis.IDENTITY
				continue
			var swing := Quaternion(target_rest_direction.normalized(), desired_direction.normalized())
			target_global[target] = Basis(_canonical_quaternion(swing)).orthonormalized()

		var node_xfm := {}
		for target_value in CORE_TARGET_ORDER:
			var target := str(target_value)
			if not target_bones.has(target) or skip_nodes.has(target) or not target_global.has(target):
				continue
			var parent_target := _effective_target_parent(target, target_parent_map, target_bones, skip_nodes)
			var global_basis: Basis = target_global[target]
			var local_basis := global_basis
			if not parent_target.is_empty() and target_global.has(parent_target):
				var parent_basis: Basis = target_global[parent_target]
				local_basis = (parent_basis.inverse() * global_basis).orthonormalized()

			var angles := [0.0, 0.0, 0.0]
			if target != "root":
				var q := _canonical_quaternion(local_basis.get_rotation_quaternion())
				angles = _quaternion_to_alabaster_angles(q, settings)
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
				xfm["trans"] = [converted.x, converted.y, converted.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	print("ALABASTER_MIXAMO_V9_OK clip=%s frames=%d target_rest=%d" % [clip_name, sample_count, target_rest_local.size()])
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
			"bridge": "mixamo_target_characterized_rest_swing_v9",
			"retarget_profile": PROFILE_NAME,
			"target_profile": "juno",
			"sample_fps": fps,
			"limb_transfer_mode": "target_rest_swing",
			"target_characterization": "actual Juno authored rest node positions",
			"source_characterization": "Skeleton3D hierarchy + Mixamo semantic segments",
			"source_to_target_basis": "pelvis frame -> Juno pelvis frame",
			"root_rotation_policy": "locked; pelvis orientation transferred to bottom",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _target_rest_local_positions(settings: Dictionary) -> Dictionary:
	var value: Variant = settings.get("target_rest_local_positions", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _target_parent_map(settings: Dictionary) -> Dictionary:
	var value: Variant = settings.get("target_parent_map", {})
	if value is Dictionary and not (value as Dictionary).is_empty():
		return (value as Dictionary).duplicate(true)
	return JUNO_PARENT_FALLBACK.duplicate(true)


static func _target_bones(settings: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var value: Variant = settings.get("target_bones", [])
	if value is Array:
		for item in value:
			var name := str(item)
			if not name.is_empty() and not result.has(name):
				result.append(name)
	if result.is_empty():
		for item in CORE_TARGET_ORDER:
			result.append(str(item))
	return result


static func _skip_nodes(settings: Dictionary) -> Dictionary:
	var result := {}
	var value: Variant = settings.get("retarget_skip_attachment_nodes", ["shoulderL", "shoulderR", "hipL", "hipR"])
	if value is Array:
		for item in value:
			result[str(item)] = true
	return result


static func _build_target_rest_global(local_positions: Dictionary, parent_map: Dictionary) -> Dictionary:
	var result := {}
	var visiting := {}
	for bone_value in local_positions.keys():
		_build_target_rest_point(str(bone_value), local_positions, parent_map, result, visiting)
	return result


static func _build_target_rest_point(
	bone: String,
	local_positions: Dictionary,
	parent_map: Dictionary,
	result: Dictionary,
	visiting: Dictionary
) -> Vector3:
	if result.has(bone):
		return result[bone]
	if visiting.has(bone):
		return Vector3.ZERO
	visiting[bone] = true
	var local_value: Variant = local_positions.get(bone, Vector3.ZERO)
	var local := local_value if local_value is Vector3 else Vector3.ZERO
	var parent := str(parent_map.get(bone, ""))
	var global := local
	if not parent.is_empty() and local_positions.has(parent):
		global += _build_target_rest_point(parent, local_positions, parent_map, result, visiting)
	visiting.erase(bone)
	result[bone] = global
	return global


static func _target_segment_rest_direction(
	target: String,
	local_positions: Dictionary,
	global_positions: Dictionary,
	parent_map: Dictionary
) -> Vector3:
	var local_value: Variant = local_positions.get(target, null)
	if local_value is Vector3 and (local_value as Vector3).length_squared() > EPS:
		return local_value as Vector3
	var parent := str(parent_map.get(target, JUNO_PARENT_FALLBACK.get(target, "")))
	if global_positions.has(target) and global_positions.has(parent):
		return (global_positions[target] as Vector3) - (global_positions[parent] as Vector3)
	return Vector3.ZERO


static func _source_pose_direction(
	pose_global: Dictionary,
	start_name: String,
	end_name: String,
	source_to_target: Basis
) -> Vector3:
	if not pose_global.has(start_name) or not pose_global.has(end_name):
		return Vector3.ZERO
	var a: Transform3D = pose_global[start_name]
	var b: Transform3D = pose_global[end_name]
	return source_to_target * (b.origin - a.origin)


static func _body_frame_transforms(
	data: Dictionary,
	origin_name: String,
	left_name: String,
	right_name: String,
	up_name: String
) -> Variant:
	for name in [origin_name, left_name, right_name, up_name]:
		if not data.has(name):
			return null
	return _body_frame_from_points(
		(data[origin_name] as Transform3D).origin,
		(data[left_name] as Transform3D).origin,
		(data[right_name] as Transform3D).origin,
		(data[up_name] as Transform3D).origin
	)


static func _body_frame_points(
	data: Dictionary,
	origin_name: String,
	left_name: String,
	right_name: String,
	up_name: String
) -> Variant:
	for name in [origin_name, left_name, right_name, up_name]:
		if not data.has(name) or not data[name] is Vector3:
			return null
	return _body_frame_from_points(
		data[origin_name] as Vector3,
		data[left_name] as Vector3,
		data[right_name] as Vector3,
		data[up_name] as Vector3
	)


static func _body_frame_from_points(origin: Vector3, left: Vector3, right: Vector3, up_point: Vector3) -> Variant:
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


static func _sample_global_transforms(
	animation: Animation,
	skeleton: Skeleton3D,
	rotation_tracks: Dictionary,
	position_tracks: Dictionary,
	scale_tracks: Dictionary,
	time: float
) -> Dictionary:
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
			var scale_value: Vector3 = animation.scale_track_interpolate(int(scale_tracks[semantic]), time)
			local_basis = local_basis.scaled(scale_value)
		if position_tracks.has(semantic):
			local_origin = animation.position_track_interpolate(int(position_tracks[semantic]), time)
		var local := Transform3D(local_basis, local_origin)
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index >= 0 and indexed.has(parent_index):
			indexed[bone_index] = (indexed[parent_index] as Transform3D) * local
		else:
			indexed[bone_index] = local
	return indexed


static func _build_track_maps(
	animation: Animation,
	rotation_tracks: Dictionary,
	position_tracks: Dictionary,
	scale_tracks: Dictionary
) -> void:
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


static func _index_transforms_by_semantic(indexed: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index_value in indexed.keys():
		var bone_index := int(bone_index_value)
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		if not semantic.is_empty() and not result.has(semantic):
			result[semantic] = indexed[bone_index_value]
	return result


static func _global_basis_motion(rest_global: Dictionary, pose_global: Dictionary, bone_name: String) -> Variant:
	if not rest_global.has(bone_name) or not pose_global.has(bone_name):
		return null
	var rest_xfm: Transform3D = rest_global[bone_name]
	var pose_xfm: Transform3D = pose_global[bone_name]
	return (pose_xfm.basis.orthonormalized() * rest_xfm.basis.orthonormalized().inverse()).orthonormalized()


static func _map_motion_basis(source_motion_value: Variant, source_to_target: Basis) -> Basis:
	var source_motion: Basis = source_motion_value
	return (source_to_target * source_motion * source_to_target.inverse()).orthonormalized()


static func _effective_target_parent(target: String, parent_map: Dictionary, target_bones: Array[String], skip_nodes: Dictionary) -> String:
	var fallback := str(JUNO_PARENT_FALLBACK.get(target, ""))
	var current := str(parent_map.get(target, fallback))
	var visited := {}
	while not current.is_empty():
		if visited.has(current):
			return fallback
		visited[current] = true
		if skip_nodes.has(current):
			current = str(parent_map.get(current, JUNO_PARENT_FALLBACK.get(current, "")))
			continue
		if target_bones.has(current) and CORE_TARGET_ORDER.has(current):
			return current
		current = str(parent_map.get(current, JUNO_PARENT_FALLBACK.get(current, "")))
	return ""


static func _hips_translation_delta(rest_global: Dictionary, pose_global: Dictionary) -> Vector3:
	if not rest_global.has("hips") or not pose_global.has("hips"):
		return Vector3.ZERO
	return (pose_global["hips"] as Transform3D).origin - (rest_global["hips"] as Transform3D).origin


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


static func _unwrap_angles(current: Array, previous: Array) -> Array:
	var result := current.duplicate()
	for index in range(mini(result.size(), previous.size())):
		var value := float(result[index])
		var prev := float(previous[index])
		while value - prev > 180.0:
			value -= 360.0
		while value - prev < -180.0:
			value += 360.0
		result[index] = value
	return result


static func _canonical_quaternion(q: Quaternion) -> Quaternion:
	var normalized := q.normalized()
	if normalized.w < 0.0:
		return Quaternion(-normalized.x, -normalized.y, -normalized.z, -normalized.w)
	return normalized


static func _bone_name_from_track_path(path: NodePath) -> String:
	var text := str(path)
	var separator := text.rfind(":")
	return text.substr(separator + 1) if separator >= 0 else text.get_file()


static func normalize(value: String) -> String:
	return (
		value.to_lower()
		.replace("mixamorig:", "")
		.replace("mixamorig_", "")
		.replace("mixamorig", "")
		.replace(" ", "")
		.replace("-", "")
		.replace("_", "")
	)
