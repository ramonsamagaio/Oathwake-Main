extends "res://scripts/labs/alabaster/AlabasterBoneStudioProfiles.gd"
class_name AlabasterBoneStudioSharedProfiles

# Final Bone Studio layer for Juno / Dummy / Male.
# This file deliberately extends the last known-stable Profiles layer directly.
# Live Tuning lives here instead of adding another inheritance hop, which keeps
# Godot's parser/class cache out of the critical path.
#
# Source Alabaster animations are always read-only. Live tuning stores additive
# corrections inside Oathwake custom copies and the same tunable runtime applies
# those corrections in the editor and gameplay.

const TunableJunoRigScript = preload("res://scripts/labs/alabaster/AlabasterRigRuntimeTunable.gd")

const LIVE_PREVIEW_NAME = "__live_tuning_preview"
const TUNING_KEY = "oathwake_tuning"
const TUNING_GLOBAL_KEY = "global"
const TUNING_FRAMES_KEY = "frames"

var _live_tabs = null
var _live_tab = null
var _live_profile_option = null
var _live_filter_option = null
var _live_animation_option = null
var _live_part_list = null
var _live_green_slider = null
var _live_green_value = null
var _live_scope_option = null
var _live_frame_label = null
var _live_source_label = null
var _live_save_name = null
var _live_play_button = null
var _live_frame_timer = null

var _live_source_record = {}
var _live_source_data = {}
var _live_working_data = {}
var _live_selected_part = ""
var _live_green_intensity = 0.65
var _live_ui_sync = false
var _live_frame_editing = false


func _ready():
	super._ready()
	_build_live_tuning_tab()
	_replace_preview_rig()
	_refresh_existing_animation_list()
	_update_profile_buttons()
	_refresh_live_animation_list(true)
	_refresh_live_part_list()
	_start_live_frame_timer()


# -----------------------------------------------------------------------------
# SHARED PREVIEW RUNTIME
# -----------------------------------------------------------------------------

func _replace_preview_rig():
	if rig != null and is_instance_valid(rig):
		if rig.get_parent() != null:
			rig.get_parent().remove_child(rig)
		rig.queue_free()

	if _active_profile == PROFILE_JUNO:
		rig = TunableJunoRigScript.new()
		rig.name = "JunoBoneStudioTunableRig"
		preview_world.add_child(rig)
	else:
		var skin_rig = PlayableSkinRigScript.new()
		skin_rig.call("configure_skin_profile", _active_profile)
		rig = skin_rig
		rig.name = "%sBoneStudioRig" % str(PROFILE_LABELS.get(_active_profile, _active_profile)).capitalize()
		preview_world.add_child(rig)
		if rig.has_method("initialize_skin"):
			var initialized = bool(rig.call("initialize_skin"))
			if not initialized:
				_set_status("Could not initialize %s source figure." % str(PROFILE_LABELS.get(_active_profile, _active_profile)), true)
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
		if camera_lock_check != null:
			viewport_editor.set_camera_locked(camera_lock_check.button_pressed)
		else:
			viewport_editor.set_camera_locked(true)
		var transform_mode = "rotate"
		if transform_mode_option != null and transform_mode_option.selected >= 0:
			transform_mode = str(transform_mode_option.get_item_metadata(transform_mode_option.selected))
		viewport_editor.set_transform_mode(transform_mode)
	_sync_pro_timeline()
	_refresh_live_part_list()


func _switch_profile(profile_id):
	var previous_profile = _active_profile
	super._switch_profile(profile_id)
	if previous_profile == _active_profile:
		return
	_sync_live_profile_option()
	_refresh_live_animation_list(true)
	_refresh_live_part_list()
	if _is_live_tuning_active():
		_start_live_preview()


func _update_profile_buttons():
	super._update_profile_buttons()
	_sync_live_profile_option()


# -----------------------------------------------------------------------------
# EXISTING ANIMATION BROWSER
# -----------------------------------------------------------------------------

