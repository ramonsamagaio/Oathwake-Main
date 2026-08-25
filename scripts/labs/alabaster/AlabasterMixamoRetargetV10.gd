extends RefCounted
class_name AlabasterMixamoRetargetV10

# Mixamo -> Juno retarget V10.
#
# V9 solved the large anatomical problem by mapping each source limb direction
# onto Juno's authored rest vectors. Two ambiguities were still visible in real
# Mixamo locomotion:
#   1. right/up alone cannot tell which side of a skeleton is FORWARD. Mixamo's
#      semantic right/up/toe-forward frame can be opposite-handed to Juno's,
#      so a right-handed cross-product silently turns a forward walk backward.
#   2. a single segment direction fixes swing but leaves one free TWIST axis.
#      The shortest quaternion can therefore put an ankle in the right place
#      while turning the visible foot 180 degrees through the heel.
#
# V10 turns those observations into reusable REST calibration, not clip hacks:
# - character forward is disambiguated by the average REST foot -> toe direction;
# - source/target handedness is preserved, including a reflection when required;
# - every limb uses a second adjacent segment as a plane hint, fixing twist;
# - the exact same calibration is reused for every sampled frame and therefore
#   for every Mixamo clip that shares the standard humanoid rest skeleton.
#
# Temporal pole stabilization (production patch 15):
# When a knee approaches full extension, the primary thigh direction and the
# shin/foot plane hint become nearly collinear. The raw two-vector frame then has
# an ill-conditioned pole axis and can flip 180 degrees between adjacent samples,
# even though the source Skeleton3D is perfectly smooth. Lower-limb pose frames
# now carry their previous projected pole axis forward, enforce hemisphere
# continuity, and progressively trust that previous axis near collinearity. This
# changes only the ambiguous twist degree of freedom; the primary segment swing,
# source handedness and Juno REST characterization remain unchanged.

const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")
const V8 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV8.gd")

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_JUNO_REST_CALIBRATED_V10"
const EPS := 0.000001
const TEMPORAL_PLANE_STABILIZATION_VERSION := 15
const PLANE_STABILITY_RATIO := 0.22
const PLANE_HARD_FALLBACK_RATIO := 0.035

const LOWER_TEMPORAL_PLANE_TARGETS := {
	"legL": true,
	"footL": true,
	"toeL": true,
	"legR": true,
	"footR": true,
	"toeR": true,
}

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

