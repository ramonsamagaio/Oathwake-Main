extends RefCounted
class_name AlabasterMixamoRetargetV8

# Mixamo -> Juno semantic retarget V8.
#
# V7 proved that the reliable source is the imported animation tracks composed
# through the real Skeleton3D parent/rest hierarchy. V8 keeps that deterministic
# REST -> POSE solve, but stops pretending the target is Default/Dummy.
#
# Juno is a 2D/2.5D figure driven by hierarchical 3D transforms. Her visible
# limbs use arm/hand/finger and leg/foot/toe chains, while shoulder*/hip* nodes
# can exist as attachment pivots. V8 therefore solves motion in a canonical
# global anatomical space first and only then projects it into Juno's effective
# target hierarchy.

const TICK_RATE := 60.0
const PROFILE_NAME := "MIXAMO_JUNO_SEMANTIC_REST_DELTA_V8"
const EPS := 0.000001

const TARGET_ANATOMICAL_RIGHT := Vector3(-1.0, 0.0, 0.0)
const TARGET_ANATOMICAL_UP := Vector3(0.0, 0.0, 1.0)
const TARGET_ANATOMICAL_FORWARD := Vector3(0.0, 1.0, 0.0)

const ATTACHMENT_PIVOTS := ["shoulderL", "shoulderR", "hipL", "hipR"]

const CORE_TARGET_ORDER := [
	"root", "bottom", "top", "head",
	"armL", "handL", "fingerL",
	"armR", "handR", "fingerR",
	"legL", "footL", "toeL",
	"legR", "footR", "toeR",
]

# Effective Juno animation hierarchy after attachment pivots are left at their
# authored/rest transforms. Runtime parent maps supplied by BonesSystem override
# this fallback whenever available.
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

const SOURCE_ROTATION_BONE := {
	"armL": "leftarm",
	"handL": "leftforearm",
	"fingerL": "lefthand",
	"armR": "rightarm",
	"handR": "rightforearm",
	"fingerR": "righthand",
	"legL": "leftupleg",
	"footL": "leftleg",
	"toeL": "leftfoot",
	"legR": "rightupleg",
	"footR": "rightleg",
	"toeR": "rightfoot",
}

const REQUIRED_SOURCE := [
	"hips", "spine", "spine2", "neck", "head",
	"leftshoulder", "leftarm", "leftforearm", "lefthand",
	"rightshoulder", "rightarm", "rightforearm", "righthand",
	"leftupleg", "leftleg", "leftfoot",
	"rightupleg", "rightleg", "rightfoot",
]

const OPTIONAL_SOURCE := [
	"spine1",
	"lefthandindex1", "righthandindex1",
	"lefttoebase", "righttoebase",
]

const AUDIT_TRACK_BONES := [
	"hips", "spine", "spine1", "spine2", "neck", "head",
	"leftshoulder", "leftarm", "leftforearm", "lefthand",
	"rightshoulder", "rightarm", "rightforearm", "righthand",
	"leftupleg", "leftleg", "leftfoot", "lefttoebase",
	"rightupleg", "rightleg", "rightfoot", "righttoebase",
]


static func run_self_test() -> Dictionary:
	var failures: Array[String] = []
	var neutral := {
		"yaw_scale": 1.0,
		"pitch_scale": 1.0,
		"roll_scale": 1.0,
		"yaw_correction_degrees": 0.0,
		"pitch_correction_degrees": 0.0,
		"roll_correction_degrees": 0.0,
		"top_down_mode": false,
	}
	var samples := [
		[0.0, 0.0, 0.0],
		[35.0, -20.0, 15.0],
		[-80.0, 45.0, -30.0],
		[120.0, 10.0, 70.0],
	]
	for angles_value in samples:
		var q1 := _angles_to_quaternion(angles_value)
		var roundtrip_angles := _quaternion_to_alabaster_angles(q1, neutral)
		var q2 := _angles_to_quaternion(roundtrip_angles)
		var dot_value := absf(q1.normalized().dot(q2.normalized()))
		if dot_value < 0.9999:
			failures.append("Quaternion/source-angle roundtrip failed for %s (dot %.6f)." % [str(angles_value), dot_value])

	var rest := {
		"a": Transform3D(Basis.IDENTITY, Vector3.ZERO),
		"b": Transform3D(Basis.IDENTITY, Vector3.RIGHT),
	}
	var pose := {
		"a": Transform3D(Basis.IDENTITY, Vector3.ZERO),
		"b": Transform3D(Basis.IDENTITY, Vector3.UP),
	}
	var swing: Variant = _segment_rest_delta(rest, pose, "a", "b", Basis.IDENTITY)
	if swing == null:
		failures.append("Synthetic segment swing returned null.")
	else:
		var swing_q := _canonical_quaternion((swing as Basis).get_rotation_quaternion())
		var swing_deg := rad_to_deg(swing_q.get_angle())
		if absf(swing_deg - 90.0) > 0.1:
			failures.append("Synthetic segment swing expected 90°, got %.3f°." % swing_deg)

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
	var solved := _solve_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings, false)
	var animation_value: Variant = solved.get("animation", {})
	return (animation_value as Dictionary).duplicate(true) if animation_value is Dictionary else {}


