extends RefCounted
class_name AlabasterMixamoRetargetV11

# Mixamo -> Juno V11 arm stabilization layer.
#
# V10 fixed the two things that must remain untouched here:
#   - source/target forward handedness, which fixed the moonwalk;
#   - two-vector lower-body/foot calibration, which fixed the 180-degree ankle.
#
# The recorded V10 walk exposed a separate upper-body problem. The adjacent
# forearm/hand segment was being used as the TWIST plane for the upper arm. In a
# walking pose that means elbow flexion can be interpreted as axial upper-arm
# roll. The primary arm direction remains mathematically correct, but Juno's
# billboarded arm/hand pieces can roll violently around that direction.
#
# V11 is deliberately surgical: first build the complete V10 animation, then
# replace ONLY armL/handL/fingerL and armR/handR/fingerR rotations with a stable
# single-segment swing solve. The solve still uses V10's reflected forward bridge
# and V10 torso motion, so arm swing follows the corrected walking direction.
# Every root/torso/leg/foot/toe value is copied from V10 and verified unchanged
# before the result is allowed to leave this adapter.

const V10 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV10.gd")
const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")

const EPS := 0.000001
const PROFILE_NAME := "MIXAMO_JUNO_REST_CALIBRATED_V10_ARM_STABLE_V11"

const ARM_TARGET_ORDER := [
	"armL", "handL", "fingerL",
	"armR", "handR", "fingerR",
]

const ARM_SOURCE_PRIMARY := {
	"armL": ["leftarm", "leftforearm"],
	"handL": ["leftforearm", "lefthand"],
	"fingerL": ["lefthand", "lefthandindex1"],
	"armR": ["rightarm", "rightforearm"],
	"handR": ["rightforearm", "righthand"],
	"fingerR": ["righthand", "righthandindex1"],
}

