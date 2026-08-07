extends RefCounted
class_name AlabasterBoneAnimationImporter

# Godot is the interchange layer: FBX/GLB from Mixamo, Blender or Unity is
# imported normally, then this bridge samples Animation tracks and converts
# local 3D bone motion into the same transform dictionary used by Juno.
const MIXAMO_TO_JUNO := {
	"root": "root",
	"hips": "bottom",
	"spine": "top",
	"spine1": "top",
	"spine2": "top",
	"neck": "head",
	"head": "head",
	"leftshoulder": "shoulderL",
	"leftarm": "shoulderL",
	"leftforearm": "armL",
	"lefthand": "handL",
	"lefthandindex1": "fingerL",
	"rightshoulder": "shoulderR",
	"rightarm": "shoulderR",
	"rightforearm": "armR",
	"righthand": "handR",
	"righthandindex1": "fingerR",
	"leftupleg": "hipL",
	"leftleg": "legL",
	"leftfoot": "footL",
	"lefttoebase": "toeL",
	"rightupleg": "hipR",
	"rightleg": "legR",
	"rightfoot": "footR",
	"righttoebase": "toeR",
}

const DEFAULT_SETTINGS := {
	"remove_reference_pose": true,
	"top_down_mode": true,
	"yaw_correction_degrees": 0.0,
	"pitch_correction_degrees": 0.0,
	"roll_correction_degrees": 0.0,
	"yaw_scale": 1.0,
	"pitch_scale": 1.0,
	"roll_scale": 1.0,
	"root_translation_scale": 0.0,
	"category": "DEFAULT",
	"spline": "LINEAR",
}

const ALABASTER_TICK_RATE := 60.0


static func inspect_scene(scene_path: String) -> Dictionary:
	if not ResourceLoader.exists(scene_path):
		return {"ok": false, "error": "Source scene not found: %s" % scene_path}
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {"ok": false, "error": "Source is not an imported PackedScene."}
	var root := packed.instantiate()
	var player := _find_animation_player(root)
	if player == null:
		root.free()
		return {"ok": false, "error": "No AnimationPlayer found in source scene."}
	var clips: Array[String] = []
	var bones: Array[String] = []
	for clip_name_value in player.get_animation_list():
		var clip_name := str(clip_name_value)
		clips.append(clip_name)
		var animation := player.get_animation(clip_name)
		for bone_name in get_source_bones(animation):
			if not bones.has(bone_name):
				bones.append(bone_name)
	clips.sort()
	bones.sort()
	root.free()
	return {"ok": true, "clips": clips, "bones": bones}


static func import_scene_clip(scene_path: String, clip_name: String, sample_fps := 60.0, loop := true, translation_scale := 0.0, custom_retarget: Dictionary = {}, settings: Dictionary = {}) -> Dictionary:
	if not ResourceLoader.exists(scene_path):
		push_warning("Bone animation source scene not found: %s" % scene_path)
		return {}
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {}
	var root := packed.instantiate()
	var player := _find_animation_player(root)
	if player == null or not player.has_animation(clip_name):
		root.free()
		push_warning("Animation '%s' not found in %s" % [clip_name, scene_path])
		return {}
	var resolved_settings := DEFAULT_SETTINGS.duplicate(true)
	for key in settings.keys():
		resolved_settings[key] = settings[key]
	if not is_zero_approx(translation_scale):
		resolved_settings["root_translation_scale"] = translation_scale
	var animation := player.get_animation(clip_name)
	var result := convert_animation(animation, sample_fps, loop, 0.0, custom_retarget, resolved_settings)
	root.free()
	return result


