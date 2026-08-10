extends VBoxContainer

# LIVE TUNING is intentionally a composited child panel, never a superclass of
# Bone Studio. It edits non-destructive tuning data on the same runtime classes
# used by gameplay.

const Library = preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const JunoRigScript = preload("res://scripts/systems/bones/BonesSystem.gd")
const PlayableSkinRigScript = preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")

const PROFILE_JUNO = "juno"
const PROFILE_DUMMY = "male_dummy"
const PROFILE_MALE = "male_temp"
const PROFILE_ORDER = [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]
const PROFILE_LABEL = {
	PROFILE_JUNO: "JUNO",
	PROFILE_DUMMY: "DUMMY",
	PROFILE_MALE: "MALE",
}
const PREVIEW_ANIMATION = "__live_tuning_preview"
const TUNING_KEY = "oathwake_tuning"
const GLOBAL_KEY = "global"
const FRAMES_KEY = "frames"
const SCOPE_WHOLE = 0
const SCOPE_FRAME = 1

var host: Control = null
var target_profile: String = PROFILE_JUNO
var current_record: Dictionary = {}
var working_tuning: Dictionary = {}
var animation_records: Array = []
var selected_part: String = ""
var _suppress_ui: bool = false

var target_buttons: Dictionary = {}
var filter_option: OptionButton = null
var animation_option: OptionButton = null
var autoplay_check: CheckBox = null
var loop_check: CheckBox = null
var parts_list: ItemList = null
var green_slider: HSlider = null
var opacity_slider: HSlider = null
var scope_option: OptionButton = null
var frame_spin: SpinBox = null
var frame_label: Label = null
var save_name: LineEdit = null
var status_label: Label = null
var play_button: Button = null

var move_x: SpinBox = null
var move_y: SpinBox = null
var move_z: SpinBox = null
var rot_yaw: SpinBox = null
var rot_pitch: SpinBox = null
var rot_roll: SpinBox = null


func setup(owner: Control) -> void:
	host = owner
	name = "LIVE TUNING"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	if not _attach_to_host_tabs():
		return
	if not _replace_host_rig(PROFILE_JUNO):
		_set_status("Could not initialize shared Juno gameplay rig.", true)
		return
	_rebuild_animation_records()
	_update_target_buttons()
	_rebuild_parts_list()
	call_deferred("_select_default_idle")
	set_process(true)


func _attach_to_host_tabs() -> bool:
	if host == null:
		return false
	var tabs: TabContainer = _find_tab_container(host)
	if tabs == null:
		_set_status("Could not find Bone Studio TabContainer.", true)
		return false
	tabs.add_child(self)
	tabs.tab_changed.connect(_on_tab_changed)
	return true


