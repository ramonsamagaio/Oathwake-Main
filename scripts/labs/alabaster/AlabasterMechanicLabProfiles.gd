extends "res://scripts/labs/alabaster/AlabasterMechanicLab.gd"
class_name AlabasterMechanicLabProfiles

const JunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")
const PlayableSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")
const ProfileLibrary := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")

const PROFILE_JUNO := "juno"
const PROFILE_DUMMY := "male_dummy"
const PROFILE_MALE := "male_temp"
const PROFILE_LABELS := {
	PROFILE_JUNO: "JUNO",
	PROFILE_DUMMY: "DUMMY",
	PROFILE_MALE: "MALE",
}

var _active_profile := PROFILE_JUNO
var _profile_buttons: Dictionary = {}
var _sprite_opacity := 1.0
var _opacity_slider: HSlider
var _opacity_value_label: Label


func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "AlabasterPlayer"
	player.position = SCREEN_SIZE * 0.5 + Vector2(0.0, 80.0)
	add_child(player)
	_replace_rig(PROFILE_JUNO, false)


func _build_ui() -> void:
	super._build_ui()
	_build_profile_switcher()


func _build_profile_switcher() -> void:
	var panel := PanelContainer.new()
	panel.name = "CharacterProfileSwitcher"
	panel.position = Vector2(SCREEN_SIZE.x - 420.0, 22.0)
	panel.custom_minimum_size = Vector2(390.0, 142.0)
	panel.z_index = 1000
	add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)
	var caption := Label.new()
	caption.text = "TEST FIGURE"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_theme_font_size_override("font_size", 13)
	box.add_child(caption)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for profile_id in [PROFILE_DUMMY, PROFILE_MALE, PROFILE_JUNO]:
		var button := Button.new()
		button.text = str(PROFILE_LABELS[profile_id])
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(104.0, 34.0)
		button.tooltip_text = "Switch the complete source figure. Mechanic Lab and gameplay share the same bone runtime."
		button.pressed.connect(_on_profile_pressed.bind(profile_id))
		row.add_child(button)
		_profile_buttons[profile_id] = button
	_update_profile_buttons()

	var opacity_row := HBoxContainer.new()
	opacity_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(opacity_row)
	var opacity_label := Label.new()
	opacity_label.text = "SPRITE OPACITY"
	opacity_label.custom_minimum_size = Vector2(112.0, 0.0)
	opacity_label.add_theme_font_size_override("font_size", 12)
	opacity_row.add_child(opacity_label)

	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.0
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.05
	_opacity_slider.value = _sprite_opacity
	_opacity_slider.custom_minimum_size = Vector2(190.0, 24.0)
	_opacity_slider.focus_mode = Control.FOCUS_NONE
	_opacity_slider.tooltip_text = "Lower the body sprite opacity while F1 skeleton/debug is enabled."
	_opacity_slider.value_changed.connect(_on_sprite_opacity_changed)
	opacity_row.add_child(_opacity_slider)

	_opacity_value_label = Label.new()
	_opacity_value_label.custom_minimum_size = Vector2(48.0, 0.0)
	_opacity_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	opacity_row.add_child(_opacity_value_label)
	_update_opacity_label()

	var note := Label.new()
	note.text = "F1 skeleton • opacity lets you inspect bones through the body"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_font_size_override("font_size", 11)
	note.modulate = Color(0.72, 0.78, 0.88)
	box.add_child(note)


func _on_profile_pressed(profile_id: String) -> void:
	get_viewport().gui_release_focus()
	_replace_rig(profile_id, true)


func _on_sprite_opacity_changed(value: float) -> void:
	_sprite_opacity = clampf(value, 0.0, 1.0)
	_apply_sprite_opacity()
	_update_opacity_label()


func _apply_sprite_opacity() -> void:
	if rig != null and rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", _sprite_opacity)


func _update_opacity_label() -> void:
	if _opacity_value_label != null:
		_opacity_value_label.text = "%d%%" % roundi(_sprite_opacity * 100.0)


