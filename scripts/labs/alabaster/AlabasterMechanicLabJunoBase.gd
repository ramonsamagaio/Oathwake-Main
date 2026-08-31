extends "res://scripts/labs/alabaster/AlabasterMechanicLabProfiles.gd"
class_name AlabasterMechanicLabJunoBase

const JunoBaseRigScript := preload("res://scripts/labs/alabaster/AlabasterJunoBaseRig.gd")
const PROFILE_JUNO_BASE := "juno_base"
const VISIBLE_PROFILE_ORDER := [
	PROFILE_DEFAULT,
	PROFILE_DUMMY,
	PROFILE_JUNO,
	PROFILE_JUNO_BASE,
	PROFILE_GOLEM_STONE,
	PROFILE_GOLEM_JADE,
]
const VISIBLE_PROFILE_LABELS := {
	PROFILE_DEFAULT: "DEFAULT",
	PROFILE_DUMMY: "DUMMY",
	PROFILE_JUNO: "JUNO",
	PROFILE_JUNO_BASE: "JUNO BASE",
	PROFILE_GOLEM_STONE: "GOLEM PEDRA",
	PROFILE_GOLEM_JADE: "GOLEM JADE",
}


func _build_profile_switcher() -> void:
	var panel := PanelContainer.new()
	panel.name = "CharacterProfileSwitcher"
	panel.position = Vector2(SCREEN_SIZE.x - 540.0, 22.0)
	panel.custom_minimum_size = Vector2(510.0, 190.0)
	panel.z_index = 1000
	add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)
	var caption := Label.new()
	caption.text = "TEST FIGURE"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_theme_font_size_override("font_size", 13)
	box.add_child(caption)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(grid)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	_profile_buttons.clear()
	for profile_id in VISIBLE_PROFILE_ORDER:
		var button := Button.new()
		button.text = str(VISIBLE_PROFILE_LABELS[profile_id])
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(150.0, 34.0)
		button.tooltip_text = "Switch the complete test figure. JunoBase is the audited core-player clone of Juno."
		button.pressed.connect(_on_profile_pressed.bind(profile_id))
		grid.add_child(button)
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
	_opacity_slider.tooltip_text = "Lower body sprite opacity while F1 skeleton/debug is enabled."
	_opacity_slider.value_changed.connect(_on_sprite_opacity_changed)
	opacity_row.add_child(_opacity_slider)

	_opacity_value_label = Label.new()
	_opacity_value_label.custom_minimum_size = Vector2(48.0, 0.0)
	_opacity_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	opacity_row.add_child(_opacity_value_label)
	_update_opacity_label()

	var note := Label.new()
	note.text = "JUNO = full source • JUNO BASE = core player sheet • MALE removed • F1 skeleton"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_font_size_override("font_size", 11)
	note.modulate = Color(0.72, 0.78, 0.88)
	box.add_child(note)


func _replace_rig(profile_id: String, refresh_ui: bool) -> void:
	if profile_id != PROFILE_JUNO_BASE:
		if profile_id in VISIBLE_PROFILE_ORDER:
			super._replace_rig(profile_id, refresh_ui)
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

	_active_profile = PROFILE_JUNO_BASE
	rig = JunoBaseRigScript.new()
	rig.name = "JunoBaseRig"
	player.add_child(rig)
	_install_profile_custom_animations(PROFILE_JUNO_BASE)
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
		PROFILE_JUNO_BASE,
		SharedActions.LAB_ACTIONS.size() - missing_actions.size(),
		SharedActions.LAB_ACTIONS.size(),
		str(missing_actions),
	])
	print("ALABASTER_LAB_ACTION_MAP profile=%s resolved=%s" % [PROFILE_JUNO_BASE, str(resolved_actions)])

	if refresh_ui:
		_refresh_catalog()
		_update_profile_buttons()
		_update_status()
		print("ALABASTER_LAB_PROFILE profile=%s label=%s animations=%d" % [
			PROFILE_JUNO_BASE, VISIBLE_PROFILE_LABELS[PROFILE_JUNO_BASE], _catalog.size(),
		])


func _update_status() -> void:
	super._update_status()
	if status_label == null or _active_profile != PROFILE_JUNO_BASE:
		return
	status_label.text = status_label.text.replace("figure=juno_base", "figure=JUNO BASE")
	status_label.text = status_label.text.replace("runtime=GAME PLAYABLE SKIN RIG", "runtime=GAME BONES SYSTEM · CORE ATLAS")
