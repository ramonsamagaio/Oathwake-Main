extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"
class_name AlabasterBoneStudioProfiles

const JunoProductionRigScript := preload("res://scripts/labs/alabaster/AlabasterRigRuntimeTunable.gd")
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
const LIVE_PREVIEW_NAME := "__live_tuning_preview"
const TUNING_KEY := "oathwake_tuning"
const TUNING_GLOBAL_KEY := "global"
const TUNING_FRAMES_KEY := "frames"

var _active_profile := PROFILE_JUNO
var _profile_buttons: Dictionary = {}
var _existing_option: OptionButton
var _existing_source_label: Label
var _existing_records: Array[Dictionary] = []
var _loaded_template: Dictionary = {}
var _loaded_source_name := ""
var _loaded_source_kind := "new"
var _loaded_read_only := false

# LIVE TUNING tab state. It edits a non-destructive correction layer over a
# source animation while the exact shared runtime continues playing it.
var _studio_tabs: TabContainer
var _live_tab: Control
var _live_profile_option: OptionButton
var _live_filter_option: OptionButton
var _live_animation_option: OptionButton
var _live_part_list: ItemList
var _live_green_slider: HSlider
var _live_green_value: Label
var _live_scope_option: OptionButton
var _live_frame_label: Label
var _live_source_label: Label
var _live_save_name: LineEdit
var _live_animation_records: Array[Dictionary] = []
var _live_source_record: Dictionary = {}
var _live_source_data: Dictionary = {}
var _live_working_data: Dictionary = {}
var _live_selected_part := ""
var _live_green_intensity := 0.65
var _live_suppress_ui := false


func _ready() -> void:
	super._ready()
	_build_profile_and_load_toolbar()
	_build_live_tuning_tab()
	# The Pro base creates the first Juno preview before this profile layer runs.
	# Replace it once so Juno, Dummy and Male all use the same tunable runtime
	# contract from this point onward.
	_replace_preview_rig()
	_refresh_existing_animation_list()
	_update_profile_buttons()
	_update_preview_heading()
	_refresh_live_animation_list(true)
	_refresh_live_part_list()


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
		button.focus_mode = Control.FOCUS_NONE
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