# Primary source segment controlled by each Juno node.
const SOURCE_PRIMARY := {
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

# A second segment does not change the primary swing. It only tells the solver
# which way the limb plane should face, removing the free axial twist. For the
# terminal finger/toe nodes the previous segment is used as the plane reference.
const SOURCE_PLANE_HINT := {
	"armL": ["leftforearm", "lefthand"],
	"handL": ["lefthand", "lefthandindex1"],
	"fingerL": ["leftforearm", "lefthand"],
	"armR": ["rightforearm", "righthand"],
	"handR": ["righthand", "righthandindex1"],
	"fingerR": ["rightforearm", "righthand"],
	"legL": ["leftleg", "leftfoot"],
	"footL": ["leftfoot", "lefttoebase"],
	"toeL": ["leftleg", "leftfoot"],
	"legR": ["rightleg", "rightfoot"],
	"footR": ["rightfoot", "righttoebase"],
	"toeR": ["rightleg", "rightfoot"],
}

const TARGET_PLANE_HINT := {
	"armL": "handL",
	"handL": "fingerL",
	"fingerL": "handL",
	"armR": "handR",
	"handR": "fingerR",
	"fingerR": "handR",
	"legL": "footL",
	"footL": "toeL",
	"toeL": "footL",
	"legR": "footR",
	"footR": "toeR",
	"toeR": "footR",
}

const REQUIRED_SOURCE := [
	"hips", "spine", "spine2", "neck", "head",
	"leftshoulder", "leftarm", "leftforearm", "lefthand",
	"rightshoulder", "rightarm", "rightforearm", "righthand",
	"leftupleg", "leftleg", "leftfoot",
	"rightupleg", "rightleg", "rightfoot",
]


static func run_self_test() -> Dictionary:
	var failures: Array[String] = []

	# Mixamo commonly arrives with semantic RIGHT=+X, UP=+Y and toe-forward=-Z.
	# That semantic frame is opposite-handed to a naive X cross Y = +Z frame.
	var source_value: Variant = _body_frame_from_points_with_forward_hint(
		Vector3.ZERO,
		Vector3(-1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -1.0)
	)
	# Juno's authored target convention is RIGHT=-X, UP=+Z, FORWARD=+Y.
	var target_value: Variant = _body_frame_from_points_with_forward_hint(
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 1.0, 0.0)
	)
	if source_value == null or target_value == null:
		failures.append("Could not construct synthetic source/target REST frames.")
	else:
		var source_basis: Basis = source_value as Basis
		var target_basis: Basis = target_value as Basis
		if source_basis.determinant() >= 0.0:
			failures.append("Synthetic Mixamo semantic frame did not preserve negative handedness.")
		var bridge := target_basis * source_basis.inverse()
		var mapped_forward := (bridge * Vector3(0.0, 0.0, -1.0)).normalized()
		if mapped_forward.dot(Vector3(0.0, 1.0, 0.0)) < 0.999:
			failures.append("Forward calibration still maps a forward walk backward.")

	# A two-vector frame must preserve the primary ankle direction while using the
	# toe plane to choose twist. This is the exact degree of freedom V9 left open.
	var rest_frame_value: Variant = _frame_from_primary_and_plane(
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 1.0, 0.0)
	)
	var pose_frame_value: Variant = _frame_from_primary_and_plane(
		Vector3(0.0, -1.0, 0.0),
		Vector3(0.0, 0.0, 1.0)
	)
	if rest_frame_value == null or pose_frame_value == null:
		failures.append("Could not construct synthetic ankle twist frames.")
	else:
		var rest_frame: Basis = rest_frame_value as Basis
		var pose_frame: Basis = pose_frame_value as Basis
		var solved := (pose_frame * rest_frame.inverse()).orthonormalized()
		var primary_out := (solved * Vector3(0.0, 0.0, -1.0)).normalized()
		var plane_out := (solved * Vector3(0.0, 1.0, 0.0)).normalized()
		if primary_out.dot(Vector3(0.0, -1.0, 0.0)) < 0.999:
			failures.append("Two-vector ankle solve changed the primary segment direction.")
		if plane_out.dot(Vector3(0.0, 0.0, 1.0)) < 0.999:
			failures.append("Two-vector ankle solve did not preserve the intended foot plane/twist.")

	# Regression for the user's mid-stride snap. As the knee crosses almost full
	# extension, the projected pole can change sign even though the anatomical
	# motion is continuous. The temporal frame must keep the previous hemisphere.
	var stable_a := _frame_from_primary_and_plane_stable(
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.06, 0.01),
		null
	)
	var stable_a_axis_value: Variant = stable_a.get("plane_axis", null)
	if not stable_a_axis_value is Vector3:
		failures.append("Temporal lower-limb plane self-test could not create the initial pole axis.")
	else:
		var stable_b := _frame_from_primary_and_plane_stable(
			Vector3(1.0, 0.0, 0.0),
			Vector3(1.0, -0.02, -0.003),
			stable_a_axis_value
		)
		var stable_b_axis_value: Variant = stable_b.get("plane_axis", null)
		if not stable_b_axis_value is Vector3:
			failures.append("Temporal lower-limb plane self-test lost the pole near extension.")
		elif (stable_a_axis_value as Vector3).dot(stable_b_axis_value as Vector3) <= 0.0:
			failures.append("Temporal lower-limb plane self-test still allowed a 180-degree pole flip.")

	return {
		"ok": failures.is_empty(),
		"status": "PASS" if failures.is_empty() else "FAIL",
		"failures": failures,
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
	var mode := str(settings.get("retarget_limb_mode", "target_rest_swing"))
	if mode == "full_global_delta" or mode == "segment_swing":
		return V8.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)

	var self_test := run_self_test()
	if not bool(self_test.get("ok", false)):
		push_warning("Mixamo -> Juno V10: REST calibration self-test failed: %s" % str(self_test.get("failures", [])))
		return {}
	if player == null or skeleton == null or clip_name.is_empty() or not player.has_animation(clip_name):
		return {}
	var animation := player.get_animation(clip_name)
	if animation == null:
		return {}

	var target_rest_local := V9._target_rest_local_positions(settings)
	var target_parent_map := V9._target_parent_map(settings)
	if target_rest_local.is_empty():
		push_warning("Mixamo -> Juno V10: target REST vectors unavailable; using V9 fallback.")
		return V9.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	V9._build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)
	if rotation_tracks.is_empty():
		return {}

	var rest_indexed := V9._build_global_rest(skeleton)
	var rest_semantic := V9._index_transforms_by_semantic(rest_indexed, skeleton)
	for required_name in REQUIRED_SOURCE:
		if not rest_semantic.has(required_name):
			push_warning("Mixamo -> Juno V10: missing required source bone '%s'." % required_name)
			return {}

	var source_forward_hint := _source_forward_hint(rest_semantic)
	var rest_pelvis_value: Variant = _body_frame_transforms_with_forward_hint(
		rest_semantic, "hips", "leftupleg", "rightupleg", "spine", source_forward_hint
	)
	if rest_pelvis_value == null:
		return {}
	var rest_pelvis: Basis = rest_pelvis_value as Basis
	var source_handedness := _basis_handedness(rest_pelvis)
	var rest_torso_value: Variant = _body_frame_transforms_with_handedness(
		rest_semantic, "spine2", "leftshoulder", "rightshoulder", "neck", source_handedness
	)
	if rest_torso_value == null:
		return {}
	var rest_torso: Basis = rest_torso_value as Basis

	var target_rest_global := V9._build_target_rest_global(target_rest_local, target_parent_map)
	var target_forward_hint := _target_forward_hint(target_rest_global)
	var target_pelvis_value: Variant = _body_frame_points_with_forward_hint(
		target_rest_global, "bottom", "legL", "legR", "top", target_forward_hint
	)
	if target_pelvis_value == null:
		push_warning("Mixamo -> Juno V10: could not characterize target pelvis; using V9 fallback.")
		return V9.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
	var target_pelvis: Basis = target_pelvis_value as Basis
	var target_handedness := _basis_handedness(target_pelvis)

	# Do NOT force this through a quaternion. If source and target semantic frames
	# have opposite handedness this bridge is intentionally a reflection. Vector
	# mapping remains correct, while conjugating rotations by it still yields a
	# proper rotation. This is what fixes the Mixamo moonwalk without swapping L/R.
	var source_to_target: Basis = target_pelvis * rest_pelvis.inverse()

	var target_bones := V9._target_bones(settings)
	var skip_nodes := V9._skip_nodes(settings)
	var fps := maxf(sample_fps, 1.0)
	if is_zero_approx(translation_scale):
		translation_scale = float(settings.get("root_translation_scale", 0.0))
	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var previous_angles := {}
	var previous_plane_axes := {}
	var plane_solved_counts := {}
	var swing_fallback_counts := {}
	var temporal_plane_low_confidence_counts := {}
	var temporal_plane_flip_prevent_counts := {}
	var temporal_plane_previous_blend_counts := {}

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var pose_indexed := V9._sample_global_transforms(
			animation,
			skeleton,
			rotation_tracks,
			position_tracks,
			scale_tracks,
			time
		)
		var pose_semantic := V9._index_transforms_by_semantic(pose_indexed, skeleton)
		if pose_semantic.is_empty():
			return {}

		var pose_pelvis_value: Variant = _body_frame_transforms_with_handedness(
			pose_semantic, "hips", "leftupleg", "rightupleg", "spine", source_handedness
		)
		var pose_torso_value: Variant = _body_frame_transforms_with_handedness(
			pose_semantic, "spine2", "leftshoulder", "rightshoulder", "neck", source_handedness
		)
		if pose_pelvis_value == null or pose_torso_value == null:
			return {}
		var pose_pelvis: Basis = pose_pelvis_value as Basis
		var pose_torso: Basis = pose_torso_value as Basis
		var pelvis_delta := (pose_pelvis * rest_pelvis.inverse()).orthonormalized()
		var torso_delta := (pose_torso * rest_torso.inverse()).orthonormalized()

		var target_global := {}
		target_global["root"] = Basis.IDENTITY
		target_global["bottom"] = V9._map_motion_basis(pelvis_delta, source_to_target)
		target_global["top"] = V9._map_motion_basis(torso_delta, source_to_target)

		var head_delta: Variant = V9._global_basis_motion(rest_semantic, pose_semantic, "head")
		target_global["head"] = V9._map_motion_basis(head_delta, source_to_target) if head_delta != null else target_global["top"]

		for target_value in SOURCE_PRIMARY.keys():
			var target := str(target_value)
			var previous_plane_axis: Variant = previous_plane_axes.get(target, null)
			var solved := _solve_limb_global(
				target,
				pose_semantic,
				source_to_target,
				target_rest_local,
				target_rest_global,
				target_parent_map,
				previous_plane_axis
			)
			var basis_value: Variant = solved.get("basis", null)
			if basis_value is Basis:
				target_global[target] = basis_value as Basis
				var diagnostic_key := "plane" if bool(solved.get("used_plane", false)) else "swing"
				if diagnostic_key == "plane":
					plane_solved_counts[target] = int(plane_solved_counts.get(target, 0)) + 1
				else:
					swing_fallback_counts[target] = int(swing_fallback_counts.get(target, 0)) + 1
				var plane_axis_value: Variant = solved.get("plane_axis", null)
				if plane_axis_value is Vector3:
					previous_plane_axes[target] = plane_axis_value
				if bool(solved.get("plane_low_confidence", false)):
					temporal_plane_low_confidence_counts[target] = int(temporal_plane_low_confidence_counts.get(target, 0)) + 1
				if bool(solved.get("plane_flip_prevented", false)):
					temporal_plane_flip_prevent_counts[target] = int(temporal_plane_flip_prevent_counts.get(target, 0)) + 1
				if bool(solved.get("plane_used_previous", false)):
					temporal_plane_previous_blend_counts[target] = int(temporal_plane_previous_blend_counts.get(target, 0)) + 1
			else:
				var parent_name := str(JUNO_PARENT_FALLBACK.get(target, ""))
				target_global[target] = target_global[parent_name] if target_global.has(parent_name) else Basis.IDENTITY

		var node_xfm := {}
		for target_value in CORE_TARGET_ORDER:
			var target := str(target_value)
			if not target_bones.has(target) or skip_nodes.has(target) or not target_global.has(target):
				continue
			var parent_target := V9._effective_target_parent(target, target_parent_map, target_bones, skip_nodes)
			var global_basis: Basis = target_global[target]
			var local_basis := global_basis
			if not parent_target.is_empty() and target_global.has(parent_target):
				var parent_basis: Basis = target_global[parent_target]
				local_basis = (parent_basis.inverse() * global_basis).orthonormalized()

			var angles := [0.0, 0.0, 0.0]
			if target != "root":
				var q := V9._canonical_quaternion(local_basis.get_rotation_quaternion())
				angles = V9._quaternion_to_alabaster_angles(q, settings)
				if previous_angles.has(target):
					angles = V9._unwrap_angles(angles, previous_angles[target])
				previous_angles[target] = angles.duplicate()

			var xfm := {
				"rot": angles,
				"trans": [0.0, 0.0, 0.0],
				"scale": 1.0,
			}
			if target == "root" and not is_zero_approx(translation_scale):
				var source_delta := V9._hips_translation_delta(rest_semantic, pose_semantic)
				var converted := source_to_target * source_delta * translation_scale
				xfm["trans"] = [converted.x, converted.y, converted.z]
			node_xfm[target] = xfm

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})

	print("ALABASTER_MIXAMO_V10_OK clip=%s frames=%d source_hand=%.0f target_hand=%.0f bridge_det=%.3f pole_low=%s pole_flip=%s" % [
		clip_name,
		sample_count,
		source_handedness,
		target_handedness,
		source_to_target.determinant(),
		str(temporal_plane_low_confidence_counts),
		str(temporal_plane_flip_prevent_counts),
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
			"bridge": "mixamo_juno_rest_calibrated_v10",
			"retarget_profile": PROFILE_NAME,
			"target_profile": "juno",
			"sample_fps": fps,
			"limb_transfer_mode": "target_rest_swing",
			"rest_calibration_version": 10,
			"temporal_plane_stabilization_version": TEMPORAL_PLANE_STABILIZATION_VERSION,
			"temporal_plane_policy": "lower-limb pole hemisphere continuity + previous projected pole near collinearity",
			"temporal_plane_low_confidence_counts": temporal_plane_low_confidence_counts,
			"temporal_plane_flip_prevent_counts": temporal_plane_flip_prevent_counts,
			"temporal_plane_previous_blend_counts": temporal_plane_previous_blend_counts,
			"forward_calibration": "average foot-to-toe REST direction",
			"twist_calibration": "primary segment + adjacent segment plane",
			"source_handedness": source_handedness,
			"target_handedness": target_handedness,
			"source_to_target_determinant": source_to_target.determinant(),
			"source_forward_rest": _vec3_array(source_forward_hint),
			"target_forward_rest": _vec3_array(target_forward_hint),
			"plane_solved_counts": plane_solved_counts,
			"swing_fallback_counts": swing_fallback_counts,
			"root_rotation_policy": "locked to gameplay facing; REST forward calibrates imported motion",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
		},
	}