# These nodes are the user's "do not touch the legs" contract. V11 refuses to
# return its patched animation if any of them differs from the V10 baseline.
const V10_PRESERVED_TARGETS := [
	"root", "bottom", "top", "head",
	"legL", "footL", "toeL",
	"legR", "footR", "toeR",
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
	var baseline := V10.convert_scene(
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

	# Old comparison modes belong to V8/V10 and should not be post-processed.
	var mode := str(settings.get("retarget_limb_mode", "target_rest_swing"))
	if mode == "full_global_delta" or mode == "segment_swing":
		return baseline

	var result: Dictionary = baseline.duplicate(true)
	var patch_info := _patch_arms_with_stable_swing(
		player,
		skeleton,
		clip_name,
		sample_fps,
		settings,
		result
	)
	if not bool(patch_info.get("ok", false)):
		push_warning("Mixamo -> Juno V11: arm stabilization could not be applied; keeping proven V10 result. %s" % str(patch_info.get("reason", "")))
		return baseline

	# Hard safety rail: the current leg result is already very close visually.
	# If an arm-only change ever mutates a lower-body key, fail closed to V10.
	if not _preserved_targets_match(baseline, result):
		push_warning("Mixamo -> Juno V11: lower-body invariant failed; refusing arm patch and keeping V10 byte-for-byte transforms.")
		return baseline

	var meta_value: Variant = result.get("import_meta", {})
	var meta: Dictionary = (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	var arm_counts_value: Variant = patch_info.get("arm_patch_counts", {})
	var arm_counts: Dictionary = (arm_counts_value as Dictionary).duplicate(true) if arm_counts_value is Dictionary else {}

	# V10's original diagnostic counted its arm plane solve. Those keys no longer
	# describe the final output, so move the arm coverage to swing diagnostics
	# while leaving all leg/foot plane counts exactly as V10 produced them.
	var plane_value: Variant = meta.get("plane_solved_counts", {})
	if plane_value is Dictionary:
		var plane_counts := (plane_value as Dictionary).duplicate(true)
		for target in ARM_TARGET_ORDER:
			plane_counts.erase(target)
		meta["plane_solved_counts"] = plane_counts
	var swing_value: Variant = meta.get("swing_fallback_counts", {})
	var swing_counts: Dictionary = (swing_value as Dictionary).duplicate(true) if swing_value is Dictionary else {}
	for target in ARM_TARGET_ORDER:
		swing_counts[target] = int(arm_counts.get(target, 0))
	meta["swing_fallback_counts"] = swing_counts

	meta["bridge"] = "mixamo_juno_v10_rest_calibration_v11_arm_stable"
	meta["retarget_profile"] = PROFILE_NAME
	# Forward/foot calibration remains V10. V11 changes only the upper-limb policy.
	meta["rest_calibration_version"] = 10
	meta["arm_stabilization_version"] = 11
	meta["arm_transfer_mode"] = "V10 reflected-forward bridge + single-segment swing; no adjacent-chain twist"
	meta["arm_patch_counts"] = arm_counts
	meta["lower_body_policy"] = "V10 transform keys preserved byte-for-byte"
	meta["lower_body_invariant_verified"] = true
	result["import_meta"] = meta

	print("ALABASTER_MIXAMO_V11_ARM_STABLE_OK clip=%s frames=%d arms=%s lower_body_unchanged=true" % [
		clip_name,
		(result.get("transforms", []) as Array).size() if result.get("transforms", []) is Array else 0,
		str(arm_counts),
	])
	return result


static func _patch_arms_with_stable_swing(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	settings: Dictionary,
	result: Dictionary
) -> Dictionary:
	if player == null or skeleton == null or clip_name.is_empty() or not player.has_animation(clip_name):
		return {"ok": false, "reason": "missing player/skeleton/clip"}
	var animation := player.get_animation(clip_name)
	if animation == null:
		return {"ok": false, "reason": "null animation"}

	var target_rest_local := V9._target_rest_local_positions(settings)
	var target_parent_map := V9._target_parent_map(settings)
	if target_rest_local.is_empty():
		return {"ok": false, "reason": "target REST vectors unavailable"}
	var target_rest_global := V9._build_target_rest_global(target_rest_local, target_parent_map)

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	V9._build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)
	if rotation_tracks.is_empty():
		return {"ok": false, "reason": "source has no rotation tracks"}

	var rest_indexed := V9._build_global_rest(skeleton)
	var rest_semantic := V9._index_transforms_by_semantic(rest_indexed, skeleton)
	if rest_semantic.is_empty():
		return {"ok": false, "reason": "source REST hierarchy unavailable"}

	# Recreate exactly V10's REST bridge. This preserves the corrected forward
	# hemisphere while changing only how upper-limb axial twist is chosen.
	var source_forward_hint := V10._source_forward_hint(rest_semantic)
	var rest_pelvis_value: Variant = V10._body_frame_transforms_with_forward_hint(
		rest_semantic, "hips", "leftupleg", "rightupleg", "spine", source_forward_hint
	)
	if not rest_pelvis_value is Basis:
		return {"ok": false, "reason": "source pelvis REST frame unavailable"}
	var rest_pelvis: Basis = rest_pelvis_value as Basis
	var source_handedness := V10._basis_handedness(rest_pelvis)

	var rest_torso_value: Variant = V10._body_frame_transforms_with_handedness(
		rest_semantic, "spine2", "leftshoulder", "rightshoulder", "neck", source_handedness
	)
	if not rest_torso_value is Basis:
		return {"ok": false, "reason": "source torso REST frame unavailable"}
	var rest_torso: Basis = rest_torso_value as Basis

	var target_forward_hint := V10._target_forward_hint(target_rest_global)
	var target_pelvis_value: Variant = V10._body_frame_points_with_forward_hint(
		target_rest_global, "bottom", "legL", "legR", "top", target_forward_hint
	)
	if not target_pelvis_value is Basis:
		return {"ok": false, "reason": "target pelvis REST frame unavailable"}
	var target_pelvis: Basis = target_pelvis_value as Basis
	var source_to_target: Basis = target_pelvis * rest_pelvis.inverse()

	var target_bones := V9._target_bones(settings)
	var skip_nodes := V9._skip_nodes(settings)
	var fps := maxf(sample_fps, 1.0)
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array:
		return {"ok": false, "reason": "V10 result has no transform frames"}
	var transforms := transforms_value as Array
	var previous_angles := {}
	var arm_patch_counts := {}

	for frame_index in range(transforms.size()):
		var frame_value: Variant = transforms[frame_index]
		if not frame_value is Dictionary:
			continue
		var frame_dict := (frame_value as Dictionary).duplicate(true)
		var source_frame := float(frame_dict.get("frame", frame_index))
		var time := minf(source_frame / fps, animation.length)

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
			return {"ok": false, "reason": "empty source pose at frame %d" % frame_index}

		# Parent torso orientation must remain the V10 torso orientation. Arms are
		# solved globally, then converted into the same local hierarchy as runtime.
		var pose_torso_value: Variant = V10._body_frame_transforms_with_handedness(
			pose_semantic, "spine2", "leftshoulder", "rightshoulder", "neck", source_handedness
		)
		if not pose_torso_value is Basis:
			return {"ok": false, "reason": "torso pose frame unavailable at frame %d" % frame_index}
		var pose_torso: Basis = pose_torso_value as Basis
		var torso_delta := (pose_torso * rest_torso.inverse()).orthonormalized()
		var target_global := {
			"top": V9._map_motion_basis(torso_delta, source_to_target),
		}

		var node_xfm_value: Variant = frame_dict.get("nodeXfm", {})
		if not node_xfm_value is Dictionary:
			continue
		var node_xfm := (node_xfm_value as Dictionary).duplicate(true)

		for target_value in ARM_TARGET_ORDER:
			var target := str(target_value)
			if not target_bones.has(target) or skip_nodes.has(target):
				continue
			var pair_value: Variant = ARM_SOURCE_PRIMARY.get(target, [])
			if not pair_value is Array or (pair_value as Array).size() < 2:
				continue
			var pair := pair_value as Array
			var desired_primary := V9._source_pose_direction(
				pose_semantic,
				str(pair[0]),
				str(pair[1]),
				source_to_target
			)
			var target_primary := V9._target_segment_rest_direction(
				target,
				target_rest_local,
				target_rest_global,
				target_parent_map
			)
			if desired_primary.length_squared() <= EPS or target_primary.length_squared() <= EPS:
				continue

			# The key change: no elbow/wrist/finger direction is allowed to become
			# axial twist of its parent segment. Each segment points where Mixamo
			# points it, while the child segment gets its own independent solve.
			var swing := Quaternion(target_primary.normalized(), desired_primary.normalized())
			var global_basis := Basis(V9._canonical_quaternion(swing)).orthonormalized()
			target_global[target] = global_basis

			var parent_target := V9._effective_target_parent(target, target_parent_map, target_bones, skip_nodes)
			var local_basis := global_basis
			if not parent_target.is_empty() and target_global.has(parent_target):
				var parent_basis: Basis = target_global[parent_target]
				local_basis = (parent_basis.inverse() * global_basis).orthonormalized()

			var q := V9._canonical_quaternion(local_basis.get_rotation_quaternion())
			var angles := V9._quaternion_to_alabaster_angles(q, settings)
			if previous_angles.has(target):
				angles = V9._unwrap_angles(angles, previous_angles[target])
			previous_angles[target] = angles.duplicate()

			var xfm_value: Variant = node_xfm.get(target, {})
			var xfm: Dictionary = (xfm_value as Dictionary).duplicate(true) if xfm_value is Dictionary else {
				"rot": [0.0, 0.0, 0.0],
				"trans": [0.0, 0.0, 0.0],
				"scale": 1.0,
			}
			xfm["rot"] = angles
			node_xfm[target] = xfm
			arm_patch_counts[target] = int(arm_patch_counts.get(target, 0)) + 1

		frame_dict["nodeXfm"] = node_xfm
		transforms[frame_index] = frame_dict

	result["transforms"] = transforms
	var total_patches := 0
	for count_value in arm_patch_counts.values():
		total_patches += int(count_value)
	return {
		"ok": total_patches > 0,
		"reason": "" if total_patches > 0 else "no arm keys were patched",
		"arm_patch_counts": arm_patch_counts,
	}


static func _preserved_targets_match(before: Dictionary, after: Dictionary) -> bool:
	var before_value: Variant = before.get("transforms", [])
	var after_value: Variant = after.get("transforms", [])
	if not before_value is Array or not after_value is Array:
		return false
	var before_frames := before_value as Array
	var after_frames := after_value as Array
	if before_frames.size() != after_frames.size():
		return false
	for frame_index in range(before_frames.size()):
		var before_frame_value: Variant = before_frames[frame_index]
		var after_frame_value: Variant = after_frames[frame_index]
		if not before_frame_value is Dictionary or not after_frame_value is Dictionary:
			continue
		var before_xfm_value: Variant = (before_frame_value as Dictionary).get("nodeXfm", {})
		var after_xfm_value: Variant = (after_frame_value as Dictionary).get("nodeXfm", {})
		if not before_xfm_value is Dictionary or not after_xfm_value is Dictionary:
			return false
		var before_xfm := before_xfm_value as Dictionary
		var after_xfm := after_xfm_value as Dictionary
		for target_value in V10_PRESERVED_TARGETS:
			var target := str(target_value)
			if before_xfm.has(target) != after_xfm.has(target):
				return false
			if before_xfm.has(target) and before_xfm[target] != after_xfm[target]:
				return false
	return true
