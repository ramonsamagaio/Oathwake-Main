extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"

# Stable Bone Studio entry point. Live Tuning is added as a composited tab, not
# as another inheritance layer, so the base editor remains loadable even while
# the tuning UI evolves.
const LiveTuningPanelScript := preload("res://scripts/labs/alabaster/AlabasterBoneStudioLiveTuningPanel.gd")

var _live_tuning_panel


func _ready() -> void:
	super._ready()
	_live_tuning_panel = LiveTuningPanelScript.new()
	_live_tuning_panel.call("setup", self)


func _on_viewport_bone_transform_delta(bone_name: String, mode: String, delta_value: Vector3) -> void:
	if _live_tuning_panel != null and bool(_live_tuning_panel.call("is_live_active")):
		_live_tuning_panel.call("apply_bone_delta", bone_name, mode, delta_value)
		return
	super._on_viewport_bone_transform_delta(bone_name, mode, delta_value)


func _on_viewport_bone_selected(bone_name: String) -> void:
	super._on_viewport_bone_selected(bone_name)
	if _live_tuning_panel != null and bool(_live_tuning_panel.call("is_live_active")):
		_live_tuning_panel.call("select_part_from_bone", bone_name)


func _live_tuning_select_bone(bone_name: String) -> void:
	# Selecting a visual sprite part and selecting its bone are the same operation
	# in Live Tuning. Keep the existing Pro gizmo/timeline synchronized without
	# writing a manual-animation keyframe.
	_suppress_auto_key = true
	_select_option_metadata(manual_bone_option, bone_name)
	_suppress_auto_key = false
	if viewport_editor != null:
		viewport_editor.set_selected_bone(bone_name)
	if timeline != null:
		timeline.set_selected_bone(bone_name)
