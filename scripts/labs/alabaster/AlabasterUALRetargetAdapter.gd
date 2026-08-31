extends RefCounted
class_name AlabasterUALRetargetAdapter

# UAL/Unreal -> canonical humanoid bridge.
#
# IMPORTANT: this class does NOT implement a second retarget solver. It only
# translates UAL bone vocabulary to the canonical semantic names expected by the
# existing Mixamo -> Juno V16 pipeline, then delegates the complete solve to V16.
# Therefore UAL inherits the exact same proven behavior that fixed Walking.fbx:
# target REST characterization, handedness/reflection, two-vector limb planes,
# temporal lower-limb stabilization, loop closure and runtime rotation codec.

const Profile := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetProfile.gd")
const V16 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV16.gd")

static func detect_skeleton(skeleton: Skeleton3D) -> bool:
	if skeleton == null:
		return false
	var names: Array[String] = []
	for i in range(skeleton.get_bone_count()):
		names.append(skeleton.get_bone_name(i))
	return Profile.detect_ual(names)

static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	if player == null or skeleton == null or clip_name.is_empty() or not player.has_animation(clip_name):
		return {}
	if not detect_skeleton(skeleton):
		return V16.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)

	var source_animation := player.get_animation(clip_name)
	if source_animation == null:
		return {}
	var canonical_skeleton := _clone_canonical_skeleton(skeleton)
	var canonical_animation := _clone_canonical_animation(source_animation)
	if canonical_skeleton == null or canonical_animation == null:
		if canonical_skeleton != null:
			canonical_skeleton.free()
		return {}

	var temp_player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	library.add_animation(clip_name, canonical_animation)
	temp_player.add_animation_library("", library)

	var tuned_settings := settings.duplicate(true)
	tuned_settings["ual_source_profile"] = "UAL1_UNREAL_STANDARD"
	tuned_settings["ual_semantic_bridge"] = true
	var result := V16.convert_scene(
		temp_player,
		canonical_skeleton,
		clip_name,
		sample_fps,
		loop,
		translation_scale,
		tuned_settings
	)

	temp_player.free()
	canonical_skeleton.free()
	if result.is_empty():
		return result
	var meta_value: Variant = result.get("import_meta", {})
	var meta := (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	meta["source_profile"] = "ual_unreal"
	meta["ual_semantic_bridge"] = true
	meta["ual_solver"] = "canonical semantic adapter -> Mixamo/Juno V16"
	meta["ual_inherits_v16_handedness_fix"] = true
	meta["ual_inherits_v16_runtime_rotation_codec"] = true
	result["import_meta"] = meta
	print("ALABASTER_UAL_V16_OK clip=%s frames=%d profile=%s" % [
		clip_name,
		int(result.get("frameCnt", 0)),
		str(meta.get("retarget_profile", "")),
	])
	return result

static func _clone_canonical_skeleton(source: Skeleton3D) -> Skeleton3D:
	var clone := Skeleton3D.new()
	var used := {}
	for i in range(source.get_bone_count()):
		var source_name := source.get_bone_name(i)
		var canonical := _canonical_name(source_name)
		if canonical.is_empty():
			canonical = source_name
		var unique_name := canonical
		var suffix := 2
		while used.has(unique_name):
			unique_name = "%s__%d" % [canonical, suffix]
			suffix += 1
		used[unique_name] = true
		clone.add_bone(unique_name)
		clone.set_bone_rest(i, source.get_bone_rest(i))
		clone.set_bone_pose_position(i, source.get_bone_pose_position(i))
		clone.set_bone_pose_rotation(i, source.get_bone_pose_rotation(i))
		clone.set_bone_pose_scale(i, source.get_bone_pose_scale(i))
	for i in range(source.get_bone_count()):
		clone.set_bone_parent(i, source.get_bone_parent(i))
	return clone

static func _clone_canonical_animation(source: Animation) -> Animation:
	var clone := source.duplicate(true) as Animation
	if clone == null:
		return null
	for track_index in range(clone.get_track_count()):
		var track_type := clone.track_get_type(track_index)
		if track_type != Animation.TYPE_ROTATION_3D and track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_SCALE_3D:
			continue
		var path := clone.track_get_path(track_index)
		var bone_name := _bone_name_from_track_path(path)
		var canonical := _canonical_name(bone_name)
		if canonical.is_empty() or canonical == bone_name:
			continue
		var text := str(path)
		var separator := text.rfind(":")
		if separator >= 0:
			clone.track_set_path(track_index, NodePath(text.substr(0, separator + 1) + canonical))
		else:
			clone.track_set_path(track_index, NodePath(canonical))
	return clone

static func _canonical_name(source_name: String) -> String:
	var clean := source_name.to_lower().replace(" ", "").replace("-", "")
	if Profile.UAL_ALIASES.has(clean):
		return str(Profile.UAL_ALIASES[clean])
	return source_name

static func _bone_name_from_track_path(path: NodePath) -> String:
	var text := str(path)
	var separator := text.rfind(":")
	return text.substr(separator + 1) if separator >= 0 else text.get_file()
