extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"
class_name AlabasterBoneStudioProfiles

const JunoProductionRigScript := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeProduction.gd")
const PlayableSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")
const ProfileLibrary := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const Retarget := preload("res://scripts/labs/alabaster/AlabasterHumanoidAnimationRetarget.gd")

const PROFILE_JUNO := "juno"
const PROFILE_DUMMY := "male_dummy"
const PROFILE_MALE := "male_temp"
const PROFILE_LABELS := {
	PROFILE_JUNO: "JUNO",
	PROFILE_DUMMY: "DUMMY",
	PROFILE_MALE: "MALE",
}
const PREVIEW_BASE_SCALE := 3.2

var _active_profile := PROFILE_JUNO
var _profile_buttons: Dictionary = {}
var _existing_option: OptionButton
var _existing_source_label: Label
var _existing_records: Array[Dictionary] = []
var _loaded_template: Dictionary = {}
var _loaded_source_name := ""
var _loaded_source_kind := "new"
var _loaded_read_only := false


func _ready() -> void:
	super._ready()
	_build_profile_and_load_toolbar()
	_refresh_existing_animation_list()
	_update_profile_buttons()
	_update_preview_heading()


func _build_profile_and_load_toolbar() -> void:
	var margin := get_child(0) as MarginContainer
	if margin == null or margin.get_child_count() <= 0:
		return
	var root := margin.get_child(0) as VBoxContainer
	if root == null:
		return

	var panel := PanelContainer.new()
	panel.name = "FigureAndAnimationToolbar"
	panel.custom_minimum_size = Vector2(0.0, 72.0)
	root.add_child(panel)
	root.move_child(panel, 1)

	var box := VBoxContainer.new()
	panel.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)

	var figure_label := Label.new()
	figure_label.text = "TARGET FIGURE"
	figure_label.custom_minimum_size = Vector2(105.0, 0.0)
	row.add_child(figure_label)

	var group := ButtonGroup.new()
	group.allow_unpress = false
	for profile_id in [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]:
		var button := Button.new()
		button.text = str(PROFILE_LABELS[profile_id])
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(82.0, 30.0)
		button.tooltip_text = "Switch the target figure used by retarget import, direct bone editing and existing-animation loading."
		button.pressed.connect(_on_profile_button_pressed.bind(profile_id))
		row.add_child(button)
		_profile_buttons[profile_id] = button

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var load_label := Label.new()
	load_label.text = "LOAD EXISTING"
	row.add_child(load_label)
	_existing_option = OptionButton.new()
	_existing_option.custom_minimum_size = Vector2(330.0, 30.0)
	_existing_option.item_selected.connect(_on_existing_selected)
	row.add_child(_existing_option)
	var load_button := Button.new()
	load_button.text = "LOAD"
	load_button.custom_minimum_size = Vector2(72.0, 30.0)
	load_button.pressed.connect(_load_selected_existing_animation)
	row.add_child(load_button)

	_existing_source_label = Label.new()
	_existing_source_label.text = "Alabaster originals are read-only. LOAD creates an editable working copy; Save As never mutates source data."
	_existing_source_label.add_theme_font_size_override("font_size", 12)
	_existing_source_label.modulate = Color(0.72, 0.82, 0.92)
	box.add_child(_existing_source_label)


func _on_profile_button_pressed(profile_id: String) -> void:
	_switch_profile(profile_id)


func _switch_profile(profile_id: String) -> void:
	if profile_id not in [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE] or profile_id == _active_profile:
		return
	_stop_manual_playback()
	_clear_loaded_animation_state()
	_active_profile = profile_id
	_replace_preview_rig()
	_refresh_existing_animation_list()
	_update_profile_buttons()
	_update_preview_heading()
	_set_status("Target figure switched to %s. Import mapping, timeline bones and existing clips now target this figure." % str(PROFILE_LABELS[_active_profile]))


