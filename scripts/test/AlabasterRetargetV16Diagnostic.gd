extends SceneTree

const WALKING_SOURCE := "res://assets/anims/Walking.fbx"
const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")
const V10 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV10.gd")
const V14 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV14.gd")
const V16 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV16.gd")

const SAMPLE_FPS := 60.0
const EPS := 0.000001
const TARGET_CHECK := ["legL", "footL", "toeL", "legR", "footR", "toeR"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var opened: Dictionary = SourceAdapter.open_preview_source(WALKING_SOURCE)
	if not bool(opened.get("ok", false)):
		_fail("Could not open Walking.fbx: %s" % str(opened.get("error", "")))
		return
	var source_root := opened.get("root") as Node
	var player := opened.get("player") as AnimationPlayer
	var skeleton := opened.get("skeleton") as Skeleton3D
	if source_root == null or player == null or skeleton == null:
		SourceAdapter.close_preview_source(opened)
		_fail("Walking source did not expose root/player/skeleton.")
		return
	root.add_child(source_root)
	await process_frame

	var clip_name := _first_real_clip(player)
	if clip_name.is_empty():
		SourceAdapter.close_preview_source(opened)
		_fail("Walking source has no real clip.")
		return
	var animation := player.get_animation(clip_name)
	if animation == null:
		SourceAdapter.close_preview_source(opened)
		_fail("Walking clip resource is null.")
		return

	var studio_scene_value: Variant = load(BONE_STUDIO_SCENE)
	if not studio_scene_value is PackedScene:
		SourceAdapter.close_preview_source(opened)
		_fail("Could not load Bone Studio for Juno characterization.")
		return
	var studio := (studio_scene_value as PackedScene).instantiate()
	root.add_child(studio)
	for _i in range(8):
		await process_frame
	var rig_value: Variant = studio.get("rig")
	if not rig_value is Object:
		SourceAdapter.close_preview_source(opened)
		_fail("Bone Studio did not expose Juno rig.")
		return
	var rig := rig_value as Object
	if not rig.has_method("get_bone_rest_local_positions") or not rig.has_method("get_bone_parent_map") or not rig.has_method("get_bone_names"):
		SourceAdapter.close_preview_source(opened)
		_fail("Juno rig lacks characterization accessors.")
		return
	var target_rest_value: Variant = rig.call("get_bone_rest_local_positions")
	var target_parent_value: Variant = rig.call("get_bone_parent_map")
	var target_bones_value: Variant = rig.call("get_bone_names")
	if not target_rest_value is Dictionary or not target_parent_value is Dictionary or not target_bones_value is Array:
		SourceAdapter.close_preview_source(opened)
		_fail("Juno characterization data has invalid types.")
		return
	var target_rest := target_rest_value as Dictionary
	var target_parent := target_parent_value as Dictionary
	var target_bones := target_bones_value as Array
	var settings := {
		"retarget_limb_mode": "target_rest_swing",
		"target_profile": "juno",
		"target_rest_local_positions": target_rest,
		"target_parent_map": target_parent,
		"target_bones": target_bones,
		"retarget_skip_attachment_nodes": ["shoulderL", "shoulderR", "hipL", "hipR"],
		"top_down_mode": true,
	}

	var v14: Dictionary = V14.convert_scene(player, skeleton, clip_name, SAMPLE_FPS, true, 0.0, settings)
	var v16: Dictionary = V16.convert_scene(player, skeleton, clip_name, SAMPLE_FPS, true, 0.0, settings)
	if v14.is_empty() or v16.is_empty():
		SourceAdapter.close_preview_source(opened)
		_fail("V14/V16 conversion returned empty result.")
		return

	var codec := _measure_codec(v14, v16)
	print("ALABASTER_V16_CODEC_REAL_WALK keys=%d legacy_runtime_mean_deg=%.4f legacy_runtime_max_deg=%.4f v16_runtime_mean_deg=%.6f v16_runtime_max_deg=%.6f" % [
		int(codec.get("count", 0)),
		float(codec.get("legacy_mean", 0.0)),
		float(codec.get("legacy_max", 0.0)),
		float(codec.get("v16_mean", 0.0)),
		float(codec.get("v16_max", 0.0)),
	])
	if float(codec.get("v16_max", 999.0)) > 0.05:
		SourceAdapter.close_preview_source(opened)
		_fail("V16 real-Walking codec roundtrip exceeds 0.05 degrees.")
		return

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	V9._build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)
	var rest_indexed := V9._build_global_rest(skeleton)
	var rest_semantic := V9._index_transforms_by_semantic(rest_indexed, skeleton)
	var source_forward := V10._source_forward_hint(rest_semantic)
	var source_pelvis_value: Variant = V10._body_frame_transforms_with_forward_hint(
		rest_semantic, "hips", "leftupleg", "rightupleg", "spine", source_forward
	)
	var target_global := V9._build_target_rest_global(target_rest, target_parent)
	var target_forward := V10._target_forward_hint(target_global)
	var target_pelvis_value: Variant = V10._body_frame_points_with_forward_hint(
		target_global, "bottom", "legL", "legR", "top", target_forward
	)
	if not source_pelvis_value is Basis or not target_pelvis_value is Basis:
		SourceAdapter.close_preview_source(opened)
		_fail("Could not reconstruct source-to-target pelvis bridge.")
		return
	var source_to_target := (target_pelvis_value as Basis) * (source_pelvis_value as Basis).inverse()

	var fidelity := _measure_target_fidelity(
		v16,
		animation,
		skeleton,
		rotation_tracks,
		position_tracks,
		scale_tracks,
		source_to_target,
		target_rest,
		target_parent
	)
	print("ALABASTER_V16_TARGET_FIDELITY standard_mean_deg=%.4f standard_max_deg=%.4f runtime_mean_deg=%.4f runtime_max_deg=%.4f worst_standard=%s worst_runtime=%s" % [
		float(fidelity.get("standard_mean", 0.0)),
		float(fidelity.get("standard_max", 0.0)),
		float(fidelity.get("runtime_mean", 0.0)),
		float(fidelity.get("runtime_max", 0.0)),
		str(fidelity.get("worst_standard", {})),
		str(fidelity.get("worst_runtime", {})),
	])

	studio.queue_free()
	SourceAdapter.close_preview_source(opened)
	await process_frame
	print("ALABASTER_RETARGET_V16_DIAGNOSTIC_OK")
	quit(0)