func _build_live_tuning_tab() -> void:
	_studio_tabs = _find_tab_container(self)
	if _studio_tabs == null:
		push_warning("AlabasterBoneStudioProfiles: could not locate main TabContainer for Live Tuning.")
		return

	var scroll := ScrollContainer.new()
	scroll.name = "Live_Tuning"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_studio_tabs.add_child(scroll)
	_live_tab = scroll

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_heading(box, "LIVE TUNING · NON-DESTRUCTIVE")
	var intro := Label.new()
	intro.text = "Choose a source animation, keep it looping, select a visible sprite part and drag its bone in the preview. WHOLE ANIMATION adds one local correction after every sampled frame; CURRENT FRAME affects only the exact displayed source frame. Alabaster originals remain locked."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	_live_profile_option = OptionButton.new()
	for profile_id in [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]:
		_live_profile_option.add_item(str(PROFILE_LABELS[profile_id]))
		_live_profile_option.set_item_metadata(_live_profile_option.item_count - 1, profile_id)
	_live_profile_option.item_selected.connect(_on_live_profile_selected)
	_add_row(box, "Target figure", _live_profile_option)

	_live_filter_option = OptionButton.new()
	for filter_label in ["ALL SOURCES", "JUNO", "DUMMY", "MALE", "CUSTOM ONLY"]:
		_live_filter_option.add_item(filter_label)
	_live_filter_option.item_selected.connect(func(_index: int) -> void: _refresh_live_animation_list(false))
	_add_row(box, "Bank filter", _live_filter_option)

	_live_animation_option = OptionButton.new()
	_live_animation_option.custom_minimum_size = Vector2(0.0, 34.0)
	_live_animation_option.item_selected.connect(_on_live_animation_selected)
	_add_row(box, "Animation", _live_animation_option)

	_live_source_label = Label.new()
	_live_source_label.text = "Source: waiting for bank"
	_live_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live_source_label.modulate = Color(0.72, 0.82, 0.92)
	box.add_child(_live_source_label)

	_add_heading(box, "Visible sprite parts")
	_live_part_list = ItemList.new()
	_live_part_list.custom_minimum_size = Vector2(0.0, 220.0)
	_live_part_list.select_mode = ItemList.SELECT_SINGLE
	_live_part_list.item_selected.connect(_on_live_part_selected)
	box.add_child(_live_part_list)

	_live_green_slider = HSlider.new()
	_live_green_slider.min_value = 0.0
	_live_green_slider.max_value = 1.0
	_live_green_slider.step = 0.05
	_live_green_slider.value = _live_green_intensity
	_live_green_slider.value_changed.connect(_on_live_green_changed)
	var green_row := HBoxContainer.new()
	green_row.add_child(_live_green_slider)
	_live_green_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_green_value = Label.new()
	_live_green_value.custom_minimum_size = Vector2(50.0, 0.0)
	green_row.add_child(_live_green_value)
	_add_row(box, "Selection green", green_row)
	_update_live_green_label()

	_add_heading(box, "Correction scope")
	_live_scope_option = OptionButton.new()
	_live_scope_option.add_item("WHOLE ANIMATION")
	_live_scope_option.set_item_metadata(0, TUNING_GLOBAL_KEY)
	_live_scope_option.add_item("CURRENT FRAME ONLY")
	_live_scope_option.set_item_metadata(1, TUNING_FRAMES_KEY)
	_live_scope_option.select(0)
	_add_row(box, "Apply drag to", _live_scope_option)

	_live_frame_label = Label.new()
	_live_frame_label.text = "Current source frame: 0"
	_live_frame_label.modulate = Color(0.93, 0.82, 0.48)
	box.add_child(_live_frame_label)

	var reset_row := HBoxContainer.new()
	box.add_child(reset_row)
	var reset_selected := Button.new()
	reset_selected.text = "Reset selected correction"
	reset_selected.pressed.connect(_reset_live_selected_correction)
	reset_row.add_child(reset_selected)
	var reset_all := Button.new()
	reset_all.text = "Reset all tuning"
	reset_all.pressed.connect(_reset_live_all_tuning)
	reset_row.add_child(reset_all)

	_add_heading(box, "Save tuned copy")
	_live_save_name = LineEdit.new()
	_live_save_name.placeholder_text = "e.g. idle_male_tuned"
	_add_row(box, "Custom name", _live_save_name)
	var save := Button.new()
	save.text = "SAVE TUNED COPY TO GLOBAL BANK"
	save.pressed.connect(_save_live_tuned_copy)
	box.add_child(save)

	var note := Label.new()
	note.text = "The green tint is editor-only. Sprite Opacity and Show Bones remain on the preview panel at right. Global and frame corrections are stored inside the custom animation and interpreted by the same runtime used by gameplay."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	_studio_tabs.tab_changed.connect(_on_studio_tab_changed)


func _find_tab_container(node: Node) -> TabContainer:
	for child in node.get_children():
		if child is TabContainer:
			return child as TabContainer
		var nested := _find_tab_container(child)
		if nested != null:
			return nested
	return null


func _on_profile_button_pressed(profile_id: String) -> void:
	_switch_profile(profile_id)


func _on_live_profile_selected(index: int) -> void:
	if _live_suppress_ui or _live_profile_option == null or index < 0:
		return
	var profile_id := str(_live_profile_option.get_item_metadata(index))
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
	_refresh_live_animation_list(true)
	_refresh_live_part_list()
	if _is_live_tuning_active():
		_start_live_preview()
	_set_status("Target figure switched to %s. Import mapping, timeline bones, Live Tuning and existing clips now target this figure." % str(PROFILE_LABELS[_active_profile]))


func _replace_preview_rig() -> void:
	if rig != null and is_instance_valid(rig):
		if rig.get_parent() != null:
			rig.get_parent().remove_child(rig)
		rig.queue_free()

	if _active_profile == PROFILE_JUNO:
		rig = JunoProductionRigScript.new()
		rig.name = "JunoBoneStudioTunableRig"
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
	if rig.has_method("set_selection_green_intensity"):
		rig.call("set_selection_green_intensity", _live_green_intensity)
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
	_refresh_live_part_list()


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
	_refresh_live_animation_list(false)
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
	_refresh_live_animation_list(false)
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


