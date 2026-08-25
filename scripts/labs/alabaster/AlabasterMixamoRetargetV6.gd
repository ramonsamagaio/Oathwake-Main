extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter
# references remain stable. The active implementation is V15: V10's proven
# forward/foot REST calibration, V11 arm stabilization, V12/V13 Juno 2D
# projection polish, V14 lower-limb loop closure, plus adaptive quaternion foot
# continuity that removes localized contact/recovery kicks without clip names.
const V15 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV15.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V15.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
