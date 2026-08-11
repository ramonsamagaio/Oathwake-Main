extends RefCounted
class_name AlabasterMixamoAnimationConverter

const Profile := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetProfile.gd")
const TICK_RATE := 60.0

static func convert(animation: Animation, sample_fps: float, loop: bool, translation_scale: float, settings: Dictionary) -> Dictionary:
	var fps := maxf(sample_fps, 1.0)
	var subtract_first := bool(settings.get("remove_reference_pose", false))
	var rotation_tracks := {}
	var position_tracks := {}
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_POSITION_3D:
			continue
		var source := Profile.normalize(_bone_name(animation.track_get_path(track_index)))
		if track_type == Animation.TYPE_ROTATION_3D:
			rotation_tracks[source] = track_index
		else:
			position_tracks[source] = track_index
	if rotation_tracks.is_empty():
		return {}

	var refs := {}
	if subtract_first:
		for target in Profile.TARGET_CHAINS.keys():
			refs[target] = _sample_chain(animation, rotation_tracks, Profile.TARGET_CHAINS[target], 0.0)

	var hips_ref := Vector3.ZERO
	if position_tracks.has("hips"):
		hips_ref = animation.position_track_interpolate(int(position_tracks["hips"]), 0.0)
	var root_scale := float(settings.get("root_translation_scale", translation_scale))
	if not is_zero_approx(translation_scale):
		root_scale = translation_scale

	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var transforms: Array = []
	for frame in range(frame_count + 1):
		var time := minf(float(frame) / fps, animation.length)
		var node_xfm := {}
		for target_value in Profile.TARGET_CHAINS.keys():
			var target := str(target_value)
			var chain: Array = Profile.TARGET_CHAINS[target]
			if not _has_track(rotation_tracks, chain):
				continue
			var q := _sample_chain(animation, rotation_tracks, chain, time)
			if subtract_first:
				var ref: Quaternion = refs.get(target, Quaternion.IDENTITY)
				q = (ref.inverse() * q).normalized()
			node_xfm[target] = {"rot": _angles(q, settings), "trans": [0.0, 0.0, 0.0], "scale": 1.0}

		if not is_zero_approx(root_scale) and position_tracks.has("hips"):
			var p := animation.position_track_interpolate(int(position_tracks["hips"]), time) - hips_ref
			p *= root_scale
			if not node_xfm.has("root"):
				node_xfm["root"] = {"rot": [0.0, 0.0, 0.0], "trans": [0.0, 0.0, 0.0], "scale": 1.0}
			var root_xfm: Dictionary = node_xfm["root"]
			root_xfm["trans"] = [p.x, p.y, p.z]
			node_xfm["root"] = root_xfm
		transforms.append({"frame": frame, "spline": str(settings.get("spline", "LINEAR")), "nodeXfm": node_xfm})

	print("ALABASTER_MIXAMO_SMART_RETARGET frames=%d tracks=%d subtract_first=%s" % [frame_count, rotation_tracks.size(), str(subtract_first)])
	return {
		"category": str(settings.get("category", "DEFAULT")),
		"frameCnt": frame_count,
		"frameRepeat": TICK_RATE / fps,
		"animStart": 0,
		"loopStart": 0,
		"repeat": loop,
		"transforms": transforms,
		"nodes": {},
		"import_meta": {"bridge": "mixamo_smart_chain_to_alabaster", "retarget_profile": "MIXAMO_SMART_CHAIN_V1", "sample_fps": fps, "subtract_first_animation_frame": subtract_first},
	}

static func _sample_chain(animation: Animation, tracks: Dictionary, chain: Array, time: float) -> Quaternion:
	var result := Quaternion.IDENTITY
	for source_value in chain:
		var source := str(source_value)
		if tracks.has(source):
			result = (result * animation.rotation_track_interpolate(int(tracks[source]), time).normalized()).normalized()
	return result

static func _has_track(tracks: Dictionary, chain: Array) -> bool:
	for source_value in chain:
		if tracks.has(str(source_value)):
			return true
	return false

static func _bone_name(path: NodePath) -> String:
	var text := str(path)
	var split := text.rfind(":")
	return text.substr(split + 1) if split >= 0 else text.get_file()

static func _angles(q: Quaternion, settings: Dictionary) -> Array:
	var e := q.normalized().get_euler()
	var yaw := rad_to_deg(e.z) * float(settings.get("yaw_scale", 1.0)) + float(settings.get("yaw_correction_degrees", 0.0))
	var pitch := rad_to_deg(e.x) * float(settings.get("pitch_scale", 1.0)) + float(settings.get("pitch_correction_degrees", 0.0))
	var roll := rad_to_deg(e.y) * float(settings.get("roll_scale", 1.0)) + float(settings.get("roll_correction_degrees", 0.0))
	if bool(settings.get("top_down_mode", true)):
		pitch = clampf(pitch, -170.0, 170.0)
		roll = clampf(roll, -170.0, 170.0)
	return [yaw, pitch, roll]
