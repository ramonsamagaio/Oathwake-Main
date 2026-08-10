extends VBoxContainer

# Composited Live Tuning UI. This is deliberately NOT part of the Bone Studio
# inheritance chain: a bug here cannot make the editor's base class hierarchy
# unresolvable. It talks to the same BonesSystem/PlayableSkinRig classes used by
# gameplay, and stores non-destructive tuning in the animation data.

const Library := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const JunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")
const PlayableSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")

const PROFILE_JUNO := "juno"
const PROFILE_DUMMY := "male_dummy"
const PROFILE_MALE := "male_temp"
const PROFILE_ORDER := [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]
const PROFILE_LABEL := {
	PROFILE_JUNO: "JUNO",
	PROFILE_DUMMY: "DUMMY",
	PROFILE_MALE: "MALE",
}
const PREVIEW_ANIMATION := "__live_tuning_preview"
const TUNING_KEY := "oathwake_tuning"
const GLOBAL_KEY := "global"
const FRAMES_KEY := "frames"
const SCOPE_WHOLE := 0
const SCOPE_FRAME := 1

var host: Control
var target_profile := PROFILE_JUNO
var current_record: Dictionary = {}
var working_tuning: Dictionary = {}
var animation_records: Array = []
var selected_part := ""
var _suppress_ui := false

var target_buttons: Dictionary = {}
var filter_option: OptionButton
var animation_option: OptionButton
var autoplay_check: CheckBox
var loop_check: CheckBox
var parts_list: ItemList
var green_slider: HSlider
var opacity_slider: HSlider
var scope_option: OptionButton
var frame_spin: SpinBox
var frame_label: Label
var save_name: LineEdit
var status_label: Label
var play_button: Button


func setup(owner: Control) -> void:
	host = owner
	name = "LIVE_TUNING"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_attach_to_host_tabs()
	_rebuild_animation_records()
	_update_target_buttons()
	call_deferred("_select_default_idle")
	set_process(true)


func _attach_to_host_tabs() -> void:
	if host == null:
		return
	var tabs := _find_tab_container(host)
	if tabs == null:
		_set_status("Could not find Bone Studio TabContainer.", true)
		return
	tabs.add_child(self)
	tabs.tab_changed.connect(_on_tab_changed)