# -----------------------------------------------------------------------------
# LIVE TUNING
# -----------------------------------------------------------------------------

func _refresh_live_animation_list(select_default: bool) -> void:
	if _live_animation_option == null:
		return
	var previous_key := _live_record_key(_live_source_record)
	_live_animation_records = _build_global_animation_records()
	_live_animation_option.clear()
	var filter_index := _live_filter_option.selected if _live_filter_option != null else 0
	var filtered: Array[Dictionary] = []
	for record in _live_animation_records:
		if _live_record_matches_filter(record, filter_index):
			filtered.append(record)
	for record in filtered:
		var profile_id := str(record.get("source_profile", PROFILE_JUNO))
		var source_kind := str(record.get("source", "builtin"))
		var tag := "CUSTOM" if source_kind == "custom" else "SOURCE"
		_live_animation_option.add_item("%s · %s · %s" % [str(PROFILE_LABELS.get(profile_id, profile_id)), tag, str(record.get("name", ""))])
		_live_animation_option.set_item_metadata(_live_animation_option.item_count - 1, record.duplicate(true))

	if _live_animation_option.item_count <= 0:
		_live_source_record = {}
		_live_source_data = {}
		_live_working_data = {}
		return

	var desired_index := -1
	if not select_default and not previous_key.is_empty():
		for index in range(_live_animation_option.item_count):
			var record_value: Variant = _live_animation_option.get_item_metadata(index)
			if record_value is Dictionary and _live_record_key(record_value as Dictionary) == previous_key:
				desired_index = index
				break
	if desired_index < 0:
		desired_index = _find_live_default_index()
	if desired_index < 0:
		desired_index = 0
	_live_animation_option.select(desired_index)
	_on_live_animation_selected(desired_index)


func _build_global_animation_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile_id in [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]:
		for record_value in ProfileLibrary.get_animation_records(profile_id):
			var record := record_value.duplicate(true)
			record["source_profile"] = profile_id
			result.append(record)
	var profile_order := {PROFILE_JUNO: 0, PROFILE_DUMMY: 1, PROFILE_MALE: 2}
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(profile_order.get(str(a.get("source_profile", "")), 9))
		var pb := int(profile_order.get(str(b.get("source_profile", "")), 9))
		if pa != pb:
			return pa < pb
		var sa := 1 if str(a.get("source", "builtin")) == "custom" else 0
		var sb := 1 if str(b.get("source", "builtin")) == "custom" else 0
		if sa != sb:
			return sa < sb
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	return result


func _live_record_matches_filter(record: Dictionary, filter_index: int) -> bool:
	var source_profile := str(record.get("source_profile", ""))
	var source_kind := str(record.get("source", "builtin"))
	match filter_index:
		1:
			return source_profile == PROFILE_JUNO
		2:
			return source_profile == PROFILE_DUMMY
		3:
			return source_profile == PROFILE_MALE
		4:
			return source_kind == "custom"
		_:
			return true


func _find_live_default_index() -> int:
	var juno_idle := -1
	for index in range(_live_animation_option.item_count):
		var record_value: Variant = _live_animation_option.get_item_metadata(index)
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		if str(record.get("name", "")) != "idle":
			continue
		if str(record.get("source_profile", "")) == _active_profile:
			return index
		if str(record.get("source_profile", "")) == PROFILE_JUNO:
			juno_idle = index
	return juno_idle


func _live_record_key(record: Dictionary) -> String:
	if record.is_empty():
		return ""
	return "%s|%s|%s" % [str(record.get("source_profile", "")), str(record.get("source", "")), str(record.get("name", ""))]


func _on_live_animation_selected(index: int) -> void:
	if _live_suppress_ui or _live_animation_option == null or index < 0 or index >= _live_animation_option.item_count:
		return
	var record_value: Variant = _live_animation_option.get_item_metadata(index)
	if not record_value is Dictionary:
		return
	_load_live_animation_record(record_value as Dictionary)