func _replace_preview_rig() -> void:
	if rig != null and is_instance_valid(rig):
		if rig.get_parent() != null:
			rig.get_parent().remove_child(rig)
		rig.queue_free()

	if _active_profile == PROFILE_JUNO:
		rig = JunoProductionRigScript.new()
		rig.name = "JunoBoneStudioProductionRig"
		preview_world.add_child(rig)
	else:
		var skin_rig = PlayableSkinRigScript.new()
		skin_rig.call("configure_skin_profile", _active_profile)
		rig = skin_rig
		rig.name = "%sBoneStudioRig" % str(PROFILE_LABELS[_active_profile]).capitalize()
		preview_world.add_child(rig)
		if rig.has_method("initialize_skin") and not bool(rig.call("initialize_skin")):
			_set_status("Could not initialize %s source figure." % str(PROFILE_LABELS[_active_profile]), true)
			return
		_install_profile_custom_animations()

	rig.scale = Vector2.ONE * PREVIEW_BASE_SCALE * preview_zoom
	if rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", opacity_slider.value)
	if rig.has_method("set_debug_enabled"):
		rig.call("set_debug_enabled", false)
	if rig.has_method("set_editor_camera_enabled"):
		rig.call("set_editor_camera_enabled", true)
	if rig.has_method("set_editor_camera_pitch_degrees"):
		rig.call("set_editor_camera_pitch_degrees", preview_pitch_degrees)
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)
	if rig.has_method("set_facing_from_vector"):
		rig.call("set_facing_from_vector", Vector2.DOWN)
	if _active_profile != PROFILE_JUNO and rig.has_method("set_rest_pose"):
		rig.call("set_rest_pose")
	elif rig.has_method("set_animation"):
		rig.call("set_animation", "idle")

	_populate_manual_bones()
	if not source_bones.is_empty():
		_rebuild_mapping_table()
	if viewport_editor != null:
		viewport_editor.configure(rig, _preview_center())
		viewport_editor.set_camera_locked(camera_lock_check.button_pressed if camera_lock_check != null else true)
		viewport_editor.set_transform_mode(str(transform_mode_option.get_item_metadata(transform_mode_option.selected)) if transform_mode_option != null and transform_mode_option.selected >= 0 else "rotate")
	_sync_pro_timeline()


func _install_profile_custom_animations() -> void:
	if rig == null:
		return
	var custom := ProfileLibrary.load_custom_animations(_active_profile)
	for name_value in custom.keys():
		var data_value: Variant = custom[name_value]
		if data_value is Dictionary:
			rig.call("install_runtime_animation", str(name_value), data_value as Dictionary)


func _refresh_existing_animation_list() -> void:
	if _existing_option == null:
		return
	_existing_records.clear()
	_existing_option.clear()
	for record in ProfileLibrary.get_animation_records(_active_profile):
		_existing_records.append(record.duplicate(true))

	if _active_profile != PROFILE_JUNO and rig != null and rig.has_method("has_animation"):
		for source_name in ["idle", "walk", "run"]:
			var retarget_name := Retarget.get_retarget_name(source_name)
			if bool(rig.call("has_animation", retarget_name)):
				_existing_records.append({
					"name": retarget_name,
					"source": "retarget",
					"read_only": true,
					"target_profile": _active_profile,
				})

	_existing_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var source_order := {"builtin": 0, "retarget": 1, "custom": 2}
		var oa := int(source_order.get(str(a.get("source", "custom")), 9))
		var ob := int(source_order.get(str(b.get("source", "custom")), 9))
		if oa != ob:
			return oa < ob
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)

	for record in _existing_records:
		var source := str(record.get("source", "custom"))
		var tag := "ALABASTER · LOCKED" if source == "builtin" else ("JUNO RETARGET · LOCKED" if source == "retarget" else "CUSTOM · EDITABLE")
		_existing_option.add_item("%s   [%s]" % [str(record.get("name", "")), tag])
		_existing_option.set_item_metadata(_existing_option.item_count - 1, record.duplicate(true))
	if _existing_option.item_count > 0:
		_existing_option.select(0)
		_on_existing_selected(0)
	else:
		_existing_source_label.text = "No animations available for %s." % str(PROFILE_LABELS[_active_profile])


