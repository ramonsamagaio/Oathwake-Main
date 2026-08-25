extends VBoxContainer

# Live visual source-to-Juno comparison workspace.
# The outer Bone Studio owns the Juno preview on the right. This tab uses the
# large left workspace for mapping + the real imported Skeleton3D.

const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const SourcePreviewScript := preload("res://scripts/labs/alabaster/AlabasterSourceSkeletonPreview.gd")

const MAPPING_MIN_WIDTH := 500.0
const SOURCE_MIN_WIDTH := 450.0
const PANEL_GAP := 12.0

var host: Control = null
var source_preview: Control = null
var mapping_box: VBoxContainer = null
var bridge_mapping_controls: Dictionary = {}
var clip_option: OptionButton = null
var play_button: Button = null
var speed_option: OptionButton = null
var source_path_edit: LineEdit = null
var status_label: Label = null
var mode_label: Label = null
var mapping_count_label: Label = null
var mapping_filter_edit: LineEdit = null
var selected_source_label: Label = null
var bridge_split: HSplitContainer = null

var _last_source_path := ""
var _last_clip := ""
var _last_mapping_signature := ""
var _source_info: Dictionary = {}
var _poll_accumulator := 0.0
var _bridge_active := false
var _refresh_queued := false
var _suppress_clip_signal := false


func setup(owner: Control) -> void:
	host = owner
	name = "BONE BRIDGE"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build_ui()
	var tabs := _find_tabs(owner)
	if tabs == null:
		push_error("Bone Studio: BONE BRIDGE could not find the workspace TabContainer.")
		return
	tabs.add_child(self)
	if not resized.is_connected(_apply_panel_layout):
		resized.connect(_apply_panel_layout)
	set_process(true)
	call_deferred("_apply_panel_layout")
	call_deferred("_refresh_from_host", true)


func _process(delta: float) -> void:
	var visible_now := is_visible_in_tree()
	if visible_now and not _bridge_active:
		_enter_bridge_mode()
	elif not visible_now and _bridge_active:
		_leave_bridge_mode()

	if not visible_now:
		return
	_poll_accumulator += delta
	if _poll_accumulator >= 0.20:
		_poll_accumulator = 0.0
		_refresh_from_host(false)