func _load_live_animation_record(record: Dictionary) -> void:
	var source_profile := str(record.get("source_profile", PROFILE_JUNO))
	var source_name := str(record.get("name", ""))
	var source_kind := str(record.get("source", "builtin"))
	var full_record := ProfileLibrary.get_animation_record(source_profile, source_name)
	var data_value: Variant = full_record.get("data", {})
	if not data_value is Dictionary or (data_value as Dictionary).is_empty():
		_set_status("Live Tuning could not load %s/%s." % [str(PROFILE_LABELS.get(source_profile, source_profile)), source_name], true)
		return

	_live_source_record = record.duplicate(true)
	_live_source_data = (data_value as Dictionary).duplicate(true)
	_live_working_data = _retarget_live_animation_data(_live_source_data, source_profile, _active_profile, source_name)
	if _live_working_data.is_empty():
		_set_status("Live Tuning could not map '%s' from %s to %s." % [source_name, str(PROFILE_LABELS.get(source_profile, source_profile)), str(PROFILE_LABELS[_active_profile])], true)
		return

	var source_locked := source_kind != "custom" or source_profile != _active_profile
	if _live_save_name != null:
		if source_locked:
			var suffix := "juno" if _active_profile == PROFILE_JUNO else ("dummy" if _active_profile == PROFILE_DUMMY else "male")
			_live_save_name.text = _sanitize_name("%s_%s_tuned" % [source_name, suffix])
		else:
			_live_save_name.text = source_name
	if _live_source_label != null:
		_live_source_label.text = "Source: %s / %s / %s  →  target %s  ·  %s" % [
			str(PROFILE_LABELS.get(source_profile, source_profile)),
			"CUSTOM" if source_kind == "custom" else "ALABASTER",
			source_name,
			str(PROFILE_LABELS[_active_profile]),
			"SAVE COPY" if source_locked else "EDITABLE CUSTOM",
		]
	_start_live_preview()


func _retarget_live_animation_data(source: Dictionary, source_profile: String, target_profile: String, source_name: String) -> Dictionary:
	if source_profile == target_profile:
		return source.duplicate(true)
	if rig == null or not rig.has_method("get_bone_names"):
		return {}
	var target_set := {}
	var names_value: Variant = rig.call("get_bone_names")
	if names_value is Array:
		for node_name_value in names_value as Array:
			target_set[str(node_name_value)] = true
	if target_set.is_empty():
		return {}

	var result := source.duplicate(true)
	var filtered_transforms: Array = []
	var transforms_value: Variant = source.get("transforms", [])
	if transforms_value is Array:
		for key_value in transforms_value as Array:
			if not key_value is Dictionary:
				continue
			var key := (key_value as Dictionary).duplicate(true)
			var node_xfm_filtered := {}
			var node_xfm_value: Variant = key.get("nodeXfm", {})
			if node_xfm_value is Dictionary:
				for node_name_value in (node_xfm_value as Dictionary).keys():
					var node_name := str(node_name_value)
					if target_set.has(node_name):
						node_xfm_filtered[node_name] = (node_xfm_value as Dictionary)[node_name_value]
			key["nodeXfm"] = node_xfm_filtered
			filtered_transforms.append(key)
	result["transforms"] = filtered_transforms
	var filtered_nodes := {}
	var nodes_value: Variant = source.get("nodes", {})
	if nodes_value is Dictionary:
		for node_name_value in (nodes_value as Dictionary).keys():
			var node_name := str(node_name_value)
			if target_set.has(node_name):
				filtered_nodes[node_name] = (nodes_value as Dictionary)[node_name_value]
	result["nodes"] = filtered_nodes
	result["live_retarget_meta"] = {
		"source_profile": source_profile,
		"target_profile": target_profile,
		"source_animation": source_name,
		"method": "common_bone_filter",
	}
	return result