func _find_tab_container(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child_value in node.get_children():
		var child: Node = child_value as Node
		if child == null:
			continue
		var found: TabContainer = _find_tab_container(child)
		if found != null:
			return found
	return null


func _build_ui() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_heading(box, "LIVE TUNING · NON-DESTRUCTIVE BONE CORRECTION")
	var intro: Label = Label.new()
	intro.text = "Source clips stay read-only. WHOLE ANIMATION adds one local bone correction over the complete clip. CURRENT FRAME ONLY applies the correction only to the selected source frame. Saving always creates/updates an Oathwake custom copy."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	_add_heading(box, "Target figure")
	var target_row: HBoxContainer = HBoxContainer.new()
	box.add_child(target_row)
	var group: ButtonGroup = ButtonGroup.new()
	group.allow_unpress = false
	for profile_value in PROFILE_ORDER:
		var profile_id: String = str(profile_value)
		var button: Button = Button.new()
		button.text = str(PROFILE_LABEL.get(profile_id, profile_id.to_upper()))
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(110.0, 34.0)
		button.pressed.connect(_on_target_pressed.bind(profile_id))
		target_row.add_child(button)
		target_buttons[profile_id] = button

	_add_heading(box, "Animation source")
	filter_option = OptionButton.new()
	for label_value in ["ALL", "JUNO", "DUMMY", "MALE", "CUSTOM"]:
		var label_text: String = str(label_value)
		filter_option.add_item(label_text)
		filter_option.set_item_metadata(filter_option.item_count - 1, label_text)
	filter_option.item_selected.connect(_on_filter_selected)
	_add_row(box, "Filter", filter_option)

	animation_option = OptionButton.new()
	animation_option.item_selected.connect(_on_animation_selected)
	_add_row(box, "Global bank", animation_option)

	var playback_row: HBoxContainer = HBoxContainer.new()
	box.add_child(playback_row)
	autoplay_check = CheckBox.new()
	autoplay_check.text = "Autoplay"
	autoplay_check.button_pressed = true
	autoplay_check.toggled.connect(_on_autoplay_toggled)
	playback_row.add_child(autoplay_check)
	loop_check = CheckBox.new()
	loop_check.text = "Repeat"
	loop_check.button_pressed = true
	loop_check.toggled.connect(_on_loop_toggled)
	playback_row.add_child(loop_check)
	play_button = Button.new()
	play_button.text = "Pause"
	play_button.focus_mode = Control.FOCUS_NONE
	play_button.pressed.connect(_toggle_playback)
	playback_row.add_child(play_button)

	_add_heading(box, "Visual part / bone")
	var part_split: HSplitContainer = HSplitContainer.new()
	part_split.custom_minimum_size = Vector2(0.0, 210.0)
	part_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(part_split)
	parts_list = ItemList.new()
	parts_list.custom_minimum_size = Vector2(220.0, 200.0)
	parts_list.item_selected.connect(_on_part_selected)
	part_split.add_child(parts_list)
	var visual_controls: VBoxContainer = VBoxContainer.new()
	part_split.add_child(visual_controls)
	green_slider = HSlider.new()
	green_slider.min_value = 0.0
	green_slider.max_value = 1.0
	green_slider.step = 0.05
	green_slider.value = 0.65
	green_slider.value_changed.connect(_on_green_changed)
	_add_row(visual_controls, "Selection green", green_slider)
	opacity_slider = HSlider.new()
	opacity_slider.min_value = 0.0
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.05
	opacity_slider.value = 0.45
	opacity_slider.value_changed.connect(_on_opacity_changed)
	_add_row(visual_controls, "Sprite opacity", opacity_slider)
	var visual_hint: Label = Label.new()
	visual_hint.text = "Selecting a sprite-part also selects its owning bone for tuning. Green and opacity are preview-only."
	visual_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visual_controls.add_child(visual_hint)

	_add_heading(box, "Edit scope")
	scope_option = OptionButton.new()
	scope_option.add_item("WHOLE ANIMATION")
	scope_option.set_item_metadata(0, SCOPE_WHOLE)
	scope_option.add_item("CURRENT FRAME ONLY")
	scope_option.set_item_metadata(1, SCOPE_FRAME)
	scope_option.item_selected.connect(_on_scope_selected)
	_add_row(box, "Bone adjustment", scope_option)

	var frame_row: HBoxContainer = HBoxContainer.new()
	box.add_child(frame_row)
	var prev_button: Button = Button.new()
	prev_button.text = "◀ Frame"
	prev_button.focus_mode = Control.FOCUS_NONE
	prev_button.pressed.connect(_step_frame.bind(-1))
	frame_row.add_child(prev_button)
	frame_spin = SpinBox.new()
	frame_spin.min_value = 0.0
	frame_spin.max_value = 9999.0
	frame_spin.step = 1.0
	frame_spin.custom_minimum_size = Vector2(110.0, 0.0)
	frame_spin.value_changed.connect(_on_frame_spin_changed)
	frame_row.add_child(frame_spin)
	var next_button: Button = Button.new()
	next_button.text = "Frame ▶"
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.pressed.connect(_step_frame.bind(1))
	frame_row.add_child(next_button)
	frame_label = Label.new()
	frame_label.text = "source frame 0"
	frame_row.add_child(frame_label)

	_add_heading(box, "Selected bone correction")
	move_x = _make_spin(0.0, -8.0, 8.0, 0.01)
	move_y = _make_spin(0.0, -8.0, 8.0, 0.01)
	move_z = _make_spin(0.0, -8.0, 8.0, 0.01)
	rot_yaw = _make_spin(0.0, -360.0, 360.0, 0.5)
	rot_pitch = _make_spin(0.0, -360.0, 360.0, 0.5)
	rot_roll = _make_spin(0.0, -360.0, 360.0, 0.5)
	_add_row(box, "Move X", move_x)
	_add_row(box, "Move Y", move_y)
	_add_row(box, "Move Z", move_z)
	_add_row(box, "Yaw", rot_yaw)
	_add_row(box, "Pitch", rot_pitch)
	_add_row(box, "Roll", rot_roll)
	move_x.value_changed.connect(_on_adjustment_changed)
	move_y.value_changed.connect(_on_adjustment_changed)
	move_z.value_changed.connect(_on_adjustment_changed)
	rot_yaw.value_changed.connect(_on_adjustment_changed)
	rot_pitch.value_changed.connect(_on_adjustment_changed)
	rot_roll.value_changed.connect(_on_adjustment_changed)
	var reset_button: Button = Button.new()
	reset_button.text = "RESET SELECTED BONE CORRECTION"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_reset_selected_correction)
	box.add_child(reset_button)

	_add_heading(box, "Save custom copy")
	save_name = LineEdit.new()
	save_name.placeholder_text = "e.g. male_idle_shoulders_v2"
	_add_row(box, "Animation name", save_name)
	var save_button: Button = Button.new()
	save_button.text = "SAVE CUSTOM TUNING"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(_save_custom_tuning)
	box.add_child(save_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var rig_object: Object = rig_value as Object
	if autoplay_check != null and autoplay_check.button_pressed and _scope_mode() == SCOPE_WHOLE:
		if rig_object.has_method("get_current_source_frame"):
			var frame: int = int(round(float(rig_object.call("get_current_source_frame"))))
			_suppress_ui = true
			frame_spin.value = frame
			_suppress_ui = false
			_update_frame_label(frame)


func _on_target_pressed(profile_id: String) -> void:
	if _suppress_ui or profile_id == target_profile:
		return
	target_profile = profile_id
	_update_target_buttons()
	if not _replace_host_rig(profile_id):
		_set_status("Could not initialize target figure %s." % str(PROFILE_LABEL.get(profile_id, profile_id)), true)
		return
	_rebuild_animation_records()
	_rebuild_parts_list()
	_select_default_idle()


func _replace_host_rig(profile_id: String) -> bool:
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

	var new_rig: Node2D = null
	if profile_id == PROFILE_JUNO:
		new_rig = JunoRigScript.new() as Node2D
		if new_rig == null:
			return false
		new_rig.name = "JunoBoneStudioSharedRig"
		preview_world.add_child(new_rig)
	else:
		var skin_rig: Node2D = PlayableSkinRigScript.new() as Node2D
		if skin_rig == null:
			return false
		skin_rig.call("configure_skin_profile", profile_id)
		new_rig = skin_rig
		new_rig.name = "%sBoneStudioSharedRig" % str(PROFILE_LABEL.get(profile_id, profile_id)).capitalize()
		preview_world.add_child(new_rig)
		if new_rig.has_method("initialize_skin"):
			if not bool(new_rig.call("initialize_skin")):
				new_rig.queue_free()
				return false

	host.set("rig", new_rig)
	new_rig.scale = Vector2.ONE * 3.2
	if new_rig.has_method("set_sprite_opacity"):
		new_rig.call("set_sprite_opacity", opacity_slider.value)
	if new_rig.has_method("set_selection_green_intensity"):
		new_rig.call("set_selection_green_intensity", green_slider.value)
	if new_rig.has_method("set_debug_enabled"):
		var bones_value: Variant = host.get("bone_visibility_check")
		var debug_enabled: bool = true
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


func _update_target_buttons() -> void:
	_suppress_ui = true
	for profile_value in target_buttons.keys():
		var button_value: Variant = target_buttons[profile_value]
		if button_value is Button:
			(button_value as Button).set_pressed_no_signal(str(profile_value) == target_profile)
	_suppress_ui = false


func _rebuild_animation_records() -> void:
	animation_records.clear()
	for source_profile_value in PROFILE_ORDER:
		var source_profile: String = str(source_profile_value)
		var records: Array = Library.get_animation_records(source_profile)
		for record_value in records:
			if not record_value is Dictionary:
				continue
			var record: Dictionary = (record_value as Dictionary).duplicate(true)
			record["source_profile"] = source_profile
			animation_records.append(record)
	_rebuild_animation_option()


func _rebuild_animation_option() -> void:
	if animation_option == null:
		return
	var previous_name: String = str(current_record.get("name", ""))
	var previous_profile: String = str(current_record.get("source_profile", ""))
	animation_option.clear()
	var filter_name: String = "ALL"
	if filter_option != null and filter_option.selected >= 0:
		filter_name = str(filter_option.get_item_metadata(filter_option.selected))
	var selected_index: int = -1
	for record_value in animation_records:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value as Dictionary
		var source_profile: String = str(record.get("source_profile", PROFILE_JUNO))
		var source_kind: String = str(record.get("source", "builtin"))
		if not _record_passes_filter(source_profile, source_kind, filter_name):
			continue
		var source_label: String = str(PROFILE_LABEL.get(source_profile, source_profile.to_upper()))
		var kind_label: String = "SOURCE"
		if source_kind == "custom":
			kind_label = "CUSTOM"
		var animation_name: String = str(record.get("name", ""))
		animation_option.add_item("%s · %s · %s" % [source_label, animation_name, kind_label])
		animation_option.set_item_metadata(animation_option.item_count - 1, record.duplicate(true))
		if animation_name == previous_name and source_profile == previous_profile:
			selected_index = animation_option.item_count - 1
	if selected_index >= 0:
		animation_option.select(selected_index)


func _record_passes_filter(source_profile: String, source_kind: String, filter_name: String) -> bool:
	if filter_name == "ALL":
		return true
	if filter_name == "CUSTOM":
		return source_kind == "custom"
	return str(PROFILE_LABEL.get(source_profile, "")) == filter_name


func _on_filter_selected(_index: int) -> void:
	_rebuild_animation_option()
	if animation_option.item_count > 0:
		animation_option.select(0)
		_on_animation_selected(0)


func _select_default_idle() -> void:
	if animation_option == null:
		return
	var best_index: int = -1
	for index in range(animation_option.item_count):
		var meta: Variant = animation_option.get_item_metadata(index)
		if not meta is Dictionary:
			continue
		var record: Dictionary = meta as Dictionary
		if str(record.get("name", "")) != "idle":
			continue
		if str(record.get("source_profile", "")) == target_profile:
			best_index = index
			break
		if best_index < 0 and str(record.get("source_profile", "")) == PROFILE_JUNO:
			best_index = index
	if best_index < 0 and animation_option.item_count > 0:
		best_index = 0
	if best_index >= 0:
		animation_option.select(best_index)
		_on_animation_selected(best_index)


func _on_animation_selected(index: int) -> void:
	if _suppress_ui or animation_option == null:
		return
	if index < 0 or index >= animation_option.item_count:
		return
	var meta: Variant = animation_option.get_item_metadata(index)
	if not meta is Dictionary:
		return
	current_record = (meta as Dictionary).duplicate(true)
	_load_selected_animation()


func _load_selected_animation() -> void:
	var source_profile: String = str(current_record.get("source_profile", PROFILE_JUNO))
	var animation_name: String = str(current_record.get("name", ""))
	var record: Dictionary = Library.get_animation_record(source_profile, animation_name)
	if record.is_empty():
		_set_status("Animation source not found: %s/%s" % [source_profile, animation_name], true)
		return
	var data_value: Variant = record.get("data", {})
	if not data_value is Dictionary:
		return
	var prepared: Dictionary = _prepare_animation_for_target(data_value as Dictionary, source_profile, target_profile)
	if prepared.is_empty():
		_set_status("Could not prepare %s for target %s." % [animation_name, target_profile], true)
		return
	var tuning_value: Variant = prepared.get(TUNING_KEY, {})
	working_tuning = {}
	if tuning_value is Dictionary:
		working_tuning = (tuning_value as Dictionary).duplicate(true)
	prepared["repeat"] = loop_check.button_pressed
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var rig_object: Object = rig_value as Object
	if not rig_object.has_method("install_runtime_animation"):
		return
	if not bool(rig_object.call("install_runtime_animation", PREVIEW_ANIMATION, prepared)):
		_set_status("Runtime rejected Live Tuning preview.", true)
		return
	rig_object.call("set_animation", PREVIEW_ANIMATION)
	_apply_working_tuning()
	_set_playback_state(autoplay_check.button_pressed and _scope_mode() == SCOPE_WHOLE)
	_rebuild_parts_list()
	_update_save_name()
	var frame_count: int = int(prepared.get("frameCnt", 1))
	_suppress_ui = true
	frame_spin.max_value = maxi(frame_count, 1)
	frame_spin.value = 0
	_suppress_ui = false
	_seek_frame(0)
	_sync_adjustment_controls()
	_set_status("Previewing %s/%s on %s. Source remains read-only." % [str(PROFILE_LABEL.get(source_profile, source_profile)), animation_name, str(PROFILE_LABEL.get(target_profile, target_profile))])


func _prepare_animation_for_target(source: Dictionary, source_profile: String, target: String) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result.erase("library_meta")
	if source_profile == target:
		return result
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return {}
	var rig_object: Object = rig_value as Object
	if not rig_object.has_method("get_bone_names"):
		return {}
	var names_value: Variant = rig_object.call("get_bone_names")
	if not names_value is Array:
		return {}
	var allowed: Dictionary = {}
	for name_value in names_value as Array:
		allowed[str(name_value)] = true

	var transforms_value: Variant = result.get("transforms", [])
	var filtered_transforms: Array = []
	if transforms_value is Array:
		for key_value in transforms_value as Array:
			if not key_value is Dictionary:
				continue
			var key: Dictionary = (key_value as Dictionary).duplicate(true)
			var node_xfm_value: Variant = key.get("nodeXfm", {})
			var filtered_xfm: Dictionary = {}
			if node_xfm_value is Dictionary:
				for bone_value in (node_xfm_value as Dictionary).keys():
					var bone_name: String = str(bone_value)
					if allowed.has(bone_name):
						filtered_xfm[bone_name] = (node_xfm_value as Dictionary)[bone_value]
			key["nodeXfm"] = filtered_xfm
			filtered_transforms.append(key)
	result["transforms"] = filtered_transforms

	var nodes_value: Variant = result.get("nodes", {})
	var filtered_nodes: Dictionary = {}
	if nodes_value is Dictionary:
		for bone_value in (nodes_value as Dictionary).keys():
			var bone_name: String = str(bone_value)
			if allowed.has(bone_name):
				filtered_nodes[bone_name] = (nodes_value as Dictionary)[bone_value]
	result["nodes"] = filtered_nodes
	result["live_retarget_meta"] = {
		"source_profile": source_profile,
		"target_profile": target,
		"method": "compatible_node_filter",
	}
	return result


func _rebuild_parts_list() -> void:
	if parts_list == null:
		return
	parts_list.clear()
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var rig_object: Object = rig_value as Object
	if not rig_object.has_method("get_sprite_part_names"):
		return
	var names_value: Variant = rig_object.call("get_sprite_part_names")
	if not names_value is Array:
		return
	for name_value in names_value as Array:
		var part_name: String = str(name_value)
		parts_list.add_item(part_name)
		parts_list.set_item_metadata(parts_list.item_count - 1, part_name)
	if not selected_part.is_empty():
		_select_part_in_list(selected_part)


func _on_part_selected(index: int) -> void:
	if index < 0 or index >= parts_list.item_count:
		return
	selected_part = str(parts_list.get_item_metadata(index))
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object: Object = rig_value as Object
		if rig_object.has_method("set_selected_sprite_part"):
			rig_object.call("set_selected_sprite_part", selected_part)
	_sync_adjustment_controls()


func _select_part_in_list(part_name: String) -> void:
	if parts_list == null:
		return
	for index in range(parts_list.item_count):
		if str(parts_list.get_item_metadata(index)) == part_name:
			parts_list.select(index)
			parts_list.ensure_current_is_visible()
			return


func _on_green_changed(value: float) -> void:
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object: Object = rig_value as Object
		if rig_object.has_method("set_selection_green_intensity"):
			rig_object.call("set_selection_green_intensity", value)


func _on_opacity_changed(value: float) -> void:
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object: Object = rig_value as Object
		if rig_object.has_method("set_sprite_opacity"):
			rig_object.call("set_sprite_opacity", value)


func _on_scope_selected(_index: int) -> void:
	if _scope_mode() == SCOPE_FRAME:
		var rig_value: Variant = _rig()
		if rig_value is Object:
			var rig_object: Object = rig_value as Object
			if rig_object.has_method("get_current_tuning_frame"):
				var frame: int = int(rig_object.call("get_current_tuning_frame"))
				_suppress_ui = true
				frame_spin.value = frame
				_suppress_ui = false
				_seek_frame(frame)
		_set_playback_state(false)
	else:
		_set_playback_state(autoplay_check.button_pressed)
	_sync_adjustment_controls()


func _scope_mode() -> int:
	if scope_option == null or scope_option.selected < 0:
		return SCOPE_WHOLE
	return int(scope_option.get_item_metadata(scope_option.selected))


func _on_frame_spin_changed(value: float) -> void:
	if _suppress_ui or _scope_mode() != SCOPE_FRAME:
		return
	_seek_frame(int(value))
	_sync_adjustment_controls()


func _step_frame(step: int) -> void:
	if _scope_mode() != SCOPE_FRAME:
		scope_option.select(1)
		_on_scope_selected(1)
	var next_frame: int = clampi(int(frame_spin.value) + step, int(frame_spin.min_value), int(frame_spin.max_value))
	frame_spin.value = next_frame
	_seek_frame(next_frame)
	_sync_adjustment_controls()


func _seek_frame(frame: int) -> void:
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object: Object = rig_value as Object
		if rig_object.has_method("seek_animation_frame"):
			rig_object.call("seek_animation_frame", float(frame))
	_update_frame_label(frame)


func _update_frame_label(frame: int) -> void:
	if frame_label != null:
		frame_label.text = "source frame %d" % frame


func _on_autoplay_toggled(enabled: bool) -> void:
	if _scope_mode() == SCOPE_FRAME and enabled:
		autoplay_check.set_pressed_no_signal(false)
		return
	_set_playback_state(enabled)


func _on_loop_toggled(_enabled: bool) -> void:
	if not current_record.is_empty():
		_load_selected_animation()


func _toggle_playback() -> void:
	if _scope_mode() == SCOPE_FRAME:
		return
	var next_state: bool = not autoplay_check.button_pressed
	autoplay_check.set_pressed_no_signal(next_state)
	_set_playback_state(next_state)


func _set_playback_state(playing: bool) -> void:
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object: Object = rig_value as Object
		if rig_object.has_method("set_editor_animation_paused"):
			rig_object.call("set_editor_animation_paused", not playing)
	if play_button != null:
		if playing:
			play_button.text = "Pause"
		else:
			play_button.text = "Play"


func _sync_adjustment_controls() -> void:
	_suppress_ui = true
	var correction: Dictionary = _selected_correction()
	var trans: Vector3 = _array3_to_vector3(correction.get("trans", [0.0, 0.0, 0.0]))
	var rot: Vector3 = _array3_to_vector3(correction.get("rot", [0.0, 0.0, 0.0]))
	move_x.value = trans.x
	move_y.value = trans.y
	move_z.value = trans.z
	rot_yaw.value = rot.x
	rot_pitch.value = rot.y
	rot_roll.value = rot.z
	_suppress_ui = false


func _selected_correction() -> Dictionary:
	if selected_part.is_empty():
		return {}
	if _scope_mode() == SCOPE_WHOLE:
		var global_value: Variant = working_tuning.get(GLOBAL_KEY, {})
		if global_value is Dictionary:
			var bone_value: Variant = (global_value as Dictionary).get(selected_part, {})
			if bone_value is Dictionary:
				return (bone_value as Dictionary).duplicate(true)
		return {}
	var frames_value: Variant = working_tuning.get(FRAMES_KEY, {})
	if not frames_value is Dictionary:
		return {}
	var frame_key: String = str(int(frame_spin.value))
	var frame_value: Variant = (frames_value as Dictionary).get(frame_key, {})
	if not frame_value is Dictionary:
		return {}
	var frame_bone_value: Variant = (frame_value as Dictionary).get(selected_part, {})
	if frame_bone_value is Dictionary:
		return (frame_bone_value as Dictionary).duplicate(true)
	return {}


func _on_adjustment_changed(_value: float) -> void:
	if _suppress_ui or selected_part.is_empty():
		return
	var correction: Dictionary = {
		"trans": [move_x.value, move_y.value, move_z.value],
		"rot": [rot_yaw.value, rot_pitch.value, rot_roll.value],
		"scale": 1.0,
	}
	_set_selected_correction(correction)
	_apply_working_tuning()


func _set_selected_correction(correction: Dictionary) -> void:
	if selected_part.is_empty():
		return
	if _scope_mode() == SCOPE_WHOLE:
		var global_value: Variant = working_tuning.get(GLOBAL_KEY, {})
		var global_map: Dictionary = {}
		if global_value is Dictionary:
			global_map = (global_value as Dictionary).duplicate(true)
		global_map[selected_part] = correction.duplicate(true)
		working_tuning[GLOBAL_KEY] = global_map
		return
	var frames_value: Variant = working_tuning.get(FRAMES_KEY, {})
	var frames_map: Dictionary = {}
	if frames_value is Dictionary:
		frames_map = (frames_value as Dictionary).duplicate(true)
	var frame_key: String = str(int(frame_spin.value))
	var frame_value: Variant = frames_map.get(frame_key, {})
	var frame_map: Dictionary = {}
	if frame_value is Dictionary:
		frame_map = (frame_value as Dictionary).duplicate(true)
	frame_map[selected_part] = correction.duplicate(true)
	frames_map[frame_key] = frame_map
	working_tuning[FRAMES_KEY] = frames_map


func _reset_selected_correction() -> void:
	if selected_part.is_empty():
		return
	if _scope_mode() == SCOPE_WHOLE:
		var global_value: Variant = working_tuning.get(GLOBAL_KEY, {})
		if global_value is Dictionary:
			var global_map: Dictionary = (global_value as Dictionary).duplicate(true)
			global_map.erase(selected_part)
			working_tuning[GLOBAL_KEY] = global_map
	else:
		var frames_value: Variant = working_tuning.get(FRAMES_KEY, {})
		if frames_value is Dictionary:
			var frames_map: Dictionary = (frames_value as Dictionary).duplicate(true)
			var frame_key: String = str(int(frame_spin.value))
			var frame_value: Variant = frames_map.get(frame_key, {})
			if frame_value is Dictionary:
				var frame_map: Dictionary = (frame_value as Dictionary).duplicate(true)
				frame_map.erase(selected_part)
				if frame_map.is_empty():
					frames_map.erase(frame_key)
				else:
					frames_map[frame_key] = frame_map
				working_tuning[FRAMES_KEY] = frames_map
	_apply_working_tuning()
	_sync_adjustment_controls()


func _apply_working_tuning() -> void:
	var rig_value: Variant = _rig()
	if not rig_value is Object:
		return
	var rig_object: Object = rig_value as Object
	if rig_object.has_method("set_animation_tuning"):
		rig_object.call("set_animation_tuning", PREVIEW_ANIMATION, working_tuning)


func _update_save_name() -> void:
	if save_name == null or current_record.is_empty():
		return
	var animation_name: String = str(current_record.get("name", "animation"))
	var source_profile: String = str(current_record.get("source_profile", PROFILE_JUNO))
	var source_kind: String = str(current_record.get("source", "builtin"))
	if source_kind == "custom" and source_profile == target_profile:
		save_name.text = animation_name
		return
	var target_suffix: String = "juno"
	if target_profile == PROFILE_DUMMY:
		target_suffix = "dummy"
	elif target_profile == PROFILE_MALE:
		target_suffix = "male"
	save_name.text = "%s_%s_tuned" % [animation_name, target_suffix]


func _save_custom_tuning() -> void:
	if current_record.is_empty():
		_set_status("Choose an animation first.", true)
		return
	var clean_name: String = _sanitize_name(save_name.text)
	if clean_name.is_empty():
		_set_status("Choose a valid custom animation name.", true)
		return
	var source_profile: String = str(current_record.get("source_profile", PROFILE_JUNO))
	var source_name: String = str(current_record.get("name", ""))
	var source_record: Dictionary = Library.get_animation_record(source_profile, source_name)
	var data_value: Variant = source_record.get("data", {})
	if not data_value is Dictionary:
		_set_status("Could not reload source animation.", true)
		return
	var save_data: Dictionary = _prepare_animation_for_target(data_value as Dictionary, source_profile, target_profile)
	if save_data.is_empty():
		return
	save_data[TUNING_KEY] = working_tuning.duplicate(true)
	save_data["repeat"] = loop_check.button_pressed
	var meta: Dictionary = {
		"type": "live_tuning",
		"target_profile": target_profile,
		"source_profile": source_profile,
		"source_animation": source_name,
		"source_kind": str(current_record.get("source", "builtin")),
		"non_destructive": true,
	}
	if not Library.save_custom_animation(clean_name, save_data, meta):
		_set_status("Save blocked. Original/retarget source clips are read-only; use a copy name.", true)
		return
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object: Object = rig_value as Object
		if rig_object.has_method("install_runtime_animation"):
			rig_object.call("install_runtime_animation", clean_name, save_data)
	_rebuild_animation_records()
	_set_status("Saved custom '%s' for %s. Original source was not modified." % [clean_name, str(PROFILE_LABEL.get(target_profile, target_profile))])


func _array3_to_vector3(value: Variant) -> Vector3:
	if value is Array:
		var array_value: Array = value as Array
		if array_value.size() >= 3:
			return Vector3(float(array_value[0]), float(array_value[1]), float(array_value[2]))
	return Vector3.ZERO


func _sanitize_name(value: String) -> String:
	var raw: String = value.strip_edges().replace(" ", "_").replace("-", "_")
	var clean: String = ""
	var allowed: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	for character_value in raw:
		var character: String = str(character_value)
		if allowed.contains(character):
			clean += character
	return clean


func _rig() -> Variant:
	if host == null:
		return null
	return host.get("rig")


func _on_tab_changed(_index: int) -> void:
	if not is_visible_in_tree():
		_set_playback_state(false)
		return
	if autoplay_check != null and autoplay_check.button_pressed and _scope_mode() == SCOPE_WHOLE:
		_set_playback_state(true)


func _make_spin(value: float, minimum: float, maximum: float, step_value: float) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = value
	return spin


func _add_heading(parent: Control, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func _add_row(parent: Control, label_text: String, control: Control) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(145.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _set_status(message: String, is_error: bool = false) -> void:
	if status_label != null:
		status_label.text = message
		if is_error:
			status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		else:
			status_label.add_theme_color_override("font_color", Color(0.65, 0.95, 0.72))
	print("ALABASTER_LIVE_TUNING: %s" % message)
