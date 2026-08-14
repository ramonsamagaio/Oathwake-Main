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

# A native Juno FBX is not a humanoid source that needs retargeting. These are
# the authored node names used by the source figure and by the Oathwake runtime.
# When enough of these exact bones are present, the importer switches to an
# identity bridge and never subtracts frame zero as a reference pose.
const JUNO_NATIVE_BONES := [
	"root", "top", "head", "headGear", "tail", "tailEnd", "eyes",
	"shoulderL", "shoulderR", "armL", "armR", "handL", "handR",
	"fingerL", "fingerR", "weaponL", "weaponR", "bottom", "hipL",
	"hipR", "legL", "legR", "footL", "footR", "toeL", "toeR",
	"weaponBelt", "sweepRoot", "sweep",
]

const JUNO_NATIVE_REQUIRED := [
	"root", "top", "head", "shoulderL", "shoulderR", "armL", "armR",
	"bottom", "hipL", "hipR", "legL", "legR", "footL", "footR",
]

# The static local positions let the bridge distinguish whether a Godot FBX
# importer emitted absolute local translations or Skeleton3D pose deltas. The
# decision is made once per clip, so large edits in later frames do not make the
# interpretation jump from one convention to the other.
const JUNO_NATIVE_REST_POSITIONS := {
	"root": Vector3(0.0, 0.0, 1.3125),
	"top": Vector3(0.0, 0.0, 0.4375),
	"head": Vector3(0.0, 0.0, 0.4375),
	"headGear": Vector3(0.0, -0.3125, 0.4375),
	"tail": Vector3(0.0, -0.1875, -0.1875),
	"tailEnd": Vector3(0.0, -0.1875, -1.0),
	"eyes": Vector3.ZERO,
	"shoulderL": Vector3(0.16666666666666666, 0.0, -0.125),
	"shoulderR": Vector3(-0.16666666666666666, 0.0, -0.125),
	"armL": Vector3(0.08333333333333333, 0.0, -0.3125),
	"armR": Vector3(-0.08333333333333333, 0.0, -0.3125),
	"handL": Vector3(0.08333333333333333, 0.0, -0.3125),
	"handR": Vector3(-0.08333333333333333, 0.0, -0.3125),
	"fingerL": Vector3(0.041666666666666664, 0.0, -0.1875),
	"fingerR": Vector3(-0.041666666666666664, 0.0, -0.1875),
	"weaponL": Vector3(0.0, 0.5, 0.0),
	"weaponR": Vector3(0.0, 0.5, 0.0),
	"bottom": Vector3(0.0, 0.0, -0.25),
	"hipL": Vector3(0.125, 0.0, 0.0),
	"hipR": Vector3(-0.125, 0.0, 0.0),
	"legL": Vector3(0.0, 0.0, -0.5),
	"legR": Vector3(0.0, 0.0, -0.5),
	"footL": Vector3(0.0, 0.0, -0.5),
	"footR": Vector3(0.0, 0.0, -0.5),
	"toeL": Vector3(0.0, 0.25, 0.0),
	"toeR": Vector3(0.0, 0.25, 0.0),
	"weaponBelt": Vector3(0.0, -0.375, 0.5),
	"sweepRoot": Vector3.ZERO,
	"sweep": Vector3(0.0, 2.0, 0.0),
}

# Only authored source directions that are non-zero are needed to detect whether
# an imported FBX rotation track contains the rest orientation or just pose
# rotation. In a normal Skeleton3D import it is already a pose delta.
const JUNO_NATIVE_REST_DIRECTIONS := {
	"shoulderL": [-90.0, 0.0, 0.0],
	"shoulderR": [90.0, 0.0, 0.0],
	"armL": [-90.0, -74.0, 0.0],
	"armR": [90.0, -74.0, 0.0],
}

