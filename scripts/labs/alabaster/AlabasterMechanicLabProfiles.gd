extends "res://scripts/labs/alabaster/AlabasterMechanicLab.gd"
class_name AlabasterMechanicLabProfiles

const JunoRigScript := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeSourceLive.gd")
const PlayableSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")

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
	panel.position = Vector2(SCREEN_SIZE.x - 390.0, 22.0)
	panel.custom_minimum_size = Vector2(360.0, 86.0)
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
		button.custom_minimum_size = Vector2(104.0, 34.0)
		button.tooltip_text = "Switch the complete source figure. Dummy/Male use the exact same playable rig class as gameplay."
		button.pressed.connect(_on_profile_pressed.bind(profile_id))
		row.add_child(button)
		_profile_buttons[profile_id] = button
	_update_profile_buttons()

	var note := Label.new()
	note.text = "Dummy/Male = SAME GAME RIG · Juno gameplay bank · native clips preserved as native__*"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_font_size_override("font_size", 11)
	note.modulate = Color(0.72, 0.78, 0.88)
	box.add_child(note)


func _on_profile_pressed(profile_id: String) -> void:
	_replace_rig(profile_id, true)


func _replace_rig(profile_id: String, refresh_ui: bool) -> void:
	if profile_id not in [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]:
		return
	_manual_active = false
	_auto_showcase = false
	_manual_elapsed = 0.0
	_manual_duration = 0.0

	if rig != null and is_instance_valid(rig):
		if rig.get_parent() != null:
			rig.get_parent().remove_child(rig)
		rig.queue_free()

	_active_profile = profile_id
	if profile_id == PROFILE_JUNO:
		rig = JunoRigScript.new()
		rig.name = "JunoRig"
		player.add_child(rig)
	else:
		# This is intentionally the same class instantiated by
		# AlabasterPlayerVisualController in actual gameplay. The lab contains no
		# separate locomotion/combat retarget path anymore.
		var skin_rig = PlayableSkinRigScript.new()
		skin_rig.call("configure_skin_profile", profile_id)
		rig = skin_rig
		rig.name = "%sRig" % str(PROFILE_LABELS[profile_id]).capitalize()
		player.add_child(rig)
		if rig.has_method("initialize_skin") and not bool(rig.call("initialize_skin")):
			push_error("AlabasterMechanicLabProfiles: could not initialize profile %s" % profile_id)

	rig.scale = Vector2(2.5, 2.5)
	if rig.has_method("set_debug_enabled"):
		rig.call("set_debug_enabled", _debug_enabled)
	if rig.has_method("set_facing_from_vector"):
		rig.call("set_facing_from_vector", Vector2.DOWN)
	_set_profile_idle()

	if refresh_ui:
		_refresh_catalog()
		_update_profile_buttons()
		_update_status()
		print("ALABASTER_LAB_PROFILE profile=%s label=%s animations=%d" % [
			_active_profile,
			str(PROFILE_LABELS[_active_profile]),
			_catalog.size(),
		])


func _physics_process(delta: float) -> void:
	if _manual_active:
		_manual_elapsed += delta
		if _manual_duration > 0.0 and _manual_elapsed >= _manual_duration:
			if _auto_showcase:
				_navigate_browser(1)
				_play_browser_animation()
			else:
				_stop_manual_animation()
		player.velocity = Vector2.ZERO
		_update_status()
		return

	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var running := Input.is_key_pressed(KEY_SHIFT)
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
		player.velocity = input_dir * (RUN_SPEED if running else WALK_SPEED)
		player.move_and_slide()
		player.position.x = clampf(player.position.x, 72.0, SCREEN_SIZE.x - 72.0)
		player.position.y = clampf(player.position.y, 92.0, SCREEN_SIZE.y - 72.0)
		rig.set_facing_from_vector(input_dir)
		# Same animation names used by gameplay. Dummy/Male resolve these names
		# because AlabasterPlayableSkinRig installs Juno onto their bones itself.
		rig.set_animation("run" if running else "walk")
	else:
		player.velocity = Vector2.ZERO
		_set_profile_idle()
	_update_status()


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
	var runtime_label := "JUNO SOURCE RIG" if _active_profile == PROFILE_JUNO else "SHARED PLAYABLE RIG"
	status_label.text = "figure=%s   runtime=%s   %s" % [
		str(PROFILE_LABELS.get(_active_profile, _active_profile)),
		runtime_label,
		status_label.text,
	]
