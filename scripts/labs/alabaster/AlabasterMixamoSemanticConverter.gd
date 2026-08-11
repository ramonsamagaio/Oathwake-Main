extends RefCounted
class_name AlabasterMixamoSemanticConverter

# Mixamo -> Alabaster V4.
#
# The important discovery is that Alabaster bone NAMES are not anatomical 1:1
# equivalents of Mixamo bone names. In the Default/Dummy figure:
#   shoulderL/R and hipL/R are attachment pivots,
#   armL/R is the upper-arm segment,
#   handL/R is the forearm segment,
#   legL/R is the thigh segment,
#   footL/R is the shin segment,
#   toeL/R is the foot segment.
#
# V3 was shifted by one articulation on both arms and legs. It also reconstructed
# FBX pose tracks manually. V4 fixes both problems:
#   1. AnimationPlayer evaluates the real transient FBX scene at every sample,
#      then Skeleton3D.get_bone_global_pose() is read directly. Godot therefore
#      owns FBX rest/pre-rotation/track semantics instead of us reimplementing it.
#   2. Limb endpoints from that evaluated pose are fitted to the actual Default
#      target chain. Source absolute anatomical directions are aligned to the
#      Default target coordinate frame, so Mixamo T-pose vs Default arms-down is
#      handled as a retarget-pose difference rather than being applied twice.
#
# shoulder/hip attachment pivots intentionally inherit torso/pelvis motion. We
# can add small clavicle/hip secondary motion later, after the main chains are
# stable, without corrupting the primary limb solve.

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_ANATOMICAL_CHAIN_V4"
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

# Exact Default/Dummy node.position vectors. These vectors are what BonesSystem
# actually rotates to place each child joint, so they are the correct target-rest
# directions for retargeting.
const TARGET_REST_VECTOR := {
	"armL": Vector3(0.08333333333333334, 0.0, -0.375),
	"handL": Vector3(0.08333333333333333, 0.0, -0.4375),
	"fingerL": Vector3(0.0, 0.0, -0.125),
	"armR": Vector3(-0.08333333333333333, 0.0, -0.375),
	"handR": Vector3(-0.08333333084980646, 0.0, -0.4375),
	"fingerR": Vector3(0.0, 0.0, -0.125),
	"legL": Vector3(0.0, 0.0, -0.5625),
	"footL": Vector3(0.0, 0.0, -0.5),
	"toeL": Vector3(0.0, 0.125, 0.0),
	"legR": Vector3(0.0, 0.0, -0.5625),
	"footR": Vector3(0.0, 0.0, -0.5),
	"toeR": Vector3(0.0, 0.125, 0.0),
}

# Target bone -> anatomical source segment whose ENDPOINT direction must match.
# Notice the one-node shift compared with the old name-based mapping:
#   Mixamo UpLeg -> Alabaster leg (thigh)
#   Mixamo Leg   -> Alabaster foot (shin)
# and the same principle for arm/forearm.
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