static func _solve_limb_global(
	target: String,
	pose_semantic: Dictionary,
	source_to_target: Basis,
	target_rest_local: Dictionary,
	target_rest_global: Dictionary,
	target_parent_map: Dictionary,
	previous_plane_axis: Variant = null
) -> Dictionary:
	var primary_pair_value: Variant = SOURCE_PRIMARY.get(target, [])
	if not primary_pair_value is Array or (primary_pair_value as Array).size() < 2:
		return {}
	var primary_pair := primary_pair_value as Array
	var desired_primary := V9._source_pose_direction(
		pose_semantic,
		str(primary_pair[0]),
		str(primary_pair[1]),
		source_to_target
	)
	var target_primary := V9._target_segment_rest_direction(
		target,
		target_rest_local,
		target_rest_global,
		target_parent_map
	)
	if desired_primary.length_squared() <= EPS or target_primary.length_squared() <= EPS:
		return {}

	var plane_pair_value: Variant = SOURCE_PLANE_HINT.get(target, [])
	var target_hint_name := str(TARGET_PLANE_HINT.get(target, ""))
	if plane_pair_value is Array and (plane_pair_value as Array).size() >= 2 and not target_hint_name.is_empty():
		var plane_pair := plane_pair_value as Array
		var desired_plane := V9._source_pose_direction(
			pose_semantic,
			str(plane_pair[0]),
			str(plane_pair[1]),
			source_to_target
		)
		var target_plane := _target_rest_vector(target_hint_name, target_rest_local, target_rest_global, target_parent_map)
		if desired_plane.length_squared() > EPS and target_plane.length_squared() > EPS:
			var rest_frame_value: Variant = _frame_from_primary_and_plane(target_primary, target_plane)
			var pose_frame_value: Variant = null
			var stable_info: Dictionary = {}
			if LOWER_TEMPORAL_PLANE_TARGETS.has(target):
				stable_info = _frame_from_primary_and_plane_stable(desired_primary, desired_plane, previous_plane_axis)
				pose_frame_value = stable_info.get("basis", null)
			else:
				pose_frame_value = _frame_from_primary_and_plane(desired_primary, desired_plane)
			if rest_frame_value is Basis and pose_frame_value is Basis:
				var rest_frame: Basis = rest_frame_value as Basis
				var pose_frame: Basis = pose_frame_value as Basis
				return {
					"basis": (pose_frame * rest_frame.inverse()).orthonormalized(),
					"used_plane": true,
					"plane_axis": stable_info.get("plane_axis", null),
					"plane_ratio": float(stable_info.get("plane_ratio", 1.0)),
					"plane_low_confidence": bool(stable_info.get("low_confidence", false)),
					"plane_flip_prevented": bool(stable_info.get("flip_prevented", false)),
					"plane_used_previous": bool(stable_info.get("used_previous", false)),
				}

	var swing := Quaternion(target_primary.normalized(), desired_primary.normalized())
	return {
		"basis": Basis(V9._canonical_quaternion(swing)).orthonormalized(),
		"used_plane": false,
	}


