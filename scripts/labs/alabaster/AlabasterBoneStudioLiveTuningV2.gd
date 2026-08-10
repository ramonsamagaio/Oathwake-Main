extends "res://scripts/labs/alabaster/AlabasterBoneStudioProfiles.gd"

# Bone Studio live tuning layer.
# Kept intentionally path-based (no class_name) so this editor-only layer does
# not participate in Godot's global script-class cache. Source animations remain
# immutable; all edits are stored as additive Oathwake tuning on custom copies.

const LIVE_PREVIEW_NAME := "__live_tuning_preview"
const TUNING_KEY := "oathwake_tuning"
const TUNING_GLOBAL_KEY := "global"
const TUNING_FRAMES_KEY := "frames"

var _live_tabs: TabContainer = null
var _live_tab: Control = null
var _live_profile_option: OptionButton = null
var _live_filter_option: OptionButton = null
var _live_animation_option: OptionButton = null
var _live_part_list: ItemList = null
var _live_green_slider: HSlider = null
var _live_green_value: Label = null
var _live_scope_option: OptionButton = null
var _live_frame_label: Label = null
var _live_source_label: Label = null
var _live_save_name: LineEdit = null
var _live_play_button: Button = null

var _live_source_record: Dictionary = {}
var _live_source_data: Dictionary = {}
var _live_working_data: Dictionary = {}
var _live_selected_part := ""
var _live_green_intensity := 0.65
var _live_ui_sync := false
var _live_frame_editing := false


func _ready() -> void:
	super._ready()
	_build_live_tuning_tab()
	_sync_live_profile_option()
	_refresh_live_animation_list(true)
	_refresh_live_part_list()


