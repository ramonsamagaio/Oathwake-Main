extends SceneTree

const WALKING_SOURCE := "res://assets/anims/Walking.fbx"
const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")

const CHECK := ["leftupleg", "leftleg", "leftfoot", "lefttoebase", "rightupleg", "rightleg", "rightfoot", "righttoebase"]

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

	print("ALABASTER_SOURCE_POSE_TRACK_COUNTS rot=%d pos=%d scale=%d" % [rotation_tracks.size(), position_tracks.size(), scale_tracks.size()])
	for semantic in CHECK:
		var rot_index := int(rotation_tracks.get(semantic, -1))
		var pos_index := int(position_tracks.get(semantic, -1))
		var scale_index := int(scale_tracks.get(semantic, -1))
		print("ALABASTER_SOURCE_POSE_TRACK bone=%s rot=%d:%s pos=%d:%s scale=%d:%s" % [
			semantic,
			rot_index, str(animation.track_get_path(rot_index)) if rot_index >= 0 else "missing",
			pos_index, str(animation.track_get_path(pos_index)) if pos_index >= 0 else "missing",
			scale_index, str(animation.track_get_path(scale_index)) if scale_index >= 0 else "missing"
		])

	var modes := ["v9_current", "rest_pose", "pose_rest", "track_local", "rest_rot_track_pos"]
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
		var track_pos := _track_position(animation, position_tracks, semantic, 0.0, rest.origin)
		var track_rot := _track_rotation(animation, rotation_tracks, semantic, 0.0, rest.basis.get_rotation_quaternion())
		var track_scale := _track_scale(animation, scale_tracks, semantic, 0.0, rest.basis.get_scale())
		print("ALABASTER_SOURCE_POSE_DETAIL bone=%s rest_origin=%s pose_pos=%s track_pos=%s pose_rot=%s track_rot=%s pose_scale=%s track_scale=%s global=%s" % [semantic, str(rest.origin), str(pose_pos), str(track_pos), str(pose_rot), str(track_rot), str(pose_scale), str(track_scale), str(global_pose.origin)])

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
	var semantic_out := {}
	for bone_index in range(skeleton.get_bone_count()):
		var semantic := V9.normalize(skeleton.get_bone_name(bone_index))
		var rest := skeleton.get_bone_rest(bone_index)
		var has_pos := position_tracks.has(semantic)
		var has_rot := rotation_tracks.has(semantic)
		var has_scale := scale_tracks.has(semantic)
		var track_pos := _track_position(animation, position_tracks, semantic, time, rest.origin)
		var track_rot := _track_rotation(animation, rotation_tracks, semantic, time, rest.basis.get_rotation_quaternion())
		var track_scale := _track_scale(animation, scale_tracks, semantic, time, rest.basis.get_scale())
		var pose_delta_pos := _track_position(animation, position_tracks, semantic, time, Vector3.ZERO)
		var pose_delta_rot := _track_rotation(animation, rotation_tracks, semantic, time, Quaternion.IDENTITY)
		var pose_delta_scale := _track_scale(animation, scale_tracks, semantic, time, Vector3.ONE)
		var local := rest
		match mode:
			"v9_current":
				var basis := rest.basis
				var origin := rest.origin
				if has_rot:
					basis = Basis(track_rot)
				if has_scale:
					basis = basis.scaled(track_scale)
				if has_pos:
					origin = track_pos
				local = Transform3D(basis, origin)
			"rest_pose":
				local = rest * Transform3D(Basis(pose_delta_rot).scaled(pose_delta_scale), pose_delta_pos)
			"pose_rest":
				local = Transform3D(Basis(pose_delta_rot).scaled(pose_delta_scale), pose_delta_pos) * rest
			"track_local":
				local = Transform3D(Basis(track_rot).scaled(track_scale), track_pos)
			"rest_rot_track_pos":
				var basis := rest.basis
				if has_rot:
					basis = Basis(track_rot)
				if has_scale:
					basis = basis.scaled(track_scale)
				local = Transform3D(basis, track_pos)
		var parent := skeleton.get_bone_parent(bone_index)
		var global := local
		if parent >= 0 and indexed.has(parent):
			global = (indexed[parent] as Transform3D) * local
		indexed[bone_index] = global
		if not semantic.is_empty():
			semantic_out[semantic] = global
	return semantic_out

func _track_position(animation: Animation, tracks: Dictionary, semantic: String, time: float, fallback: Vector3) -> Vector3:
	if tracks.has(semantic):
		var value: Variant = animation.position_track_interpolate(int(tracks[semantic]), time)
		if value is Vector3:
			return value
	return fallback

func _track_rotation(animation: Animation, tracks: Dictionary, semantic: String, time: float, fallback: Quaternion) -> Quaternion:
	if tracks.has(semantic):
		var value: Variant = animation.rotation_track_interpolate(int(tracks[semantic]), time)
		if value is Quaternion:
			return (value as Quaternion).normalized()
	return fallback.normalized()

func _track_scale(animation: Animation, tracks: Dictionary, semantic: String, time: float, fallback: Vector3) -> Vector3:
	if tracks.has(semantic):
		var value: Variant = animation.scale_track_interpolate(int(tracks[semantic]), time)
		if value is Vector3:
			return value
	return fallback

func _basis_error_deg(a: Basis, b: Basis) -> float:
	var qa := a.orthonormalized().get_rotation_quaternion().normalized()
	var qb := b.orthonormalized().get_rotation_quaternion().normalized()
	var dot_value := clampf(absf(qa.dot(qb)), 0.0, 1.0)
	return rad_to_deg(2.0 * acos(dot_value))

func _fail(message: String) -> void:
	printerr("ALABASTER_SOURCE_POSE_COMPOSITION_DIAGNOSTIC_FAILURE: %s" % message)
	quit(1)