static func build_audit(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	var solved := _solve_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings, true)
	var audit_value: Variant = solved.get("audit", {})
	return (audit_value as Dictionary).duplicate(true) if audit_value is Dictionary else {}


static func _solve_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary,
	collect_deep_audit: bool
) -> Dictionary:
	var audit := _empty_audit(clip_name)
	var self_test := run_self_test()
	audit["solver_self_test"] = self_test
	if not bool(self_test.get("ok", false)):
		_add_issue(audit, "WARN", "V8_SELF_TEST_FAILED", "Internal V8 diagnostic self-test reported: %s" % str(self_test.get("failures", [])))
	if player == null:
		_add_issue(audit, "FAIL", "NO_ANIMATION_PLAYER", "No AnimationPlayer was supplied.")
		return {"animation": {}, "audit": _finish_audit(audit)}
	if skeleton == null:
		_add_issue(audit, "FAIL", "NO_SKELETON3D", "No Skeleton3D was supplied. Full REST-space retarget is unavailable.")
		return {"animation": {}, "audit": _finish_audit(audit)}
	if clip_name.is_empty() or not player.has_animation(clip_name):
		_add_issue(audit, "FAIL", "CLIP_NOT_FOUND", "Animation clip '%s' was not found." % clip_name)
		return {"animation": {}, "audit": _finish_audit(audit)}

	var animation := player.get_animation(clip_name)
	if animation == null:
		_add_issue(audit, "FAIL", "NULL_ANIMATION", "AnimationPlayer returned a null Animation resource.")
		return {"animation": {}, "audit": _finish_audit(audit)}

	var fps := maxf(sample_fps, 1.0)
	if is_zero_approx(translation_scale):
		translation_scale = float(settings.get("root_translation_scale", 0.0))
	var bone_index := _build_bone_index(skeleton)
	var duplicate_names := _duplicate_normalized_bones(skeleton)
	var missing_required := _missing_names(bone_index, REQUIRED_SOURCE)
	var missing_optional := _missing_names(bone_index, OPTIONAL_SOURCE)

	audit["source_bone_count"] = skeleton.get_bone_count()
	audit["source_root_bones"] = _root_bone_names(skeleton)
	audit["duplicate_normalized_bones"] = duplicate_names
	audit["missing_required_source"] = missing_required
	audit["missing_optional_source"] = missing_optional
	audit["clip_length_seconds"] = animation.length
	audit["sample_fps"] = fps

	if not duplicate_names.is_empty():
		_add_issue(audit, "FAIL", "DUPLICATE_NORMALIZED_BONES", "Multiple source bones collapse to the same normalized Mixamo name: %s" % str(duplicate_names))
	if not missing_required.is_empty():
		_add_issue(audit, "FAIL", "MISSING_REQUIRED_SOURCE", "Required Mixamo bones are missing: %s" % _join_names(missing_required))
		return {"animation": {}, "audit": _finish_audit(audit)}
	if not missing_optional.is_empty():
		_add_issue(audit, "WARN", "MISSING_OPTIONAL_SOURCE", "Optional finger/toe/spine helper bones are missing: %s" % _join_names(missing_optional))

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	var duplicate_tracks := {}
	_build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks, duplicate_tracks)
	audit["rotation_track_count"] = rotation_tracks.size()
	audit["position_track_count"] = position_tracks.size()
	audit["scale_track_count"] = scale_tracks.size()
	audit["duplicate_semantic_tracks"] = duplicate_tracks

	if rotation_tracks.is_empty():
		_add_issue(audit, "FAIL", "NO_ROTATION_TRACKS", "The selected clip contains no Skeleton3D rotation tracks.")
		return {"animation": {}, "audit": _finish_audit(audit)}
	if not duplicate_tracks.is_empty():
		_add_issue(audit, "WARN", "DUPLICATE_TRACKS", "More than one transform track maps to the same normalized bone/channel: %s" % str(duplicate_tracks))

	var rest_indexed := _build_global_rest(skeleton)
	var rest_semantic := _index_transforms_by_semantic(rest_indexed, skeleton)
	var rest_pelvis_value: Variant = _body_frame(rest_semantic, "hips", "leftupleg", "rightupleg", "spine")
	var rest_torso_value: Variant = _body_frame(rest_semantic, "spine2", "leftshoulder", "rightshoulder", "neck")
	if rest_pelvis_value == null or rest_torso_value == null:
		_add_issue(audit, "FAIL", "INVALID_REST_FRAME", "Could not construct pelvis/torso anatomical frames from the source REST pose.")
		return {"animation": {}, "audit": _finish_audit(audit)}

	var rest_pelvis: Basis = rest_pelvis_value
	var rest_torso: Basis = rest_torso_value
	var target_anatomical := Basis(
		TARGET_ANATOMICAL_RIGHT,
		TARGET_ANATOMICAL_UP,
		TARGET_ANATOMICAL_FORWARD
	).orthonormalized()
	var source_to_target := (target_anatomical * rest_pelvis.inverse()).orthonormalized()

	var target_bones := _resolve_target_bones(settings)
	var target_parent_map := _resolve_target_parent_map(settings)
	var skip_nodes := _resolve_skip_nodes(settings)
	var target_validation := _validate_target(target_bones, target_parent_map, skip_nodes)
	audit["target_validation"] = target_validation
	for issue_value in target_validation.get("issues", []):
		if issue_value is Dictionary:
			audit["issues"].append((issue_value as Dictionary).duplicate(true))
	if bool(target_validation.get("fatal", false)):
		return {"animation": {}, "audit": _finish_audit(audit)}

	if collect_deep_audit:
		_append_rest_audit(audit, skeleton, rest_indexed)
		_append_track_audit(audit, animation, rotation_tracks, position_tracks, scale_tracks, fps)

	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var sample_count := frame_count if loop else frame_count + 1
	var transforms: Array = []
	var previous_angles := {}
	var output_metrics := _new_output_metrics()
	var source_metrics := {}
	var source_twist_metrics := {}
	var first_pose_semantic := {}
	var frame_diagnostics: Array = []

	for frame in range(sample_count):
		var time := minf(float(frame) / fps, animation.length)
		var pose_indexed := _sample_global_transforms_manual(
			animation,
			skeleton,
			rotation_tracks,
			position_tracks,
			scale_tracks,
			time
		)
		var pose_semantic := _index_transforms_by_semantic(pose_indexed, skeleton)
		if pose_semantic.is_empty():
			_add_issue(audit, "FAIL", "EMPTY_POSE", "Source pose sampling returned no transforms at frame %d." % frame)
			return {"animation": {}, "audit": _finish_audit(audit)}

		if first_pose_semantic.is_empty():
			first_pose_semantic = pose_semantic.duplicate(true)

		var source_global := _build_semantic_global_delta(
			rest_semantic,
			pose_semantic,
			rest_pelvis,
			rest_torso,
			source_to_target,
			settings
		)
		if source_global.is_empty():
			_add_issue(audit, "FAIL", "SEMANTIC_SOLVE_FAILED", "Could not solve semantic global motion at frame %d." % frame)
			return {"animation": {}, "audit": _finish_audit(audit)}

		# Juno's root facing is a separate gameplay/runtime concept. Imported
		# pelvis orientation is transferred to bottom, while root remains neutral.
		source_global["root"] = Basis.IDENTITY

		var node_xfm := {}
		var frame_row := {"frame": frame, "time": time, "targets": {}}
		for target_value in CORE_TARGET_ORDER:
			var target := str(target_value)
			if not target_bones.has(target):
				continue
			if skip_nodes.has(target):
				continue
			if not source_global.has(target):
				continue

			var parent_target := _effective_target_parent(target, target_parent_map, target_bones, skip_nodes)
			var global_basis: Basis = source_global[target]
			var local_basis := global_basis
			if not parent_target.is_empty() and source_global.has(parent_target):
				var parent_basis: Basis = source_global[parent_target]
				local_basis = (parent_basis.inverse() * global_basis).orthonormalized()

			var q := _canonical_quaternion(local_basis.get_rotation_quaternion())
			var angles := [0.0, 0.0, 0.0]
			if target != "root":
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
			_update_output_metrics(output_metrics, target, q, xfm, frame)

			if collect_deep_audit:
				var source_swing := _source_target_swing_degrees(
					target,
					rest_semantic,
					pose_semantic,
					source_to_target
				)
				var source_twist := _source_target_twist_residual_degrees(
					target,
					rest_semantic,
					pose_semantic,
					source_to_target
				)
				_update_source_metric(source_metrics, target, source_swing)
				_update_source_metric(source_twist_metrics, target, source_twist)
				frame_row["targets"][target] = {
					"source_swing_deg": snappedf(source_swing, 0.01),
					"source_twist_residual_deg": snappedf(source_twist, 0.01),
					"yaw": snappedf(float(angles[0]), 0.01),
					"pitch": snappedf(float(angles[1]), 0.01),
					"roll": snappedf(float(angles[2]), 0.01),
					"parent": parent_target,
				}

		transforms.append({
			"frame": frame,
			"spline": str(settings.get("spline", "LINEAR")),
			"nodeXfm": node_xfm,
		})
		if collect_deep_audit:
			frame_diagnostics.append(frame_row)

	var animation_result := {
		"category": str(settings.get("category", "DEFAULT")),
		"frameCnt": frame_count,
		"frameRepeat": TICK_RATE / fps,
		"animStart": 0,
		"loopStart": 0,
		"repeat": loop,
		"transforms": transforms,
		"nodes": {},
		"import_meta": {
			"bridge": "mixamo_track_hierarchy_rest_delta_to_juno_v8",
			"retarget_profile": PROFILE_NAME,
			"target_profile": "juno",
			"sample_fps": fps,
			"source_rest": "Skeleton3D local Bone Rest composed through parent hierarchy",
			"source_pose": "Animation 3D transform tracks composed through Skeleton3D parent hierarchy",
			"semantic_space": "global anatomical REST->POSE delta",
			"limb_transfer_mode": str(settings.get("retarget_limb_mode", "full_global_delta")),
			"root_rotation_policy": "locked; pelvis orientation transferred to bottom",
			"attachment_policy": "shoulder/hip attachment pivots left at authored rest unless explicitly enabled",
			"root_translation_scale": translation_scale,
			"terminal_frame_excluded_for_loop": loop,
			"output_metrics": _finalize_output_metrics(output_metrics),
		},
	}

	audit["output"] = _finalize_output_metrics(output_metrics)
	audit["source_motion"] = _rounded_number_dictionary(source_metrics)
	audit["source_twist_residual"] = _rounded_number_dictionary(source_twist_metrics)
	audit["frame_count"] = frame_count
	audit["sample_count"] = sample_count
	audit["frame_diagnostics"] = frame_diagnostics
	_append_motion_loss_issues(audit)
	_append_output_issues(audit)
	_finish_audit(audit)

	print("ALABASTER_MIXAMO_V8_OK clip=%s frames=%d source_bones=%d target_bones=%d status=%s" % [
		clip_name,
		sample_count,
		skeleton.get_bone_count(),
		target_bones.size(),
		str(audit.get("status", "UNKNOWN")),
	])

	return {"animation": animation_result, "audit": audit}