func _build_ui() -> void:
	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size.y = 40.0
	title_row.add_theme_constant_override("separation", 12)
	add_child(title_row)

	var title := Label.new()
	title.text = "BONE BRIDGE"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	mapping_count_label = Label.new()
	mapping_count_label.text = "0 mapped / 0 animated"
	mapping_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mapping_count_label.add_theme_font_size_override("font_size", 14)
	title_row.add_child(mapping_count_label)

	var subtitle := Label.new()
	subtitle.text = "Source skeleton and Juno run on the same clock. Map a bone, watch the result immediately."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color(0.72, 0.78, 0.78))
	add_child(subtitle)

	var source_row := HBoxContainer.new()
	source_row.custom_minimum_size.y = 42.0
	source_row.add_theme_constant_override("separation", 8)
	add_child(source_row)

	var browse := Button.new()
	browse.text = "LOAD SOURCE"
	browse.custom_minimum_size = Vector2(132.0, 38.0)
	browse.tooltip_text = "Load FBX, GLB, GLTF or TSCN animation source"
	browse.pressed.connect(_open_source_dialog)
	source_row.add_child(browse)

	source_path_edit = LineEdit.new()
	source_path_edit.editable = false
	source_path_edit.placeholder_text = "No source selected"
	source_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_path_edit.custom_minimum_size.y = 38.0
	source_row.add_child(source_path_edit)

	var transport_row := HBoxContainer.new()
	transport_row.custom_minimum_size.y = 42.0
	transport_row.add_theme_constant_override("separation", 8)
	add_child(transport_row)

	var clip_label := Label.new()
	clip_label.text = "CLIP"
	clip_label.custom_minimum_size = Vector2(42.0, 0.0)
	transport_row.add_child(clip_label)

	clip_option = OptionButton.new()
	clip_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_option.custom_minimum_size = Vector2(260.0, 38.0)
	clip_option.item_selected.connect(_on_bridge_clip_selected)
	transport_row.add_child(clip_option)

	play_button = Button.new()
	play_button.text = "PAUSE"
	play_button.custom_minimum_size = Vector2(92.0, 38.0)
	play_button.pressed.connect(_toggle_playback)
	transport_row.add_child(play_button)

	speed_option = OptionButton.new()
	speed_option.custom_minimum_size = Vector2(96.0, 38.0)
	for speed_value in [0.25, 0.5, 1.0, 1.5, 2.0]:
		var speed := float(speed_value)
		speed_option.add_item("%sx" % str(speed))
		speed_option.set_item_metadata(speed_option.item_count - 1, speed)
	speed_option.select(2)
	speed_option.item_selected.connect(_on_speed_selected)
	transport_row.add_child(speed_option)

	var reset_auto := Button.new()
	reset_auto.text = "RESET AUTO MAP"
	reset_auto.custom_minimum_size = Vector2(150.0, 38.0)
	reset_auto.tooltip_text = "Restore Bone Studio automatic mapping, including folded helper joints."
	reset_auto.pressed.connect(_reset_auto_mapping)
	transport_row.add_child(reset_auto)

	var refresh := Button.new()
	refresh.text = "REBUILD TARGET"
	refresh.custom_minimum_size = Vector2(150.0, 38.0)
	refresh.tooltip_text = "Rebuild the Juno preview now. Mapping changes already do this automatically."
	refresh.pressed.connect(_queue_target_refresh)
	transport_row.add_child(refresh)

	mode_label = Label.new()
	mode_label.text = "RETARGET PATH: waiting for source"
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_label.custom_minimum_size.y = 30.0
	mode_label.add_theme_font_size_override("font_size", 13)
	add_child(mode_label)

	bridge_split = HSplitContainer.new()
	bridge_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bridge_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bridge_split.add_theme_constant_override("separation", int(PANEL_GAP))
	add_child(bridge_split)

	_build_mapping_panel(bridge_split)
	_build_source_preview_panel(bridge_split)

	status_label = Label.new()
	status_label.text = "Select an animation source."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 34.0
	status_label.add_theme_font_size_override("font_size", 13)
	add_child(status_label)


func _build_mapping_panel(parent: HSplitContainer) -> void:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(MAPPING_MIN_WIDTH, 540.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 7)
	parent.add_child(panel)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 34.0
	panel.add_child(header)

	var mapping_title := Label.new()
	mapping_title.text = "SOURCE BONE  →  JUNO"
	mapping_title.add_theme_font_size_override("font_size", 16)
	mapping_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(mapping_title)

	mapping_filter_edit = LineEdit.new()
	mapping_filter_edit.placeholder_text = "Filter bones..."
	mapping_filter_edit.custom_minimum_size = Vector2(190.0, 34.0)
	mapping_filter_edit.text_changed.connect(_on_mapping_filter_changed)
	header.add_child(mapping_filter_edit)

	var hint := Label.new()
	hint.text = "Click the source name to highlight that joint. Dropdown changes rebuild Juno live."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.68, 0.74, 0.74))
	panel.add_child(hint)

	var columns := HBoxContainer.new()
	columns.custom_minimum_size.y = 28.0
	panel.add_child(columns)
	var source_column := Label.new()
	source_column.text = "SOURCE"
	source_column.custom_minimum_size.x = 230.0
	source_column.add_theme_font_size_override("font_size", 12)
	columns.add_child(source_column)
	var target_column := Label.new()
	target_column.text = "TARGET / BEHAVIOR"
	target_column.add_theme_font_size_override("font_size", 12)
	columns.add_child(target_column)

	var mapping_scroll := ScrollContainer.new()
	mapping_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapping_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mapping_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(mapping_scroll)

	mapping_box = VBoxContainer.new()
	mapping_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapping_box.add_theme_constant_override("separation", 4)
	mapping_scroll.add_child(mapping_box)


