extends "res://scripts/labs/alabaster/AlabasterBoneStudioSharedProfiles.gd"
class_name AlabasterBoneStudioImportSourceFix

const RobustImporter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const RetargetJunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")
const RetargetDebugPanelScript := preload("res://scripts/labs/alabaster/AlabasterRetargetDebugPanel.gd")
const BoneBridgePanelScript := preload("res://scripts/labs/alabaster/AlabasterBoneBridgePanel.gd")
const FOLD_PREFIX := "@fold:"

var _retarget_reference_rig: Node2D = null
var _retarget_debug_panel: Control = null
var _bone_bridge_panel: Control = null
# Juno is not a Mixamo T-pose skeleton. Target-aware rest swing characterizes
# both ends of the bridge and is therefore the safe default for imported motion.
var retarget_limb_mode := "target_rest_swing"


func _ready() -> void:
	super._ready()
	# The advanced Live Tuning layer historically promoted DEFAULT after setup.
	# Retarget authoring is now explicitly Juno-first, so restore Juno and keep a
	# hidden canonical Juno reference rig for target hierarchy diagnostics even if
	# the user later inspects another skin in LIVE TUNING.
	call_deferred("_initialize_juno_retarget_workspace")


func _initialize_juno_retarget_workspace() -> void:
	_ensure_retarget_reference_rig()
	ensure_juno_retarget_target()
	_install_retarget_debug_panel()
	_install_bone_bridge_panel()


func _ensure_retarget_reference_rig() -> void:
	if _retarget_reference_rig != null and is_instance_valid(_retarget_reference_rig):
		return
	var rig_value: Variant = RetargetJunoRigScript.new()
	if not rig_value is Node2D:
		push_error("Bone Studio: could not create canonical Juno retarget reference rig.")
		return
	_retarget_reference_rig = rig_value as Node2D
	_retarget_reference_rig.name = "JunoRetargetReferenceRig"
	_retarget_reference_rig.visible = false
	add_child(_retarget_reference_rig)
	_retarget_reference_rig.set_process(false)


func get_retarget_reference_rig() -> Object:
	_ensure_retarget_reference_rig()
	return _retarget_reference_rig


func ensure_juno_retarget_target() -> void:
	if _live_tuning_panel != null and is_instance_valid(_live_tuning_panel):
		var panel_object := _live_tuning_panel as Object
		if panel_object.has_method("_on_target_pressed"):
			panel_object.call("_on_target_pressed", "juno")
			return
	# Safety fallback if Live Tuning failed to initialize.
	var current_rig_name := ""
	if rig is Node:
		current_rig_name = str((rig as Node).name)
	if rig != null and current_rig_name == "JunoBoneStudioSharedRig":
		return
	var preview_world_value: Variant = get("preview_world")
	if not preview_world_value is Node2D:
		return
	var old_rig_value: Variant = get("rig")
	if old_rig_value is Node and is_instance_valid(old_rig_value):
		var old_rig := old_rig_value as Node
		if old_rig.get_parent() != null:
			old_rig.get_parent().remove_child(old_rig)
		old_rig.queue_free()
	var new_rig := RetargetJunoRigScript.new() as Node2D
	if new_rig == null:
		return
	new_rig.name = "JunoBoneStudioSharedRig"
	(preview_world_value as Node2D).add_child(new_rig)
	set("rig", new_rig)
	new_rig.scale = Vector2.ONE * 3.2
	new_rig.call_deferred("set_debug_enabled", true)
	new_rig.call_deferred("set_facing_from_vector", Vector2.DOWN)
	call_deferred("_populate_manual_bones")
	call_deferred("_rebuild_mapping_table")


