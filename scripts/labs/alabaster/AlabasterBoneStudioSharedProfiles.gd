extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"

# Stable Bone Studio entry point. Live Tuning is loaded dynamically at runtime,
# while the preview itself starts with the exact BonesSystem used by gameplay.
# The workspace composition adds editor ergonomics without moving them into the
# gameplay runtime.

const LIVE_TUNING_PANEL_PATH = "res://scripts/labs/alabaster/AlabasterBoneStudioJunoBaseLiveTuning.gd"
const SharedJunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")
const SharedAnimationLibrary := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")

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


# Import/Retarget and Manual Animator write the same persistent custom bank used
# by LIVE TUNING. Notify the composed panel immediately after a successful save
# so users do not need to restart Bone Studio just to see the new copy.
func _save_import() -> void:
	var animation_name := _sanitize_name(import_name_edit.text)
	super._save_import()
	_queue_live_tuning_bank_refresh(animation_name, "juno")


func _save_manual() -> void:
	var animation_name := _sanitize_name(manual_name_edit.text)
	super._save_manual()
	_queue_live_tuning_bank_refresh(animation_name, "juno")


func _queue_live_tuning_bank_refresh(animation_name: String, profile_id: String) -> void:
	if animation_name.is_empty():
		return
	var record: Dictionary = SharedAnimationLibrary.get_animation_record(profile_id, animation_name)
	if record.is_empty() or str(record.get("source", "")) != "custom":
		return
	call_deferred("_refresh_live_tuning_bank", animation_name, profile_id)


func _refresh_live_tuning_bank(animation_name: String, profile_id: String) -> void:
	if _live_tuning_panel == null or not is_instance_valid(_live_tuning_panel):
		return
	if not _live_tuning_panel.has_method("refresh_animation_bank"):
		return
	_live_tuning_panel.call("refresh_animation_bank", animation_name, profile_id)
