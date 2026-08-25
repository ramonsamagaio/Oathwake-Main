extends SceneTree

const WALKING_SOURCE := "res://assets/anims/Walking.fbx"
const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")
const V10 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV10.gd")
const V14 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV14.gd")
const RuntimeSource := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeSource.gd")

const EPS := 0.000001
const SAMPLE_FPS := 60.0
const SOURCE_CHECK_BONES := [
	"hips", "spine", "spine2", "neck", "head",
	"leftupleg", "leftleg", "leftfoot", "lefttoebase",
	"rightupleg", "rightleg", "rightfoot", "righttoebase",
	"leftarm", "leftforearm", "lefthand",
	"rightarm", "rightforearm", "righthand",
]
const TARGET_CHECK := ["legL", "footL", "toeL", "legR", "footR", "toeR"]

var _runtime_math: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_runtime_math = RuntimeSource.new()
	if _runtime_math == null:
		_fail("Could not instantiate source-runtime math helper.")
		return

	_rotation_serialization_diagnostic()

	var opened: Dictionary = SourceAdapter.open_preview_source(WALKING_SOURCE)
	if not bool(opened.get("ok", false)):
		_fail("Could not open Walking.fbx: %s" % str(opened.get("error", "")))
		return
	var source_root: Node = opened.get("root") as Node
	var player: AnimationPlayer = opened.get("player") as AnimationPlayer
	var skeleton: Skeleton3D = opened.get("skeleton") as Skeleton3D
	if source_root == null or player == null or skeleton == null:
		SourceAdapter.close_preview_source(opened)
		_fail("Walking source did not expose root/player/skeleton.")
		return
	root.add_child(source_root)
	await process_frame

	var clip_name := _first_real_clip(player)
	if clip_name.is_empty():
		SourceAdapter.close_preview_source(opened)
		_fail("Walking source has no usable animation clip.")
		return
	var animation: Animation = player.get_animation(clip_name)
	if animation == null:
		SourceAdapter.close_preview_source(opened)
		_fail("Walking animation resource is null.")
		return

	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	V9._build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)
	var rest_indexed: Dictionary = V9._build_global_rest(skeleton)
	var rest_semantic: Dictionary = V9._index_transforms_by_semantic(rest_indexed, skeleton)

	await _source_reconstruction_diagnostic(player, skeleton, animation, clip_name, rotation_tracks, position_tracks, scale_tracks)

	var studio_scene_value: Variant = load(BONE_STUDIO_SCENE)
	if not studio_scene_value is PackedScene:
		SourceAdapter.close_preview_source(opened)
		_fail("Could not load Bone Studio for target characterization.")
		return
	var studio: Node = (studio_scene_value as PackedScene).instantiate()
	root.add_child(studio)
	for _i in range(8):
		await process_frame
	var rig_value: Variant = studio.get("rig")
	if not rig_value is Object:
		SourceAdapter.close_preview_source(opened)
		_fail("Bone Studio did not expose Juno rig.")
		return
	var rig: Object = rig_value as Object
	if not rig.has_method("get_bone_rest_local_positions") or not rig.has_method("get_bone_parent_map") or not rig.has_method("get_bone_names"):
		SourceAdapter.close_preview_source(opened)
		_fail("Juno rig lacks characterization accessors.")
		return
	var target_rest_local_value: Variant = rig.call("get_bone_rest_local_positions")
	var target_parent_map_value: Variant = rig.call("get_bone_parent_map")
	var target_bones_value: Variant = rig.call("get_bone_names")
	if not target_rest_local_value is Dictionary or not target_parent_map_value is Dictionary or not target_bones_value is Array:
		SourceAdapter.close_preview_source(opened)
		_fail("Juno characterization data has invalid types.")
		return
	var target_rest_local := target_rest_local_value as Dictionary
	var target_parent_map := target_parent_map_value as Dictionary
	var target_bones: Array = target_bones_value as Array
	var settings := {
		"retarget_limb_mode": "target_rest_swing",
		"target_profile": "juno",
		"target_rest_local_positions": target_rest_local,
		"target_parent_map": target_parent_map,
		"target_bones": target_bones,
		"retarget_skip_attachment_nodes": ["shoulderL", "shoulderR", "hipL", "hipR"],
		"top_down_mode": true,
	}

	var v10_result: Dictionary = V10.convert_scene(player, skeleton, clip_name, SAMPLE_FPS, true, 0.0, settings)
	var v14_result: Dictionary = V14.convert_scene(player, skeleton, clip_name, SAMPLE_FPS, true, 0.0, settings)
	if v10_result.is_empty() or v14_result.is_empty():
		SourceAdapter.close_preview_source(opened)
		_fail("V10/V14 could not build Walking for fidelity diagnostic.")
		return

	var source_forward_hint: Vector3 = V10._source_forward_hint(rest_semantic)
	var rest_pelvis_value: Variant = V10._body_frame_transforms_with_forward_hint(
		rest_semantic, "hips", "leftupleg", "rightupleg", "spine", source_forward_hint
	)
	var target_rest_global: Dictionary = V9._build_target_rest_global(target_rest_local, target_parent_map)
	var target_forward_hint: Vector3 = V10._target_forward_hint(target_rest_global)
	var target_pelvis_value: Variant = V10._body_frame_points_with_forward_hint(
		target_rest_global, "bottom", "legL", "legR", "top", target_forward_hint
	)
	if not rest_pelvis_value is Basis or not target_pelvis_value is Basis:
		SourceAdapter.close_preview_source(opened)
		_fail("Could not build source/target REST bridge for fidelity diagnostic.")
		return
	var source_to_target: Basis = (target_pelvis_value as Basis) * (rest_pelvis_value as Basis).inverse()

	_target_direction_diagnostic(
		"V10",
		v10_result,
		animation,
		skeleton,
		rotation_tracks,
		position_tracks,
		scale_tracks,
		source_to_target,
		target_rest_local,
		target_parent_map
	)
	_target_direction_diagnostic(
		"V14",
		v14_result,
		animation,
		skeleton,
		rotation_tracks,
		position_tracks,
		scale_tracks,
		source_to_target,
		target_rest_local,
		target_parent_map
	)

	studio.queue_free()
	SourceAdapter.close_preview_source(opened)
	await process_frame
	print("ALABASTER_RETARGET_FIDELITY_DIAGNOSTIC_OK")
	quit(0)