func _build_live_tuning_tab() -> void:
	_live_tabs = _find_live_tab_container(self)
	if _live_tabs == null:
		push_warning("AlabasterBoneStudioLiveTuningV2: main TabContainer not found.")
		return

	var scroll := ScrollContainer.new()
	scroll.name = "Live_Tuning"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_live_tabs.add_child(scroll)
	_live_tab = scroll

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_heading(box, "LIVE TUNING · NON-DESTRUCTIVE")
	var intro := Label.new()
	intro.text = "Choose JUNO, DUMMY or MALE, autoplay any animation from the global bank, select a visible sprite part and edit its bone directly in the preview. WHOLE ANIMATION adds one correction across the full clip. CURRENT FRAME ONLY pauses on one source frame and changes only that frame. Source clips are never overwritten."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	_live_profile_option = OptionButton.new()
	_add_profile_item(_live_profile_option, PROFILE_JUNO)
	_add_profile_item(_live_profile_option, PROFILE_DUMMY)
	_add_profile_item(_live_profile_option, PROFILE_MALE)
	_live_profile_option.item_selected.connect(_on_live_profile_selected)
	_add_row(box, "Target figure", _live_profile_option)

	_live_filter_option = OptionButton.new()
	_live_filter_option.add_item("ALL SOURCES")
	_live_filter_option.add_item("JUNO")
	_live_filter_option.add_item("DUMMY")
	_live_filter_option.add_item("MALE")
	_live_filter_option.add_item("CUSTOM ONLY")
	_live_filter_option.item_selected.connect(_on_live_filter_selected)
	_add_row(box, "Bank filter", _live_filter_option)

	_live_animation_option = OptionButton.new()
	_live_animation_option.custom_minimum_size = Vector2(0.0, 34.0)
	_live_animation_option.item_selected.connect(_on_live_animation_selected)
	_add_row(box, "Animation", _live_animation_option)

	_live_source_label = Label.new()
	_live_source_label.text = "Source: waiting for animation bank"
	_live_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_live_source_label.modulate = Color(0.72, 0.82, 0.92)
	box.add_child(_live_source_label)

	_add_heading(box, "VISIBLE SPRITE PARTS")
	_live_part_list = ItemList.new()
	_live_part_list.custom_minimum_size = Vector2(0.0, 230.0)
	_live_part_list.select_mode = ItemList.SELECT_SINGLE
	_live_part_list.item_selected.connect(_on_live_part_selected)
	box.add_child(_live_part_list)

	var green_row := HBoxContainer.new()
	_live_green_slider = HSlider.new()
	_live_green_slider.min_value = 0.0
	_live_green_slider.max_value = 1.0
	_live_green_slider.step = 0.05
	_live_green_slider.value = _live_green_intensity
	_live_green_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_green_slider.value_changed.connect(_on_live_green_changed)
	green_row.add_child(_live_green_slider)
	_live_green_value = Label.new()
	_live_green_value.custom_minimum_size = Vector2(52.0, 0.0)
	green_row.add_child(_live_green_value)
	_add_row(box, "Selection green", green_row)
	_update_live_green_label()

	_add_heading(box, "CORRECTION SCOPE")
	_live_scope_option = OptionButton.new()
	_live_scope_option.add_item("WHOLE ANIMATION")
	_live_scope_option.set_item_metadata(0, TUNING_GLOBAL_KEY)
	_live_scope_option.add_item("CURRENT FRAME ONLY")
	_live_scope_option.set_item_metadata(1, TUNING_FRAMES_KEY)
	_live_scope_option.select(0)
	_live_scope_option.item_selected.connect(_on_live_scope_selected)
	_add_row(box, "Apply bone edit to", _live_scope_option)

	var frame_row := HBoxContainer.new()
	var prev_frame := Button.new()
	prev_frame.text = "◀ FRAME"
	prev_frame.focus_mode = Control.FOCUS_NONE
	prev_frame.pressed.connect(_on_live_prev_frame)
	frame_row.add_child(prev_frame)
	_live_play_button = Button.new()
	_live_play_button.text = "Ⅱ PAUSE"
	_live_play_button.focus_mode = Control.FOCUS_NONE
	_live_play_button.pressed.connect(_on_live_play_toggle)
	frame_row.add_child(_live_play_button)
	var next_frame := Button.new()
	next_frame.text = "FRAME ▶"
	next_frame.focus_mode = Control.FOCUS_NONE
	next_frame.pressed.connect(_on_live_next_frame)
	frame_row.add_child(next_frame)
	_add_row(box, "Preview control", frame_row)

	_live_frame_label = Label.new()
	_live_frame_label.text = "Current source frame: 0 · autoplay LOOP"
	_live_frame_label.modulate = Color(0.93, 0.82, 0.48)
	box.add_child(_live_frame_label)

	var reset_row := HBoxContainer.new()
	box.add_child(reset_row)
	var reset_selected := Button.new()
	reset_selected.text = "Reset selected correction"
	reset_selected.focus_mode = Control.FOCUS_NONE
	reset_selected.pressed.connect(_reset_live_selected_correction)
	reset_row.add_child(reset_selected)
	var reset_all := Button.new()
	reset_all.text = "Reset all tuning"
	reset_all.focus_mode = Control.FOCUS_NONE
	reset_all.pressed.connect(_reset_live_all_tuning)
	reset_row.add_child(reset_all)

	_add_heading(box, "SAVE TUNED COPY")
	_live_save_name = LineEdit.new()
	_live_save_name.placeholder_text = "e.g. idle_male_tuned"
	_add_row(box, "Custom name", _live_save_name)
	var save := Button.new()
	save.text = "SAVE TUNED COPY TO GLOBAL BANK"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_live_tuned_copy)
	box.add_child(save)

	var note := Label.new()
	note.text = "Green highlight is editor-only. Sprite Opacity and Show Bones remain available in the preview controls. Saved tuning is interpreted by the same tunable runtime used by the playable rigs."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	_live_tabs.tab_changed.connect(_on_live_tab_changed)


func _add_profile_item(option: OptionButton, profile_id: String) -> void:
	option.add_item(str(PROFILE_LABELS.get(profile_id, profile_id)))
	option.set_item_metadata(option.item_count - 1, profile_id)


func _find_live_tab_container(node: Node):
	var children := node.get_children()
	for child in children:
		if child is TabContainer:
			return child
		var nested = _find_live_tab_container(child)
		if nested != null:
			return nested
	return null


func _switch_profile(profile_id: String) -> void:
	var previous := _active_profile
	super._switch_profile(profile_id)
	if previous == _active_profile:
		return
	_sync_live_profile_option()
	_refresh_live_animation_list(true)
	_refresh_live_part_list()
	if _is_live_tuning_active():
		_start_live_preview()


func _update_profile_buttons() -> void:
	super._update_profile_buttons()
	_sync_live_profile_option()


func _sync_live_profile_option() -> void:
	if _live_profile_option == null:
		return
	_live_ui_sync = true
	for index in range(_live_profile_option.item_count):
		var profile_id := str(_live_profile_option.get_item_metadata(index))
		if profile_id == _active_profile:
			_live_profile_option.select(index)
			break
	_live_ui_sync = false