func _measure_codec(v14: Dictionary, v16: Dictionary) -> Dictionary:
	var a_value: Variant = v14.get("transforms", [])
	var b_value: Variant = v16.get("transforms", [])
	if not a_value is Array or not b_value is Array:
		return {}
	var a := a_value as Array
	var b := b_value as Array
	var legacy_errors: Array[float] = []
	var v16_errors: Array[float] = []
	for frame_index in range(mini(a.size(), b.size())):
		if not a[frame_index] is Dictionary or not b[frame_index] is Dictionary:
			continue
		var a_nodes_value: Variant = (a[frame_index] as Dictionary).get("nodeXfm", {})
		var b_nodes_value: Variant = (b[frame_index] as Dictionary).get("nodeXfm", {})
		if not a_nodes_value is Dictionary or not b_nodes_value is Dictionary:
			continue
		var a_nodes := a_nodes_value as Dictionary
		var b_nodes := b_nodes_value as Dictionary
		for bone_value in a_nodes.keys():
			if not b_nodes.has(bone_value):
				continue
			var a_xfm_value: Variant = a_nodes[bone_value]
			var b_xfm_value: Variant = b_nodes[bone_value]
			if not a_xfm_value is Dictionary or not b_xfm_value is Dictionary:
				continue
			var legacy_angles := _rot_array((a_xfm_value as Dictionary).get("rot", [0.0, 0.0, 0.0]))
			var v16_angles := _rot_array((b_xfm_value as Dictionary).get("rot", [0.0, 0.0, 0.0]))
			var intended := V16._legacy_angles_to_quaternion(legacy_angles)
			var legacy_runtime := V16._runtime_angles_to_quaternion(legacy_angles)
			var v16_runtime := V16._runtime_angles_to_quaternion(v16_angles)
			legacy_errors.append(_quat_error_deg(intended, legacy_runtime))
			v16_errors.append(_quat_error_deg(intended, v16_runtime))
	return {
		"count": v16_errors.size(),
		"legacy_mean": _mean(legacy_errors),
		"legacy_max": _max(legacy_errors),
		"v16_mean": _mean(v16_errors),
		"v16_max": _max(v16_errors),
	}


