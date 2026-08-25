extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"

# Stable Bone Studio entry point. Live Tuning is loaded dynamically at runtime,
# while the preview itself starts with the exact BonesSystem used by gameplay.
# The workspace composition adds editor ergonomics without moving them into the
# gameplay runtime.

const LIVE_TUNING_PANEL_PATH = "res://scripts/labs/alabaster/AlabasterBoneStudioWorkspaceViewportFix.gd"
const SharedJunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")

var _live_tuning_panel: Node = null


func _build_preview() -> void:
	rig = SharedJunoRigScript.new()
	rig.name = "JunoBoneStudioSharedRig"
	preview_world.add_child(rig)
	rig.scale = Vector2.ONE * 3.2
	if rig.has_method("set_sprite_opacity"):
		rig.call_deferred("set_sprite_opacity", opacity_slider.value)
	if rig.has_method("set_debug_enabled"):
		rig.call_deferred("set_debug_enabled", true)
	if rig.has_method("set_facing_from_vector"):
		rig.call_deferred("set_facing_from_vector", Vector2.DOWN)
	call_deferred("_populate_manual_bones")


func _ready() -> void:
	super._ready()
	var panel_script_value: Variant = load(LIVE_TUNING_PANEL_PATH)
	if panel_script_value == null:
		push_error("Bone Studio: Live Tuning workspace could not be loaded. Base editor remains available.")
		return
	if not panel_script_value is Script:
		push_error("Bone Studio: Live Tuning workspace resource is not a Script. Base editor remains available.")
		return
	var panel_value: Variant = (panel_script_value as Script).new()
	if not panel_value is Node:
		push_error("Bone Studio: Live Tuning workspace did not create a Node. Base editor remains available.")
		return
	_live_tuning_panel = panel_value as Node
	_live_tuning_panel.call("setup", self)