func _on_live_profile_selected(index: int) -> void:
	if _live_ui_sync or _live_profile_option == null:
		return
	if index < 0 or index >= _live_profile_option.item_count:
		return
	var profile_id := str(_live_profile_option.get_item_metadata(index))
	_switch_profile(profile_id)


func _on_live_filter_selected(_index: int) -> void:
	_refresh_live_animation_list(false)


func _refresh_live_animation_list(select_default: bool) -> void:
	if _live_animation_option == null:
		return
	var previous_key := _live_record_key(_live_source_record)
	var records := _build_global_animation_records()
	_live_animation_option.clear()
	var filter_index := 0
	if _live_filter_option != null:
		filter_index = _live_filter_option.selected
	for record_value in records:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		if not _live_record_matches_filter(record, filter_index):
			continue
		var profile_id := str(record.get("source_profile", PROFILE_JUNO))
		var source_kind := str(record.get("source", "builtin"))
		var tag := "SOURCE"
		if source_kind == "custom":
			tag = "CUSTOM"
		var profile_label := str(PROFILE_LABELS.get(profile_id, profile_id))
		var animation_name := str(record.get("name", ""))
		_live_animation_option.add_item("%s · %s · %s" % [profile_label, tag, animation_name])
		_live_animation_option.set_item_metadata(_live_animation_option.item_count - 1, record.duplicate(true))

	if _live_animation_option.item_count <= 0:
		_live_source_record = {}
		_live_source_data = {}
		_live_working_data = {}
		return

	var desired_index := -1
	if not select_default and not previous_key.is_empty():
		for index in range(_live_animation_option.item_count):
			var candidate_value = _live_animation_option.get_item_metadata(index)
			if candidate_value is Dictionary:
				var candidate: Dictionary = candidate_value
				if _live_record_key(candidate) == previous_key:
					desired_index = index
					break
	if desired_index < 0:
		desired_index = _find_live_default_index()
	if desired_index < 0:
		desired_index = 0
	_live_animation_option.select(desired_index)
	_on_live_animation_selected(desired_index)


func _build_global_animation_records() -> Array:
	var result: Array = []
	var profiles: Array = [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]
	for profile_value in profiles:
		var profile_id := str(profile_value)
		var records: Array = ProfileLibrary.get_animation_records(profile_id)
		for record_value in records:
			if not record_value is Dictionary:
				continue
			var record: Dictionary = (record_value as Dictionary).duplicate(true)
			record["source_profile"] = profile_id
			result.append(record)
	return result


func _live_record_matches_filter(record: Dictionary, filter_index: int) -> bool:
	var source_profile := str(record.get("source_profile", ""))
	var source_kind := str(record.get("source", "builtin"))
	if filter_index == 1:
		return source_profile == PROFILE_JUNO
	if filter_index == 2:
		return source_profile == PROFILE_DUMMY
	if filter_index == 3:
		return source_profile == PROFILE_MALE
	if filter_index == 4:
		return source_kind == "custom"
	return true


func _find_live_default_index() -> int:
	var juno_idle := -1
	for index in range(_live_animation_option.item_count):
		var value = _live_animation_option.get_item_metadata(index)
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		if str(record.get("name", "")) != "idle":
			continue
		var profile_id := str(record.get("source_profile", ""))
		if profile_id == _active_profile:
			return index
		if profile_id == PROFILE_JUNO:
			juno_idle = index
	return juno_idle


func _live_record_key(record: Dictionary) -> String:
	if record.is_empty():
		return ""
	return "%s|%s|%s" % [str(record.get("source_profile", "")), str(record.get("source", "")), str(record.get("name", ""))]


func _on_live_animation_selected(index: int) -> void:
	if _live_animation_option == null:
		return
	if index < 0 or index >= _live_animation_option.item_count:
		return
	var value = _live_animation_option.get_item_metadata(index)
	if value is Dictionary:
		_load_live_animation_record(value)