static func _target_rest_vector(
	bone: String,
	local_positions: Dictionary,
	global_positions: Dictionary,
	parent_map: Dictionary
) -> Vector3:
	var local_value: Variant = local_positions.get(bone, null)
	if local_value is Vector3 and (local_value as Vector3).length_squared() > EPS:
		return local_value as Vector3
	var parent := str(parent_map.get(bone, JUNO_PARENT_FALLBACK.get(bone, "")))
	if global_positions.has(bone) and global_positions.has(parent):
		return (global_positions[bone] as Vector3) - (global_positions[parent] as Vector3)
	return Vector3.ZERO


static func _frame_from_primary_and_plane(primary: Vector3, plane_hint: Vector3) -> Variant:
	if primary.length_squared() <= EPS or plane_hint.length_squared() <= EPS:
		return null
	var axis_x := primary.normalized()
	var axis_y := plane_hint - axis_x * plane_hint.dot(axis_x)
	if axis_y.length_squared() <= EPS:
		return null
	axis_y = axis_y.normalized()
	var axis_z := axis_x.cross(axis_y)
	if axis_z.length_squared() <= EPS:
		return null
	axis_z = axis_z.normalized()
	axis_y = axis_z.cross(axis_x).normalized()
	return Basis(axis_x, axis_y, axis_z)


