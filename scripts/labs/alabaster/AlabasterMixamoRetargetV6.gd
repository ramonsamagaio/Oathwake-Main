extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter callers
# remain stable. Production routes through V16. UAL/Unreal skeletons take a tiny
# semantic-name bridge first, then enter the SAME V16 solver used by Mixamo.
const V16 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV16.gd")
const UALAdapter := preload("res://scripts/labs/alabaster/AlabasterUALRetargetAdapter.gd")

static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	if UALAdapter.detect_skeleton(skeleton):
		return UALAdapter.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
	return V16.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