func _on_existing_selected(index: int) -> void:
	if _existing_option == null or index < 0 or index >= _existing_option.item_count:
		return
	var record_value: Variant = _existing_option.get_item_metadata(index)
	if not record_value is Dictionary:
		return
	var record := record_value as Dictionary
	var source := str(record.get("source", "custom"))
	if source == "builtin":
		_existing_source_label.text = "ALABASTER ORIGINAL · READ ONLY. LOAD makes a working copy. Saving with the original name is blocked."
	elif source == "retarget":
		_existing_source_label.text = "GENERATED JUNO → %s · READ ONLY. LOAD makes a working copy you can tune visually." % str(PROFILE_LABELS[_active_profile])
	else:
		_existing_source_label.text = "OATHWAKE CUSTOM · EDITABLE. LOAD and Save may update this custom animation."


func _load_selected_existing_animation() -> void:
	if _existing_option == null or _existing_option.selected < 0:
		return
	var record_value: Variant = _existing_option.get_item_metadata(_existing_option.selected)
	if not record_value is Dictionary:
		return
	var record := record_value as Dictionary
	var name := str(record.get("name", ""))
	var source := str(record.get("source", "custom"))
	var data := {}
	if source == "retarget":
		if rig != null and rig.has_method("get_animation_data"):
			var value: Variant = rig.call("get_animation_data", name)
			if value is Dictionary:
				data = (value as Dictionary).duplicate(true)
	else:
		var full_record := ProfileLibrary.get_animation_record(_active_profile, name)
		var value: Variant = full_record.get("data", {})
		if value is Dictionary:
			data = (value as Dictionary).duplicate(true)
	if data.is_empty():
		_set_status("Could not load animation '%s'." % name, true)
		return
	_load_animation_into_manual_editor(name, source, bool(record.get("read_only", source != "custom")), data)


func _load_animation_into_manual_editor(animation_name: String, source_kind: String, read_only: bool, data: Dictionary) -> void:
	_loaded_template = data.duplicate(true)
	_loaded_source_name = animation_name
	_loaded_source_kind = source_kind
	_loaded_read_only = read_only
	manual_keys.clear()

	var transforms_value: Variant = data.get("transforms", [])
	if transforms_value is Array:
		for key_value in transforms_value as Array:
			if not key_value is Dictionary:
				continue
			var key := (key_value as Dictionary).duplicate(true)
			var frame := int(key.get("frame", 0))
			if not manual_keys.has(frame):
				manual_keys[frame] = {
					"spline": str(key.get("spline", "LINEAR")),
					"tween_enabled": str(key.get("spline", "LINEAR")) != "LINEAR",
					"nodeXfm": {},
					"hooks": [],
				}
			var frame_data: Dictionary = manual_keys[frame]
			frame_data["spline"] = str(key.get("spline", frame_data.get("spline", "LINEAR")))
			frame_data["tween_enabled"] = str(frame_data["spline"]) != "LINEAR"
			var merged_xfm: Dictionary = frame_data.get("nodeXfm", {})
			var node_xfm_value: Variant = key.get("nodeXfm", {})
			if node_xfm_value is Dictionary:
				for node_name_value in (node_xfm_value as Dictionary).keys():
					merged_xfm[str(node_name_value)] = (node_xfm_value as Dictionary)[node_name_value]
			frame_data["nodeXfm"] = merged_xfm
			var merged_hooks: Array = frame_data.get("hooks", [])
			var hooks_value: Variant = key.get("hooks", [])
			if hooks_value is Array:
				for hook in hooks_value as Array:
					merged_hooks.append(hook)
			frame_data["hooks"] = merged_hooks
			manual_keys[frame] = frame_data

	var frame_repeat := maxf(float(data.get("frameRepeat", 1.0)), 0.001)
	manual_fps_spin.value = clampf(60.0 / frame_repeat, manual_fps_spin.min_value, manual_fps_spin.max_value)
	manual_loop_check.button_pressed = bool(data.get("repeat", true))
	var start_frame := int(data.get("animStart", 0))
	manual_frame_spin.value = start_frame
	if timeline_length_spin != null:
		timeline_length_spin.value = maxf(float(data.get("frameCnt", 1)), 1.0)

	if read_only:
		manual_name_edit.text = _copy_name(animation_name)
	else:
		manual_name_edit.text = animation_name
	_refresh_manual_key_list()
	_populate_manual_bones()
	if manual_bone_option.item_count > 0:
		_load_editor_values_for_bone_frame(_current_manual_bone(), start_frame)
	_preview_current_manual_frame()
	var mode := "READ-ONLY SOURCE → EDITABLE COPY" if read_only else "EDITABLE CUSTOM"
	_set_status("Loaded '%s' for %s · %s." % [animation_name, str(PROFILE_LABELS[_active_profile]), mode])