func _measure_target_fidelity(
	result: Dictionary,
	animation: Animation,
	skeleton: Skeleton3D,
	rotation_tracks: Dictionary,
	position_tracks: Dictionary,
	scale_tracks: Dictionary,
	source_to_target: Basis,
	target_rest: Dictionary,
	target_parent: Dictionary
) -> Dictionary:
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array:
		return {}
	var standard_errors: Array[float] = []
	var runtime_errors: Array[float] = []
	var worst_standard := {}
	var worst_runtime := {}
	var frame_count := int(result.get("frameCnt", 0))
	for frame_value in transforms_value as Array:
		if not frame_value is Dictionary:
			continue
		var frame_dict := frame_value as Dictionary
		var frame := int(frame_dict.get("frame", -1))
		if frame < 0 or frame >= frame_count:
			continue
		var time := minf(float(frame) / SAMPLE_FPS, animation.length)
		var pose_indexed := V9._sample_global_transforms(animation, skeleton, rotation_tracks, position_tracks, scale_tracks, time)
		var pose_semantic := V9._index_transforms_by_semantic(pose_indexed, skeleton)
		var node_value: Variant = frame_dict.get("nodeXfm", {})
		if not node_value is Dictionary:
			continue
		var nodes := node_value as Dictionary
		var cache := {}
		for target in TARGET_CHECK:
			if not target_rest.has(target):
				continue
			var pair_value: Variant = V10.SOURCE_PRIMARY.get(target, [])
			if not pair_value is Array or (pair_value as Array).size() < 2:
				continue
			var pair := pair_value as Array
			var desired := V9._source_pose_direction(pose_semantic, str(pair[0]), str(pair[1]), source_to_target)
			var rest_value: Variant = target_rest[target]
			if desired.length_squared() <= EPS or not rest_value is Vector3:
				continue
			var rest_vec := rest_value as Vector3
			if rest_vec.length_squared() <= EPS:
				continue
			var global_q := _global_runtime_q(target, nodes, target_parent, cache)
			var standard_dir := global_q * rest_vec
			var runtime_dir := _figure_transform(rest_vec, global_q)
			var standard_error := _vector_error_deg(standard_dir, desired)
			var runtime_error := _vector_error_deg(runtime_dir, desired)
			standard_errors.append(standard_error)
			runtime_errors.append(runtime_error)
			if worst_standard.is_empty() or standard_error > float(worst_standard.get("error", -1.0)):
				worst_standard = {"frame": frame, "target": target, "error": standard_error, "actual": standard_dir.normalized(), "desired": desired.normalized()}
			if worst_runtime.is_empty() or runtime_error > float(worst_runtime.get("error", -1.0)):
				worst_runtime = {"frame": frame, "target": target, "error": runtime_error, "actual": runtime_dir.normalized(), "desired": desired.normalized()}
	return {
		"standard_mean": _mean(standard_errors),
		"standard_max": _max(standard_errors),
		"runtime_mean": _mean(runtime_errors),
		"runtime_max": _max(runtime_errors),
		"worst_standard": worst_standard,
		"worst_runtime": worst_runtime,
	}


func _global_runtime_q(name: String, nodes: Dictionary, parents: Dictionary, cache: Dictionary) -> Quaternion:
	if cache.has(name):
		return cache[name] as Quaternion
	var parent := str(parents.get(name, ""))
	var parent_q := Quaternion.IDENTITY
	if not parent.is_empty():
		parent_q = _global_runtime_q(parent, nodes, parents, cache)
	var local_q := Quaternion.IDENTITY
	var xfm_value: Variant = nodes.get(name, {})
	if xfm_value is Dictionary:
		local_q = V16._runtime_angles_to_quaternion(_rot_array((xfm_value as Dictionary).get("rot", [0.0, 0.0, 0.0])))
	var result := (parent_q * local_q).normalized()
	cache[name] = result
	return result


func _figure_transform(value: Vector3, q: Quaternion) -> Vector3:
	var p := value
	p.z /= 1.325
	p = q * p
	p.z *= 1.325
	return p


func _rot_array(value: Variant) -> Array:
	var out: Array = [0.0, 0.0, 0.0]
	if value is Array:
		var source := value as Array
		for i in range(mini(source.size(), 3)):
			out[i] = float(source[i])
	return out


func _quat_error_deg(a: Quaternion, b: Quaternion) -> float:
	var dot_value := clampf(absf(a.normalized().dot(b.normalized())), 0.0, 1.0)
	return rad_to_deg(2.0 * acos(dot_value))


func _vector_error_deg(a: Vector3, b: Vector3) -> float:
	if a.length_squared() <= EPS or b.length_squared() <= EPS:
		return 0.0
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _max(values: Array[float]) -> float:
	var maximum := 0.0
	for value in values:
		maximum = maxf(maximum, value)
	return maximum


func _first_real_clip(player: AnimationPlayer) -> String:
	for clip_value in player.get_animation_list():
		var clip := str(clip_value)
		if clip != "RESET":
			return clip
	return ""


func _fail(message: String) -> void:
	printerr("ALABASTER_RETARGET_V16_DIAGNOSTIC_FAILURE: %s" % message)
	quit(1)