func _find_tab_container(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child in node.get_children():
		var found := _find_tab_container(child)
		if found != null:
			return found
	return null


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_add_heading(box, "LIVE TUNING · NON-DESTRUCTIVE BONE CORRECTION")
	var intro := Label.new()
	intro.text = "Original Alabaster clips are read-only. Whole Animation applies an additive bone offset to the complete clip; Current Frame applies it only to the displayed source frame. Save creates/updates an Oathwake custom copy."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	_add_heading(box, "Target figure")
	var target_row := HBoxContainer.new()
	box.add_child(target_row)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for profile_value in PROFILE_ORDER:
		var profile_id := str(profile_value)
		var button := Button.new()
		button.text = str(PROFILE_LABEL[profile_id])
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(110, 34)
		button.pressed.connect(_on_target_pressed.bind(profile_id))
		target_row.add_child(button)
		target_buttons[profile_id] = button

	_add_heading(box, "Animation source")
	filter_option = OptionButton.new()
	for label in ["ALL", "JUNO", "DUMMY", "MALE", "CUSTOM"]:
		filter_option.add_item(label)
		filter_option.set_item_metadata(filter_option.item_count - 1, label)
	filter_option.item_selected.connect(_on_filter_selected)
	_add_row(box, "Filter", filter_option)

	animation_option = OptionButton.new()
	animation_option.item_selected.connect(_on_animation_selected)
	_add_row(box, "Global bank", animation_option)

	var playback_row := HBoxContainer.new()
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

	_add_heading(box, "Visual part selection")
	var part_split := HSplitContainer.new()
	part_split.custom_minimum_size = Vector2(0, 210)
	part_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(part_split)
	parts_list = ItemList.new()
	parts_list.custom_minimum_size = Vector2(220, 200)
	parts_list.item_selected.connect(_on_part_selected)
	part_split.add_child(parts_list)
	var visual_controls := VBoxContainer.new()
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
	var visual_hint := Label.new()
	visual_hint.text = "Click a sprite-part name to select its owning bone. The green tint is editor-only and is never saved."
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

	var frame_row := HBoxContainer.new()
	box.add_child(frame_row)
	var prev_button := Button.new()
	prev_button.text = "◀ Frame"
	prev_button.focus_mode = Control.FOCUS_NONE
	prev_button.pressed.connect(_step_frame.bind(-1))
	frame_row.add_child(prev_button)
	frame_spin = SpinBox.new()
	frame_spin.min_value = 0
	frame_spin.max_value = 9999
	frame_spin.step = 1
	frame_spin.value_changed.connect(_on_frame_spin_changed)
	frame_spin.custom_minimum_size = Vector2(110, 0)
	frame_row.add_child(frame_spin)
	var next_button := Button.new()
	next_button.text = "Frame ▶"
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.pressed.connect(_step_frame.bind(1))
	frame_row.add_child(next_button)
	frame_label = Label.new()
	frame_label.text = "source frame 0"
	frame_row.add_child(frame_label)

	_add_heading(box, "Save custom copy")
	save_name = LineEdit.new()
	save_name.placeholder_text = "e.g. male_idle_shoulders_v2"
	_add_row(box, "Animation name", save_name)
	var save_button := Button.new()
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
	var rig := _rig()
	if rig == null:
		return
	if autoplay_check != null and autoplay_check.button_pressed and _scope_mode() == SCOPE_WHOLE:
		if rig.has_method("get_current_source_frame"):
			var frame := int(round(float(rig.call("get_current_source_frame"))))
			_suppress_ui = true
			frame_spin.value = frame
			_suppress_ui = false
			_update_frame_label(frame)


func is_live_active() -> bool:
	return is_inside_tree() and is_visible_in_tree()


func apply_bone_delta(bone_name: String, mode: String, delta_value: Vector3) -> void:
	if not is_live_active() or bone_name.is_empty():
		return
	selected_part = bone_name
	_select_part_in_list(bone_name)
	var scope_key := GLOBAL_KEY
	var scope_map: Dictionary
	if _scope_mode() == SCOPE_FRAME:
		scope_key = FRAMES_KEY
		var frames_value: Variant = working_tuning.get(FRAMES_KEY, {})
		var frames := (frames_value as Dictionary).duplicate(true) if frames_value is Dictionary else {}
		var frame_key := str(int(frame_spin.value))
		var frame_scope_value: Variant = frames.get(frame_key, {})
		scope_map = (frame_scope_value as Dictionary).duplicate(true) if frame_scope_value is Dictionary else {}
		_apply_delta_to_scope(scope_map, bone_name, mode, delta_value)
		frames[frame_key] = scope_map
		working_tuning[FRAMES_KEY] = frames
	else:
		var global_value: Variant = working_tuning.get(GLOBAL_KEY, {})
		scope_map = (global_value as Dictionary).duplicate(true) if global_value is Dictionary else {}
		_apply_delta_to_scope(scope_map, bone_name, mode, delta_value)
		working_tuning[GLOBAL_KEY] = scope_map
	_apply_working_tuning()
	_set_status("%s adjusted in %s." % [bone_name, "frame %d" % int(frame_spin.value) if scope_key == FRAMES_KEY else "whole animation"])


func select_part_from_bone(bone_name: String) -> void:
	if not is_live_active():
		return
	selected_part = bone_name
	_select_part_in_list(bone_name)
	var rig := _rig()
	if rig != null and rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", bone_name)


func _apply_delta_to_scope(scope: Dictionary, bone_name: String, mode: String, delta_value: Vector3) -> void:
	var bone_value: Variant = scope.get(bone_name, {})
	var bone := (bone_value as Dictionary).duplicate(true) if bone_value is Dictionary else {}
	var rot := _array3_to_vector3(bone.get("rot", [0.0, 0.0, 0.0]))
	var trans := _array3_to_vector3(bone.get("trans", [0.0, 0.0, 0.0]))
	if mode == "move":
		trans += delta_value
	else:
		rot += delta_value
	bone["rot"] = [rot.x, rot.y, rot.z]
	bone["trans"] = [trans.x, trans.y, trans.z]
	bone["scale"] = float(bone.get("scale", 1.0))
	scope[bone_name] = bone


func _array3_to_vector3(value: Variant) -> Vector3:
	if value is Array:
		var array := value as Array
		if array.size() >= 3:
			return Vector3(float(array[0]), float(array[1]), float(array[2]))
	return Vector3.ZERO


func _on_target_pressed(profile_id: String) -> void:
	if _suppress_ui or profile_id == target_profile:
		return
	target_profile = profile_id
	_update_target_buttons()
	if not _replace_host_rig(profile_id):
		_set_status("Could not initialize target figure %s." % str(PROFILE_LABEL[profile_id]), true)
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
	var preview_world := preview_world_value as Node2D
	var old_rig_value: Variant = host.get("rig")
	if old_rig_value is Node and is_instance_valid(old_rig_value as Node):
		var old_rig := old_rig_value as Node
		if old_rig.get_parent() != null:
			old_rig.get_parent().remove_child(old_rig)
		old_rig.queue_free()

	var new_rig
	if profile_id == PROFILE_JUNO:
		new_rig = JunoRigScript.new()
		new_rig.name = "JunoBoneStudioSharedRig"
		preview_world.add_child(new_rig)
	else:
		var skin_rig = PlayableSkinRigScript.new()
		skin_rig.call("configure_skin_profile", profile_id)
		new_rig = skin_rig
		new_rig.name = "%sBoneStudioSharedRig" % str(PROFILE_LABEL[profile_id]).capitalize()
		preview_world.add_child(new_rig)
		if new_rig.has_method("initialize_skin") and not bool(new_rig.call("initialize_skin")):
			new_rig.queue_free()
			return false

	host.set("rig", new_rig)
	var preview_zoom := float(host.get("preview_zoom")) if host.get("preview_zoom") != null else 1.0
	new_rig.scale = Vector2.ONE * 3.2 * preview_zoom
	if new_rig.has_method("set_sprite_opacity"):
		new_rig.call("set_sprite_opacity", opacity_slider.value)
	if new_rig.has_method("set_selection_green_intensity"):
		new_rig.call("set_selection_green_intensity", green_slider.value)
	if new_rig.has_method("set_debug_enabled"):
		new_rig.call("set_debug_enabled", false)
	if new_rig.has_method("set_editor_camera_enabled"):
		new_rig.call("set_editor_camera_enabled", true)
	if new_rig.has_method("set_editor_camera_pitch_degrees"):
		new_rig.call("set_editor_camera_pitch_degrees", float(host.get("preview_pitch_degrees")))
	if new_rig.has_method("set_facing_from_vector"):
		new_rig.call("set_facing_from_vector", Vector2.DOWN)
	if new_rig.has_method("set_editor_animation_paused"):
		new_rig.call("set_editor_animation_paused", false)

	var viewport_editor_value: Variant = host.get("viewport_editor")
	if viewport_editor_value != null:
		var center: Variant = host.call("_preview_center")
		viewport_editor_value.call("configure", new_rig, center)
		var camera_lock_value: Variant = host.get("camera_lock_check")
		if camera_lock_value is CheckBox:
			viewport_editor_value.call("set_camera_locked", (camera_lock_value as CheckBox).button_pressed)
		var transform_value: Variant = host.get("transform_mode_option")
		if transform_value is OptionButton:
			var option := transform_value as OptionButton
			if option.selected >= 0:
				viewport_editor_value.call("set_transform_mode", str(option.get_item_metadata(option.selected)))

	host.call_deferred("_populate_manual_bones")
	host.call_deferred("_sync_pro_timeline")
	host.call_deferred("_rebuild_mapping_table")
	return true


func _update_target_buttons() -> void:
	_suppress_ui = true
	for profile_value in target_buttons.keys():
		var button := target_buttons[profile_value] as Button
		if button != null:
			button.set_pressed_no_signal(str(profile_value) == target_profile)
	_suppress_ui = false


func _rebuild_animation_records() -> void:
	animation_records.clear()
	for source_profile_value in PROFILE_ORDER:
		var source_profile := str(source_profile_value)
		var records := Library.get_animation_records(source_profile)
		for record_value in records:
			if not record_value is Dictionary:
				continue
			var record := (record_value as Dictionary).duplicate(true)
			record["source_profile"] = source_profile
			animation_records.append(record)
	_rebuild_animation_option()


func _rebuild_animation_option() -> void:
	if animation_option == null:
		return
	var previous_name := str(current_record.get("name", ""))
	var previous_profile := str(current_record.get("source_profile", ""))
	animation_option.clear()
	var filter_name := "ALL"
	if filter_option != null and filter_option.selected >= 0:
		filter_name = str(filter_option.get_item_metadata(filter_option.selected))
	var selected_index := -1
	for record_value in animation_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var source_profile := str(record.get("source_profile", PROFILE_JUNO))
		var source_kind := str(record.get("source", "builtin"))
		if not _record_passes_filter(source_profile, source_kind, filter_name):
			continue
		var source_label := str(PROFILE_LABEL.get(source_profile, source_profile.to_upper()))
		var kind_label := "CUSTOM" if source_kind == "custom" else "SOURCE"
		var animation_name := str(record.get("name", ""))
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
	var best_index := -1
	for index in range(animation_option.item_count):
		var meta: Variant = animation_option.get_item_metadata(index)
		if not meta is Dictionary:
			continue
		var record := meta as Dictionary
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
	if _suppress_ui or animation_option == null or index < 0 or index >= animation_option.item_count:
		return
	var meta: Variant = animation_option.get_item_metadata(index)
	if not meta is Dictionary:
		return
	current_record = (meta as Dictionary).duplicate(true)
	_load_selected_animation()


func _load_selected_animation() -> void:
	var source_profile := str(current_record.get("source_profile", PROFILE_JUNO))
	var animation_name := str(current_record.get("name", ""))
	var record := Library.get_animation_record(source_profile, animation_name)
	if record.is_empty():
		_set_status("Animation source not found: %s/%s" % [source_profile, animation_name], true)
		return
	var data_value: Variant = record.get("data", {})
	if not data_value is Dictionary:
		return
	var prepared := _prepare_animation_for_target(data_value as Dictionary, source_profile, target_profile)
	if prepared.is_empty():
		_set_status("Could not prepare %s for target %s." % [animation_name, target_profile], true)
		return
	var tuning_value: Variant = prepared.get(TUNING_KEY, {})
	working_tuning = (tuning_value as Dictionary).duplicate(true) if tuning_value is Dictionary else {}
	prepared["repeat"] = loop_check.button_pressed
	var rig := _rig()
	if rig == null or not rig.has_method("install_runtime_animation"):
		return
	if not bool(rig.call("install_runtime_animation", PREVIEW_ANIMATION, prepared)):
		_set_status("Runtime rejected Live Tuning preview.", true)
		return
	rig.call("set_animation", PREVIEW_ANIMATION)
	_apply_working_tuning()
	_set_playback_state(autoplay_check.button_pressed and _scope_mode() == SCOPE_WHOLE)
	_rebuild_parts_list()
	_update_save_name()
	var frame_count := int(prepared.get("frameCnt", 1))
	_suppress_ui = true
	frame_spin.max_value = maxi(frame_count, 1)
	frame_spin.value = 0
	_suppress_ui = false
	_seek_frame(0)
	_set_status("Previewing %s/%s on %s. Source remains read-only." % [str(PROFILE_LABEL.get(source_profile, source_profile)), animation_name, str(PROFILE_LABEL.get(target_profile, target_profile))])


func _prepare_animation_for_target(source: Dictionary, source_profile: String, target: String) -> Dictionary:
	var result := source.duplicate(true)
	result.erase("library_meta")
	if source_profile == target:
		return result
	var rig := _rig()
	if rig == null or not rig.has_method("get_bone_names"):
		return {}
	var names_value: Variant = rig.call("get_bone_names")
	if not names_value is Array:
		return {}
	var allowed := {}
	for name_value in names_value as Array:
		allowed[str(name_value)] = true

	var transforms_value: Variant = result.get("transforms", [])
	var filtered_transforms: Array = []
	if transforms_value is Array:
		for key_value in transforms_value as Array:
			if not key_value is Dictionary:
				continue
			var key := (key_value as Dictionary).duplicate(true)
			var node_xfm_value: Variant = key.get("nodeXfm", {})
			var filtered_xfm := {}
			if node_xfm_value is Dictionary:
				for bone_value in (node_xfm_value as Dictionary).keys():
					var bone_name := str(bone_value)
					if allowed.has(bone_name):
						filtered_xfm[bone_name] = (node_xfm_value as Dictionary)[bone_value]
			key["nodeXfm"] = filtered_xfm
			filtered_transforms.append(key)
	result["transforms"] = filtered_transforms

	var nodes_value: Variant = result.get("nodes", {})
	var filtered_nodes := {}
	if nodes_value is Dictionary:
		for bone_value in (nodes_value as Dictionary).keys():
			var bone_name := str(bone_value)
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
	parts_list.clear()
	var rig := _rig()
	if rig == null or not rig.has_method("get_sprite_part_names"):
		return
	var names_value: Variant = rig.call("get_sprite_part_names")
	if not names_value is Array:
		return
	for name_value in names_value as Array:
		var part_name := str(name_value)
		parts_list.add_item(part_name)
		parts_list.set_item_metadata(parts_list.item_count - 1, part_name)
	if not selected_part.is_empty():
		_select_part_in_list(selected_part)


func _on_part_selected(index: int) -> void:
	if index < 0 or index >= parts_list.item_count:
		return
	selected_part = str(parts_list.get_item_metadata(index))
	var rig := _rig()
	if rig != null and rig.has_method("set_selected_sprite_part"):
		rig.call("set_selected_sprite_part", selected_part)
	if host != null:
		host.call("_live_tuning_select_bone", selected_part)


func _select_part_in_list(part_name: String) -> void:
	if parts_list == null:
		return
	for index in range(parts_list.item_count):
		if str(parts_list.get_item_metadata(index)) == part_name:
			parts_list.select(index)
			parts_list.ensure_current_is_visible()
			return


func _on_green_changed(value: float) -> void:
	var rig := _rig()
	if rig != null and rig.has_method("set_selection_green_intensity"):
		rig.call("set_selection_green_intensity", value)


func _on_opacity_changed(value: float) -> void:
	var rig := _rig()
	if rig != null and rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", value)


func _on_scope_selected(_index: int) -> void:
	if _scope_mode() == SCOPE_FRAME:
		var rig := _rig()
		if rig != null and rig.has_method("get_current_tuning_frame"):
			var frame := int(rig.call("get_current_tuning_frame"))
			_suppress_ui = true
			frame_spin.value = frame
			_suppress_ui = false
			_seek_frame(frame)
		_set_playback_state(false)
	else:
		_set_playback_state(autoplay_check.button_pressed)


func _scope_mode() -> int:
	if scope_option == null or scope_option.selected < 0:
		return SCOPE_WHOLE
	return int(scope_option.get_item_metadata(scope_option.selected))


func _on_frame_spin_changed(value: float) -> void:
	if _suppress_ui or _scope_mode() != SCOPE_FRAME:
		return
	_seek_frame(int(value))


func _step_frame(step: int) -> void:
	if _scope_mode() != SCOPE_FRAME:
		scope_option.select(1)
		_on_scope_selected(1)
	var next_frame := clampi(int(frame_spin.value) + step, int(frame_spin.min_value), int(frame_spin.max_value))
	frame_spin.value = next_frame
	_seek_frame(next_frame)


func _seek_frame(frame: int) -> void:
	var rig := _rig()
	if rig != null and rig.has_method("seek_animation_frame"):
		rig.call("seek_animation_frame", float(frame))
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
	var next := not autoplay_check.button_pressed
	autoplay_check.set_pressed_no_signal(next)
	_set_playback_state(next)


func _set_playback_state(playing: bool) -> void:
	var rig := _rig()
	if rig != null and rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", not playing)
	if play_button != null:
		play_button.text = "Pause" if playing else "Play"


func _apply_working_tuning() -> void:
	var rig := _rig()
	if rig != null and rig.has_method("set_animation_tuning"):
		rig.call("set_animation_tuning", PREVIEW_ANIMATION, working_tuning)


func _update_save_name() -> void:
	if save_name == null or current_record.is_empty():
		return
	var animation_name := str(current_record.get("name", "animation"))
	var source_profile := str(current_record.get("source_profile", PROFILE_JUNO))
	var source_kind := str(current_record.get("source", "builtin"))
	if source_kind == "custom" and source_profile == target_profile:
		save_name.text = animation_name
		return
	var target_suffix := "juno"
	if target_profile == PROFILE_DUMMY:
		target_suffix = "dummy"
	elif target_profile == PROFILE_MALE:
		target_suffix = "male"
	save_name.text = "%s_%s_tuned" % [animation_name, target_suffix]


func _save_custom_tuning() -> void:
	if current_record.is_empty():
		_set_status("Choose an animation first.", true)
		return
	var clean_name := _sanitize_name(save_name.text)
	if clean_name.is_empty():
		_set_status("Choose a valid custom animation name.", true)
		return
	var source_profile := str(current_record.get("source_profile", PROFILE_JUNO))
	var source_name := str(current_record.get("name", ""))
	var source_record := Library.get_animation_record(source_profile, source_name)
	var data_value: Variant = source_record.get("data", {})
	if not data_value is Dictionary:
		_set_status("Could not reload source animation.", true)
		return
	var save_data := _prepare_animation_for_target(data_value as Dictionary, source_profile, target_profile)
	if save_data.is_empty():
		return
	save_data[TUNING_KEY] = working_tuning.duplicate(true)
	save_data["repeat"] = loop_check.button_pressed
	var meta := {
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
	var rig := _rig()
	if rig != null and rig.has_method("install_runtime_animation"):
		rig.call("install_runtime_animation", clean_name, save_data)
	_rebuild_animation_records()
	_set_status("Saved custom '%s' for %s. Original source was not modified." % [clean_name, str(PROFILE_LABEL.get(target_profile, target_profile))])


func _sanitize_name(value: String) -> String:
	var raw := value.strip_edges().replace(" ", "_").replace("-", "_")
	var clean := ""
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	for character in raw:
		if allowed.contains(str(character)):
			clean += str(character)
	return clean


func _rig():
	if host == null:
		return null
	return host.get("rig")


func _on_tab_changed(_index: int) -> void:
	if not is_visible_in_tree():
		_set_playback_state(false)
		return
	if autoplay_check != null and autoplay_check.button_pressed and _scope_mode() == SCOPE_WHOLE:
		_set_playback_state(true)


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func _add_row(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(145, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _set_status(message: String, is_error: bool = false) -> void:
	if status_label != null:
		status_label.text = message
		status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if is_error else Color(0.65, 0.95, 0.72))
	print("ALABASTER_LIVE_TUNING: %s" % message)