func _rotation_serialization_diagnostic() -> void:
	var tests: Array[Vector3] = [
		Vector3(12.0, 18.0, -7.0),
		Vector3(-35.0, 24.0, 19.0),
		Vector3(47.0, -31.0, 28.0),
		Vector3(-68.0, 41.0, -52.0),
		Vector3(8.0, 73.0, 16.0),
	]
	var current_errors: Array[float] = []
	var xyz_errors: Array[float] = []
	for euler_deg in tests:
		var euler_rad := Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z))
		var q: Quaternion = Basis.from_euler(euler_rad, EULER_ORDER_XYZ).get_rotation_quaternion().normalized()
		var current: Array = V9._quaternion_to_alabaster_angles(q, {"top_down_mode": false})
		var current_vec := Vector3(float(current[0]), float(current[1]), float(current[2]))
		var current_q_value: Variant = _runtime_math.call("_source_quat", current_vec)
		if current_q_value is Quaternion:
			current_errors.append(_quat_error_degrees(q, current_q_value as Quaternion))
		var xyz: Vector3 = q.get_euler(EULER_ORDER_XYZ)
		var xyz_vec := Vector3(rad_to_deg(xyz.z), rad_to_deg(xyz.x), rad_to_deg(xyz.y))
		var xyz_q_value: Variant = _runtime_math.call("_source_quat", xyz_vec)
		if xyz_q_value is Quaternion:
			xyz_errors.append(_quat_error_degrees(q, xyz_q_value as Quaternion))
	print("ALABASTER_FIDELITY_ROTATION current_mean=%.4f current_max=%.4f xyz_mean=%.4f xyz_max=%.4f current=%s xyz=%s" % [
		_mean_float(current_errors), _max_float(current_errors), _mean_float(xyz_errors), _max_float(xyz_errors), str(current_errors), str(xyz_errors)
	])