func _build_source_preview_panel(parent: HSplitContainer) -> void:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(SOURCE_MIN_WIDTH, 540.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	parent.add_child(panel)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 34.0
	panel.add_child(header)

	var preview_title := Label.new()
	preview_title.text = "IMPORTED SOURCE · LIVE SKELETON3D"
	preview_title.add_theme_font_size_override("font_size", 16)
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(preview_title)

	selected_source_label = Label.new()
	selected_source_label.text = ""
	selected_source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	selected_source_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
	header.add_child(selected_source_label)

	var preview_value: Variant = SourcePreviewScript.new()
	if not preview_value is Control:
		push_error("Bone Studio: could not create source Skeleton3D preview.")
		return
	source_preview = preview_value as Control
	source_preview.custom_minimum_size = Vector2(SOURCE_MIN_WIDTH, 500.0)
	source_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source_preview.connect("pose_updated", Callable(self, "_on_source_pose_updated"))
	panel.add_child(source_preview)


func _apply_panel_layout() -> void:
	if bridge_split == null:
		return
	var available := maxf(size.x - PANEL_GAP, MAPPING_MIN_WIDTH + SOURCE_MIN_WIDTH + PANEL_GAP)
	var desired := available * 0.51
	var maximum := maxf(MAPPING_MIN_WIDTH, available - SOURCE_MIN_WIDTH - PANEL_GAP)
	bridge_split.split_offset = int(clampf(desired, MAPPING_MIN_WIDTH, maximum))


func _open_source_dialog() -> void:
	if host == null:
		return
	var dialog := host.get("file_dialog") as FileDialog
	if dialog != null:
		dialog.popup_centered_ratio(0.86)


func _refresh_from_host(force: bool = false) -> void:
	if host == null:
		return
	var path := str(host.get("source_path"))
	var clip := _host_selected_clip()
	var mapping_signature := _host_mapping_signature()
	var path_changed := force or path != _last_source_path
	var clip_changed := force or clip != _last_clip
	var mapping_changed := force or mapping_signature != _last_mapping_signature

	if path_changed:
		_last_source_path = path
		if source_path_edit != null:
			source_path_edit.text = path
			source_path_edit.tooltip_text = path
		_source_info.clear()
		if not path.is_empty():
			_source_info = SourceAdapter.inspect_scene(path)
		_copy_clips_from_host()
		_load_source_preview(path, clip)
		_rebuild_mapping_rows()
		_last_mapping_signature = _host_mapping_signature()

	if clip_changed and not path_changed:
		_last_clip = clip
		_select_bridge_clip(clip)
		if source_preview != null and not clip.is_empty():
			source_preview.call("set_clip", clip)
		_queue_target_refresh()
	elif path_changed:
		_last_clip = clip

	if mapping_changed and not path_changed:
		_last_mapping_signature = mapping_signature
		_rebuild_mapping_rows()
		_queue_target_refresh()

	_update_mode_label()


func _load_source_preview(path: String, clip: String) -> void:
	if source_preview == null:
		return
	if path.is_empty():
		source_preview.call("clear_source")
		_set_local_status("Select a source animation in BONE BRIDGE or Import_Retarget.", false)
		return
	var result_value: Variant = source_preview.call("load_source", path, clip)
	var result: Dictionary = {}
	if result_value is Dictionary:
		result = result_value as Dictionary
	if not bool(result.get("ok", false)):
		_set_local_status(str(result.get("error", "Could not display source Skeleton3D.")), true)
		return
	var skeleton_bones := int(result.get("bone_count", 0))
	var animated_bones := _host_source_bones().size()
	mapping_count_label.text = "%d skeleton · %d animated" % [skeleton_bones, animated_bones]
	_set_local_status("LIVE: source Skeleton3D and Juno share the same clock. Mapping changes rebuild the target automatically.", false)
	_queue_target_refresh()


func _copy_clips_from_host() -> void:
	if clip_option == null or host == null:
		return
	_suppress_clip_signal = true
	clip_option.clear()
	var source_option := host.get("source_clip_option") as OptionButton
	if source_option != null:
		for index in range(source_option.item_count):
			clip_option.add_item(source_option.get_item_text(index))
			clip_option.set_item_metadata(clip_option.item_count - 1, source_option.get_item_metadata(index))
	_select_bridge_clip(_host_selected_clip())
	_suppress_clip_signal = false


func _select_bridge_clip(clip_name: String) -> void:
	if clip_option == null:
		return
	for index in range(clip_option.item_count):
		if str(clip_option.get_item_metadata(index)) == clip_name:
			clip_option.select(index)
			return


func _on_bridge_clip_selected(index: int) -> void:
	if _suppress_clip_signal or host == null or clip_option == null:
		return
	if index < 0 or index >= clip_option.item_count:
		return
	var clip_name := str(clip_option.get_item_metadata(index))
	var host_option := host.get("source_clip_option") as OptionButton
	if host_option != null:
		for host_index in range(host_option.item_count):
			if str(host_option.get_item_metadata(host_index)) == clip_name:
				host_option.select(host_index)
				break
	_last_clip = clip_name
	if source_preview != null:
		source_preview.call("set_clip", clip_name)
	_queue_target_refresh()


func _on_mapping_filter_changed(_text: String) -> void:
	_rebuild_mapping_rows()


func _rebuild_mapping_rows() -> void:
	if mapping_box == null:
		return
	bridge_mapping_controls.clear()
	for child_value in mapping_box.get_children():
		var child := child_value as Node
		if child != null:
			child.queue_free()

	var source_bones := _host_source_bones()
	var host_controls: Dictionary = {}
	if host != null:
		var host_controls_value: Variant = host.get("mapping_controls")
		if host_controls_value is Dictionary:
			host_controls = host_controls_value as Dictionary

	var filter_text := ""
	if mapping_filter_edit != null:
		filter_text = mapping_filter_edit.text.strip_edges().to_lower()

	var mapped_count := 0
	var visible_count := 0
	for source_bone in source_bones:
		var host_option := host_controls.get(source_bone) as OptionButton
		if host_option == null:
			continue
		var current_value := ""
		if host_option.selected >= 0:
			current_value = str(host_option.get_item_metadata(host_option.selected))
		if not current_value.is_empty():
			mapped_count += 1

		var short_name := _short_bone_name(source_bone)
		if not filter_text.is_empty():
			var searchable := "%s %s %s" % [source_bone.to_lower(), short_name.to_lower(), current_value.to_lower()]
			if not searchable.contains(filter_text):
				continue
		visible_count += 1

		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 40.0
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		mapping_box.add_child(row)

		var bone_button := Button.new()
		bone_button.text = short_name
		bone_button.tooltip_text = source_bone
		bone_button.custom_minimum_size = Vector2(230.0, 38.0)
		bone_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bone_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bone_button.pressed.connect(_highlight_source_bone.bind(source_bone))
		row.add_child(bone_button)

		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.custom_minimum_size = Vector2(250.0, 38.0)
		for item_index in range(host_option.item_count):
			option.add_item(host_option.get_item_text(item_index))
			option.set_item_metadata(option.item_count - 1, host_option.get_item_metadata(item_index))
		option.select(host_option.selected)
		option.item_selected.connect(_on_mapping_selected.bind(source_bone, option))
		row.add_child(option)
		bridge_mapping_controls[source_bone] = option

	var suffix := ""
	if visible_count != source_bones.size():
		suffix = " · %d shown" % visible_count
	mapping_count_label.text = "%d mapped / %d animated%s" % [mapped_count, source_bones.size(), suffix]


func _on_mapping_selected(_index: int, source_bone: String, bridge_option: OptionButton) -> void:
	if bridge_option == null or bridge_option.selected < 0:
		return
	var value := str(bridge_option.get_item_metadata(bridge_option.selected))
	_set_host_mapping(source_bone, value)
	_last_mapping_signature = _host_mapping_signature()
	_highlight_source_bone(source_bone)
	_update_mode_label()
	_queue_target_refresh()


func _set_host_mapping(source_bone: String, target_value: String) -> void:
	if host == null:
		return
	var controls_value: Variant = host.get("mapping_controls")
	if not controls_value is Dictionary:
		return
	var controls := controls_value as Dictionary
	var host_option := controls.get(source_bone) as OptionButton
	if host_option == null:
		return
	for index in range(host_option.item_count):
		if str(host_option.get_item_metadata(index)) == target_value:
			host_option.select(index)
			return


func _highlight_source_bone(source_bone: String) -> void:
	if source_preview != null:
		source_preview.call("select_bone", source_bone)
	if selected_source_label != null:
		selected_source_label.text = _short_bone_name(source_bone)
		selected_source_label.tooltip_text = source_bone


func _reset_auto_mapping() -> void:
	if host == null or not host.has_method("_rebuild_mapping_table"):
		return
	host.call("_rebuild_mapping_table")
	_last_mapping_signature = _host_mapping_signature()
	_rebuild_mapping_rows()
	_update_mode_label()
	_queue_target_refresh()


func _queue_target_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_target_preview")


func _refresh_target_preview() -> void:
	_refresh_queued = false
	if host == null or not is_visible_in_tree():
		return
	if _last_source_path.is_empty() or _host_selected_clip().is_empty():
		return
	if host.has_method("ensure_juno_retarget_target"):
		host.call("ensure_juno_retarget_target")
	if not host.has_method("_build_import_animation"):
		_set_local_status("Bone Studio host cannot build an import preview.", true)
		return

	var data_value: Variant = host.call("_build_import_animation")
	if not data_value is Dictionary:
		_set_local_status("The source did not produce a target animation.", true)
		return
	var data := data_value as Dictionary
	if data.is_empty():
		_set_local_status("This mapping did not produce a target animation. RETARGET DEBUG can show which stage rejected it.", true)
		return

	var rig := _target_rig()
	if rig == null or not rig.has_method("install_runtime_animation") or not rig.has_method("set_animation"):
		_set_local_status("The live Juno target rig is unavailable.", true)
		return
	if not bool(rig.call("install_runtime_animation", "__bone_bridge_preview", data)):
		_set_local_status("Juno rejected the generated Bone Bridge preview animation.", true)
		return
	rig.call("set_animation", "__bone_bridge_preview")
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)

	var source_time := 0.0
	if source_preview != null:
		source_time = float(source_preview.call("get_time"))
	_sync_target_to_source_time(source_time)
	_set_local_status("LIVE: source and Juno synchronized. Change any mapping to compare the result immediately.", false)


