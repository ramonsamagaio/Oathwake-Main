extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter
# references remain stable. The active implementation is now the target-aware
# V9 solver. V9 can still delegate to the V8 full-delta/segment modes for A/B
# comparison through RETARGET DEBUG.
const V9 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV9.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V9.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