static func _build_semantic_global_delta(
	rest_global: Dictionary,
	pose_global: Dictionary,
	rest_pelvis: Basis,
	rest_torso: Basis,
	source_to_target: Basis,
	settings: Dictionary
) -> Dictionary:
	var result := {}
	var pose_pelvis_value: Variant = _body_frame(pose_global, "hips", "leftupleg", "rightupleg", "spine")
	var pose_torso_value: Variant = _body_frame(pose_global, "spine2", "leftshoulder", "rightshoulder", "neck")
	if pose_pelvis_value == null or pose_torso_value == null:
		return result

	var pose_pelvis: Basis = pose_pelvis_value
	var pose_torso: Basis = pose_torso_value
	var pelvis_delta := (pose_pelvis * rest_pelvis.inverse()).orthonormalized()
	var torso_delta := (pose_torso * rest_torso.inverse()).orthonormalized()

	result["root"] = _map_motion_basis(pelvis_delta, source_to_target)
	result["bottom"] = result["root"]
	result["top"] = _map_motion_basis(torso_delta, source_to_target)

	var head_delta: Variant = _global_basis_motion(rest_global, pose_global, "head")
	result["head"] = _map_motion_basis(head_delta, source_to_target) if head_delta != null else result["top"]

	var limb_mode := str(settings.get("retarget_limb_mode", "full_global_delta"))
	for target_value in SOURCE_SEGMENT.keys():
		var target := str(target_value)
		var solved_basis: Variant = null
		if limb_mode == "full_global_delta" and SOURCE_ROTATION_BONE.has(target):
			var source_bone := str(SOURCE_ROTATION_BONE[target])
			var full_delta: Variant = _global_basis_motion(rest_global, pose_global, source_bone)
			if full_delta != null:
				solved_basis = _map_motion_basis(full_delta, source_to_target)
		if solved_basis == null:
			var pair: Array = SOURCE_SEGMENT[target]
			solved_basis = _segment_rest_delta(
				rest_global,
				pose_global,
				str(pair[0]),
				str(pair[1]),
				source_to_target
			)
		if solved_basis != null:
			result[target] = solved_basis
		else:
			var fallback_parent := str(JUNO_PARENT_FALLBACK.get(target, ""))
			result[target] = result[fallback_parent] if result.has(fallback_parent) else Basis.IDENTITY
	return result


