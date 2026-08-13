extends RefCounted
class_name AlabasterSmartBoneAnimationImporter

const Legacy := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationImporter.gd")
const Profile := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetProfile.gd")
const MixamoConverter := preload("res://scripts/labs/alabaster/AlabasterMixamoAnimationConverter.gd")

static func get_source_bones(animation: Animation) -> Array[String]:
	return Legacy.get_source_bones(animation)

static func find_animation_player(node: Node) -> AnimationPlayer:
	return Legacy.find_animation_player(node)

static func detect_source_profile(source_bones: Array[String]) -> String:
	return "mixamo" if Profile.detect(source_bones) else "generic"

static func make_auto_retarget(source_bones: Array[String]) -> Dictionary:
	return Profile.make_auto_map(source_bones) if Profile.detect(source_bones) else Legacy.make_auto_retarget(source_bones)

static func convert_animation(animation: Animation, sample_fps := 60.0, loop := true, translation_scale := 0.0, custom_retarget: Dictionary = {}, settings: Dictionary = {}) -> Dictionary:
	if animation == null:
		return {}
	var bones := get_source_bones(animation)
	if Profile.detect(bones) and _mapping_is_auto(bones, custom_retarget):
		return MixamoConverter.convert(animation, sample_fps, loop, translation_scale, settings)
	return Legacy.convert_animation(animation, sample_fps, loop, translation_scale, custom_retarget, settings)

static func _mapping_is_auto(source_bones: Array[String], mapping: Dictionary) -> bool:
	if mapping.is_empty():
		return true
	var expected := Profile.make_auto_map(source_bones)
	for bone in source_bones:
		if str(mapping.get(bone, "")) != str(expected.get(bone, "")):
			return false
	return true