# Default anatomical axes, rebuilt from the actual figure semantics:
# anatomical right = target right hip/shoulder = -X
# anatomical up    = +Z
# anatomical forward = right x up = +Y
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
		push_warning("Mixamo Anatomical V4: source skeleton is missing %s" % str(missing))
		return {}

	# Rest transforms are authoritative only for constructing the source anatomical
	# coordinate frame and root/torso/head motion deltas. Animated samples below
	# come from the evaluated Skeleton3D, not manually reconstructed tracks.
	var rest_global := {}
	for semantic_value in indices.keys():
		var semantic := str(semantic_value)
		var bone_index := int(indices[semantic_value])
		rest_global[semantic] = skeleton.get_bone_global_rest(bone_index)

	var rest_pelvis_value: Variant = _body_frame(rest_global, "hips", "leftupleg", "rightupleg", "spine")
	var rest_torso_value: Variant = _body_frame(rest_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	if rest_pelvis_value == null or rest_torso_value == null:
		push_warning("Mixamo Anatomical V4: could not construct source rest anatomical frames.")
		return {}
	var rest_pelvis: Basis = rest_pelvis_value
	var rest_torso: Basis = rest_torso_value

	# Dynamic source-world -> Default-world conversion. This is superior to a
	# hard-coded FBX axis swap because it derives right/up/forward directly from
	# the imported humanoid's own rest anatomy.
	var target_anatomical := Basis(TARGET_ANATOMICAL_RIGHT, TARGET_ANATOMICAL_UP, TARGET_ANATOMICAL_FORWARD).orthonormalized()
	var source_to_target := (target_anatomical * rest_pelvis.inverse()).orthonormalized()

	var fps := maxf(sample_fps, 1.0)
	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var max_angles := {}
	var max_root_translation := 0.0

	# Force AnimationPlayer to own FBX animation evaluation immediately. seek(...,
	# true, true) applies transform tracks while suppressing method/audio side
	# effects, which is exactly what an offline retarget tool needs.
	player.play(clip_name)
	player.advance(0.0)

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var pose_global := _evaluate_source_pose(player, skeleton, indices, time)
		if pose_global.is_empty():
			return {}

		var target_global := _build_target_global_motion(rest_global, pose_global, rest_pelvis, rest_torso, source_to_target)
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
				var converted := source_to_target * source_delta * translation_scale
				max_root_translation = maxf(max_root_translation, converted.length())
				xfm["trans"] = [converted.x, converted.y, converted.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	player.stop(true)
	print("ALABASTER_MIXAMO_ANATOMICAL_OK clip=%s frames=%d bones=%d root_trans=%.4f max=%s" % [
		clip_name, sample_count, indices.size(), max_root_translation, str(max_angles),
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
			"bridge": "mixamo_evaluated_pose_anatomical_chain_to_default",
			"retarget_profile": PROFILE_NAME,
			"sample_fps": fps,
			"source_rest": "Skeleton3D global Bone Rest",
			"source_pose": "AnimationPlayer evaluated Skeleton3D global pose",
			"limb_transfer": "absolute source joint direction fitted to Default target-rest vectors",
			"target_chain": "shoulder/hip anchors + arm/hand and leg/foot segment solve",
			"axis_conversion": "derived from source rest pelvis anatomical frame",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _evaluate_source_pose(player: AnimationPlayer, skeleton: Skeleton3D, indices: Dictionary, time: float) -> Dictionary:
	# Reset first so bones omitted from a particular source track cannot retain a
	# value from the previous sample.
	skeleton.reset_bone_poses()
	player.seek(time, true, true)
	var result := {}
	for semantic_value in indices.keys():
		var semantic := str(semantic_value)
		var bone_index := int(indices[semantic_value])
		result[semantic] = skeleton.get_bone_global_pose(bone_index)
	return result


static func _build_target_global_motion(rest_global: Dictionary, pose_global: Dictionary, rest_pelvis: Basis, rest_torso: Basis, source_to_target: Basis) -> Dictionary:
	var result := {}

	var pose_pelvis_value: Variant = _body_frame(pose_global, "hips", "leftupleg", "rightupleg", "spine")
	var pose_torso_value: Variant = _body_frame(pose_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	if pose_pelvis_value == null or pose_torso_value == null:
		return {}
	var pose_pelvis: Basis = pose_pelvis_value
	var pose_torso: Basis = pose_torso_value

	var source_root_motion := (pose_pelvis * rest_pelvis.inverse()).orthonormalized()
	var source_top_motion := (pose_torso * rest_torso.inverse()).orthonormalized()
	result["root"] = _map_motion_basis(source_root_motion, source_to_target)
	result["bottom"] = result["root"]
	result["top"] = _map_motion_basis(source_top_motion, source_to_target)

	var head_motion_value: Variant = _global_basis_motion(rest_global, pose_global, "head")
	result["head"] = _map_motion_basis(head_motion_value, source_to_target) if head_motion_value != null else result["top"]

	# Alabaster shoulder/hip nodes are attachment pivots, not the upper limb bones.
	# Stabilize them to their parent. This is the crucial one-node semantic shift
	# that V1-V3 were missing.
	result["shoulderL"] = result["top"]
	result["shoulderR"] = result["top"]
	result["hipL"] = result["bottom"]
	result["hipR"] = result["bottom"]

	for target in ["armL", "handL", "fingerL", "armR", "handR", "fingerR", "legL", "footL", "toeL", "legR", "footR", "toeR"]:
		var pair: Array = SOURCE_SEGMENT[target]
		var parent := str(TARGET_PARENT[target])
		if not result.has(parent):
			continue
		var parent_global: Basis = result[parent]
		var solved: Variant = _fit_source_segment_to_target_rest(
			pose_global,
			str(pair[0]),
			str(pair[1]),
			source_to_target,
			parent_global,
			TARGET_REST_VECTOR[target]
		)
		if solved == null:
			# Tiny fingers/toes can be missing from animation-only exports. Inherit the
			# parent rather than injecting an arbitrary rotation.
			result[target] = parent_global
		else:
			result[target] = solved

	return result


static func _fit_source_segment_to_target_rest(pose_global: Dictionary, source_start: String, source_end: String, source_to_target: Basis, parent_global: Basis, target_rest_vector: Vector3) -> Variant:
	if not pose_global.has(source_start) or not pose_global.has(source_end):
		return null
	var source_a: Transform3D = pose_global[source_start]
	var source_b: Transform3D = pose_global[source_end]
	var source_dir := source_b.origin - source_a.origin
	if source_dir.length_squared() <= EPS or target_rest_vector.length_squared() <= EPS:
		return null
	var desired_global_dir := (source_to_target * source_dir.normalized()).normalized()
	var desired_local_dir := (parent_global.inverse() * desired_global_dir).normalized()
	var rest_dir := target_rest_vector.normalized()
	var local_q := Quaternion(rest_dir, desired_local_dir).normalized()
	return (parent_global * Basis(local_q)).orthonormalized()


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


static func _quaternion_to_alabaster_angles(q: Quaternion, settings: Dictionary) -> Array:
	# Alabaster Quaternion.setAngles(yaw,pitch,roll) rebuilds from
	# Euler(pitch, roll, yaw), so encode Godot Quaternion Euler X/Y/Z as [Z,X,Y].
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