func _refresh_existing_animation_list():
	if _existing_option == null:
		return
	_existing_records.clear()
	_existing_option.clear()

	var profile_records = ProfileLibrary.get_animation_records(_active_profile)
	for record_value in profile_records:
		if record_value is Dictionary:
			_existing_records.append(record_value.duplicate(true))

	# Dummy/Male expose the exact Juno-retarget clips installed by the shared
	# playable rig. They remain read-only source material.
	if _active_profile != PROFILE_JUNO and rig != null:
		if rig.has_method("get_animation_catalog") and rig.has_method("get_animation_data"):
			var catalog_value = rig.call("get_animation_catalog")
			if catalog_value is Array:
				for entry_value in catalog_value:
					if not entry_value is Dictionary:
						continue
					var animation_name = str(entry_value.get("name", ""))
					if animation_name.is_empty() or animation_name.begins_with("native__"):
						continue
					var data_value = rig.call("get_animation_data", animation_name)
					if not data_value is Dictionary:
						continue
					var meta_value = data_value.get("retarget_meta", {})
					if not meta_value is Dictionary:
						continue
					if str(meta_value.get("source_profile", "")) != "juno":
						continue
					if bool(meta_value.get("compat_alias", false)):
						continue
					_existing_records.append({
						"name": animation_name,
						"source": "retarget",
						"read_only": true,
						"target_profile": _active_profile
					})

	_existing_records.sort_custom(_shared_animation_record_less)

	for record_value in _existing_records:
		if not record_value is Dictionary:
			continue
		var source_kind = str(record_value.get("source", "custom"))
		var tag = "CUSTOM · EDITABLE"
		if source_kind == "builtin":
			tag = "ALABASTER ORIGINAL · LOCKED"
		elif source_kind == "retarget":
			tag = "JUNO RETARGET · LOCKED"
		_existing_option.add_item("%s   [%s]" % [str(record_value.get("name", "")), tag])
		_existing_option.set_item_metadata(_existing_option.item_count - 1, record_value.duplicate(true))

	if _existing_option.item_count > 0:
		_existing_option.select(0)
		_on_existing_selected(0)
	else:
		_existing_source_label.text = "No animations available for %s." % str(PROFILE_LABELS.get(_active_profile, _active_profile))


func _shared_animation_record_less(a, b):
	var name_cmp = str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", "")))
	if name_cmp != 0:
		return name_cmp < 0
	var source_order = {"builtin": 0, "retarget": 1, "custom": 2}
	var a_order = int(source_order.get(str(a.get("source", "custom")), 9))
	var b_order = int(source_order.get(str(b.get("source", "custom")), 9))
	return a_order < b_order


# -----------------------------------------------------------------------------
# LIVE TUNING UI
# -----------------------------------------------------------------------------

