extends RefCounted
class_name AlabasterMixamoSemanticConverter

# Mixamo -> Alabaster V3.
#
# The two rigs do not share bone axes, bone count, or even the same hierarchy.
# Copying local Euler/quaternion values therefore cannot be made robust merely
# by improving the name mapping. This converter transfers SEMANTIC MOTION:
#
#   * pelvis/root: body frame built from hips + upper legs + spine
#   * torso/top: body frame built from shoulders + neck
#   * arm/leg chains: shortest-arc change of the actual joint-to-joint direction
#   * head: global rest-space orientation delta
#
# Every semantic result is first expressed as a GLOBAL motion delta and is then
# re-parented into Alabaster's reduced hierarchy. This means a forearm keeps the
# walking/punching direction seen in Mixamo without inheriting Mixamo's private
# bone/pre-rotation axes or its extra Spine/Clavicle nodes.

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_SEMANTIC_SWING_V3"
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

# Target bone -> source segment whose visible direction should be preserved.
# These pairs deliberately skip Mixamo helper/intermediate bones where Alabaster
# has no equivalent articulation.
const SEGMENTS := {
	"shoulderL": ["leftarm", "leftforearm"],
	"armL": ["leftforearm", "lefthand"],
	"handL": ["lefthand", "lefthandindex1"],
	"fingerL": ["lefthandindex1", "lefthandindex2"],
	"shoulderR": ["rightarm", "rightforearm"],
	"armR": ["rightforearm", "righthand"],
	"handR": ["righthand", "righthandindex1"],
	"fingerR": ["righthandindex1", "righthandindex2"],
	"hipL": ["leftupleg", "leftleg"],
	"legL": ["leftleg", "leftfoot"],
	"footL": ["leftfoot", "lefttoebase"],
	"toeL": ["lefttoebase", "lefttoeend"],
	"hipR": ["rightupleg", "rightleg"],
	"legR": ["rightleg", "rightfoot"],
	"footR": ["rightfoot", "righttoebase"],
	"toeR": ["righttoebase", "righttoeend"],
}

# Proper right-handed coordinate rotation:
# Godot X right -> Alabaster X right
# Godot Y up    -> Alabaster Z up
# Godot Z back  -> Alabaster -Y (depth/forward)
static var _source_to_alabaster := Basis(
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, -1.0, 0.0)
)


