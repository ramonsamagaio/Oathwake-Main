extends "res://scripts/labs/alabaster/AlabasterBoneBridgePanel.gd"
class_name AlabasterBoneBridgePanelPolish

# Final interaction polish for the comparison workspace. Source selection should
# immediately explain the mapping visually: click a Mixamo bone on the left and,
# when it resolves to a Juno target, select/highlight that target on the right too.


func _highlight_source_bone(source_bone: String) -> void:
	super._highlight_source_bone(source_bone)
	var target := _mapped_juno_target(source_bone)
	if target.begins_with("@fold:"):
		target = target.trim_prefix("@fold:")
	if target.is_empty() or host == null:
		return
	if host.has_method("_select_juno_bone"):
		host.call("_select_juno_bone", target, true)
		return
	var live_panel_value: Variant = host.get("_live_tuning_panel")
	if live_panel_value is Object:
		var live_panel := live_panel_value as Object
		if live_panel.has_method("_on_workspace_bone_selected"):
			live_panel.call("_on_workspace_bone_selected", target)


func _sync_target_to_source_time(time_seconds: float) -> void:
	# The DEFAULT target rig can be rebuilt when profiles/sources change. Ensure
	# the Bone Bridge-only z-order controller follows the CURRENT rig before every
	# synchronized pose, then let the proven clock sync perform the actual seek.
	if host != null and host.has_method("_ensure_bone_bridge_depth_polish"):
		host.call("_ensure_bone_bridge_depth_polish")
	super._sync_target_to_source_time(time_seconds)
	if host != null:
		var controller_value: Variant = host.get("_depth_polish_controller")
		if controller_value is Object and (controller_value as Object).has_method("apply_now"):
			(controller_value as Object).call("apply_now")


func _mapped_juno_target(source_bone: String) -> String:
	var bridge_option := bridge_mapping_controls.get(source_bone) as OptionButton
	if bridge_option != null and bridge_option.selected >= 0:
		return str(bridge_option.get_item_metadata(bridge_option.selected))
	if host == null:
		return ""
	var controls_value: Variant = host.get("mapping_controls")
	if not controls_value is Dictionary:
		return ""
	var host_option := (controls_value as Dictionary).get(source_bone) as OptionButton
	if host_option == null or host_option.selected < 0:
		return ""
	return str(host_option.get_item_metadata(host_option.selected))
