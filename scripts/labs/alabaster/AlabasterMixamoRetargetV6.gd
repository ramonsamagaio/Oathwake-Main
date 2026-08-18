extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter
# references remain stable. The active implementation is the Juno-first V8
# semantic REST-delta retarget.
const V8 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV8.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V8.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