func _copy_name(source_name: String) -> String:
	var suffix := "juno" if _active_profile == PROFILE_JUNO else ("dummy" if _active_profile == PROFILE_DUMMY else "male")
	return _sanitize_name("%s_%s_copy" % [source_name, suffix])


func _clear_loaded_animation_state() -> void:
	_loaded_template = {}
	_loaded_source_name = ""
	_loaded_source_kind = "new"
	_loaded_read_only = false
	manual_keys.clear()
	manual_name_edit.text = "OW_%s_manual" % ("juno" if _active_profile == PROFILE_JUNO else ("dummy" if _active_profile == PROFILE_DUMMY else "male"))
	_refresh_manual_key_list()


func _build_manual_animation() -> Dictionary:
	if manual_keys.is_empty():
		_set_status("Add or LOAD at least one keyframe first.", true)
		return {}
	var frames: Array = manual_keys.keys()
	frames.sort()
	var transforms: Array = []
	for frame_value in frames:
		var frame := int(frame_value)
		var frame_data_value: Variant = manual_keys[frame]
		if not frame_data_value is Dictionary:
			continue
		var frame_data := (frame_data_value as Dictionary).duplicate(true)
		frame_data.erase("tween_enabled")
		frame_data["frame"] = frame
		if not frame_data.has("spline"):
			frame_data["spline"] = "LINEAR"
		if not frame_data.get("nodeXfm", {}) is Dictionary:
			frame_data["nodeXfm"] = {}
		transforms.append(frame_data)

	var last_frame := int(frames.back())
	var timeline_fps := maxf(manual_fps_spin.value, 1.0)
	var result := _loaded_template.duplicate(true) if not _loaded_template.is_empty() else {}
	result["category"] = str(result.get("category", "DEFAULT"))
	result["frameCnt"] = maxi(int(result.get("frameCnt", 1)), maxi(last_frame, 1))
	result["frameRepeat"] = 60.0 / timeline_fps
	result["animStart"] = int(result.get("animStart", 0))
	result["loopStart"] = int(result.get("loopStart", result["animStart"]))
	result["repeat"] = manual_loop_check.button_pressed
	result["transforms"] = transforms
	if not result.get("nodes", {}) is Dictionary:
		result["nodes"] = {}
	result["manual_meta"] = {
		"timeline_fps": timeline_fps,
		"alabaster_frame_repeat": 60.0 / timeline_fps,
		"studio": "AlabasterBoneStudioProfiles",
		"target_profile": _active_profile,
		"copied_from": _loaded_source_name,
		"copied_from_kind": _loaded_source_kind,
	}
	return result