static func convert_animation(animation: Animation, sample_fps := 60.0, loop := true, translation_scale := 0.0, custom_retarget: Dictionary = {}, settings: Dictionary = {}) -> Dictionary:
	if animation == null:
		return {}
	var fps := maxf(sample_fps, 1.0)
	var resolved := DEFAULT_SETTINGS.duplicate(true)
	for key in settings.keys():
		resolved[key] = settings[key]
	if not is_zero_approx(translation_scale):
		resolved["root_translation_scale"] = translation_scale

	var retarget := MIXAMO_TO_JUNO.duplicate(true)
	for source_name in custom_retarget.keys():
		retarget[_normalize_bone_name(str(source_name))] = custom_retarget[source_name]

	var tracks := []
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_SCALE_3D:
			continue
		var source_bone := _bone_name_from_track_path(animation.track_get_path(track_index))
		var map_entry: Variant = retarget.get(_normalize_bone_name(source_bone), "")
		var target_bone := ""
		var per_bone := {}
		if map_entry is Dictionary:
			per_bone = (map_entry as Dictionary).duplicate(true)
			target_bone = str(per_bone.get("target", ""))
		else:
			target_bone = str(map_entry)
		if target_bone.is_empty():
			continue
		tracks.append({"index": track_index, "type": track_type, "source": source_bone, "target": target_bone, "settings": per_bone})

	if tracks.is_empty():
		push_warning("Bone animation has no tracks matching the Juno retarget profile.")
		return {}

	var rotation_refs := {}
	var position_refs := {}
	if bool(resolved.get("remove_reference_pose", true)):
		for track in tracks:
			var track_index := int(track["index"])
			match int(track["type"]):
				Animation.TYPE_ROTATION_3D:
					rotation_refs[track_index] = animation.rotation_track_interpolate(track_index, 0.0).normalized()
				Animation.TYPE_POSITION_3D:
					position_refs[track_index] = animation.position_track_interpolate(track_index, 0.0)

	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var transforms := []
	for frame in range(frame_count + 1):
		var time := minf(float(frame) / fps, animation.length)
		var node_xfm := {}
		for track in tracks:
			var target := str(track["target"])
			if not node_xfm.has(target):
				node_xfm[target] = {"rot": [0.0, 0.0, 0.0], "trans": [0.0, 0.0, 0.0], "scale": 1.0}
			var xfm: Dictionary = node_xfm[target]
			var per_bone: Dictionary = track["settings"]
			match int(track["type"]):
				Animation.TYPE_ROTATION_3D:
					var track_index := int(track["index"])
					var q: Quaternion = animation.rotation_track_interpolate(track_index, time).normalized()
					if rotation_refs.has(track_index):
						var reference: Quaternion = rotation_refs[track_index]
						q = (reference.inverse() * q).normalized()
					xfm["rot"] = _correct_source_angles(_quaternion_to_source_angles(q), resolved, per_bone)
				Animation.TYPE_POSITION_3D:
					var translation_factor := float(resolved.get("root_translation_scale", 0.0))
					if not is_zero_approx(translation_factor) and (target == "root" or target == "bottom"):
						var track_index := int(track["index"])
						var p: Vector3 = animation.position_track_interpolate(track_index, time)
						if position_refs.has(track_index):
							p -= position_refs[track_index] as Vector3
						p *= translation_factor
						xfm["trans"] = [p.x, p.y, p.z]
				Animation.TYPE_SCALE_3D:
					var s: Vector3 = animation.scale_track_interpolate(int(track["index"]), time)
					xfm["scale"] = (s.x + s.y + s.z) / 3.0
			node_xfm[target] = xfm
		transforms.append({"frame": frame, "spline": str(resolved.get("spline", "LINEAR")), "nodeXfm": node_xfm})

	return {
		"category": str(resolved.get("category", "DEFAULT")),
		"frameCnt": frame_count,
		"frameRepeat": ALABASTER_TICK_RATE / fps,
		"animStart": 0,
		"loopStart": 0,
		"repeat": loop,
		"transforms": transforms,
		"nodes": {},
		"import_meta": {
			"bridge": "godot_animationplayer_3d_to_alabaster",
			"sample_fps": fps,
			"alabaster_frame_repeat": ALABASTER_TICK_RATE / fps,
			"remove_reference_pose": bool(resolved.get("remove_reference_pose", true)),
			"top_down_mode": bool(resolved.get("top_down_mode", true)),
			"root_translation_scale": float(resolved.get("root_translation_scale", 0.0)),
		},
	}


static func get_source_bones(animation: Animation) -> Array[String]:
	var names: Array[String] = []
	if animation == null:
		return names
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_SCALE_3D:
			continue
		var bone_name := _bone_name_from_track_path(animation.track_get_path(track_index))
		if not bone_name.is_empty() and not names.has(bone_name):
			names.append(bone_name)
	names.sort()
	return names


static func make_auto_retarget(source_bones: Array[String]) -> Dictionary:
	var result := {}
	for source_bone in source_bones:
		var target := str(MIXAMO_TO_JUNO.get(_normalize_bone_name(source_bone), ""))
		result[source_bone] = target
	return result


static func install_on_rig(rig: Object, animation_name: String, animation_data: Dictionary) -> bool:
	if rig == null or not rig.has_method("install_runtime_animation"):
		return false
	return bool(rig.call("install_runtime_animation", animation_name, animation_data))


static func find_animation_player(node: Node) -> AnimationPlayer:
	return _find_animation_player(node)


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


static func _bone_name_from_track_path(path: NodePath) -> String:
	var text := str(path)
	var separator := text.rfind(":")
	return text.substr(separator + 1) if separator >= 0 else text.get_file()


static func _normalize_bone_name(value: String) -> String:
	return value.to_lower().replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "").replace(" ", "").replace("-", "").replace("_", "")


static func _quaternion_to_source_angles(q: Quaternion) -> Array:
	# Juno stores [yaw,pitch,roll]. The source runtime rebuild maps these into
	# quaternion Z/X/Y axes, therefore Godot Euler X/Y/Z is re-ordered here.
	var euler := q.normalized().get_euler()
	return [rad_to_deg(euler.z), rad_to_deg(euler.x), rad_to_deg(euler.y)]


static func _correct_source_angles(raw: Array, global_settings: Dictionary, per_bone: Dictionary) -> Array:
	var yaw := float(raw[0]) * float(per_bone.get("yaw_scale", global_settings.get("yaw_scale", 1.0)))
	var pitch := float(raw[1]) * float(per_bone.get("pitch_scale", global_settings.get("pitch_scale", 1.0)))
	var roll := float(raw[2]) * float(per_bone.get("roll_scale", global_settings.get("roll_scale", 1.0)))
	yaw += float(global_settings.get("yaw_correction_degrees", 0.0)) + float(per_bone.get("yaw_offset", 0.0))
	pitch += float(global_settings.get("pitch_correction_degrees", 0.0)) + float(per_bone.get("pitch_offset", 0.0))
	roll += float(global_settings.get("roll_correction_degrees", 0.0)) + float(per_bone.get("roll_offset", 0.0))
	if bool(global_settings.get("top_down_mode", true)):
		# Clamp pathological imported flips but keep Juno's broad 3D articulation.
		pitch = clampf(pitch, -170.0, 170.0)
		roll = clampf(roll, -170.0, 170.0)
	return [yaw, pitch, roll]