static func _resolve_target_bones(settings: Dictionary) -> Array[String]:
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


static func _resolve_target_parent_map(settings: Dictionary) -> Dictionary:
	var value: Variant = settings.get("target_parent_map", {})
	if value is Dictionary and not (value as Dictionary).is_empty():
		return (value as Dictionary).duplicate(true)
	return JUNO_PARENT_FALLBACK.duplicate(true)


static func _resolve_skip_nodes(settings: Dictionary) -> Dictionary:
	var result := {}
	var value: Variant = settings.get("retarget_skip_attachment_nodes", ATTACHMENT_PIVOTS)
	if value is Array:
		for item in value:
			result[str(item)] = true
	for name in ATTACHMENT_PIVOTS:
		if not result.has(name):
			result[name] = true
	return result


static func _validate_target(target_bones: Array[String], parent_map: Dictionary, skip_nodes: Dictionary) -> Dictionary:
	var issues: Array = []
	var fatal := false
	var required := ["root", "bottom", "top", "head", "armL", "handL", "armR", "handR", "legL", "footL", "legR", "footR"]
	var optional := ["fingerL", "fingerR", "toeL", "toeR"]
	var missing_required: Array[String] = []
	var missing_optional: Array[String] = []
	for name in required:
		if not target_bones.has(name):
			missing_required.append(name)
	for name in optional:
		if not target_bones.has(name):
			missing_optional.append(name)

	if not missing_required.is_empty():
		fatal = true
		issues.append({
			"severity": "FAIL",
			"code": "MISSING_JUNO_TARGETS",
			"message": "Juno target rig is missing core nodes: %s" % _join_names(missing_required),
		})
	if not missing_optional.is_empty():
		issues.append({
			"severity": "WARN",
			"code": "MISSING_JUNO_OPTIONAL",
			"message": "Juno target rig has no optional finger/toe nodes: %s" % _join_names(missing_optional),
		})

	var cycles := _find_parent_cycles(parent_map)
	if not cycles.is_empty():
		fatal = true
		issues.append({
			"severity": "FAIL",
			"code": "TARGET_PARENT_CYCLE",
			"message": "Target parent map contains a cycle: %s" % str(cycles),
		})

	var effective := {}
	for target in CORE_TARGET_ORDER:
		if target_bones.has(target) and not skip_nodes.has(target):
			effective[target] = _effective_target_parent(target, parent_map, target_bones, skip_nodes)

	return {
		"fatal": fatal,
		"missing_required": missing_required,
		"missing_optional": missing_optional,
		"effective_parent_map": effective,
		"skipped_attachment_nodes": skip_nodes.keys(),
		"issues": issues,
	}