func _load_live_animation_record(record: Dictionary) -> void:
	var source_profile := str(record.get("source_profile", PROFILE_JUNO))
	var source_name := str(record.get("name", ""))
	var source_kind := str(record.get("source", "builtin"))
	var full_record: Dictionary = ProfileLibrary.get_animation_record(source_profile, source_name)
	var data_value = full_record.get("data", {})
	if not data_value is Dictionary:
		_set_status("Live Tuning could not load %s/%s." % [source_profile, source_name], true)
		return
	var source_data: Dictionary = data_value
	if source_data.is_empty():
		_set_status("Live Tuning could not load %s/%s." % [source_profile, source_name], true)
		return

	_live_source_record = record.duplicate(true)
	_live_source_data = source_data.duplicate(true)
	_live_working_data = _retarget_live_animation_data(_live_source_data, source_profile, _active_profile, source_name)
	if _live_working_data.is_empty():
		_set_status("Live Tuning could not map '%s' to %s." % [source_name, str(PROFILE_LABELS.get(_active_profile, _active_profile))], true)
		return

	var source_locked := source_kind != "custom" or source_profile != _active_profile
	if _live_save_name != null:
		if source_locked:
			var suffix := "juno"
			if _active_profile == PROFILE_DUMMY:
				suffix = "dummy"
			elif _active_profile == PROFILE_MALE:
				suffix = "male"
			_live_save_name.text = _sanitize_name("%s_%s_tuned" % [source_name, suffix])
		else:
			_live_save_name.text = source_name

	if _live_source_label != null:
		var kind_label := "ALABASTER"
		if source_kind == "custom":
			kind_label = "CUSTOM"
		var lock_label := "SAVE COPY"
		if not source_locked:
			lock_label = "EDITABLE CUSTOM"
		_live_source_label.text = "Source: %s / %s / %s → target %s · %s" % [str(PROFILE_LABELS.get(source_profile, source_profile)), kind_label, source_name, str(PROFILE_LABELS.get(_active_profile, _active_profile)), lock_label]

	_live_frame_editing = false
	_start_live_preview()


func _retarget_live_animation_data(source: Dictionary, source_profile: String, target_profile: String, source_name: String) -> Dictionary:
	if source_profile == target_profile:
		return source.duplicate(true)
	if rig == null or not rig.has_method("get_bone_names"):
		return {}

	var target_set: Dictionary = {}
	var names_value = rig.call("get_bone_names")
	if names_value is Array:
		var names: Array = names_value
		for node_name_value in names:
			target_set[str(node_name_value)] = true
	if target_set.is_empty():
		return {}

	var result: Dictionary = source.duplicate(true)
	var filtered_transforms: Array = []
	var transforms_value = source.get("transforms", [])
	if transforms_value is Array:
		var transforms: Array = transforms_value
		for key_value in transforms:
			if not key_value is Dictionary:
				continue
			var key: Dictionary = (key_value as Dictionary).duplicate(true)
			var filtered_xfm: Dictionary = {}
			var xfm_value = key.get("nodeXfm", {})
			if xfm_value is Dictionary:
				var xfm: Dictionary = xfm_value
				var xfm_names := xfm.keys()
				for node_name_value in xfm_names:
					var node_name := str(node_name_value)
					if target_set.has(node_name):
						filtered_xfm[node_name] = xfm[node_name_value]
			key["nodeXfm"] = filtered_xfm
			filtered_transforms.append(key)
	result["transforms"] = filtered_transforms

	var filtered_nodes: Dictionary = {}
	var nodes_value = source.get("nodes", {})
	if nodes_value is Dictionary:
		var nodes: Dictionary = nodes_value
		var node_names := nodes.keys()
		for node_name_value in node_names:
			var node_name := str(node_name_value)
			if target_set.has(node_name):
				filtered_nodes[node_name] = nodes[node_name_value]
	result["nodes"] = filtered_nodes
	result["live_retarget_meta"] = {
		"source_profile": source_profile,
		"target_profile": target_profile,
		"source_animation": source_name,
		"method": "common_bone_filter"
	}
	return result


func _start_live_preview() -> void:
	if rig == null or _live_working_data.is_empty():
		return
	var preview_data: Dictionary = _live_working_data.duplicate(true)
	preview_data["repeat"] = true
	if rig.has_method("install_runtime_animation"):
		rig.call("install_runtime_animation", LIVE_PREVIEW_NAME, preview_data)
	if rig.has_method("set_animation"):
		rig.call("set_animation", LIVE_PREVIEW_NAME)
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", _live_frame_editing)
	if rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", _live_selected_part)
	if rig.has_method("set_selection_green_intensity"):
		rig.call("set_selection_green_intensity", _live_green_intensity)
	_update_live_play_button()


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
	var names_value = rig.call("get_sprite_part_names")
	if not names_value is Array:
		return
	var names: Array = names_value
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
	if _live_part_list == null:
		return
	if index < 0 or index >= _live_part_list.item_count:
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