func _source_reconstruction_diagnostic(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	animation: Animation,
	clip_name: String,
	rotation_tracks: Dictionary,
	position_tracks: Dictionary,
	scale_tracks: Dictionary
) -> void:
	player.play(clip_name)
	var sample_times: Array[float] = [0.0, animation.length * 0.125, animation.length * 0.25, animation.length * 0.5, animation.length * 0.75, animation.length * 0.875]
	var position_errors: Array[float] = []
	var direction_errors: Array[float] = []
	var worst_position := {}
	var worst_direction := {}
	for time in sample_times:
		player.seek(time, true)
		await process_frame
		if skeleton.has_method("force_update_all_bone_transforms"):
			skeleton.call("force_update_all_bone_transforms")
		var sampled: Dictionary = V9._sample_global_transforms(animation, skeleton, rotation_tracks, position_tracks, scale_tracks, time)
		var sampled_semantic: Dictionary = V9._index_transforms_by_semantic(sampled, skeleton)
		var actual_semantic := {}
		for bone_index in range(skeleton.get_bone_count()):
			var semantic := V9.normalize(skeleton.get_bone_name(bone_index))
			if semantic.is_empty():
				continue
			actual_semantic[semantic] = skeleton.get_bone_global_pose(bone_index)

		for semantic in SOURCE_CHECK_BONES:
			if not sampled_semantic.has(semantic) or not actual_semantic.has(semantic):
				continue
			var reconstructed: Transform3D = sampled_semantic[semantic]
			var actual: Transform3D = actual_semantic[semantic]
			var error := reconstructed.origin.distance_to(actual.origin)
			position_errors.append(error)
			if worst_position.is_empty() or error > float(worst_position.get("error", -1.0)):
				worst_position = {"time": time, "bone": semantic, "error": error, "reconstructed": reconstructed.origin, "actual": actual.origin}

		for target_value in V10.SOURCE_PRIMARY.keys():
			var target := str(target_value)
			if target not in TARGET_CHECK:
				continue
			var pair_value: Variant = V10.SOURCE_PRIMARY[target_value]
			if not pair_value is Array or (pair_value as Array).size() < 2:
				continue
			var pair := pair_value as Array
			var a_name := str(pair[0])
			var b_name := str(pair[1])
			if not sampled_semantic.has(a_name) or not sampled_semantic.has(b_name) or not actual_semantic.has(a_name) or not actual_semantic.has(b_name):
				continue
			var reconstructed_dir := (sampled_semantic[b_name] as Transform3D).origin - (sampled_semantic[a_name] as Transform3D).origin
			var actual_dir := (actual_semantic[b_name] as Transform3D).origin - (actual_semantic[a_name] as Transform3D).origin
			var angle := _vector_angle_degrees(reconstructed_dir, actual_dir)
			direction_errors.append(angle)
			if worst_direction.is_empty() or angle > float(worst_direction.get("error", -1.0)):
				worst_direction = {"time": time, "segment": "%s>%s" % [a_name, b_name], "target": target, "error": angle, "reconstructed": reconstructed_dir.normalized(), "actual": actual_dir.normalized()}

	print("ALABASTER_FIDELITY_SOURCE position_mean=%.6f position_max=%.6f direction_mean_deg=%.4f direction_max_deg=%.4f worst_pos=%s worst_dir=%s" % [
		_mean_float(position_errors), _max_float(position_errors), _mean_float(direction_errors), _max_float(direction_errors), str(worst_position), str(worst_direction)
	])