static func _effective_target_parent(
	target: String,
	parent_map: Dictionary,
	target_bones: Array[String],
	skip_nodes: Dictionary
) -> String:
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


static func _find_parent_cycles(parent_map: Dictionary) -> Array:
	var cycles: Array = []
	for node_value in parent_map.keys():
		var node := str(node_value)
		var current := node
		var path: Array[String] = []
		var seen := {}
		while not current.is_empty() and parent_map.has(current):
			if seen.has(current):
				path.append(current)
				cycles.append(path)
				break
			seen[current] = true
			path.append(current)
			current = str(parent_map.get(current, ""))
	return cycles


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


static func _sample_global_transforms_manual(
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
	scale_tracks: Dictionary,
	duplicate_tracks: Dictionary
) -> void:
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_SCALE_3D:
			continue
		var semantic := normalize(_bone_name_from_track_path(animation.track_get_path(track_index)))
		if semantic.is_empty():
			continue
		var channel := ""
		var target_dict := {}
		match track_type:
			Animation.TYPE_ROTATION_3D:
				channel = "rotation"
				target_dict = rotation_tracks
			Animation.TYPE_POSITION_3D:
				channel = "position"
				target_dict = position_tracks
			Animation.TYPE_SCALE_3D:
				channel = "scale"
				target_dict = scale_tracks
		var duplicate_key := "%s:%s" % [semantic, channel]
		if target_dict.has(semantic):
			if not duplicate_tracks.has(duplicate_key):
				duplicate_tracks[duplicate_key] = [target_dict[semantic]]
			duplicate_tracks[duplicate_key].append(track_index)
		target_dict[semantic] = track_index


