extends SceneTree

const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const SOURCE_PATH := "res://assets/anims/UAL1_Standard.glb"


func _initialize() -> void:
	var info: Dictionary = SourceAdapter.inspect_scene(SOURCE_PATH)
	print("ALABASTER_UAL1_INSPECT ok=%s kind=%s profile=%s mode=%s skeleton=%s clips=%d bones=%d" % [
		str(bool(info.get("ok", false))),
		str(info.get("resource_kind", "")),
		str(info.get("retarget_profile", "")),
		str(info.get("retarget_mode", "")),
		str(bool(info.get("has_skeleton", false))),
		(info.get("clips", []) as Array).size(),
		(info.get("bones", []) as Array).size(),
	])
	if not bool(info.get("ok", false)):
		push_error("ALABASTER_UAL1_DIAGNOSTIC_FAILURE: %s" % str(info.get("error", "unknown error")))
		quit(1)
		return

	var clips_value: Variant = info.get("clips", [])
	var bones_value: Variant = info.get("bones", [])
	var clips: Array = clips_value as Array if clips_value is Array else []
	var bones: Array = bones_value as Array if bones_value is Array else []
	print("ALABASTER_UAL1_CLIPS_JSON %s" % JSON.stringify(clips))
	print("ALABASTER_UAL1_TRACK_BONES_JSON %s" % JSON.stringify(bones))

	var opened: Dictionary = SourceAdapter.open_preview_source(SOURCE_PATH)
	if not bool(opened.get("ok", false)):
		push_error("ALABASTER_UAL1_DIAGNOSTIC_FAILURE: could not reopen source: %s" % str(opened.get("error", "unknown error")))
		quit(1)
		return

	var player := opened.get("player") as AnimationPlayer
	var skeleton := opened.get("skeleton") as Skeleton3D
	if skeleton != null:
		var skeleton_bones: Array[String] = []
		for bone_index in range(skeleton.get_bone_count()):
			skeleton_bones.append(skeleton.get_bone_name(bone_index))
		print("ALABASTER_UAL1_SKELETON_BONES_JSON %s" % JSON.stringify(skeleton_bones))

	if player == null:
		SourceAdapter.close_preview_source(opened)
		push_error("ALABASTER_UAL1_DIAGNOSTIC_FAILURE: source has no AnimationPlayer")
		quit(1)
		return

	for clip_value in clips:
		var clip_name := str(clip_value)
		if not player.has_animation(clip_name):
			continue
		var animation := player.get_animation(clip_name)
		if animation == null:
			continue
		var clip_bones: Array[String] = []
		for bone_value in SourceAdapter.make_auto_retarget(bones).keys():
			var bone_name := str(bone_value)
			if bones.has(bone_name):
				clip_bones.append(bone_name)
		var mapping: Dictionary = SourceAdapter.make_auto_retarget(clip_bones)
		var mapped_count := 0
		for target_value in mapping.values():
			if not str(target_value).is_empty():
				mapped_count += 1
		print("ALABASTER_UAL1_CLIP name=%s length=%.4f tracks=%d mapped=%d/%d" % [
			clip_name,
			animation.length,
			animation.get_track_count(),
			mapped_count,
			clip_bones.size(),
		])

	SourceAdapter.close_preview_source(opened)
	print("ALABASTER_UAL1_DIAGNOSTIC_OK clips=%d bones=%d" % [clips.size(), bones.size()])
	quit(0)
