extends RefCounted
class_name AlabasterBoneAnimationImporter

# Godot is the interchange layer: FBX/GLB from Mixamo, Blender or Unity is
# imported normally, then this bridge samples its AnimationPlayer and converts
# local bone rotations into the same transform dictionary used by the Juno rig.
const MIXAMO_TO_JUNO := {
	"root": "root",
	"hips": "bottom",
	"spine2": "top",
	"head": "head",
	"leftarm": "shoulderL",
	"leftforearm": "armL",
	"lefthand": "handL",
	"lefthandindex1": "fingerL",
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


static func import_scene_clip(scene_path: String, clip_name: String, sample_fps := 60.0, loop := true, translation_scale := 0.0, custom_retarget: Dictionary = {}) -> Dictionary:
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
	var animation := player.get_animation(clip_name)
	var result := convert_animation(animation, sample_fps, loop, translation_scale, custom_retarget)
	root.free()
	return result


static func convert_animation(animation: Animation, sample_fps := 60.0, loop := true, translation_scale := 0.0, custom_retarget: Dictionary = {}) -> Dictionary:
	if animation == null:
		return {}
	var fps := maxf(sample_fps, 1.0)
	var retarget := MIXAMO_TO_JUNO.duplicate(true)
	for source_name in custom_retarget.keys():
		retarget[_normalize_bone_name(str(source_name))] = str(custom_retarget[source_name])

	var tracks := []
	for track_index in range(animation.get_track_count()):
		var track_type := animation.track_get_type(track_index)
		if track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_SCALE_3D:
			continue
		var source_bone := _bone_name_from_track_path(animation.track_get_path(track_index))
		var target_bone := str(retarget.get(_normalize_bone_name(source_bone), ""))
		if target_bone.is_empty():
			continue
		tracks.append({"index": track_index, "type": track_type, "target": target_bone})

	if tracks.is_empty():
		push_warning("Bone animation has no tracks matching the Juno retarget profile.")
		return {}

	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var transforms := []
	for frame in range(frame_count):
		var time := minf(float(frame) / fps, animation.length)
		var node_xfm := {}
		for track in tracks:
			var target := str(track["target"])
			if not node_xfm.has(target):
				node_xfm[target] = {"rot": [0.0, 0.0, 0.0], "trans": [0.0, 0.0, 0.0], "scale": 1.0}
			var xfm: Dictionary = node_xfm[target]
			match int(track["type"]):
				Animation.TYPE_ROTATION_3D:
					var q: Quaternion = animation.rotation_track_interpolate(int(track["index"]), time)
					xfm["rot"] = _quaternion_to_source_angles(q)
				Animation.TYPE_POSITION_3D:
					if not is_zero_approx(translation_scale):
						var p: Vector3 = animation.position_track_interpolate(int(track["index"]), time) * translation_scale
						xfm["trans"] = [p.x, p.y, p.z]
				Animation.TYPE_SCALE_3D:
					var s: Vector3 = animation.scale_track_interpolate(int(track["index"]), time)
					xfm["scale"] = (s.x + s.y + s.z) / 3.0
			node_xfm[target] = xfm
		transforms.append({"frame": frame, "spline": "LINEAR", "nodeXfm": node_xfm})

	return {
		"category": "DEFAULT",
		"frameCnt": frame_count,
		"frameRepeat": 1,
		"animStart": 0,
		"loopStart": 0,
		"repeat": loop,
		"transforms": transforms,
		"nodes": {},
		"import_meta": {"bridge": "godot_skeleton3d", "sample_fps": fps, "translation_scale": translation_scale},
	}


static func install_on_rig(rig: Object, animation_name: String, animation_data: Dictionary) -> bool:
	if rig == null or not rig.has_method("install_runtime_animation"):
		return false
	return bool(rig.call("install_runtime_animation", animation_name, animation_data))


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
	# Juno's source stores [yaw,pitch,roll], while the runtime rebuild maps those
	# to quaternion Z/X/Y axes. This axis swap converts Godot local Euler values
	# into the source convention. Per-skeleton rest-pose offsets can be supplied
	# later as a retarget profile without changing the animation format.
	var euler := q.normalized().get_euler()
	return [rad_to_deg(euler.z), rad_to_deg(euler.x), rad_to_deg(euler.y)]