func _build_live_tuning_tab():
	_live_tabs = _find_live_tab_container(self)
	if _live_tabs == null:
		push_warning("AlabasterBoneStudioSharedProfiles: main TabContainer not found for Live Tuning.")
		return

	var scroll = ScrollContainer.new()
	scroll.name = "Live_Tuning"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_live_tabs.add_child(scroll)
	_live_tab = scroll

	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_heading(box, "LIVE TUNING · NON-DESTRUCTIVE")
	var intro = Label.new()
	intro.text = "Choose JUNO, DUMMY or MALE, autoplay any animation from the global bank, select a visible sprite part and edit its bone directly in the preview. WHOLE ANIMATION changes that bone across the full clip. CURRENT FRAME ONLY changes only the displayed source frame. Alabaster/Juno source clips are never overwritten."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	_live_profile_option = OptionButton.new()
	_add_live_profile_item(PROFILE_JUNO)
	_add_live_profile_item(PROFILE_DUMMY)
	_add_live_profile_item(PROFILE_MALE)
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

	var green_row = HBoxContainer.new()
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

	var frame_row = HBoxContainer.new()
	var prev_frame = Button.new()
	prev_frame.text = "◀ FRAME"
	prev_frame.focus_mode = Control.FOCUS_NONE
	prev_frame.pressed.connect(_on_live_prev_frame)
	frame_row.add_child(prev_frame)

	_live_play_button = Button.new()
	_live_play_button.text = "Ⅱ PAUSE"
	_live_play_button.focus_mode = Control.FOCUS_NONE
	_live_play_button.pressed.connect(_on_live_play_toggle)
	frame_row.add_child(_live_play_button)

	var next_frame = Button.new()
	next_frame.text = "FRAME ▶"
	next_frame.focus_mode = Control.FOCUS_NONE
	next_frame.pressed.connect(_on_live_next_frame)
	frame_row.add_child(next_frame)
	_add_row(box, "Preview control", frame_row)

	_live_frame_label = Label.new()
	_live_frame_label.text = "Current source frame: 0 · autoplay LOOP"
	_live_frame_label.modulate = Color(0.93, 0.82, 0.48)
	box.add_child(_live_frame_label)

	var reset_row = HBoxContainer.new()
	box.add_child(reset_row)
	var reset_selected = Button.new()
	reset_selected.text = "Reset selected correction"
	reset_selected.focus_mode = Control.FOCUS_NONE
	reset_selected.pressed.connect(_reset_live_selected_correction)
	reset_row.add_child(reset_selected)
	var reset_all = Button.new()
	reset_all.text = "Reset all tuning"
	reset_all.focus_mode = Control.FOCUS_NONE
	reset_all.pressed.connect(_reset_live_all_tuning)
	reset_row.add_child(reset_all)

	_add_heading(box, "SAVE TUNED COPY")
	_live_save_name = LineEdit.new()
	_live_save_name.placeholder_text = "e.g. idle_male_tuned"
	_add_row(box, "Custom name", _live_save_name)
	var save_button = Button.new()
	save_button.text = "SAVE TUNED COPY TO GLOBAL BANK"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(_save_live_tuned_copy)
	box.add_child(save_button)

	var note = Label.new()
	note.text = "Green highlight is editor-only. Use Sprite Opacity and Show Bones in the preview controls for an X-ray view. Saved tuning is interpreted by the same tunable runtime used by gameplay."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	_live_tabs.tab_changed.connect(_on_live_tab_changed)


func _add_live_profile_item(profile_id):
	if _live_profile_option == null:
		return
	_live_profile_option.add_item(str(PROFILE_LABELS.get(profile_id, profile_id)))
	_live_profile_option.set_item_metadata(_live_profile_option.item_count - 1, profile_id)


func _find_live_tab_container(node):
	for child in node.get_children():
		if child is TabContainer:
			return child
		var nested = _find_live_tab_container(child)
		if nested != null:
			return nested
	return null


func _start_live_frame_timer():
	if _live_frame_timer != null:
		return
	_live_frame_timer = Timer.new()
	_live_frame_timer.wait_time = 0.08
	_live_frame_timer.one_shot = false
	_live_frame_timer.autostart = true
	_live_frame_timer.timeout.connect(_update_live_frame_label)
	add_child(_live_frame_timer)


func _update_live_frame_label():
	if not _is_live_tuning_active():
		return
	if _live_frame_label == null:
		return
	var state_label = "autoplay LOOP"
	if _live_frame_editing:
		state_label = "FRAME EDIT · paused"
	_live_frame_label.text = "Current source frame: %d · %s" % [_live_current_frame(), state_label]


# -----------------------------------------------------------------------------
# GLOBAL ANIMATION BANK
# -----------------------------------------------------------------------------

func _sync_live_profile_option():
	if _live_profile_option == null:
		return
	_live_ui_sync = true
	for index in range(_live_profile_option.item_count):
		if str(_live_profile_option.get_item_metadata(index)) == _active_profile:
			_live_profile_option.select(index)
			break
	_live_ui_sync = false


func _on_live_profile_selected(index):
	if _live_ui_sync or _live_profile_option == null:
		return
	if index < 0 or index >= _live_profile_option.item_count:
		return
	_switch_profile(str(_live_profile_option.get_item_metadata(index)))


func _on_live_filter_selected(_index):
	_refresh_live_animation_list(false)


func _build_global_animation_records():
	var result = []
	var profile_ids = [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]
	for profile_id in profile_ids:
		var records = ProfileLibrary.get_animation_records(profile_id)
		for record_value in records:
			if not record_value is Dictionary:
				continue
			var copy = record_value.duplicate(true)
			copy["source_profile"] = profile_id
			result.append(copy)
	return result


