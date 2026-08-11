extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/adapter references do
# not break while the implementation advances. V7 deliberately bypasses the
# detached Skeleton3D pose cache and composes the imported animation tracks
# through the real FBX bone hierarchy itself.

const V7 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV7.gd")


static func convert_scene(player: AnimationPlayer, skeleton: Skeleton3D, clip_name: String, sample_fps: float, loop: bool, translation_scale: float, settings: Dictionary) -> Dictionary:
	return V7.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