static func _frame_from_primary_and_plane_stable(
	primary: Vector3,
	plane_hint: Vector3,
	previous_plane_axis: Variant
) -> Dictionary:
	if primary.length_squared() <= EPS or plane_hint.length_squared() <= EPS:
		return {}
	var axis_x := primary.normalized()
	var raw_axis_y := plane_hint - axis_x * plane_hint.dot(axis_x)
	var plane_length := plane_hint.length()
	var raw_length := raw_axis_y.length()
	var ratio := raw_length / maxf(plane_length, EPS)

	var previous_projected := Vector3.ZERO
	var has_previous := false
	if previous_plane_axis is Vector3:
		previous_projected = previous_plane_axis as Vector3
		previous_projected -= axis_x * previous_projected.dot(axis_x)
		if previous_projected.length_squared() > EPS:
			previous_projected = previous_projected.normalized()
			has_previous = true

	var low_confidence := ratio < PLANE_STABILITY_RATIO
	var used_previous := false
	var flip_prevented := false
	var axis_y := Vector3.ZERO
	if raw_length <= EPS:
		if not has_previous:
			return {}
		axis_y = previous_projected
		used_previous = true
	else:
		axis_y = raw_axis_y / raw_length
		# A pole normal and its negation describe the same near-degenerate plane
		# numerically, but not the same twist for Juno. Keep the hemisphere that is
		# temporally closest to the preceding sample.
		if has_previous and axis_y.dot(previous_projected) < 0.0:
			axis_y = -axis_y
			flip_prevented = true
		if has_previous and low_confidence:
			var trust_raw := clampf(
				(ratio - PLANE_HARD_FALLBACK_RATIO) / maxf(PLANE_STABILITY_RATIO - PLANE_HARD_FALLBACK_RATIO, EPS),
				0.0,
				1.0
			)
			var blended := previous_projected.lerp(axis_y, trust_raw)
			if blended.length_squared() > EPS:
				axis_y = blended.normalized()
				used_previous = trust_raw < 0.999

	var axis_z := axis_x.cross(axis_y)
	if axis_z.length_squared() <= EPS:
		return {}
	axis_z = axis_z.normalized()
	axis_y = axis_z.cross(axis_x).normalized()
	return {
		"basis": Basis(axis_x, axis_y, axis_z),
		"plane_axis": axis_y,
		"plane_ratio": ratio,
		"low_confidence": low_confidence,
		"flip_prevented": flip_prevented,
		"used_previous": used_previous,
	}


