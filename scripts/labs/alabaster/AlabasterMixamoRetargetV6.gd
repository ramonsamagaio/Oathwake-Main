extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter
# references remain stable. The active implementation is V11: V10's proven
# forward/foot REST calibration plus a surgical upper-arm swing stabilization.
const V11 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV11.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V11.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