func _refresh_live_animation_list(select_default):
	if _live_animation_option == null:
		return
	var previous_key = _live_record_key(_live_source_record)
	var records = _build_global_animation_records()
	_live_animation_option.clear()
	var filter_index = 0
	if _live_filter_option != null:
		filter_index = _live_filter_option.selected

	for record_value in records:
		if not record_value is Dictionary:
			continue
		if not _live_record_matches_filter(record_value, filter_index):
			continue
		var profile_id = str(record_value.get("source_profile", PROFILE_JUNO))
		var source_kind = str(record_value.get("source", "builtin"))
		var source_tag = "SOURCE"
		if source_kind == "custom":
			source_tag = "CUSTOM"
		var label = "%s · %s · %s" % [str(PROFILE_LABELS.get(profile_id, profile_id)), source_tag, str(record_value.get("name", ""))]
		_live_animation_option.add_item(label)
		_live_animation_option.set_item_metadata(_live_animation_option.item_count - 1, record_value.duplicate(true))

	if _live_animation_option.item_count <= 0:
		_live_source_record = {}
		_live_source_data = {}
		_live_working_data = {}
		return

	var desired_index = -1
	if not select_default and not previous_key.is_empty():
		for index in range(_live_animation_option.item_count):
			var candidate = _live_animation_option.get_item_metadata(index)
			if candidate is Dictionary:
				if _live_record_key(candidate) == previous_key:
					desired_index = index
					break
	if desired_index < 0:
		desired_index = _find_live_default_index()
	if desired_index < 0:
		desired_index = 0
	_live_animation_option.select(desired_index)
	_on_live_animation_selected(desired_index)


func _live_record_matches_filter(record, filter_index):
	var source_profile = str(record.get("source_profile", ""))
	var source_kind = str(record.get("source", "builtin"))
	if filter_index == 1:
		return source_profile == PROFILE_JUNO
	if filter_index == 2:
		return source_profile == PROFILE_DUMMY
	if filter_index == 3:
		return source_profile == PROFILE_MALE
	if filter_index == 4:
		return source_kind == "custom"
	return true


func _find_live_default_index():
	var juno_idle_index = -1
	for index in range(_live_animation_option.item_count):
		var record = _live_animation_option.get_item_metadata(index)
		if not record is Dictionary:
			continue
		if str(record.get("name", "")) != "idle":
			continue
		var source_profile = str(record.get("source_profile", ""))
		if source_profile == _active_profile:
			return index
		if source_profile == PROFILE_JUNO:
			juno_idle_index = index
	return juno_idle_index


func _live_record_key(record):
	if not record is Dictionary:
		return ""
	if record.is_empty():
		return ""
	return "%s|%s|%s" % [str(record.get("source_profile", "")), str(record.get("source", "")), str(record.get("name", ""))]


func _on_live_animation_selected(index):
	if _live_animation_option == null:
		return
	if index < 0 or index >= _live_animation_option.item_count:
		return
	var record = _live_animation_option.get_item_metadata(index)
	if record is Dictionary:
		_load_live_animation_record(record)