func _on_live_scope_selected(index: int) -> void:
	if _live_scope_option == null or index < 0:
		return
	var scope := str(_live_scope_option.get_item_metadata(index))
	_live_frame_editing = scope == TUNING_FRAMES_KEY
	if rig != null and rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", _live_frame_editing)
	_update_live_play_button()


func _live_scope() -> String:
	if _live_scope_option == null or _live_scope_option.selected < 0:
		return TUNING_GLOBAL_KEY
	return str(_live_scope_option.get_item_metadata(_live_scope_option.selected))


func _on_live_prev_frame() -> void:
	_step_live_frame(-1)


func _on_live_next_frame() -> void:
	_step_live_frame(1)


func _step_live_frame(direction: int) -> void:
	if rig == null or _live_working_data.is_empty():
		return
	_live_frame_editing = true
	if _live_scope_option != null:
		_live_scope_option.select(1)
	var frame_count := maxi(int(_live_working_data.get("frameCnt", 1)), 1)
	var frame := _live_current_frame() + direction
	if frame < 0:
		frame = frame_count - 1
	elif frame >= frame_count:
		frame = 0
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)
	if rig.has_method("seek_animation_frame"):
		rig.call("seek_animation_frame", float(frame))
	_update_live_play_button()


func _on_live_play_toggle() -> void:
	_live_frame_editing = not _live_frame_editing
	if rig != null and rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", _live_frame_editing)
	_update_live_play_button()


func _update_live_play_button() -> void:
	if _live_play_button == null:
		return
	if _live_frame_editing:
		_live_play_button.text = "▶ PLAY LOOP"
	else:
		_live_play_button.text = "Ⅱ PAUSE"


func _on_viewport_bone_transform_delta(bone_name: String, mode: String, delta_value: Vector3) -> void:
	if not _is_live_tuning_active():
		super._on_viewport_bone_transform_delta(bone_name, mode, delta_value)
		return
	if _live_working_data.is_empty() or bone_name.is_empty():
		return
	_live_selected_part = bone_name
	_select_live_part_by_name(bone_name)

	var tuning_value = _live_working_data.get(TUNING_KEY, {})
	var tuning: Dictionary = {}
	if tuning_value is Dictionary:
		tuning = (tuning_value as Dictionary).duplicate(true)

	var scope := _live_scope()
	var scope_label := "whole animation"
	if scope == TUNING_FRAMES_KEY:
		var frames_value = tuning.get(TUNING_FRAMES_KEY, {})
		var frames: Dictionary = {}
		if frames_value is Dictionary:
			frames = (frames_value as Dictionary).duplicate(true)
		var frame_key := str(_live_current_frame())
		var frame_value = frames.get(frame_key, {})
		var frame_map: Dictionary = {}
		if frame_value is Dictionary:
			frame_map = (frame_value as Dictionary).duplicate(true)
		_apply_live_delta(frame_map, bone_name, mode, delta_value)
		frames[frame_key] = frame_map
		tuning[TUNING_FRAMES_KEY] = frames
		scope_label = "frame %s" % frame_key
	else:
		var global_value = tuning.get(TUNING_GLOBAL_KEY, {})
		var global_map: Dictionary = {}
		if global_value is Dictionary:
			global_map = (global_value as Dictionary).duplicate(true)
		_apply_live_delta(global_map, bone_name, mode, delta_value)
		tuning[TUNING_GLOBAL_KEY] = global_map

	_live_working_data[TUNING_KEY] = tuning
	_start_live_preview()
	_set_status("Live Tuning: %s correction on %s · %s." % [mode, bone_name, scope_label])


