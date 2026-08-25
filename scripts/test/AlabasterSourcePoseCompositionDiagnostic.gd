extends SceneTree

const WALKING_SOURCE := "res://assets/anims/Walking.fbx"
const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")

const CHECK := ["leftupleg", "leftleg", "leftfoot", "lefttoebase", "rightupleg", "rightleg", "rightfoot", "righttoebase"]
const EPS := 0.000001

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var opened: Dictionary = SourceAdapter.open_preview_source(WALKING_SOURCE)
	if not bool(opened.get("ok", false)):
		_fail("Could not open Walking.fbx")
		return
	var source_root := opened.get("root") as Node
	var player := opened.get("player") as AnimationPlayer
	var skeleton := opened.get("skeleton") as Skeleton3D
	if source_root == null or player == null or skeleton == null:
		_fail("Walking source missing root/player/skeleton")
		return
	root.add_child(source_root)
	await process_frame
	var clip := ""
	for clip_value in player.get_animation_list():
		if str(clip_value) != "RESET":
			clip = str(clip_value)
			break
	if clip.is_empty():
		_fail("No clip")
		return
	var animation := player.get_animation(clip)
	if animation == null:
		_fail("Null animation")
		return
	var rotation_tracks := {}
	var position_tracks := {}
	var scale_tracks := {}
	V9._build_track_maps(animation, rotation_tracks, position_tracks, scale_tracks)

	var modes := ["replace", "rest_pose", "pose_rest", "rest_rot_pose_pos_replace", "rest_rot_pose_pos_offset"]
	var totals := {}
	var maxima := {}
	var worst := {}
	for mode in modes:
		totals[mode] = 0.0
		maxima[mode] = 0.0
		worst[mode] = {}
	var counts := 0
	var times: Array[float] = [0.0, animation.length * 0.125, animation.length * 0.25, animation.length * 0.375, animation.length * 0.5, animation.length * 0.625, animation.length * 0.75, animation.length * 0.875]
	for time in times:
		player.play(clip)
		player.seek(time, true)
		await process_frame
		if skeleton.has_method("force_update_all_bone_transforms"):
			skeleton.call("force_update_all_bone_transforms")
		var actual := _actual_globals(skeleton)
		for mode in modes:
			var candidate := _sample_candidate(animation, skeleton, rotation_tracks, position_tracks, scale_tracks, time, mode)
			for semantic in CHECK:
				if not actual.has(semantic) or not candidate.has(semantic):
					continue
				var a: Transform3D = actual[semantic]
				var c: Transform3D = candidate[semantic]
				var pos_err := a.origin.distance_to(c.origin)
				var basis_err := _basis_error_deg(a.basis, c.basis)
				var score := pos_err + basis_err / 100.0
				totals[mode] = float(totals[mode]) + score
				if score > float(maxima[mode]):
					maxima[mode] = score
					worst[mode] = {"time": time, "bone": semantic, "pos": pos_err, "basis_deg": basis_err, "actual": a.origin, "candidate": c.origin}
				if mode == modes[0]:
					counts += 1

	print("ALABASTER_SOURCE_POSE_COMPOSITION count=%d" % counts)
	for mode in modes:
		print("ALABASTER_SOURCE_POSE_MODE %s mean_score=%.6f max_score=%.6f worst=%s" % [mode, float(totals[mode]) / maxf(float(counts), 1.0), float(maxima[mode]), str(worst[mode])])

	player.play(clip)
	player.seek(0.0, true)
	await process_frame
	if skeleton.has_method("force_update_all_bone_transforms"):
		skeleton.call("force_update_all_bone_transforms")
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := V9.normalize(skeleton.get_bone_name(bone_index))
		if semantic not in ["leftleg", "leftfoot", "lefttoebase"]:
			continue
		var rest := skeleton.get_bone_rest(bone_index)
		var pose_pos := skeleton.get_bone_pose_position(bone_index)
		var pose_rot := skeleton.get_bone_pose_rotation(bone_index)
		var pose_scale := skeleton.get_bone_pose_scale(bone_index)
		var global_pose := skeleton.get_bone_global_pose(bone_index)
		var track_pos := _interpolated_position(animation, position_tracks, bone_index, 0.0)
		var track_rot := _interpolated_rotation(animation, rotation_tracks, bone_index, 0.0)
		print("ALABASTER_SOURCE_POSE_DETAIL bone=%s rest_origin=%s pose_pos=%s track_pos=%s pose_rot=%s track_rot=%s pose_scale=%s global=%s" % [semantic, str(rest.origin), str(pose_pos), str(track_pos), str(pose_rot), str(track_rot), str(pose_scale), str(global_pose.origin)])

	SourceAdapter.close_preview_source(opened)
	await process_frame
	print("ALABASTER_SOURCE_POSE_COMPOSITION_DIAGNOSTIC_OK")
	quit(0)

