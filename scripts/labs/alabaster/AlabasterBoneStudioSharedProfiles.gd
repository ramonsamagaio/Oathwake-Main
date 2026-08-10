extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"

# Stable Bone Studio entry point. Live Tuning is loaded dynamically at runtime.
# If the optional panel ever fails to parse/load, the base Bone Studio still
# opens instead of becoming part of the same parser failure chain.

const LIVE_TUNING_PANEL_PATH = "res://scripts/labs/alabaster/AlabasterBoneStudioLiveTuningPanel.gd"

var _live_tuning_panel: Node = null


func _ready() -> void:
	super._ready()
	var panel_script_value: Variant = load(LIVE_TUNING_PANEL_PATH)
	if panel_script_value == null:
		push_error("Bone Studio: Live Tuning panel could not be loaded. Base editor remains available.")
		return
	if not panel_script_value is Script:
		push_error("Bone Studio: Live Tuning resource is not a Script. Base editor remains available.")
		return
	var panel_value: Variant = (panel_script_value as Script).new()
	if not panel_value is Node:
		push_error("Bone Studio: Live Tuning script did not create a Node. Base editor remains available.")
		return
	_live_tuning_panel = panel_value as Node
	_live_tuning_panel.call("setup", self)