func _apply_live_delta(scope_map: Dictionary, bone_name: String, mode: String, delta_value: Vector3) -> void:
	var correction: Dictionary = {}
	var current_value = scope_map.get(bone_name, {})
	if current_value is Dictionary:
		correction = (current_value as Dictionary).duplicate(true)

	var rot: Array = [0.0, 0.0, 0.0]
	var trans: Array = [0.0, 0.0, 0.0]
	var rot_value = correction.get("rot", rot)
	var trans_value = correction.get("trans", trans)
	if rot_value is Array:
		rot = (rot_value as Array).duplicate()
	if trans_value is Array:
		trans = (trans_value as Array).duplicate()
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
	var tuning_value = _live_working_data.get(TUNING_KEY, {})
	if not tuning_value is Dictionary:
		return
	var tuning: Dictionary = (tuning_value as Dictionary).duplicate(true)
	var scope := _live_scope()
	if scope == TUNING_GLOBAL_KEY:
		var global_value = tuning.get(TUNING_GLOBAL_KEY, {})
		if global_value is Dictionary:
			var global_map: Dictionary = (global_value as Dictionary).duplicate(true)
			global_map.erase(_live_selected_part)
			tuning[TUNING_GLOBAL_KEY] = global_map
	else:
		var frames_value = tuning.get(TUNING_FRAMES_KEY, {})
		if frames_value is Dictionary:
			var frames: Dictionary = (frames_value as Dictionary).duplicate(true)
			var frame_key := str(_live_current_frame())
			var frame_value = frames.get(frame_key, {})
			if frame_value is Dictionary:
				var frame_map: Dictionary = (frame_value as Dictionary).duplicate(true)
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
	_set_status("Live Tuning corrections cleared. Source animation remains untouched.")


func _save_live_tuned_copy() -> void:
	if _live_working_data.is_empty() or _live_source_record.is_empty():
		_set_status("Choose an animation in Live Tuning first.", true)
		return
	var animation_name := ""
	if _live_save_name != null:
		animation_name = _sanitize_name(_live_save_name.text)
	if animation_name.is_empty():
		_set_status("Choose a custom name for the tuned animation.", true)
		return
	if ProfileLibrary.is_read_only_animation(_active_profile, animation_name):
		_set_status("'%s' is a locked source name. Save the tuned version with a custom name." % animation_name, true)
		return

	var data: Dictionary = _live_working_data.duplicate(true)
	var meta := {
		"type": "live_tuning",
		"studio": "AlabasterBoneStudioLiveTuningV2",
		"target_profile": _active_profile,
		"source_profile": str(_live_source_record.get("source_profile", PROFILE_JUNO)),
		"copied_from": str(_live_source_record.get("name", "")),
		"copied_from_kind": str(_live_source_record.get("source", "builtin")),
		"non_destructive_tuning": true
	}
	if not ProfileLibrary.save_custom_animation(animation_name, data, meta):
		_set_status("Could not save tuned animation '%s'." % animation_name, true)
		return
	if rig != null and rig.has_method("install_runtime_animation"):
		rig.call("install_runtime_animation", animation_name, data)

	_live_source_record = {
		"name": animation_name,
		"source": "custom",
		"read_only": false,
		"target_profile": _active_profile,
		"source_profile": _active_profile
	}
	_live_source_data = data.duplicate(true)
	_live_working_data = data.duplicate(true)
	_refresh_existing_animation_list()
	_refresh_live_animation_list(false)
	_start_live_preview()
	_set_status("Saved tuned custom '%s' for %s. Original source was not modified." % [animation_name, str(PROFILE_LABELS.get(_active_profile, _active_profile))])


func _live_current_frame() -> int:
	if rig != null and rig.has_method("get_current_tuning_frame"):
		return int(rig.call("get_current_tuning_frame"))
	if rig != null and rig.has_method("get_current_source_frame"):
		return roundi(float(rig.call("get_current_source_frame")))
	return 0


func _on_live_tab_changed(index: int) -> void:
	if _live_tabs == null or _live_tab == null:
		return
	if index < 0 or index >= _live_tabs.get_child_count():
		return
	if _live_tabs.get_child(index) == _live_tab:
		_start_live_preview()
		_refresh_live_part_list()
	else:
		_stop_live_preview()


func _is_live_tuning_active() -> bool:
	if _live_tabs == null or _live_tab == null:
		return false
	var index := _live_tabs.current_tab
	if index < 0 or index >= _live_tabs.get_child_count():
		return false
	return _live_tabs.get_child(index) == _live_tab


func _process(delta: float) -> void:
	super._process(delta)
	if _is_live_tuning_active() and _live_frame_label != null:
		var state_label := "autoplay LOOP"
		if _live_frame_editing:
			state_label = "FRAME EDIT · paused"
		_live_frame_label.text = "Current source frame: %d · %s" % [_live_current_frame(), state_label]