func _on_source_pose_updated(time_seconds: float) -> void:
	if not _bridge_active:
		return
	_sync_target_to_source_time(time_seconds)


func _sync_target_to_source_time(time_seconds: float) -> void:
	var rig := _target_rig()
	if rig == null or not rig.has_method("seek_animation_frame"):
		return
	var fps := 60.0
	if host != null:
		var fps_spin := host.get("import_fps") as SpinBox
		if fps_spin != null:
			fps = maxf(fps_spin.value, 1.0)
	rig.call("seek_animation_frame", time_seconds * fps)


func _toggle_playback() -> void:
	if source_preview == null:
		return
	var playing := not bool(source_preview.call("is_playing"))
	source_preview.call("set_playing", playing)
	play_button.text = "PAUSE" if playing else "PLAY"


func _on_speed_selected(index: int) -> void:
	if source_preview == null or speed_option == null:
		return
	if index < 0 or index >= speed_option.item_count:
		return
	source_preview.call("set_speed", float(speed_option.get_item_metadata(index)))


func _enter_bridge_mode() -> void:
	_bridge_active = true
	if source_preview != null:
		source_preview.call("set_playing", true)
	play_button.text = "PAUSE"
	_queue_target_refresh()


func _leave_bridge_mode() -> void:
	_bridge_active = false
	var rig := _target_rig()
	if rig != null and rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", false)