func _load_live_animation_record(record):
	var source_profile = str(record.get("source_profile", PROFILE_JUNO))
	var source_name = str(record.get("name", ""))
	var source_kind = str(record.get("source", "builtin"))
	var full_record = ProfileLibrary.get_animation_record(source_profile, source_name)
	var data_value = full_record.get("data", {})
	if not data_value is Dictionary or data_value.is_empty():
		_set_status("Live Tuning could not load %s/%s." % [source_profile, source_name], true)
		return

	_live_source_record = record.duplicate(true)
	_live_source_data = data_value.duplicate(true)
	_live_working_data = _retarget_live_animation_data(_live_source_data, source_profile, _active_profile, source_name)
	if _live_working_data.is_empty():
		_set_status("Live Tuning could not map '%s' to %s." % [source_name, str(PROFILE_LABELS.get(_active_profile, _active_profile))], true)
		return

	var source_locked = source_kind != "custom" or source_profile != _active_profile
	if _live_save_name != null:
		if source_locked:
			var suffix = "juno"
			if _active_profile == PROFILE_DUMMY:
				suffix = "dummy"
			elif _active_profile == PROFILE_MALE:
				suffix = "male"
			_live_save_name.text = _sanitize_name("%s_%s_tuned" % [source_name, suffix])
		else:
			_live_save_name.text = source_name

	if _live_source_label != null:
		var source_label = "ALABASTER"
		if source_kind == "custom":
			source_label = "CUSTOM"
		var edit_label = "SAVE COPY"
		if not source_locked:
			edit_label = "EDITABLE CUSTOM"
		_live_source_label.text = "Source: %s / %s / %s → target %s · %s" % [str(PROFILE_LABELS.get(source_profile, source_profile)), source_label, source_name, str(PROFILE_LABELS.get(_active_profile, _active_profile)), edit_label]

	_live_frame_editing = false
	_start_live_preview()


func _retarget_live_animation_data(source, source_profile, target_profile, source_name):
	if source_profile == target_profile:
		return source.duplicate(true)
	if rig == null or not rig.has_method("get_bone_names"):
		return {}

	var target_set = {}
	var names_value = rig.call("get_bone_names")
	if names_value is Array:
		for node_name in names_value:
			target_set[str(node_name)] = true
	if target_set.is_empty():
		return {}

	var result = source.duplicate(true)
	var filtered_transforms = []
	var transforms_value = source.get("transforms", [])
	if transforms_value is Array:
		for key_value in transforms_value:
			if not key_value is Dictionary:
				continue
			var key_copy = key_value.duplicate(true)
			var filtered_xfm = {}
			var node_xfm = key_copy.get("nodeXfm", {})
			if node_xfm is Dictionary:
				for node_name in node_xfm.keys():
					var clean_name = str(node_name)
					if target_set.has(clean_name):
						filtered_xfm[clean_name] = node_xfm[node_name]
			key_copy["nodeXfm"] = filtered_xfm
			filtered_transforms.append(key_copy)
	result["transforms"] = filtered_transforms

	var filtered_nodes = {}
	var nodes_value = source.get("nodes", {})
	if nodes_value is Dictionary:
		for node_name in nodes_value.keys():
			var clean_name = str(node_name)
			if target_set.has(clean_name):
				filtered_nodes[clean_name] = nodes_value[node_name]
	result["nodes"] = filtered_nodes
	result["live_retarget_meta"] = {
		"source_profile": source_profile,
		"target_profile": target_profile,
		"source_animation": source_name,
		"method": "common_bone_filter"
	}
	return result


# -----------------------------------------------------------------------------
# LIVE PREVIEW + SPRITE SELECTION
# -----------------------------------------------------------------------------

func _start_live_preview():
	if rig == null or _live_working_data.is_empty():
		return
	var preview_data = _live_working_data.duplicate(true)
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


func _stop_live_preview():
	if rig == null:
		return
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)
	if rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", "")


func _refresh_live_part_list():
	if _live_part_list == null:
		return
	_live_part_list.clear()
	if rig == null or not rig.has_method("get_sprite_part_names"):
		return
	var names_value = rig.call("get_sprite_part_names")
	if not names_value is Array:
		return
	for node_name in names_value:
		var clean_name = str(node_name)
		_live_part_list.add_item(clean_name)
		_live_part_list.set_item_metadata(_live_part_list.item_count - 1, clean_name)
	if _live_part_list.item_count <= 0:
		return

	var select_index = 0
	for index in range(_live_part_list.item_count):
		var candidate = str(_live_part_list.get_item_metadata(index))
		if candidate == _live_selected_part:
			select_index = index
			break
		if candidate == "head":
			select_index = index
	_live_part_list.select(select_index)
	_on_live_part_selected(select_index)


func _on_live_part_selected(index):
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


func _on_live_green_changed(value):
	_live_green_intensity = clampf(float(value), 0.0, 1.0)
	_update_live_green_label()
	if rig != null and rig.has_method("set_selection_green_intensity"):
		rig.call("set_selection_green_intensity", _live_green_intensity)


