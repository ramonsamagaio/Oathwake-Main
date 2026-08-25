extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter
# references remain stable. V14 remains the validated retarget solve: V10 REST
# forward/handedness calibration, V11 arm stabilization, V12/V13 Juno 2D polish
# and V14 lower-limb loop continuity. The rejected V15 temporal foot filter is
# deliberately bypassed because its own Walking diagnostic increased curvature.
const V14 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV14.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V14.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