func _replace_rig(profile_id: String, refresh_ui: bool) -> void:
	if profile_id not in [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]:
		return
	_manual_active = false
	_auto_showcase = false
	_manual_elapsed = 0.0
	_manual_duration = 0.0
	reset_command_latches()

	if rig != null and is_instance_valid(rig):
		if rig.get_parent() != null:
			rig.get_parent().remove_child(rig)
		rig.queue_free()

	_active_profile = profile_id
	if profile_id == PROFILE_JUNO:
		# Same production BonesSystem used by the actual player.
		rig = JunoRigScript.new()
		rig.name = "JunoRig"
		player.add_child(rig)
	else:
		# Same playable skin rig instantiated by AlabasterPlayerVisualController.
		var skin_rig = PlayableSkinRigScript.new()
		skin_rig.call("configure_skin_profile", profile_id)
		rig = skin_rig
		rig.name = "%sRig" % str(PROFILE_LABELS[profile_id]).capitalize()
		player.add_child(rig)
		if rig.has_method("initialize_skin") and not bool(rig.call("initialize_skin")):
			push_error("AlabasterMechanicLabProfiles: could not initialize profile %s" % profile_id)

	_install_profile_custom_animations(profile_id)
	rig.scale = Vector2(2.5, 2.5)
	if rig.has_method("set_debug_enabled"):
		rig.call("set_debug_enabled", _debug_enabled)
	_apply_sprite_opacity()
	if rig.has_method("set_facing_from_vector"):
		rig.call("set_facing_from_vector", Vector2.DOWN)
	_set_profile_idle()

	var missing_actions := SharedActions.missing_lab_actions(rig)
	var resolved_actions := SharedActions.resolved_lab_actions(rig)
	print("ALABASTER_LAB_ACTIONS profile=%s available=%d/%d missing=%s" % [
		profile_id,
		SharedActions.LAB_ACTIONS.size() - missing_actions.size(),
		SharedActions.LAB_ACTIONS.size(),
		str(missing_actions),
	])
	print("ALABASTER_LAB_ACTION_MAP profile=%s resolved=%s" % [profile_id, str(resolved_actions)])

	if refresh_ui:
		_refresh_catalog()
		_update_profile_buttons()
		_update_status()
		print("ALABASTER_LAB_PROFILE profile=%s label=%s animations=%d" % [
			_active_profile,
			str(PROFILE_LABELS[_active_profile]),
			_catalog.size(),
		])


func _install_profile_custom_animations(profile_id: String) -> void:
	if rig == null or not rig.has_method("install_runtime_animation"):
		return
	var custom := ProfileLibrary.load_custom_animations(profile_id)
	for animation_name_value in custom.keys():
		var data_value: Variant = custom[animation_name_value]
		if data_value is Dictionary:
			rig.call("install_runtime_animation", str(animation_name_value), data_value as Dictionary)
	if not custom.is_empty():
		print("ALABASTER_LAB_CUSTOM_BANK profile=%s animations=%d" % [profile_id, custom.size()])


func _physics_process(delta: float) -> void:
	# Base class owns all keyboard/mouse command polling. Profile mode only changes
	# which shared rig receives those actions.
	super._physics_process(delta)


func _set_profile_idle() -> void:
	if rig == null:
		return
	if rig.has_method("has_animation") and bool(rig.call("has_animation", "idle")):
		rig.call("set_animation", "idle")
	elif rig.has_method("set_rest_pose"):
		rig.call("set_rest_pose")


func _stop_manual_animation() -> void:
	_manual_active = false
	_manual_elapsed = 0.0
	_manual_duration = 0.0
	_set_profile_idle()
	_update_status()


func _update_profile_buttons() -> void:
	for profile_id in _profile_buttons.keys():
		var button := _profile_buttons[profile_id] as Button
		if button != null:
			button.set_pressed_no_signal(str(profile_id) == _active_profile)


func _update_status() -> void:
	super._update_status()
	if status_label == null:
		return
	var runtime_label := "GAME BONES SYSTEM" if _active_profile == PROFILE_JUNO else "GAME PLAYABLE SKIN RIG"
	status_label.text = "figure=%s   runtime=%s   opacity=%d%%   %s" % [
		str(PROFILE_LABELS.get(_active_profile, _active_profile)),
		runtime_label,
		roundi(_sprite_opacity * 100.0),
		status_label.text,
	]
