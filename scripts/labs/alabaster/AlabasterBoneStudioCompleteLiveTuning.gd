extends "res://scripts/labs/alabaster/AlabasterBoneStudioJunoBaseLiveTuning.gd"

# Final figure layer for Bone Studio Live Tuning. The inherited panel already
# removes legacy Male and adds JunoBase. This layer completes the exact figure
# set shared by Import/Retarget and Manual Animator: Juno, JunoBase, Dummy,
# Default.

const DefaultRigScript := preload("res://scripts/labs/alabaster/AlabasterDefaultPlayableSkinRig.gd")
const PROFILE_DEFAULT := "default"
const DEFAULT_LABEL := "DEFAULT"


func setup(owner: Control) -> void:
	super.setup(owner)
	_install_default_controls()
	_rebuild_animation_records()
	_update_target_buttons()
	_refresh_live_inspection(true)


func _install_default_controls() -> void:
	if target_buttons.has(PROFILE_DEFAULT):
		return
	var anchor_value: Variant = target_buttons.get(PROFILE_DUMMY, target_buttons.get(PROFILE_JUNO, null))
	if not anchor_value is Button:
		return
	var anchor := anchor_value as Button
	var row := anchor.get_parent()
	if row == null:
		return
	var button := Button.new()
	button.text = DEFAULT_LABEL
	button.toggle_mode = true
	button.button_group = anchor.button_group
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(118.0, 34.0)
	button.tooltip_text = "DEFAULT: Oathwake-owned production humanoid using the same bone-animation editing workflow."
	button.pressed.connect(_on_target_pressed.bind(PROFILE_DEFAULT))
	row.add_child(button)
	target_buttons[PROFILE_DEFAULT] = button

	if filter_option != null:
		var has_default := false
		for index in range(filter_option.item_count):
			if str(filter_option.get_item_metadata(index)) == DEFAULT_LABEL:
				has_default = true
				break
		if not has_default:
			filter_option.add_item(DEFAULT_LABEL)
			filter_option.set_item_metadata(filter_option.item_count - 1, DEFAULT_LABEL)


func _replace_host_rig(profile_id: String) -> bool:
	if profile_id != PROFILE_DEFAULT:
		var replaced := super._replace_host_rig(profile_id)
		if replaced:
			_sync_host_editor_selector(profile_id)
		return replaced
	if host == null:
		return false
	var preview_world_value: Variant = host.get("preview_world")
	if not preview_world_value is Node2D:
		return false
	var preview_world := preview_world_value as Node2D
	var old_rig_value: Variant = host.get("rig")
	if old_rig_value is Node and is_instance_valid(old_rig_value):
		var old_rig := old_rig_value as Node
		if old_rig.get_parent() != null:
			old_rig.get_parent().remove_child(old_rig)
		old_rig.queue_free()

	var new_rig := DefaultRigScript.new() as Node2D
	if new_rig == null:
		return false
	new_rig.name = "DefaultBoneStudioSharedRig"
	preview_world.add_child(new_rig)
	host.set("rig", new_rig)
	new_rig.scale = Vector2.ONE * PREVIEW_BASE_SCALE * _preview_zoom
	if new_rig.has_method("set_sprite_opacity") and opacity_slider != null:
		new_rig.call("set_sprite_opacity", opacity_slider.value)
	if new_rig.has_method("set_selection_green_intensity") and green_slider != null:
		new_rig.call("set_selection_green_intensity", green_slider.value)
	if new_rig.has_method("set_debug_enabled"):
		var bones_value: Variant = host.get("bone_visibility_check")
		var debug_enabled := true
		if bones_value is CheckBox:
			debug_enabled = (bones_value as CheckBox).button_pressed
		new_rig.call("set_debug_enabled", debug_enabled)
	if new_rig.has_method("set_facing_from_vector"):
		new_rig.call("set_facing_from_vector", Vector2.DOWN)
	if new_rig.has_method("set_editor_animation_paused"):
		new_rig.call("set_editor_animation_paused", false)

	host.call_deferred("_populate_manual_bones")
	host.call_deferred("_rebuild_mapping_table")
	_atlas_signature = ""
	_layers_signature = ""
	_sync_host_editor_selector(PROFILE_DEFAULT)
	return true


func _sync_host_editor_selector(profile_id: String) -> void:
	if host != null and host.has_method("_sync_editor_preview_selector"):
		host.call("_sync_editor_preview_selector", profile_id)


func _rebuild_animation_records() -> void:
	super._rebuild_animation_records()
	var default_records: Array = Library.get_animation_records(PROFILE_DEFAULT)
	for record_value in default_records:
		if not record_value is Dictionary:
			continue
		var copy := (record_value as Dictionary).duplicate(true)
		copy["source_profile"] = PROFILE_DEFAULT
		animation_records.append(copy)
	_rebuild_animation_option()


func _record_passes_filter(source_profile: String, source_kind: String, filter_name: String) -> bool:
	if filter_name == DEFAULT_LABEL:
		return source_profile == PROFILE_DEFAULT
	return super._record_passes_filter(source_profile, source_kind, filter_name)