func _start_live_preview() -> void:
	if rig == null or _live_working_data.is_empty():
		return
	var preview_data := _live_working_data.duplicate(true)
	# Preview is always autoplay + loop. Saving keeps the source repeat flag.
	preview_data["repeat"] = true
	if rig.has_method("install_runtime_animation"):
		rig.call("install_runtime_animation", LIVE_PREVIEW_NAME, preview_data)
	var summary: Dictionary = rig.call("get_runtime_summary") as Dictionary if rig.has_method("get_runtime_summary") else {}
	if str(summary.get("animation", "")) != LIVE_PREVIEW_NAME and rig.has_method("set_animation"):
		rig.call("set_animation", LIVE_PREVIEW_NAME)
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", false)
	if rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", _live_selected_part)
	if rig.has_method("set_selection_green_intensity"):
		rig.call("set_selection_green_intensity", _live_green_intensity)


func _stop_live_preview() -> void:
	if rig == null:
		return
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)
	if rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", "")


func _refresh_live_part_list() -> void:
	if _live_part_list == null:
		return
	_live_part_list.clear()
	if rig == null or not rig.has_method("get_sprite_part_names"):
		return
	var names_value: Variant = rig.call("get_sprite_part_names")
	if not names_value is Array:
		return
	var names: Array = names_value as Array
	for node_name_value in names:
		var node_name := str(node_name_value)
		_live_part_list.add_item(node_name)
		_live_part_list.set_item_metadata(_live_part_list.item_count - 1, node_name)
	if _live_part_list.item_count <= 0:
		return
	var select_index := 0
	for index in range(_live_part_list.item_count):
		var candidate := str(_live_part_list.get_item_metadata(index))
		if candidate == _live_selected_part:
			select_index = index
			break
		if candidate == "head":
			select_index = index
	_live_part_list.select(select_index)
	_on_live_part_selected(select_index)


func _on_live_part_selected(index: int) -> void:
	if _live_part_list == null or index < 0 or index >= _live_part_list.item_count:
		return
	_live_selected_part = str(_live_part_list.get_item_metadata(index))
	if rig != null and rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", _live_selected_part)
	if viewport_editor != null:
		viewport_editor.set_selected_bone(_live_selected_part)
	_on_viewport_bone_selected(_live_selected_part)


func _on_live_green_changed(value: float) -> void:
	_live_green_intensity = clampf(value, 0.0, 1.0)
	_update_live_green_label()
	if rig != null and rig.has_method("set_selection_green_intensity"):
		rig.call("set_selection_green_intensity", _live_green_intensity)


func _update_live_green_label() -> void:
	if _live_green_value != null:
		_live_green_value.text = "%d%%" % roundi(_live_green_intensity * 100.0)


func _live_scope() -> String:
	if _live_scope_option == null or _live_scope_option.selected < 0:
		return TUNING_GLOBAL_KEY
	return str(_live_scope_option.get_item_metadata(_live_scope_option.selected))


func _on_viewport_bone_transform_delta(bone_name: String, mode: String, delta_value: Vector3) -> void:
	if not _is_live_tuning_active():
		super._on_viewport_bone_transform_delta(bone_name, mode, delta_value)
		return
	if _live_working_data.is_empty() or bone_name.is_empty():
		return
	if bone_name != _live_selected_part:
		_live_selected_part = bone_name
		_select_live_part_by_name(bone_name)
		if rig != null and rig.has_method("set_selected_sprite_part"):
			rig.call("set_selected_sprite_part", bone_name)

	var tuning_value: Variant = _live_working_data.get(TUNING_KEY, {})
	var tuning: Dictionary = (tuning_value as Dictionary).duplicate(true) if tuning_value is Dictionary else {}
	var scope := _live_scope()
	var scope_map: Dictionary
	var frame_key := ""
	if scope == TUNING_FRAMES_KEY:
		var frames_value: Variant = tuning.get(TUNING_FRAMES_KEY, {})
		var frames := (frames_value as Dictionary).duplicate(true) if frames_value is Dictionary else {}
		var frame := _live_current_frame()
		frame_key = str(frame)
		var frame_value: Variant = frames.get(frame_key, {})
		scope_map = (frame_value as Dictionary).duplicate(true) if frame_value is Dictionary else {}
		_apply_live_delta_to_scope(scope_map, bone_name, mode, delta_value)
		frames[frame_key] = scope_map
		tuning[TUNING_FRAMES_KEY] = frames
	else:
		var global_value: Variant = tuning.get(TUNING_GLOBAL_KEY, {})
		scope_map = (global_value as Dictionary).duplicate(true) if global_value is Dictionary else {}
		_apply_live_delta_to_scope(scope_map, bone_name, mode, delta_value)
		tuning[TUNING_GLOBAL_KEY] = scope_map
	_live_working_data[TUNING_KEY] = tuning
	_start_live_preview()
	var scope_label := "whole animation" if scope == TUNING_GLOBAL_KEY else "frame %s" % frame_key
	_set_status("Live Tuning: %s %s correction on %s (%s)." % [mode, scope_label, bone_name, str(PROFILE_LABELS[_active_profile])])