func _install_retarget_debug_panel() -> void:
	if _retarget_debug_panel != null and is_instance_valid(_retarget_debug_panel):
		return
	var panel_value: Variant = RetargetDebugPanelScript.new()
	if not panel_value is Control:
		push_error("Bone Studio: RETARGET DEBUG panel could not be created.")
		return
	_retarget_debug_panel = panel_value as Control
	_retarget_debug_panel.call("setup", self)
	# Preserve the old V8 modes for A/B work but make the actual V10 production
	# path visible in the diagnostics selector too.
	var limb_option_value: Variant = _retarget_debug_panel.get("limb_mode_option")
	if limb_option_value is OptionButton:
		var limb_option := limb_option_value as OptionButton
		limb_option.add_item("V10 REST-calibrated · recommended")
		limb_option.set_item_metadata(limb_option.item_count - 1, "target_rest_swing")
		limb_option.select(limb_option.item_count - 1)


func _install_bone_bridge_panel() -> void:
	if _bone_bridge_panel != null and is_instance_valid(_bone_bridge_panel):
		return
	var panel_value: Variant = BoneBridgePanelScript.new()
	if not panel_value is Control:
		push_error("Bone Studio: BONE BRIDGE panel could not be created.")
		return
	_bone_bridge_panel = panel_value as Control
	_bone_bridge_panel.call("setup", self)


func set_retarget_limb_mode(mode: String) -> void:
	if mode != "full_global_delta" and mode != "segment_swing" and mode != "target_rest_swing":
		return
	retarget_limb_mode = mode
	_set_status("Retarget limb solver: %s. Preview again to compare the result." % mode)


func get_retarget_limb_mode() -> String:
	return retarget_limb_mode


func _on_source_selected(path: String) -> void:
	source_path = path
	source_path_label.text = path
	source_clip_option.clear()
	source_bones.clear()
	var info := RobustImporter.inspect_scene(path)
	if not bool(info.get("ok", false)):
		_rebuild_mapping_table()
		_set_status(str(info.get("error", "Could not inspect source animation.")), true)
		return

	for clip in info.get("clips", []):
		source_clip_option.add_item(str(clip))
		source_clip_option.set_item_metadata(source_clip_option.item_count - 1, str(clip))
	for bone in info.get("bones", []):
		source_bones.append(str(bone))

	var profile := str(info.get("retarget_profile", "generic"))
	var retarget_mode := str(info.get("retarget_mode", "generic_track"))
	var has_mixamo_scene := profile == "mixamo" and bool(info.get("has_skeleton", false)) and retarget_mode != "mixamo_track_fallback"
	if profile == "mixamo":
		import_reference_pose.button_pressed = false
		if has_mixamo_scene:
			import_reference_pose.disabled = true
			import_reference_pose.tooltip_text = "Mixamo → Juno reads the real Skeleton3D REST hierarchy, uses foot→toe REST vectors to resolve forward/handedness, and uses adjacent limb segments to resolve ankle/wrist twist before transferring motion into Juno."
		else:
			import_reference_pose.disabled = false
			import_reference_pose.tooltip_text = "No Skeleton3D was exposed by this import, so only the lower-fidelity track fallback is available."
	else:
		import_reference_pose.disabled = false
		import_reference_pose.tooltip_text = "Subtract frame zero from the imported source motion."

	_rebuild_mapping_table()

	if source_clip_option.item_count > 0:
		source_clip_option.select(0)
		import_name_edit.text = "OW_%s" % _sanitize_name(str(source_clip_option.get_item_metadata(0)))

	var kind := str(info.get("resource_kind", "godot_resource"))
	if has_mixamo_scene:
		_set_status("Mixamo → Juno V10 ready: %d clips, %d source bones. REST forward/handedness + two-vector limb twist calibration are active. Open BONE BRIDGE for live comparison." % [source_clip_option.item_count, source_bones.size()])
	elif profile == "mixamo":
		_set_status("Mixamo detected, but this resource exposes no Skeleton3D. Track-only fallback is available; importing the raw FBX/GLB scene is recommended.")
	else:
		_set_status("Loaded %d clips and %d source bones from %s. Open BONE BRIDGE to inspect the real source skeleton and mapping." % [source_clip_option.item_count, source_bones.size(), kind])