func _actual_globals(skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for i in range(skeleton.get_bone_count()):
		var semantic := V9.normalize(skeleton.get_bone_name(i))
		if not semantic.is_empty():
			out[semantic] = skeleton.get_bone_global_pose(i)
	return out

func _sample_candidate(animation: Animation, skeleton: Skeleton3D, rotation_tracks: Dictionary, position_tracks: Dictionary, scale_tracks: Dictionary, time: float, mode: String) -> Dictionary:
	var indexed := {}
	var semantic := {}
	for bone_index in range(skeleton.get_bone_count()):
		var rest := skeleton.get_bone_rest(bone_index)
		var pose_pos := _interpolated_position(animation, position_tracks, bone_index, time)
		var pose_rot := _interpolated_rotation(animation, rotation_tracks, bone_index, time)
		var pose_scale := _interpolated_scale(animation, scale_tracks, bone_index, time)
		var pose := Transform3D(Basis(pose_rot).scaled(pose_scale), pose_pos)
		var local := rest
		match mode:
			"replace":
				local = pose
			"rest_pose":
				local = rest * pose
			"pose_rest":
				local = pose * rest
			"rest_rot_pose_pos_replace":
				local = Transform3D(rest.basis * Basis(pose_rot).scaled(pose_scale), pose_pos)
			"rest_rot_pose_pos_offset":
				local = Transform3D(rest.basis * Basis(pose_rot).scaled(pose_scale), rest.origin + pose_pos)
		var parent := skeleton.get_bone_parent(bone_index)
		var global := local
		if parent >= 0 and indexed.has(parent):
			global = (indexed[parent] as Transform3D) * local
		indexed[bone_index] = global
		var name := V9.normalize(skeleton.get_bone_name(bone_index))
		if not name.is_empty():
			semantic[name] = global
	return semantic

func _interpolated_position(animation: Animation, tracks: Dictionary, bone_index: int, time: float) -> Vector3:
	if tracks.has(bone_index):
		var value: Variant = animation.position_track_interpolate(int(tracks[bone_index]), time)
		if value is Vector3:
			return value
	return Vector3.ZERO

func _interpolated_rotation(animation: Animation, tracks: Dictionary, bone_index: int, time: float) -> Quaternion:
	if tracks.has(bone_index):
		var value: Variant = animation.rotation_track_interpolate(int(tracks[bone_index]), time)
		if value is Quaternion:
			return (value as Quaternion).normalized()
	return Quaternion.IDENTITY

func _interpolated_scale(animation: Animation, tracks: Dictionary, bone_index: int, time: float) -> Vector3:
	if tracks.has(bone_index):
		var value: Variant = animation.scale_track_interpolate(int(tracks[bone_index]), time)
		if value is Vector3:
			return value
	return Vector3.ONE

func _basis_error_deg(a: Basis, b: Basis) -> float:
	var qa := a.orthonormalized().get_rotation_quaternion().normalized()
	var qb := b.orthonormalized().get_rotation_quaternion().normalized()
	var dot_value := clampf(absf(qa.dot(qb)), 0.0, 1.0)
	return rad_to_deg(2.0 * acos(dot_value))

func _fail(message: String) -> void:
	printerr("ALABASTER_SOURCE_POSE_COMPOSITION_DIAGNOSTIC_FAILURE: %s" % message)
	quit(1)