func _update_mode_label() -> void:
	if mode_label == null:
		return
	if _last_source_path.is_empty():
		mode_label.text = "RETARGET PATH: waiting for source"
		mode_label.add_theme_color_override("font_color", Color(0.70, 0.74, 0.74))
		return

	var profile := str(_source_info.get("retarget_profile", "generic"))
	var has_skeleton := bool(_source_info.get("has_skeleton", false))
	var auto_match := _mapping_matches_auto()
	if profile == "mixamo" and has_skeleton and auto_match:
		mode_label.text = "V8 REST→POSE · full Skeleton3D · AUTO semantic mapping"
		mode_label.add_theme_color_override("font_color", Color(0.48, 1.0, 0.62))
	elif profile == "mixamo" and has_skeleton:
		mode_label.text = "MANUAL mapping · current adapter uses generic track conversion when V8 auto semantics are overridden"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	elif has_skeleton:
		mode_label.text = "Generic Skeleton3D · source is visible; canonical humanoid characterization is still needed for V8-quality transfer"
		mode_label.add_theme_color_override("font_color", Color(0.75, 0.86, 1.0))
	else:
		mode_label.text = "Track-only fallback · source exposes no Skeleton3D"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.35))


func _mapping_matches_auto() -> bool:
	var bones := _host_source_bones()
	if bones.is_empty():
		return true
	var expected := SourceAdapter.make_auto_retarget(bones)
	if host == null:
		return false
	var controls_value: Variant = host.get("mapping_controls")
	if not controls_value is Dictionary:
		return false
	var controls := controls_value as Dictionary
	for source_bone in bones:
		var option := controls.get(source_bone) as OptionButton
		if option == null or option.selected < 0:
			return false
		if str(option.get_item_metadata(option.selected)) != str(expected.get(source_bone, "")):
			return false
	return true