func _apply_live_delta_to_scope(scope_map: Dictionary, bone_name: String, mode: String, delta_value: Vector3) -> void:
	var current_value: Variant = scope_map.get(bone_name, {})
	var correction := (current_value as Dictionary).duplicate(true) if current_value is Dictionary else {}
	var rot_value: Variant = correction.get("rot", [0.0, 0.0, 0.0])
	var trans_value: Variant = correction.get("trans", [0.0, 0.0, 0.0])
	var rot: Array = (rot_value as Array).duplicate() if rot_value is Array else [0.0, 0.0, 0.0]
	var trans: Array = (trans_value as Array).duplicate() if trans_value is Array else [0.0, 0.0, 0.0]
	while rot.size() < 3:
		rot.append(0.0)
	while trans.size() < 3:
		trans.append(0.0)
	if mode == "move":
		trans[0] = float(trans[0]) + delta_value.x
		trans[1] = float(trans[1]) + delta_value.y
		trans[2] = float(trans[2]) + delta_value.z
	else:
		rot[0] = float(rot[0]) + delta_value.x
		rot[1] = float(rot[1]) + delta_value.y
		rot[2] = float(rot[2]) + delta_value.z
	correction["rot"] = rot
	correction["trans"] = trans
	correction["scale"] = float(correction.get("scale", 1.0))
	scope_map[bone_name] = correction


func _on_viewport_bone_selected(bone_name: String) -> void:
	super._on_viewport_bone_selected(bone_name)
	if not _is_live_tuning_active():
		return
	_live_selected_part = bone_name
	_select_live_part_by_name(bone_name)
	if rig != null and rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", bone_name)


func _select_live_part_by_name(bone_name: String) -> void:
	if _live_part_list == null:
		return
	for index in range(_live_part_list.item_count):
		if str(_live_part_list.get_item_metadata(index)) == bone_name:
			_live_part_list.select(index)
			return


func _reset_live_selected_correction() -> void:
	if _live_working_data.is_empty() or _live_selected_part.is_empty():
		return
	var tuning_value: Variant = _live_working_data.get(TUNING_KEY, {})
	if not tuning_value is Dictionary:
		return
	var tuning := (tuning_value as Dictionary).duplicate(true)
	var scope := _live_scope()
	if scope == TUNING_GLOBAL_KEY:
		var global_value: Variant = tuning.get(TUNING_GLOBAL_KEY, {})
		if global_value is Dictionary:
			var global_map := (global_value as Dictionary).duplicate(true)
			global_map.erase(_live_selected_part)
			tuning[TUNING_GLOBAL_KEY] = global_map
	else:
		var frames_value: Variant = tuning.get(TUNING_FRAMES_KEY, {})
		if frames_value is Dictionary:
			var frames := (frames_value as Dictionary).duplicate(true)
			var frame_key := str(_live_current_frame())
			var frame_value: Variant = frames.get(frame_key, {})
			if frame_value is Dictionary:
				var frame_map := (frame_value as Dictionary).duplicate(true)
				frame_map.erase(_live_selected_part)
				if frame_map.is_empty():
					frames.erase(frame_key)
				else:
					frames[frame_key] = frame_map
			tuning[TUNING_FRAMES_KEY] = frames
	_live_working_data[TUNING_KEY] = tuning
	_start_live_preview()