func _rebuild_mapping_table() -> void:
	mapping_controls.clear()
	for child in mapping_container.get_children():
		child.queue_free()
	var targets: Array = []
	var reference_rig := get_retarget_reference_rig()
	if reference_rig != null and reference_rig.has_method("get_bone_names"):
		var runtime_names: Variant = reference_rig.call("get_bone_names")
		if runtime_names is Array:
			targets = runtime_names.duplicate()
	elif rig != null and rig.has_method("get_bone_names"):
		var fallback_names: Variant = rig.call("get_bone_names")
		if fallback_names is Array:
			targets = fallback_names.duplicate()

	var auto := RobustImporter.make_auto_retarget(source_bones)
	for source_bone in source_bones:
		var option := OptionButton.new()
		option.add_item("-- Ignore --")
		option.set_item_metadata(0, "")
		var selected := 0
		var auto_value := str(auto.get(source_bone, ""))
		if auto_value.begins_with(FOLD_PREFIX):
			var fold_target := auto_value.trim_prefix(FOLD_PREFIX)
			option.add_item("AUTO FOLD -> %s" % fold_target)
			option.set_item_metadata(option.item_count - 1, auto_value)
			option.set_item_tooltip(option.item_count - 1, "This source joint contributes to the anatomical solve but does not independently overwrite a Juno node.")
			selected = option.item_count - 1
		for target_value in targets:
			var target := str(target_value)
			option.add_item(target)
			option.set_item_metadata(option.item_count - 1, target)
			if target == auto_value:
				selected = option.item_count - 1
		option.select(selected)
		_add_row(mapping_container, source_bone, option)
		mapping_controls[source_bone] = option


func _get_import_settings() -> Dictionary:
	var settings := super._get_import_settings()
	settings["retarget_target_profile"] = "juno"
	settings["retarget_limb_mode"] = retarget_limb_mode
	settings["retarget_skip_attachment_nodes"] = ["shoulderL", "shoulderR", "hipL", "hipR"]

	var reference_rig := get_retarget_reference_rig()
	if reference_rig != null:
		if reference_rig.has_method("get_bone_names"):
			var names_value: Variant = reference_rig.call("get_bone_names")
			if names_value is Array:
				settings["target_bones"] = (names_value as Array).duplicate()
		if reference_rig.has_method("get_bone_parent_map"):
			var parent_value: Variant = reference_rig.call("get_bone_parent_map")
			if parent_value is Dictionary:
				settings["target_parent_map"] = (parent_value as Dictionary).duplicate(true)
		if reference_rig.has_method("get_bone_rest_local_positions"):
			var rest_value: Variant = reference_rig.call("get_bone_rest_local_positions")
			if rest_value is Dictionary:
				settings["target_rest_local_positions"] = (rest_value as Dictionary).duplicate(true)
	return settings


func _build_import_animation() -> Dictionary:
	if source_path.is_empty() or source_clip_option.item_count <= 0 or source_clip_option.selected < 0:
		_set_status("The source file is selected, but Godot exposed no animation clip. Reimport the FBX with Animation enabled and try again.", true)
		return {}
	var clip_name := _selected_clip()
	if clip_name.is_empty():
		_set_status("Select an animation clip first.", true)
		return {}

	ensure_juno_retarget_target()
	var settings := _get_import_settings()
	var result := RobustImporter.import_scene_clip(
		source_path,
		clip_name,
		import_fps.value,
		import_loop.button_pressed,
		0.0,
		_get_mapping(),
		settings
	)
	if result.is_empty():
		_set_status("The clip was found but could not be converted. Keep automatic Mixamo mapping unchanged for the full semantic solver, then open RETARGET DEBUG to inspect the source/target characterization.", true)
	return result
