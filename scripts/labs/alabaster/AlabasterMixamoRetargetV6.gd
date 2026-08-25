extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter callers
# remain stable. Production now routes through V16: V14 anatomical/presentation
# solve plus an exact inverse of Juno's real runtime rotation codec.
const V16 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV16.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V16.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
