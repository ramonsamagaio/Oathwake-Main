extends "res://scripts/labs/alabaster/AlabasterBoneStudioLiveTuningPanelFixed.gd"

const DefaultSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterDefaultPlayableSkinRig.gd")
const PROFILE_DEFAULT := "default"
const DEFAULT_LABEL := "DEFAULT"


func setup(owner: Control) -> void:
	# Build the proven Live Tuning panel first, then compose DEFAULT into it without
	# changing the stable base class/parser chain.
	super.setup(owner)
	_install_default_controls()
	target_profile = PROFILE_DEFAULT
	_update_target_buttons()
	if not _replace_host_rig(PROFILE_DEFAULT):
		_set_status("Could not initialize DEFAULT target figure.", true)
		return
	_rebuild_animation_records()
	_rebuild_parts_list()
	_select_default_idle()


func _install_default_controls() -> void:
	if target_buttons.has(PROFILE_DEFAULT):
		return
	var template_button: Button = null
	for button_value in target_buttons.values():
		if button_value is Button:
			template_button = button_value as Button
			break
	if template_button != null and template_button.get_parent() != null:
		var row := template_button.get_parent()
		var button := Button.new()
		button.text = DEFAULT_LABEL
		button.toggle_mode = true
		button.button_group = template_button.button_group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(110.0, 34.0)
		button.tooltip_text = "Oathwake DEFAULT body. Starts as an independent deep clone of Dummy."
		button.pressed.connect(_on_target_pressed.bind(PROFILE_DEFAULT))
		row.add_child(button)
		row.move_child(button, 0)
		target_buttons[PROFILE_DEFAULT] = button

	if filter_option != null:
		var already_present := false
		for index in range(filter_option.item_count):
			if str(filter_option.get_item_metadata(index)) == DEFAULT_LABEL:
				already_present = true
				break
		if not already_present:
			filter_option.add_item(DEFAULT_LABEL)
			filter_option.set_item_metadata(filter_option.item_count - 1, DEFAULT_LABEL)


func _replace_host_rig(profile_id: String) -> bool:
	if profile_id != PROFILE_DEFAULT:
		return super._replace_host_rig(profile_id)
	if host == null:
		return false
	var preview_world_value: Variant = host.get("preview_world")
	if not preview_world_value is Node2D:
		return false
	var preview_world: Node2D = preview_world_value as Node2D
	var old_rig_value: Variant = host.get("rig")
	if old_rig_value is Node:
		var old_rig: Node = old_rig_value as Node
		if is_instance_valid(old_rig):
			if old_rig.get_parent() != null:
				old_rig.get_parent().remove_child(old_rig)
			old_rig.queue_free()

	var new_rig: Node2D = DefaultSkinRigScript.new() as Node2D
	if new_rig == null:
		return false
	new_rig.call("configure_skin_profile", PROFILE_DEFAULT)
	new_rig.name = "DefaultBoneStudioSharedRig"
	preview_world.add_child(new_rig)
	if new_rig.has_method("initialize_skin") and not bool(new_rig.call("initialize_skin")):
		new_rig.queue_free()
		return false

	host.set("rig", new_rig)
	new_rig.scale = Vector2.ONE * 3.2
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
	return true


func _rebuild_animation_records() -> void:
	# Parent owns Juno/Dummy/Male. DEFAULT adds its own immutable native source and
	# its own custom-copy namespace; Juno clips remain globally available to retarget.
	super._rebuild_animation_records()
	var records: Array = Library.get_animation_records(PROFILE_DEFAULT)
	for record_value in records:
		if not record_value is Dictionary:
			continue
		var record := (record_value as Dictionary).duplicate(true)
		record["source_profile"] = PROFILE_DEFAULT
		animation_records.append(record)
	_rebuild_animation_option()


func _record_passes_filter(source_profile: String, source_kind: String, filter_name: String) -> bool:
	if filter_name == DEFAULT_LABEL:
		return source_profile == PROFILE_DEFAULT
	return super._record_passes_filter(source_profile, source_kind, filter_name)