# FBX itself cannot carry Alabaster-only sprite-frame sequences and gameplay
# hooks in a portable way. Known native clips keep those source semantics here,
# while Blender owns the actual bone curves. This makes an edit/export/import
# roundtrip preserve more than just the visible pose.
const JUNO_NATIVE_CLIP_META := {
	"walk-smooth": {
		"sample_fps": 20.0,
		"category": "OTHER",
		"animStart": 1,
		"loopStart": 4,
		"repeat": true,
		"nodes": {
			"head": {"frameRepeat": 2, "frames": [0, 2, 1, 0, 1, 2, 1, 0, 1, 2, 0]},
			"tailEnd": {"frameRepeat": 2, "frames": [0, 8, 5, 6, 7, 8, 5, 6, 7, 8, 0]},
		},
		"hooks": {
			4: [{"change": "FIXED", "hook": "STEP", "pos": [-0.125, 0.25, 0.0]}],
			12: [{"change": "FIXED", "hook": "STEP", "pos": [0.125, 0.25, 0.0]}],
			20: [{"change": "FIXED", "hook": "STEP", "pos": [-0.125, 0.25, 0.0]}],
		},
	},
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
	"native_preserve_timing": true,
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
	var native_juno := is_juno_native_skeleton(bones)
	root.free()
	return {
		"ok": true,
		"clips": clips,
		"bones": bones,
		"source_profile": "juno_native" if native_juno else "generic",
		"identity_import": native_juno,
	}


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
	var animation := player.get_animation(clip_name)
	var native_juno := is_juno_native_skeleton(get_source_bones(animation))
	var resolved_settings := DEFAULT_SETTINGS.duplicate(true)
	for key in settings.keys():
		resolved_settings[key] = settings[key]
	if not is_zero_approx(translation_scale):
		resolved_settings["root_translation_scale"] = translation_scale

	var resolved_fps := sample_fps
	var resolved_loop := loop
	if native_juno:
		resolved_settings["native_juno_identity"] = true
		resolved_settings["source_clip_name"] = clip_name
		resolved_settings["remove_reference_pose"] = false
		var native_meta := get_native_clip_metadata(clip_name)
		if bool(resolved_settings.get("native_preserve_timing", true)) and not native_meta.is_empty():
			resolved_fps = float(native_meta.get("sample_fps", sample_fps))
			resolved_loop = bool(native_meta.get("repeat", loop))
			resolved_settings["category"] = str(native_meta.get("category", resolved_settings.get("category", "DEFAULT")))

	var result := convert_animation(animation, resolved_fps, resolved_loop, 0.0, custom_retarget, resolved_settings)
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

	var source_bones := get_source_bones(animation)
	var native_juno := bool(resolved.get("native_juno_identity", false)) or is_juno_native_skeleton(source_bones)
	if native_juno:
		resolved["remove_reference_pose"] = false

	var retarget := _native_retarget_table() if native_juno else MIXAMO_TO_JUNO.duplicate(true)
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
		push_warning("Bone animation has no tracks matching the Juno import profile.")
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

	var native_positions_absolute := native_juno and _native_position_tracks_are_absolute(animation, tracks)
	var native_rotations_absolute := native_juno and _native_rotation_tracks_are_absolute(animation, tracks)
	var source_clip_name := str(resolved.get("source_clip_name", ""))
	var native_meta := get_native_clip_metadata(source_clip_name) if native_juno else {}

	var frame_count := maxi(int(ceil(maxf(animation.length, 1.0 / fps) * fps)), 1)
	var transforms := []
	var native_hooks: Dictionary = native_meta.get("hooks", {}) if not native_meta.is_empty() else {}
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
					if native_juno:
						if native_rotations_absolute:
							var rest_q := _native_rest_quaternion(target)
							q = (rest_q.inverse() * q).normalized()
						xfm["rot"] = _quaternion_to_juno_angles(q)
					else:
						xfm["rot"] = _correct_source_angles(_quaternion_to_source_angles(q), resolved, per_bone)
				Animation.TYPE_POSITION_3D:
					var track_index := int(track["index"])
					var p: Vector3 = animation.position_track_interpolate(track_index, time)
					if native_juno:
						if native_positions_absolute and JUNO_NATIVE_REST_POSITIONS.has(target):
							p -= JUNO_NATIVE_REST_POSITIONS[target] as Vector3
						xfm["trans"] = [p.x, p.y, p.z]
					else:
						var translation_factor := float(resolved.get("root_translation_scale", 0.0))
						if not is_zero_approx(translation_factor) and (target == "root" or target == "bottom"):
							if position_refs.has(track_index):
								p -= position_refs[track_index] as Vector3
							p *= translation_factor
							xfm["trans"] = [p.x, p.y, p.z]
				Animation.TYPE_SCALE_3D:
					var s: Vector3 = animation.scale_track_interpolate(int(track["index"]), time)
					xfm["scale"] = (s.x + s.y + s.z) / 3.0
			node_xfm[target] = xfm
		var transform_entry := {"frame": frame, "spline": str(resolved.get("spline", "LINEAR")), "nodeXfm": node_xfm}
		if native_hooks.has(frame):
			transform_entry["hooks"] = (native_hooks[frame] as Array).duplicate(true)
		transforms.append(transform_entry)

	var category := str(resolved.get("category", "DEFAULT"))
	var anim_start := 0
	var loop_start := 0
	var nodes := {}
	if native_juno and not native_meta.is_empty():
		category = str(native_meta.get("category", category))
		anim_start = int(native_meta.get("animStart", 0))
		loop_start = int(native_meta.get("loopStart", 0))
		var native_nodes: Variant = native_meta.get("nodes", {})
		if native_nodes is Dictionary:
			nodes = (native_nodes as Dictionary).duplicate(true)

	return {
		"category": category,
		"frameCnt": frame_count,
		"frameRepeat": ALABASTER_TICK_RATE / fps,
		"animStart": mini(anim_start, frame_count),
		"loopStart": mini(loop_start, frame_count),
		"repeat": loop,
		"transforms": transforms,
		"nodes": nodes,
		"import_meta": {
			"bridge": "juno_native_identity" if native_juno else "godot_animationplayer_3d_to_alabaster",
			"source_profile": "juno_native" if native_juno else "generic",
			"retarget_mode": "identity" if native_juno else "mapped",
			"sample_fps": fps,
			"alabaster_frame_repeat": ALABASTER_TICK_RATE / fps,
			"remove_reference_pose": bool(resolved.get("remove_reference_pose", true)),
			"top_down_mode": bool(resolved.get("top_down_mode", true)),
			"root_translation_scale": float(resolved.get("root_translation_scale", 0.0)),
			"native_positions_absolute": native_positions_absolute,
			"native_rotations_absolute": native_rotations_absolute,
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


static func is_juno_native_skeleton(source_bones: Array[String]) -> bool:
	if source_bones.is_empty():
		return false
	var normalized := {}
	for source_bone in source_bones:
		normalized[_normalize_bone_name(source_bone)] = true
	for required_bone in JUNO_NATIVE_REQUIRED:
		if not normalized.has(_normalize_bone_name(required_bone)):
			return false
	return true


static func get_native_clip_metadata(clip_name: String) -> Dictionary:
	var meta: Variant = JUNO_NATIVE_CLIP_META.get(clip_name, {})
	return (meta as Dictionary).duplicate(true) if meta is Dictionary else {}


static func make_auto_retarget(source_bones: Array[String]) -> Dictionary:
	var result := {}
	var native_juno := is_juno_native_skeleton(source_bones)
	var native_table := _native_retarget_table() if native_juno else {}
	for source_bone in source_bones:
		var normalized := _normalize_bone_name(source_bone)
		var target := str(native_table.get(normalized, "")) if native_juno else str(MIXAMO_TO_JUNO.get(normalized, ""))
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


static func _native_retarget_table() -> Dictionary:
	var result := {}
	for bone_name in JUNO_NATIVE_BONES:
		result[_normalize_bone_name(bone_name)] = bone_name
	return result


static func _native_position_tracks_are_absolute(animation: Animation, tracks: Array) -> bool:
	var rest_error := 0.0
	var zero_error := 0.0
	var sample_count := 0
	for track in tracks:
		if int(track["type"]) != Animation.TYPE_POSITION_3D:
			continue
		var target := str(track["target"])
		if not JUNO_NATIVE_REST_POSITIONS.has(target):
			continue
		var p: Vector3 = animation.position_track_interpolate(int(track["index"]), 0.0)
		var rest: Vector3 = JUNO_NATIVE_REST_POSITIONS[target]
		rest_error += p.distance_to(rest)
		zero_error += p.length()
		sample_count += 1
	return sample_count > 0 and rest_error + 0.0001 < zero_error


static func _native_rotation_tracks_are_absolute(animation: Animation, tracks: Array) -> bool:
	var direct_error := 0.0
	var stripped_error := 0.0
	var sample_count := 0
	for track in tracks:
		if int(track["type"]) != Animation.TYPE_ROTATION_3D:
			continue
		var target := str(track["target"])
		if target != "shoulderL" and target != "shoulderR":
			continue
		var q: Quaternion = animation.rotation_track_interpolate(int(track["index"]), 0.0).normalized()
		var rest_q := _native_rest_quaternion(target)
		direct_error += absf(q.get_angle())
		stripped_error += absf((rest_q.inverse() * q).normalized().get_angle())
		sample_count += 1
	return sample_count > 0 and stripped_error + deg_to_rad(10.0) < direct_error


static func _native_rest_quaternion(bone_name: String) -> Quaternion:
	var raw: Variant = JUNO_NATIVE_REST_DIRECTIONS.get(bone_name, [0.0, 0.0, 0.0])
	var angles: Array = raw as Array
	return _juno_angles_to_quaternion([float(angles[0]), float(angles[1]), float(angles[2])])


static func _bone_name_from_track_path(path: NodePath) -> String:
	var text := str(path)
	var separator := text.rfind(":")
	return text.substr(separator + 1) if separator >= 0 else text.get_file()


static func _normalize_bone_name(value: String) -> String:
	return value.to_lower().replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "").replace(" ", "").replace("-", "").replace("_", "")


static func _juno_angles_to_quaternion(raw: Array) -> Quaternion:
	# Source bundle semantics: Quaternion.setAngles(yaw,pitch,roll) calls
	# glMatrix.fromEuler(pitch, roll, yaw), i.e. X=pitch, Y=roll, Z=yaw.
	var x := deg_to_rad(float(raw[1])) * 0.5
	var y := deg_to_rad(float(raw[2])) * 0.5
	var z := deg_to_rad(float(raw[0])) * 0.5
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


static func _quaternion_to_juno_angles(q: Quaternion) -> Array:
	# Exact inverse of _juno_angles_to_quaternion for the native path. Equivalent
	# Euler representations are fine because the Alabaster runtime rebuilds the
	# same quaternion before applying the pose.
	var n := q.normalized()
	var sin_roll_y := clampf(2.0 * (n.w * n.y - n.z * n.x), -1.0, 1.0)
	var pitch_x := atan2(2.0 * (n.w * n.x + n.y * n.z), 1.0 - 2.0 * (n.x * n.x + n.y * n.y))
	var roll_y := asin(sin_roll_y)
	var yaw_z := atan2(2.0 * (n.w * n.z + n.x * n.y), 1.0 - 2.0 * (n.y * n.y + n.z * n.z))
	return [rad_to_deg(yaw_z), rad_to_deg(pitch_x), rad_to_deg(roll_y)]


static func _quaternion_to_source_angles(q: Quaternion) -> Array:
	# Legacy/generic bridge kept intact for Mixamo and other humanoid sources.
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
