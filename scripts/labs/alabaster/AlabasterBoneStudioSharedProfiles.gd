extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"

# Stabilization wrapper for the Bone Studio.
#
# IMPORTANT:
# This script intentionally uses path-based inheritance only. The previous
# Profiles/LiveTuning inheritance chain registered global script classes and a
# parse failure in any one layer prevented the entire Bone Studio from loading.
# Keeping the scene entry script as a thin wrapper lets the proven Pro editor
# compile independently while the profile/live-tuning UI is rebuilt by
# composition instead of inheritance.


func _ready() -> void:
	super._ready()