static func _source_forward_hint(data: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for pair in [["leftfoot", "lefttoebase"], ["rightfoot", "righttoebase"]]:
		var a_name := str(pair[0])
		var b_name := str(pair[1])
		if not data.has(a_name) or not data.has(b_name):
			continue
		var a: Transform3D = data[a_name]
		var b: Transform3D = data[b_name]
		var direction := b.origin - a.origin
		if direction.length_squared() > EPS:
			sum += direction.normalized()
			count += 1
	return sum.normalized() if count > 0 and sum.length_squared() > EPS else Vector3.ZERO


static func _target_forward_hint(data: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for pair in [["footL", "toeL"], ["footR", "toeR"]]:
		var a_name := str(pair[0])
		var b_name := str(pair[1])
		if not data.has(a_name) or not data.has(b_name):
			continue
		var a_value: Variant = data[a_name]
		var b_value: Variant = data[b_name]
		if not a_value is Vector3 or not b_value is Vector3:
			continue
		var direction := (b_value as Vector3) - (a_value as Vector3)
		if direction.length_squared() > EPS:
			sum += direction.normalized()
			count += 1
	return sum.normalized() if count > 0 and sum.length_squared() > EPS else Vector3.ZERO


static func _body_frame_transforms_with_forward_hint(
	data: Dictionary,
	origin_name: String,
	left_name: String,
	right_name: String,
	up_name: String,
	forward_hint: Vector3
) -> Variant:
	for name in [origin_name, left_name, right_name, up_name]:
		if not data.has(name):
			return null
	return _body_frame_from_points_with_forward_hint(
		(data[origin_name] as Transform3D).origin,
		(data[left_name] as Transform3D).origin,
		(data[right_name] as Transform3D).origin,
		(data[up_name] as Transform3D).origin,
		forward_hint
	)


static func _body_frame_points_with_forward_hint(
	data: Dictionary,
	origin_name: String,
	left_name: String,
	right_name: String,
	up_name: String,
	forward_hint: Vector3
) -> Variant:
	for name in [origin_name, left_name, right_name, up_name]:
		if not data.has(name) or not data[name] is Vector3:
			return null
	return _body_frame_from_points_with_forward_hint(
		data[origin_name] as Vector3,
		data[left_name] as Vector3,
		data[right_name] as Vector3,
		data[up_name] as Vector3,
		forward_hint
	)


static func _body_frame_transforms_with_handedness(
	data: Dictionary,
	origin_name: String,
	left_name: String,
	right_name: String,
	up_name: String,
	handedness: float
) -> Variant:
	for name in [origin_name, left_name, right_name, up_name]:
		if not data.has(name):
			return null
	return _body_frame_from_points_with_handedness(
		(data[origin_name] as Transform3D).origin,
		(data[left_name] as Transform3D).origin,
		(data[right_name] as Transform3D).origin,
		(data[up_name] as Transform3D).origin,
		handedness
	)


static func _body_frame_from_points_with_forward_hint(
	origin: Vector3,
	left: Vector3,
	right: Vector3,
	up_point: Vector3,
	forward_hint: Vector3
) -> Variant:
	var base_value: Variant = _body_axes(origin, left, right, up_point)
	if not base_value is Dictionary:
		return null
	var axes := base_value as Dictionary
	var anatomical_right: Vector3 = axes["right"]
	var anatomical_up: Vector3 = axes["up"]
	var cross_forward: Vector3 = axes["cross_forward"]
	if forward_hint.length_squared() > EPS:
		var projected := forward_hint
		projected -= anatomical_right * projected.dot(anatomical_right)
		projected -= anatomical_up * projected.dot(anatomical_up)
		if projected.length_squared() > EPS and cross_forward.dot(projected) < 0.0:
			cross_forward = -cross_forward
	return Basis(anatomical_right, anatomical_up, cross_forward)


static func _body_frame_from_points_with_handedness(
	origin: Vector3,
	left: Vector3,
	right: Vector3,
	up_point: Vector3,
	handedness: float
) -> Variant:
	var base_value: Variant = _body_axes(origin, left, right, up_point)
	if not base_value is Dictionary:
		return null
	var axes := base_value as Dictionary
	var anatomical_right: Vector3 = axes["right"]
	var anatomical_up: Vector3 = axes["up"]
	var cross_forward: Vector3 = axes["cross_forward"]
	if handedness < 0.0:
		cross_forward = -cross_forward
	return Basis(anatomical_right, anatomical_up, cross_forward)


static func _body_axes(origin: Vector3, left: Vector3, right: Vector3, up_point: Vector3) -> Variant:
	var anatomical_right := right - left
	var anatomical_up := up_point - origin
	if anatomical_right.length_squared() <= EPS or anatomical_up.length_squared() <= EPS:
		return null
	anatomical_right = anatomical_right.normalized()
	anatomical_up -= anatomical_right * anatomical_up.dot(anatomical_right)
	if anatomical_up.length_squared() <= EPS:
		return null
	anatomical_up = anatomical_up.normalized()
	var cross_forward := anatomical_right.cross(anatomical_up)
	if cross_forward.length_squared() <= EPS:
		return null
	cross_forward = cross_forward.normalized()
	return {
		"right": anatomical_right,
		"up": anatomical_up,
		"cross_forward": cross_forward,
	}


static func _basis_handedness(value: Basis) -> float:
	return -1.0 if value.determinant() < 0.0 else 1.0


static func _vec3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
