extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter
# references remain stable. The active implementation is V13: V10's proven
# forward/foot REST calibration, V11 arm stabilization, V12 Juno 2D projection,
# plus profile posture, lower-foot smoothing and a real exclusive loop closure.
const V13 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV13.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V13.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