func _update_live_green_label():
	if _live_green_value != null:
		_live_green_value.text = "%d%%" % roundi(_live_green_intensity * 100.0)


# -----------------------------------------------------------------------------
# WHOLE ANIMATION / CURRENT FRAME TUNING
# -----------------------------------------------------------------------------

func _on_live_scope_selected(index):
	if _live_scope_option == null or index < 0:
		return
	var scope = str(_live_scope_option.get_item_metadata(index))
	_live_frame_editing = scope == TUNING_FRAMES_KEY
	if rig != null and rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", _live_frame_editing)
	_update_live_play_button()


func _live_scope():
	if _live_scope_option == null or _live_scope_option.selected < 0:
		return TUNING_GLOBAL_KEY
	return str(_live_scope_option.get_item_metadata(_live_scope_option.selected))


func _on_live_prev_frame():
	_step_live_frame(-1)


func _on_live_next_frame():
	_step_live_frame(1)


func _step_live_frame(direction):
	if rig == null or _live_working_data.is_empty():
		return
	_live_frame_editing = true
	if _live_scope_option != null:
		_live_scope_option.select(1)
	var frame_count = maxi(int(_live_working_data.get("frameCnt", 1)), 1)
	var frame = _live_current_frame() + int(direction)
	if frame < 0:
		frame = frame_count - 1
	elif frame >= frame_count:
		frame = 0
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)
	if rig.has_method("seek_animation_frame"):
		rig.call("seek_animation_frame", float(frame))
	_update_live_play_button()


func _on_live_play_toggle():
	_live_frame_editing = not _live_frame_editing
	if rig != null and rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", _live_frame_editing)
	_update_live_play_button()


func _update_live_play_button():
	if _live_play_button == null:
		return
	if _live_frame_editing:
		_live_play_button.text = "▶ PLAY LOOP"
	else:
		_live_play_button.text = "Ⅱ PAUSE"


func _on_viewport_bone_transform_delta(bone_name, mode, delta_value):
	if not _is_live_tuning_active():
		super._on_viewport_bone_transform_delta(bone_name, mode, delta_value)
		return
	if _live_working_data.is_empty() or str(bone_name).is_empty():
		return
	_live_selected_part = str(bone_name)
	_select_live_part_by_name(_live_selected_part)

	var tuning = {}
	var tuning_value = _live_working_data.get(TUNING_KEY, {})
	if tuning_value is Dictionary:
		tuning = tuning_value.duplicate(true)

	var scope = _live_scope()
	var scope_label = "whole animation"
	if scope == TUNING_FRAMES_KEY:
		var frames = {}
		var frames_value = tuning.get(TUNING_FRAMES_KEY, {})
		if frames_value is Dictionary:
			frames = frames_value.duplicate(true)
		var frame_key = str(_live_current_frame())
		var frame_map = {}
		var frame_value = frames.get(frame_key, {})
		if frame_value is Dictionary:
			frame_map = frame_value.duplicate(true)
		_apply_live_delta(frame_map, _live_selected_part, str(mode), delta_value)
		frames[frame_key] = frame_map
		tuning[TUNING_FRAMES_KEY] = frames
		scope_label = "frame %s" % frame_key
	else:
		var global_map = {}
		var global_value = tuning.get(TUNING_GLOBAL_KEY, {})
		if global_value is Dictionary:
			global_map = global_value.duplicate(true)
		_apply_live_delta(global_map, _live_selected_part, str(mode), delta_value)
		tuning[TUNING_GLOBAL_KEY] = global_map

	_live_working_data[TUNING_KEY] = tuning
	_start_live_preview()
	_set_status("Live Tuning: %s correction on %s · %s." % [str(mode), _live_selected_part, scope_label])


