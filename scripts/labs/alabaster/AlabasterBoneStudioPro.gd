extends "res://scripts/labs/alabaster/AlabasterBoneStudio.gd"

# Stabilization shim.
#
# The previous Pro/Profile/LiveTuning inheritance chain became a parser failure
# point in Godot. Keep the scene loading through the proven base Bone Studio while
# the advanced panels are rebuilt as composed child controllers instead of script
# inheritance layers. No global class_name is registered here on purpose.

func _ready() -> void:
	super._ready()
