extends "res://scripts/labs/alabaster/AlabasterBoneStudioWorkspaceLayout.gd"

const BoneBridgePolishScript := preload("res://scripts/labs/alabaster/AlabasterBoneBridgePanelPolish.gd")
const BoneStudioDepthPolishScript := preload("res://scripts/labs/alabaster/AlabasterBoneStudioDepthPolish.gd")

# Final Bone Studio interaction layer. The editor overlay is now the ONE source of
# Juno bone graphics. The runtime's older debug skeleton stays off, which removes
# the doubled skeleton while preserving RMB orbit, wheel zoom and MMB pan even
# when the user hides the bones.

var _depth_polish_controller: Node = null


func _install_bone_bridge_panel() -> void:
	if _bone_bridge_panel != null and is_instance_valid(_bone_bridge_panel):
		return
	var panel_value: Variant = BoneBridgePolishScript.new()
	if not panel_value is Control:
		push_error("Bone Studio: polished BONE BRIDGE panel could not be created.")
		return
	_bone_bridge_panel = panel_value as Control
	_bone_bridge_panel.call("setup", self)


func _connect_juno_overlay() -> void:
	super._connect_juno_overlay()
	_sync_single_juno_bone_display()
	call_deferred("_ensure_bone_bridge_depth_polish")


func _on_bones_toggled(enabled: bool) -> void:
	# If the interactive overlay has not attached yet, preserve the old fallback.
	if _juno_overlay == null or not is_instance_valid(_juno_overlay):
		super._on_bones_toggled(enabled)
		return
	_set_juno_overlay_bones_visible(enabled)
	_disable_runtime_debug_skeleton()


func _sync_single_juno_bone_display() -> void:
	if _juno_overlay == null or not is_instance_valid(_juno_overlay):
		return
	var enabled := true
	if bone_visibility_check != null:
		enabled = bone_visibility_check.button_pressed
	_set_juno_overlay_bones_visible(enabled)
	_disable_runtime_debug_skeleton()


func _set_juno_overlay_bones_visible(enabled: bool) -> void:
	if _juno_overlay == null or not is_instance_valid(_juno_overlay):
		return
	# Alpha 0 hides only the overlay drawing. The Control remains active, so RMB
	# orbit / wheel zoom / MMB pan continue to work with Show bones disabled.
	_juno_overlay.modulate = Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.0)
	_juno_overlay.set_meta("alabaster_bones_visible", enabled)


func _disable_runtime_debug_skeleton() -> void:
	if rig == null or not is_instance_valid(rig):
		return
	if rig.has_method("set_debug_enabled"):
		rig.call("set_debug_enabled", false)
	if rig is CanvasItem:
		(rig as CanvasItem).queue_redraw()


func _ensure_bone_bridge_depth_polish() -> Node:
	if rig == null or not is_instance_valid(rig):
		return null
	if _depth_polish_controller != null and is_instance_valid(_depth_polish_controller):
		var current_rig_value: Variant = _depth_polish_controller.get("rig")
		if current_rig_value == rig and _depth_polish_controller.get_parent() == rig:
			return _depth_polish_controller
		_depth_polish_controller.queue_free()
		_depth_polish_controller = null

	var controller_value: Variant = BoneStudioDepthPolishScript.new()
	if not controller_value is Node:
		push_error("Bone Studio: could not create Bone Bridge depth polish controller.")
		return null
	_depth_polish_controller = controller_value as Node
	_depth_polish_controller.name = "BoneBridgeDepthPolish"
	rig.add_child(_depth_polish_controller)
	_depth_polish_controller.call("setup", rig)
	return _depth_polish_controller