func _host_mapping_signature() -> String:
	if host == null:
		return ""
	var controls_value: Variant = host.get("mapping_controls")
	if not controls_value is Dictionary:
		return ""
	var controls := controls_value as Dictionary
	var keys: Array = controls.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a).naturalnocasecmp_to(str(b)) < 0
	)
	var parts := PackedStringArray()
	for key_value in keys:
		var key := str(key_value)
		var option := controls.get(key_value) as OptionButton
		var value := ""
		if option != null and option.selected >= 0:
			value = str(option.get_item_metadata(option.selected))
		parts.append("%s=%s" % [key, value])
	return "|".join(parts)


func _host_source_bones() -> Array[String]:
	var result: Array[String] = []
	if host == null:
		return result
	var value: Variant = host.get("source_bones")
	if value is Array:
		for bone_value in value:
			result.append(str(bone_value))
	return result


func _host_selected_clip() -> String:
	if host == null:
		return ""
	var option := host.get("source_clip_option") as OptionButton
	if option == null or option.item_count <= 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _target_rig() -> Object:
	if host == null:
		return null
	var value: Variant = host.get("rig")
	if value is Object:
		return value as Object
	return null


func _set_local_status(message: String, is_error: bool) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.38, 0.32) if is_error else Color(0.62, 0.96, 0.72)
	)


func _short_bone_name(source_bone: String) -> String:
	var clean := source_bone
	if clean.contains(":"):
		var pieces := clean.split(":", false)
		if not pieces.is_empty():
			clean = str(pieces[pieces.size() - 1])
	return clean


func _find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_tabs(child)
		if found != null:
			return found
	return null