func _apply_live_delta(scope_map, bone_name, mode, delta_value):
	var correction = {}
	var current_value = scope_map.get(bone_name, {})
	if current_value is Dictionary:
		correction = current_value.duplicate(true)

	var rot = [0.0, 0.0, 0.0]
	var trans = [0.0, 0.0, 0.0]
	var rot_value = correction.get("rot", rot)
	var trans_value = correction.get("trans", trans)
	if rot_value is Array:
		rot = rot_value.duplicate()
	if trans_value is Array:
		trans = trans_value.duplicate()
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


func _on_viewport_bone_selected(bone_name):
	super._on_viewport_bone_selected(bone_name)
	if not _is_live_tuning_active():
		return
	_live_selected_part = str(bone_name)
	_select_live_part_by_name(_live_selected_part)
	if rig != null and rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", _live_selected_part)


func _select_live_part_by_name(bone_name):
	if _live_part_list == null:
		return
	for index in range(_live_part_list.item_count):
		if str(_live_part_list.get_item_metadata(index)) == str(bone_name):
			_live_part_list.select(index)
			return


func _reset_live_selected_correction():
	if _live_working_data.is_empty() or _live_selected_part.is_empty():
		return
	var tuning_value = _live_working_data.get(TUNING_KEY, {})
	if not tuning_value is Dictionary:
		return
	var tuning = tuning_value.duplicate(true)
	var scope = _live_scope()
	if scope == TUNING_GLOBAL_KEY:
		var global_value = tuning.get(TUNING_GLOBAL_KEY, {})
		if global_value is Dictionary:
			var global_map = global_value.duplicate(true)
			global_map.erase(_live_selected_part)
			tuning[TUNING_GLOBAL_KEY] = global_map
	else:
		var frames_value = tuning.get(TUNING_FRAMES_KEY, {})
		if frames_value is Dictionary:
			var frames = frames_value.duplicate(true)
			var frame_key = str(_live_current_frame())
			var frame_value = frames.get(frame_key, {})
			if frame_value is Dictionary:
				var frame_map = frame_value.duplicate(true)
				frame_map.erase(_live_selected_part)
				if frame_map.is_empty():
					frames.erase(frame_key)
				else:
					frames[frame_key] = frame_map
			tuning[TUNING_FRAMES_KEY] = frames
	_live_working_data[TUNING_KEY] = tuning
	_start_live_preview()


func _reset_live_all_tuning():
	if _live_working_data.is_empty():
		return
	_live_working_data.erase(TUNING_KEY)
	_start_live_preview()
	_set_status("Live Tuning corrections cleared. Source animation remains untouched.")


# -----------------------------------------------------------------------------
# SAVE / FRAME STATE
# -----------------------------------------------------------------------------

func _save_live_tuned_copy():
	if _live_working_data.is_empty() or _live_source_record.is_empty():
		_set_status("Choose an animation in Live Tuning first.", true)
		return
	var animation_name = ""
	if _live_save_name != null:
		animation_name = _sanitize_name(_live_save_name.text)
	if animation_name.is_empty():
		_set_status("Choose a custom name for the tuned animation.", true)
		return
	if ProfileLibrary.is_read_only_animation(_active_profile, animation_name):
		_set_status("'%s' is a locked source name. Save the tuned version with a custom name." % animation_name, true)
		return

	var data = _live_working_data.duplicate(true)
	var meta = {
		"type": "live_tuning",
		"studio": "AlabasterBoneStudioSharedProfiles",
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


func _live_current_frame():
	if rig != null and rig.has_method("get_current_tuning_frame"):
		return int(rig.call("get_current_tuning_frame"))
	if rig != null and rig.has_method("get_current_source_frame"):
		return roundi(float(rig.call("get_current_source_frame")))
	return 0


func _on_live_tab_changed(index):
	if _live_tabs == null or _live_tab == null:
		return
	if index < 0 or index >= _live_tabs.get_child_count():
		return
	if _live_tabs.get_child(index) == _live_tab:
		_start_live_preview()
		_refresh_live_part_list()
	else:
		_stop_live_preview()


func _is_live_tuning_active():
	if _live_tabs == null or _live_tab == null:
		return false
	var current_index = _live_tabs.current_tab
	if current_index < 0 or current_index >= _live_tabs.get_child_count():
		return false
	return _live_tabs.get_child(current_index) == _live_tab