func _target_direction_diagnostic(
	label: String,
	result: Dictionary,
	animation: Animation,
	skeleton: Skeleton3D,
	rotation_tracks: Dictionary,
	position_tracks: Dictionary,
	scale_tracks: Dictionary,
	source_to_target: Basis,
	target_rest_local: Dictionary,
	target_parent_map: Dictionary
) -> void:
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array:
		return
	var transforms := transforms_value as Array
	var frame_count := int(result.get("frameCnt", 0))
	var standard_errors: Array[float] = []
	var runtime_errors: Array[float] = []
	var worst_standard := {}
	var worst_runtime := {}
	for frame_value in transforms:
		if not frame_value is Dictionary:
			continue
		var frame_dict := frame_value as Dictionary
		var frame := int(frame_dict.get("frame", -1))
		if frame < 0 or frame >= frame_count:
			continue
		var time := minf(float(frame) / SAMPLE_FPS, animation.length)
		var pose_indexed: Dictionary = V9._sample_global_transforms(animation, skeleton, rotation_tracks, position_tracks, scale_tracks, time)
		var pose_semantic: Dictionary = V9._index_transforms_by_semantic(pose_indexed, skeleton)
		var node_xfm_value: Variant = frame_dict.get("nodeXfm", {})
		if not node_xfm_value is Dictionary:
			continue
		var node_xfm := node_xfm_value as Dictionary
		var accumulated := {}
		for target in TARGET_CHECK:
			if not target_rest_local.has(target):
				continue
			var pair_value: Variant = V10.SOURCE_PRIMARY.get(target, [])
			if not pair_value is Array or (pair_value as Array).size() < 2:
				continue
			var pair := pair_value as Array
			var desired := V9._source_pose_direction(pose_semantic, str(pair[0]), str(pair[1]), source_to_target)
			if desired.length_squared() <= EPS:
				continue
			var global_q := _accumulated_target_quaternion(target, node_xfm, target_parent_map, accumulated)
			var rest_value: Variant = target_rest_local[target]
			if not rest_value is Vector3:
				continue
			var rest_vec := rest_value as Vector3
			if rest_vec.length_squared() <= EPS:
				continue
			var standard_dir := global_q * rest_vec
			var runtime_dir := _runtime_figure_transform(rest_vec, global_q)
			var standard_error := _vector_angle_degrees(standard_dir, desired)
			var runtime_error := _vector_angle_degrees(runtime_dir, desired)
			standard_errors.append(standard_error)
			runtime_errors.append(runtime_error)
			if worst_standard.is_empty() or standard_error > float(worst_standard.get("error", -1.0)):
				worst_standard = {"frame": frame, "target": target, "error": standard_error, "actual": standard_dir.normalized(), "desired": desired.normalized()}
			if worst_runtime.is_empty() or runtime_error > float(worst_runtime.get("error", -1.0)):
				worst_runtime = {"frame": frame, "target": target, "error": runtime_error, "actual": runtime_dir.normalized(), "desired": desired.normalized()}
	print("ALABASTER_FIDELITY_TARGET_%s standard_mean_deg=%.4f standard_max_deg=%.4f runtime_mean_deg=%.4f runtime_max_deg=%.4f worst_standard=%s worst_runtime=%s" % [
		label, _mean_float(standard_errors), _max_float(standard_errors), _mean_float(runtime_errors), _max_float(runtime_errors), str(worst_standard), str(worst_runtime)
	])


func _accumulated_target_quaternion(node_name: String, node_xfm: Dictionary, parent_map: Dictionary, cache: Dictionary) -> Quaternion:
	if cache.has(node_name):
		return cache[node_name] as Quaternion
	var parent := str(parent_map.get(node_name, ""))
	var parent_q := Quaternion.IDENTITY
	if not parent.is_empty():
		parent_q = _accumulated_target_quaternion(parent, node_xfm, parent_map, cache)
	var local_q := Quaternion.IDENTITY
	var xfm_value: Variant = node_xfm.get(node_name, {})
	if xfm_value is Dictionary:
		var rot_value: Variant = (xfm_value as Dictionary).get("rot", [0.0, 0.0, 0.0])
		var rot := _vec3_from_array(rot_value)
		var q_value: Variant = _runtime_math.call("_source_quat", rot)
		if q_value is Quaternion:
			local_q = q_value as Quaternion
	var result := (parent_q * local_q).normalized()
	cache[node_name] = result
	return result


func _runtime_figure_transform(value: Vector3, q: Quaternion) -> Vector3:
	var result := value
	result.z /= 1.325
	result = q * result
	result.z *= 1.325
	return result


func _first_real_clip(player: AnimationPlayer) -> String:
	for clip_value in player.get_animation_list():
		var clip := str(clip_value)
		if clip != "RESET":
			return clip
	return ""


func _vec3_from_array(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array:
		var data := value as Array
		return Vector3(
			float(data[0]) if data.size() > 0 else 0.0,
			float(data[1]) if data.size() > 1 else 0.0,
			float(data[2]) if data.size() > 2 else 0.0
		)
	return Vector3.ZERO


func _quat_error_degrees(a: Quaternion, b: Quaternion) -> float:
	var qa := a.normalized()
	var qb := b.normalized()
	var dot_value := clampf(absf(qa.dot(qb)), 0.0, 1.0)
	return rad_to_deg(2.0 * acos(dot_value))


func _vector_angle_degrees(a: Vector3, b: Vector3) -> float:
	if a.length_squared() <= EPS or b.length_squared() <= EPS:
		return 0.0
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


func _mean_float(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _max_float(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


func _fail(message: String) -> void:
	printerr("ALABASTER_RETARGET_FIDELITY_DIAGNOSTIC_FAILURE: %s" % message)
	quit(1)