static func _build_bone_index(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		if not semantic.is_empty() and not result.has(semantic):
			result[semantic] = bone_index
	return result


static func _duplicate_normalized_bones(skeleton: Skeleton3D) -> Dictionary:
	var seen := {}
	var duplicates := {}
	for bone_index in range(skeleton.get_bone_count()):
		var original := str(skeleton.get_bone_name(bone_index))
		var semantic := normalize(original)
		if semantic.is_empty():
			continue
		if seen.has(semantic):
			if not duplicates.has(semantic):
				duplicates[semantic] = [seen[semantic]]
			duplicates[semantic].append(original)
		else:
			seen[semantic] = original
	return duplicates


static func _root_bone_names(skeleton: Skeleton3D) -> Array[String]:
	var roots: Array[String] = []
	for bone_index in range(skeleton.get_bone_count()):
		if skeleton.get_bone_parent(bone_index) < 0:
			roots.append(str(skeleton.get_bone_name(bone_index)))
	return roots


static func _index_transforms_by_semantic(indexed: Dictionary, skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for bone_index_value in indexed.keys():
		var bone_index := int(bone_index_value)
		var semantic := normalize(skeleton.get_bone_name(bone_index))
		if not semantic.is_empty() and not result.has(semantic):
			result[semantic] = indexed[bone_index_value]
	return result


static func _body_frame(
	data: Dictionary,
	origin_name: String,
	left_name: String,
	right_name: String,
	up_name: String
) -> Variant:
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


static func _segment_rest_delta(
	rest_global: Dictionary,
	pose_global: Dictionary,
	source_start: String,
	source_end: String,
	source_to_target: Basis
) -> Variant:
	if not rest_global.has(source_start) or not rest_global.has(source_end):
		return null
	if not pose_global.has(source_start) or not pose_global.has(source_end):
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


static func _source_target_swing_degrees(
	target: String,
	rest_global: Dictionary,
	pose_global: Dictionary,
	source_to_target: Basis
) -> float:
	if not SOURCE_SEGMENT.has(target):
		return 0.0
	var pair: Array = SOURCE_SEGMENT[target]
	var swing: Variant = _segment_rest_delta(
		rest_global,
		pose_global,
		str(pair[0]),
		str(pair[1]),
		source_to_target
	)
	if swing == null:
		return 0.0
	var q := _canonical_quaternion((swing as Basis).get_rotation_quaternion())
	return rad_to_deg(q.get_angle())


static func _source_target_twist_residual_degrees(
	target: String,
	rest_global: Dictionary,
	pose_global: Dictionary,
	source_to_target: Basis
) -> float:
	if not SOURCE_ROTATION_BONE.has(target) or not SOURCE_SEGMENT.has(target):
		return 0.0
	var source_bone := str(SOURCE_ROTATION_BONE[target])
	var full_delta: Variant = _global_basis_motion(rest_global, pose_global, source_bone)
	if full_delta == null:
		return 0.0
	var pair: Array = SOURCE_SEGMENT[target]
	var swing: Variant = _segment_rest_delta(
		rest_global,
		pose_global,
		str(pair[0]),
		str(pair[1]),
		source_to_target
	)
	if swing == null:
		return 0.0
	var mapped_full := _map_motion_basis(full_delta, source_to_target)
	var residual := ((swing as Basis).inverse() * mapped_full).orthonormalized()
	var q := _canonical_quaternion(residual.get_rotation_quaternion())
	return rad_to_deg(q.get_angle())


static func _map_motion_basis(source_motion_value: Variant, source_to_target: Basis) -> Basis:
	var source_motion: Basis = source_motion_value
	return (source_to_target * source_motion * source_to_target.inverse()).orthonormalized()


static func _global_basis_motion(rest_global: Dictionary, pose_global: Dictionary, bone_name: String) -> Variant:
	if not rest_global.has(bone_name) or not pose_global.has(bone_name):
		return null
	var rest_xfm: Transform3D = rest_global[bone_name]
	var pose_xfm: Transform3D = pose_global[bone_name]
	return (
		pose_xfm.basis.orthonormalized()
		* rest_xfm.basis.orthonormalized().inverse()
	).orthonormalized()


static func _hips_translation_delta(rest_global: Dictionary, pose_global: Dictionary) -> Vector3:
	if not rest_global.has("hips") or not pose_global.has("hips"):
		return Vector3.ZERO
	return (pose_global["hips"] as Transform3D).origin - (rest_global["hips"] as Transform3D).origin


static func _missing_names(index: Dictionary, names: Array) -> Array[String]:
	var result: Array[String] = []
	for name_value in names:
		var name := str(name_value)
		if not index.has(name):
			result.append(name)
	return result


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


static func _angles_to_quaternion(angles_value: Variant) -> Quaternion:
	if not angles_value is Array:
		return Quaternion.IDENTITY
	var angles: Array = angles_value
	if angles.size() < 3:
		return Quaternion.IDENTITY
	var x := deg_to_rad(float(angles[1])) * 0.5
	var y := deg_to_rad(float(angles[2])) * 0.5
	var z := deg_to_rad(float(angles[0])) * 0.5
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


static func _new_output_metrics() -> Dictionary:
	return {
		"first_q": {},
		"previous_q": {},
		"motion_span_deg": {},
		"max_step_deg": {},
		"max_step_frame": {},
		"max_abs_angle_deg": {},
		"max_root_translation": 0.0,
	}


static func _update_output_metrics(
	metrics: Dictionary,
	target: String,
	q: Quaternion,
	xfm: Dictionary,
	frame: int
) -> void:
	var first_q: Dictionary = metrics["first_q"]
	var previous_q: Dictionary = metrics["previous_q"]
	var span: Dictionary = metrics["motion_span_deg"]
	var max_step: Dictionary = metrics["max_step_deg"]
	var max_step_frame: Dictionary = metrics["max_step_frame"]
	var max_abs: Dictionary = metrics["max_abs_angle_deg"]

	if not first_q.has(target):
		first_q[target] = q
		span[target] = 0.0
	else:
		var first: Quaternion = first_q[target]
		var dot_first := clampf(absf(first.dot(q)), 0.0, 1.0)
		span[target] = maxf(float(span.get(target, 0.0)), rad_to_deg(2.0 * acos(dot_first)))

	if previous_q.has(target):
		var prev: Quaternion = previous_q[target]
		var dot_step := clampf(absf(prev.dot(q)), 0.0, 1.0)
		var step_deg := rad_to_deg(2.0 * acos(dot_step))
		if step_deg > float(max_step.get(target, 0.0)):
			max_step[target] = step_deg
			max_step_frame[target] = frame
	previous_q[target] = q

	var angle_deg := rad_to_deg(q.get_angle())
	max_abs[target] = maxf(float(max_abs.get(target, 0.0)), absf(angle_deg))

	if target == "root":
		var trans_value: Variant = xfm.get("trans", [0.0, 0.0, 0.0])
		if trans_value is Array and (trans_value as Array).size() >= 3:
			var trans: Array = trans_value
			var v := Vector3(float(trans[0]), float(trans[1]), float(trans[2]))
			metrics["max_root_translation"] = maxf(float(metrics.get("max_root_translation", 0.0)), v.length())


static func _finalize_output_metrics(metrics: Dictionary) -> Dictionary:
	return {
		"motion_span_deg": _rounded_number_dictionary(metrics.get("motion_span_deg", {})),
		"max_step_deg": _rounded_number_dictionary(metrics.get("max_step_deg", {})),
		"max_step_frame": (metrics.get("max_step_frame", {}) as Dictionary).duplicate(true),
		"max_abs_angle_deg": _rounded_number_dictionary(metrics.get("max_abs_angle_deg", {})),
		"max_root_translation": snappedf(float(metrics.get("max_root_translation", 0.0)), 0.0001),
	}


static func _rounded_number_dictionary(value: Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary:
		return result
	for key in (value as Dictionary).keys():
		result[key] = snappedf(float((value as Dictionary)[key]), 0.01)
	return result


static func _update_source_metric(metrics: Dictionary, target: String, swing_deg: float) -> void:
	metrics[target] = maxf(float(metrics.get(target, 0.0)), swing_deg)


static func _append_motion_loss_issues(audit: Dictionary) -> void:
	var source_value: Variant = audit.get("source_motion", {})
	var output_value: Variant = audit.get("output", {})
	if not source_value is Dictionary or not output_value is Dictionary:
		return
	var source: Dictionary = source_value
	var output: Dictionary = output_value
	var span_value: Variant = output.get("motion_span_deg", {})
	if not span_value is Dictionary:
		return
	var spans: Dictionary = span_value
	for target_value in SOURCE_SEGMENT.keys():
		var target := str(target_value)
		var source_span := float(source.get(target, 0.0))
		var output_span := float(spans.get(target, 0.0))
		if source_span >= 5.0 and output_span < 0.75:
			_add_issue(
				audit,
				"WARN",
				"MOTION_LOST_%s" % target.to_upper(),
				"%s moves %.1f° in the source but only %.1f° reaches Juno." % [target, source_span, output_span]
			)


static func _append_output_issues(audit: Dictionary) -> void:
	var output_value: Variant = audit.get("output", {})
	if not output_value is Dictionary:
		return
	var output: Dictionary = output_value
	var max_step_value: Variant = output.get("max_step_deg", {})
	if max_step_value is Dictionary:
		for target_value in (max_step_value as Dictionary).keys():
			var target := str(target_value)
			var step := float((max_step_value as Dictionary)[target_value])
			if step > 120.0:
				var frame := int((output.get("max_step_frame", {}) as Dictionary).get(target, -1))
				_add_issue(
					audit,
					"WARN",
					"OUTPUT_JUMP_%s" % target.to_upper(),
					"%s changes %.1f° in one sampled frame at frame %d. This usually indicates axis/rest discontinuity." % [target, step, frame]
				)
	var max_abs_value: Variant = output.get("max_abs_angle_deg", {})
	if max_abs_value is Dictionary:
		for target_value in (max_abs_value as Dictionary).keys():
			var target := str(target_value)
			var angle := float((max_abs_value as Dictionary)[target_value])
			if angle > 175.0 and target != "root":
				_add_issue(
					audit,
					"WARN",
					"NEAR_180_%s" % target.to_upper(),
					"%s approaches %.1f°. Inspect this joint for Euler wrapping or an inverted local axis." % [target, angle]
				)


static func _append_rest_audit(audit: Dictionary, skeleton: Skeleton3D, rest_indexed: Dictionary) -> void:
	var non_uniform: Array = []
	var reflected: Array = []
	var tiny_segments: Array = []
	for bone_index in range(skeleton.get_bone_count()):
		var name := str(skeleton.get_bone_name(bone_index))
		var rest := skeleton.get_bone_rest(bone_index)
		var scale := rest.basis.get_scale().abs()
		var min_scale := minf(scale.x, minf(scale.y, scale.z))
		var max_scale := maxf(scale.x, maxf(scale.y, scale.z))
		if min_scale > EPS and max_scale / min_scale > 1.05:
			non_uniform.append({"bone": name, "scale": [scale.x, scale.y, scale.z]})
		if rest.basis.determinant() < 0.0:
			reflected.append(name)

		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index >= 0 and rest_indexed.has(parent_index) and rest_indexed.has(bone_index):
			var parent_global: Transform3D = rest_indexed[parent_index]
			var child_global: Transform3D = rest_indexed[bone_index]
			var length := parent_global.origin.distance_to(child_global.origin)
			if length <= 0.0001:
				tiny_segments.append(name)

	audit["rest_non_uniform_scale"] = non_uniform
	audit["rest_reflected_bones"] = reflected
	audit["rest_tiny_segments"] = tiny_segments

	if not non_uniform.is_empty():
		_add_issue(audit, "WARN", "NON_UNIFORM_REST_SCALE", "Source REST has non-uniform bone scale on %d bones." % non_uniform.size())
	if not reflected.is_empty():
		_add_issue(audit, "WARN", "REFLECTED_REST_BASIS", "Source REST contains negative-determinant/reflected bases: %s" % _join_names(reflected))
	if not tiny_segments.is_empty():
		_add_issue(audit, "WARN", "TINY_REST_SEGMENTS", "Near-zero parent/child REST segments were found: %s" % _join_names(tiny_segments))


static func _append_track_audit(
	audit: Dictionary,
	animation: Animation,
	rotation_tracks: Dictionary,
	position_tracks: Dictionary,
	scale_tracks: Dictionary,
	fps: float
) -> void:
	var rotation_span := {}
	var max_rotation_step := {}
	var max_rotation_step_frame := {}
	var root_position_span := 0.0
	var scale_span := {}

	var sample_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 2)
	for semantic in AUDIT_TRACK_BONES:
		if rotation_tracks.has(semantic):
			var track := int(rotation_tracks[semantic])
			var first: Quaternion = animation.rotation_track_interpolate(track, 0.0).normalized()
			var previous := first
			var max_span := 0.0
			var max_step := 0.0
			var max_step_at := 0
			for frame in range(sample_count):
				var t := minf(float(frame) / fps, animation.length)
				var q: Quaternion = animation.rotation_track_interpolate(track, t).normalized()
				var dot_first := clampf(absf(first.dot(q)), 0.0, 1.0)
				max_span = maxf(max_span, rad_to_deg(2.0 * acos(dot_first)))
				var dot_step := clampf(absf(previous.dot(q)), 0.0, 1.0)
				var step := rad_to_deg(2.0 * acos(dot_step))
				if step > max_step:
					max_step = step
					max_step_at = frame
				previous = q
			rotation_span[semantic] = snappedf(max_span, 0.01)
			max_rotation_step[semantic] = snappedf(max_step, 0.01)
			max_rotation_step_frame[semantic] = max_step_at

	if position_tracks.has("hips"):
		var hips_track := int(position_tracks["hips"])
		var p0: Vector3 = animation.position_track_interpolate(hips_track, 0.0)
		for frame in range(sample_count):
			var t := minf(float(frame) / fps, animation.length)
			var p: Vector3 = animation.position_track_interpolate(hips_track, t)
			root_position_span = maxf(root_position_span, p.distance_to(p0))

	for semantic_value in scale_tracks.keys():
		var semantic := str(semantic_value)
		var track := int(scale_tracks[semantic_value])
		var s0: Vector3 = animation.scale_track_interpolate(track, 0.0)
		var max_delta := 0.0
		for frame in range(sample_count):
			var t := minf(float(frame) / fps, animation.length)
			var scale_now: Vector3 = animation.scale_track_interpolate(track, t)
			max_delta = maxf(max_delta, (scale_now - s0).length())
		scale_span[semantic] = snappedf(max_delta, 0.0001)

	audit["source_rotation_span_deg"] = rotation_span
	audit["source_max_rotation_step_deg"] = max_rotation_step
	audit["source_max_rotation_step_frame"] = max_rotation_step_frame
	audit["source_root_position_span"] = snappedf(root_position_span, 0.0001)
	audit["source_scale_track_span"] = scale_span

	for semantic_value in max_rotation_step.keys():
		var semantic := str(semantic_value)
		var step := float(max_rotation_step[semantic_value])
		if step > 120.0:
			_add_issue(
				audit,
				"WARN",
				"SOURCE_JUMP_%s" % semantic.to_upper(),
				"Source %s changes %.1f° in one sampled frame at frame %d." % [
					semantic,
					step,
					int(max_rotation_step_frame.get(semantic, -1)),
				]
			)

	for semantic_value in scale_span.keys():
		if float(scale_span[semantic_value]) > 0.02:
			_add_issue(
				audit,
				"WARN",
				"ANIMATED_SCALE_%s" % str(semantic_value).to_upper(),
				"Source bone %s contains animated scale (span %.4f). Juno V8 intentionally ignores scale motion." % [
					str(semantic_value),
					float(scale_span[semantic_value]),
				]
			)


static func _join_names(values: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value in values:
		parts.append(str(value))
	return ", ".join(parts)


static func _empty_audit(clip_name: String) -> Dictionary:
	return {
		"ok": false,
		"status": "FAIL",
		"profile": PROFILE_NAME,
		"clip": clip_name,
		"issues": [],
		"frame_diagnostics": [],
	}


static func _add_issue(audit: Dictionary, severity: String, code: String, message: String) -> void:
	var issues_value: Variant = audit.get("issues", [])
	if not issues_value is Array:
		audit["issues"] = []
	audit["issues"].append({
		"severity": severity,
		"code": code,
		"message": message,
	})


static func _finish_audit(audit: Dictionary) -> Dictionary:
	var has_fail := false
	var has_warn := false
	for issue_value in audit.get("issues", []):
		if not issue_value is Dictionary:
			continue
		var severity := str((issue_value as Dictionary).get("severity", "INFO"))
		if severity == "FAIL":
			has_fail = true
		elif severity == "WARN":
			has_warn = true
	audit["status"] = "FAIL" if has_fail else ("WARN" if has_warn else "PASS")
	audit["ok"] = not has_fail
	return audit