static func convert_scene(player: AnimationPlayer, skeleton: Skeleton3D, clip_name: String, sample_fps: float, loop: bool, translation_scale: float, settings: Dictionary) -> Dictionary:
	if player == null or skeleton == null or clip_name.is_empty() or not player.has_animation(clip_name):
		return {}
	var animation := player.get_animation(clip_name)
	if animation == null:
		return {}

	var indices := _build_bone_index(skeleton)
	var missing := _required_missing(indices)
	if not missing.is_empty():
		push_warning("Mixamo Semantic V3: source skeleton is missing %s" % str(missing))
		return {}

	var rotation_tracks := {}
	var position_tracks := {}
	_build_track_maps(animation, rotation_tracks, position_tracks)
	if rotation_tracks.is_empty():
		push_warning("Mixamo Semantic V3: no Skeleton3D rotation tracks were found.")
		return {}

	var rest_global := {}
	for semantic_value in indices.keys():
		var semantic := str(semantic_value)
		var bone_index := int(indices[semantic_value])
		rest_global[semantic] = skeleton.get_bone_global_rest(bone_index)

	var fps := maxf(sample_fps, 1.0)
	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	# Alabaster frameCnt is an exclusive loop boundary.
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var max_angles := {}
	var max_root_translation := 0.0

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var pose_global := _sample_global_transforms(animation, skeleton, rotation_tracks, position_tracks, time)
		if pose_global.is_empty():
			return {}

		var target_global := _build_semantic_global_motion(rest_global, pose_global)
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

			var q := local_basis.get_rotation_quaternion().normalized()
			var angle_deg := absf(rad_to_deg(q.get_angle()))
			max_angles[target] = maxf(float(max_angles.get(target, 0.0)), angle_deg)
			var xfm := {
				"rot": _quaternion_to_alabaster_angles(q, settings),
				"trans": [0.0, 0.0, 0.0],
				"scale": 1.0,
			}

			if target == "root" and not is_zero_approx(translation_scale):
				var source_delta := _hips_translation_delta(rest_global, pose_global)
				var converted := _convert_vector(source_delta) * translation_scale
				max_root_translation = maxf(max_root_translation, converted.length())
				xfm["trans"] = [converted.x, converted.y, converted.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	print("ALABASTER_MIXAMO_SEMANTIC_OK clip=%s frames=%d bones=%d rot_tracks=%d root_trans=%.4f max=%s" % [
		clip_name, sample_count, indices.size(), rotation_tracks.size(), max_root_translation, str(max_angles),
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
			"bridge": "mixamo_semantic_joint_direction_to_alabaster",
			"retarget_profile": PROFILE_NAME,
			"sample_fps": fps,
			"source_rest": "Skeleton3D global Bone Rest",
			"source_pose": "Animation tracks reconstructed through Skeleton3D hierarchy",
			"limb_transfer": "rest-to-pose joint direction shortest arc",
			"torso_transfer": "pelvis/shoulder semantic body frames",
			"axis_conversion": "godot(X,Y,Z)->alabaster(X,-Z,Y)",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _build_semantic_global_motion(rest_global: Dictionary, pose_global: Dictionary) -> Dictionary:
	var result := {}

	var rest_pelvis: Variant = _body_frame(rest_global, "hips", "leftupleg", "rightupleg", "spine")
	var pose_pelvis: Variant = _body_frame(pose_global, "hips", "leftupleg", "rightupleg", "spine")
	if rest_pelvis == null or pose_pelvis == null:
		return {}
	var root_motion := _basis_delta(rest_pelvis, pose_pelvis)
	result["root"] = _convert_basis(root_motion)
	# bottom is a visual pelvis child in Alabaster; inherit root and do not apply
	# the Mixamo Hips rotation twice.
	result["bottom"] = result["root"]

	var rest_torso: Variant = _body_frame(rest_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	var pose_torso: Variant = _body_frame(pose_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	if rest_torso != null and pose_torso != null:
		result["top"] = _convert_basis(_basis_delta(rest_torso, pose_torso))
	else:
		result["top"] = result["root"]

	# Head yaw/roll matter for directional sprite selection, so keep its complete
	# global rest-space orientation delta rather than reducing it to one vector.
	var head_motion: Variant = _global_basis_motion(rest_global, pose_global, "head")
	result["head"] = _convert_basis(head_motion) if head_motion != null else result["top"]

	for target_value in SEGMENTS.keys():
		var target := str(target_value)
		var pair: Array = SEGMENTS[target_value]
		var motion: Variant = _segment_swing(rest_global, pose_global, str(pair[0]), str(pair[1]))
		if motion == null:
			# End bones are sometimes absent. Parent-follow is stable and avoids
			# inventing a rotation from an unrelated FBX local axis.
			var parent := str(TARGET_PARENT.get(target, ""))
			if result.has(parent):
				result[target] = result[parent]
			continue
		result[target] = motion

	return result


static func _segment_swing(rest_global: Dictionary, pose_global: Dictionary, start_name: String, end_name: String) -> Variant:
	if not rest_global.has(start_name) or not rest_global.has(end_name) or not pose_global.has(start_name) or not pose_global.has(end_name):
		return null
	var rest_a: Transform3D = rest_global[start_name]
	var rest_b: Transform3D = rest_global[end_name]
	var pose_a: Transform3D = pose_global[start_name]
	var pose_b: Transform3D = pose_global[end_name]
	var rest_dir := _convert_vector(rest_b.origin - rest_a.origin)
	var pose_dir := _convert_vector(pose_b.origin - pose_a.origin)
	if rest_dir.length_squared() <= EPS or pose_dir.length_squared() <= EPS:
		return null
	rest_dir = rest_dir.normalized()
	pose_dir = pose_dir.normalized()
	return Basis(Quaternion(rest_dir, pose_dir).normalized()).orthonormalized()


static func _body_frame(data: Dictionary, origin_name: String, left_name: String, right_name: String, up_name: String) -> Variant:
	for bone_name in [origin_name, left_name, right_name, up_name]:
		if not data.has(bone_name):
			return null
	var origin_xfm: Transform3D = data[origin_name]
	var left_xfm: Transform3D = data[left_name]
	var right_xfm: Transform3D = data[right_name]
	var up_xfm: Transform3D = data[up_name]
	var origin := origin_xfm.origin
	var left := left_xfm.origin
	var right := right_xfm.origin
	var up_point := up_xfm.origin
	var x_axis := right - left
	var y_axis := up_point - origin
	if x_axis.length_squared() <= EPS or y_axis.length_squared() <= EPS:
		return null
	x_axis = x_axis.normalized()
	y_axis = y_axis - x_axis * y_axis.dot(x_axis)
	if y_axis.length_squared() <= EPS:
		return null
	y_axis = y_axis.normalized()
	var z_axis := x_axis.cross(y_axis)
	if z_axis.length_squared() <= EPS:
		return null
	z_axis = z_axis.normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


static func _basis_delta(rest_basis_value: Variant, pose_basis_value: Variant) -> Basis:
	var rest_basis: Basis = rest_basis_value
	var pose_basis: Basis = pose_basis_value
	return (pose_basis * rest_basis.inverse()).orthonormalized()


static func _global_basis_motion(rest_global: Dictionary, pose_global: Dictionary, bone_name: String) -> Variant:
	if not rest_global.has(bone_name) or not pose_global.has(bone_name):
		return null
	var rest_xfm: Transform3D = rest_global[bone_name]
	var pose_xfm: Transform3D = pose_global[bone_name]
	return (pose_xfm.basis.orthonormalized() * rest_xfm.basis.orthonormalized().inverse()).orthonormalized()


static func _hips_translation_delta(rest_global: Dictionary, pose_global: Dictionary) -> Vector3:
	if not rest_global.has("hips") or not pose_global.has("hips"):
		return Vector3.ZERO
	var rest_hips: Transform3D = rest_global["hips"]
	var pose_hips: Transform3D = pose_global["hips"]
	return pose_hips.origin - rest_hips.origin


static func _sample_global_transforms(animation: Animation, skeleton: Skeleton3D, rotation_tracks: Dictionary, position_tracks: Dictionary, time: float) -> Dictionary:
	var indexed := {}
	# Skeleton3D guarantees parent index < child index.
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		var rest_local := skeleton.get_bone_rest(bone_index)
		var local_basis := rest_local.basis.orthonormalized()
		var local_origin := rest_local.origin
		if rotation_tracks.has(semantic):
			var rot_track := int(rotation_tracks[semantic])
			var q := animation.rotation_track_interpolate(rot_track, time).normalized()
			local_basis = Basis(q).orthonormalized()
		if position_tracks.has(semantic):
			var pos_track := int(position_tracks[semantic])
			local_origin = animation.position_track_interpolate(pos_track, time)
		var local := Transform3D(local_basis, local_origin)
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index >= 0 and indexed.has(parent_index):
			var parent_global: Transform3D = indexed[parent_index]
			indexed[bone_index] = parent_global * local
		else:
			indexed[bone_index] = local
	return _index_transforms_by_semantic(indexed, skeleton)


static func _index_transforms_by_semantic(indexed: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index_variant in indexed.keys():
		var bone_index := int(bone_index_variant)
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		if not semantic.is_empty():
			result[semantic] = indexed[bone_index_variant]
	return result


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
	for bone_name in required:
		if not indices.has(bone_name):
			missing.append(bone_name)
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
	# Alabaster Quaternion.setAngles(yaw,pitch,roll) reconstructs Euler(pitch,
	# roll,yaw). Therefore Godot XYZ Euler is serialized as [Z,X,Y].
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
