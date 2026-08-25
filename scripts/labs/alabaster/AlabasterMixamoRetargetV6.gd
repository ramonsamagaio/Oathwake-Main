extends RefCounted
class_name AlabasterMixamoRetargetV6

# Compatibility entry point kept so existing Bone Studio/source-adapter
# references remain stable. The active implementation is now the REST-calibrated
# V10 solver. V10 preserves the older V8 comparison modes through RETARGET DEBUG.
const V10 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV10.gd")


static func convert_scene(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	return V10.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
