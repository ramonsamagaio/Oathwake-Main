extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"

# Parser-safe compatibility wrapper.
# Profile switching and Live Tuning will be reintroduced by composition so this
# file can no longer poison the Bone Studio class chain during project reload.

func _ready() -> void:
	super._ready()