func _reset_live_all_tuning() -> void:
	if _live_working_data.is_empty():
		return
	_live_working_data.erase(TUNING_KEY)
	_start_live_preview()
	_set_status("Live Tuning corrections cleared for the working copy. Source animation remains untouched.")


func _save_live_tuned_copy() -> void:
	if _live_working_data.is_empty() or _live_source_record.is_empty():
		_set_status("Choose an animation in Live Tuning first.", true)
		return
	var animation_name := _sanitize_name(_live_save_name.text if _live_save_name != null else "")
	if animation_name.is_empty():
		_set_status("Choose a custom name for the tuned animation.", true)
		return
	if ProfileLibrary.is_read_only_animation(_active_profile, animation_name):
		_set_status("'%s' is a locked Alabaster/Juno source name for %s. Save the tuned version with a custom name." % [animation_name, str(PROFILE_LABELS[_active_profile])], true)
		return

	var data := _live_working_data.duplicate(true)
	var source_profile := str(_live_source_record.get("source_profile", PROFILE_JUNO))
	var source_name := str(_live_source_record.get("name", ""))
	var source_kind := str(_live_source_record.get("source", "builtin"))
	var meta := {
		"type": "live_tuning",
		"studio": "AlabasterBoneStudioProfiles",
		"target_profile": _active_profile,
		"source_profile": source_profile,
		"copied_from": source_name,
		"copied_from_kind": source_kind,
		"non_destructive_tuning": true,
	}
	if not ProfileLibrary.save_custom_animation(animation_name, data, meta):
		_set_status("Could not save tuned animation '%s'." % animation_name, true)
		return
	if rig != null and rig.has_method("install_runtime_animation"):
		rig.call("install_runtime_animation", animation_name, data)
	_refresh_existing_animation_list()
	_refresh_live_animation_list(false)
	_live_source_record = {
		"name": animation_name,
		"source": "custom",
		"read_only": false,
		"target_profile": _active_profile,
		"source_profile": _active_profile,
	}
	_live_source_data = data.duplicate(true)
	_live_working_data = data.duplicate(true)
	if _live_save_name != null:
		_live_save_name.text = animation_name
	_start_live_preview()
	_set_status("Saved tuned custom '%s' for %s. The original source animation was not modified." % [animation_name, str(PROFILE_LABELS[_active_profile])])


func _live_current_frame() -> int:
	if rig != null and rig.has_method("get_current_tuning_frame"):
		return int(rig.call("get_current_tuning_frame"))
	if rig != null and rig.has_method("get_current_source_frame"):
		return roundi(float(rig.call("get_current_source_frame")))
	return 0


func _on_studio_tab_changed(index: int) -> void:
	if _studio_tabs == null or index < 0 or index >= _studio_tabs.get_child_count():
		return
	if _studio_tabs.get_child(index) == _live_tab:
		_start_live_preview()
		_refresh_live_part_list()
	else:
		_stop_live_preview()


func _is_live_tuning_active() -> bool:
	return _studio_tabs != null and _live_tab != null and _studio_tabs.current_tab >= 0 and _studio_tabs.current_tab < _studio_tabs.get_child_count() and _studio_tabs.get_child(_studio_tabs.current_tab) == _live_tab


func _process(delta: float) -> void:
	super._process(delta)
	if _is_live_tuning_active() and _live_frame_label != null:
		_live_frame_label.text = "Current source frame: %d   ·   autoplay LOOP" % _live_current_frame()


func _update_profile_buttons() -> void:
	for profile_id in _profile_buttons.keys():
		var button := _profile_buttons[profile_id] as Button
		if button != null:
			button.set_pressed_no_signal(str(profile_id) == _active_profile)
	if _live_profile_option != null:
		_live_suppress_ui = true
		for index in range(_live_profile_option.item_count):
			if str(_live_profile_option.get_item_metadata(index)) == _active_profile:
				_live_profile_option.select(index)
				break
		_live_suppress_ui = false


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