func _save_manual() -> void:
	var data := _build_manual_animation()
	if data.is_empty():
		return
	var animation_name := _sanitize_name(manual_name_edit.text)
	if animation_name.is_empty():
		_set_status("Choose a name for the manual animation copy.", true)
		return
	if ProfileLibrary.is_builtin_animation(_active_profile, animation_name):
		_set_status("'%s' is an Alabaster source animation and is locked. Save with a copy name." % animation_name, true)
		return
	var meta := {
		"type": "manual",
		"studio": "AlabasterBoneStudioProfiles",
		"target_profile": _active_profile,
		"copied_from": _loaded_source_name,
		"copied_from_kind": _loaded_source_kind,
	}
	if not ProfileLibrary.save_custom_animation(animation_name, data, meta):
		_set_status("Could not save custom animation. Originals are protected and custom names cannot collide across target figures.", true)
		return
	rig.call("install_runtime_animation", animation_name, data)
	rig.call("set_animation", animation_name)
	_loaded_template = data.duplicate(true)
	_loaded_source_name = animation_name
	_loaded_source_kind = "custom"
	_loaded_read_only = false
	_refresh_existing_animation_list()
	_select_existing_name(animation_name, "custom")
	_set_status("Saved custom '%s' for %s. Source Alabaster data was not modified." % [animation_name, str(PROFILE_LABELS[_active_profile])])


func _save_import() -> void:
	var data := _build_import_animation()
	if data.is_empty():
		return
	var animation_name := _sanitize_name(import_name_edit.text)
	if animation_name.is_empty():
		_set_status("Choose a name for the imported animation.", true)
		return
	if ProfileLibrary.is_builtin_animation(_active_profile, animation_name):
		_set_status("'%s' is a locked Alabaster source animation. Choose a custom copy name." % animation_name, true)
		return
	var meta := {
		"type": "retarget_import",
		"target_profile": _active_profile,
		"source_path": source_path,
		"source_clip": _selected_clip(),
		"mapping": _get_mapping(),
		"settings": _get_import_settings(),
	}
	if not ProfileLibrary.save_custom_animation(animation_name, data, meta):
		_set_status("Could not save imported animation for %s." % str(PROFILE_LABELS[_active_profile]), true)
		return
	rig.call("install_runtime_animation", animation_name, data)
	rig.call("set_animation", animation_name)
	_refresh_existing_animation_list()
	_select_existing_name(animation_name, "custom")
	_set_status("Saved imported '%s' for %s." % [animation_name, str(PROFILE_LABELS[_active_profile])])


func _select_existing_name(animation_name: String, source_kind: String) -> void:
	if _existing_option == null:
		return
	for index in range(_existing_option.item_count):
		var record_value: Variant = _existing_option.get_item_metadata(index)
		if record_value is Dictionary:
			var record := record_value as Dictionary
			if str(record.get("name", "")) == animation_name and str(record.get("source", "")) == source_kind:
				_existing_option.select(index)
				_on_existing_selected(index)
				return


func _update_profile_buttons() -> void:
	for profile_id in _profile_buttons.keys():
		var button := _profile_buttons[profile_id] as Button
		if button != null:
			button.set_pressed_no_signal(str(profile_id) == _active_profile)


func _update_preview_heading() -> void:
	_update_label_text_recursive(self, "Live Juno Preview", "Live %s Preview" % str(PROFILE_LABELS[_active_profile]))
	if import_reference_pose != null:
		import_reference_pose.tooltip_text = "Recommended: removes the source character rest pose and keeps only animation delta before applying it to %s." % str(PROFILE_LABELS[_active_profile])


func _update_label_text_recursive(node: Node, prefix: String, replacement: String) -> bool:
	for child in node.get_children():
		if child is Label and (child as Label).text.begins_with(prefix):
			(child as Label).text = replacement
			return true
		if _update_label_text_recursive(child, prefix, replacement):
			return true
	return false
