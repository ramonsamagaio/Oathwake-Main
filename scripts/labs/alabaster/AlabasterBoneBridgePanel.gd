extends VBoxContainer

# Visual, live source-to-Juno comparison workspace.
#
# Layout intentionally uses the Bone Studio's existing right-hand Juno preview:
#   [mapping list | imported Skeleton3D in green]  ||  [live Juno preview]
# This keeps both animations visible at useful size instead of squeezing three
# columns into the already narrow TabContainer.

const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const SourcePreviewScript := preload("res://scripts/labs/alabaster/AlabasterSourceSkeletonPreview.gd")
const FOLD_PREFIX := "@fold:"

var host: Control = null
var source_preview: Control = null
var mapping_box: VBoxContainer = null
var bridge_mapping_controls: Dictionary = {}
var clip_option: OptionButton = null
var play_button: Button = null
var speed_option: OptionButton = null
var source_label: Label = null
var status_label: Label = null
var mode_label: Label = null
var mapping_count_label: Label = null

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
	_build_ui()
	var tabs := _find_tabs(owner)
	if tabs == null:
		push_error("Bone Studio: BONE BRIDGE could not find the workspace TabContainer.")
		return
	tabs.add_child(self)
	set_process(true)
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
	var title := Label.new()
	title.text = "BONE BRIDGE · SOURCE ↔ JUNO LIVE"
	title.add_theme_font_size_override("font_size", 19)
	add_child(title)

	var intro := Label.new()
	intro.text = "Load the source here, watch its real Skeleton3D in the same green/orange language as Bone Studio, and map each animated source bone to Juno or Ignore. The normal Juno preview on the RIGHT stays synchronized with this source."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)

	var source_row := HBoxContainer.new()
	add_child(source_row)
	var browse := Button.new()
	browse.text = "LOAD FBX / GLB"
	browse.pressed.connect(_open_source_dialog)
	source_row.add_child(browse)
	source_label = Label.new()
	source_label.text = "No source selected"
	source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_row.add_child(source_label)

	var clip_row := HBoxContainer.new()
	add_child(clip_row)
	var clip_label := Label.new()
	clip_label.text = "Clip"
	clip_label.custom_minimum_size = Vector2(52.0, 0.0)
	clip_row.add_child(clip_label)
	clip_option = OptionButton.new()
	clip_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_option.item_selected.connect(_on_bridge_clip_selected)
	clip_row.add_child(clip_option)

	play_button = Button.new()
	play_button.text = "PAUSE"
	play_button.pressed.connect(_toggle_playback)
	clip_row.add_child(play_button)

	speed_option = OptionButton.new()
	for speed in [0.25, 0.5, 1.0, 1.5, 2.0]:
		speed_option.add_item("%.2gx" % speed)
		speed_option.set_item_metadata(speed_option.item_count - 1, speed)
	speed_option.select(2)
	speed_option.item_selected.connect(_on_speed_selected)
	clip_row.add_child(speed_option)

	mode_label = Label.new()
	mode_label.text = "RETARGET PATH: waiting for source"
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(mode_label)

	var actions := HBoxContainer.new()
	add_child(actions)
	var reset_auto := Button.new()
	reset_auto.text = "RESET AUTO MAP"
	reset_auto.tooltip_text = "Restore Bone Studio's automatic mapping, including folded helper joints."
	reset_auto.pressed.connect(_reset_auto_mapping)
	actions.add_child(reset_auto)
	var refresh := Button.new()
	refresh.text = "REBUILD TARGET"
	refresh.tooltip_text = "Rebuild the Juno preview now. Mapping changes already do this automatically."
	refresh.pressed.connect(_queue_target_refresh)
	actions.add_child(refresh)
	mapping_count_label = Label.new()
	mapping_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapping_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(mapping_count_label)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 285
	add_child(split)

	var mapping_panel := VBoxContainer.new()
	mapping_panel.custom_minimum_size = Vector2(265.0, 430.0)
	mapping_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapping_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(mapping_panel)
	var mapping_title := Label.new()
	mapping_title.text = "SOURCE BONE  →  JUNO"
	mapping_title.add_theme_font_size_override("font_size", 14)
	mapping_panel.add_child(mapping_title)
	var mapping_hint := Label.new()
	mapping_hint.text = "Click a bone name to highlight it. Dropdown changes are live."
	mapping_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mapping_panel.add_child(mapping_hint)
	var mapping_scroll := ScrollContainer.new()
	mapping_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapping_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mapping_panel.add_child(mapping_scroll)
	mapping_box = VBoxContainer.new()
	mapping_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapping_scroll.add_child(mapping_box)

	var source_panel := VBoxContainer.new()
	source_panel.custom_minimum_size = Vector2(280.0, 430.0)
	source_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(source_panel)
	var preview_title := Label.new()
	preview_title.text = "IMPORTED SOURCE · LIVE SKELETON3D"
	preview_title.add_theme_font_size_override("font_size", 14)
	source_panel.add_child(preview_title)
	source_preview = SourcePreviewScript.new() as Control
	if source_preview == null:
		push_error("Bone Studio: could not create source Skeleton3D preview.")
	else:
		source_preview.custom_minimum_size = Vector2(280.0, 430.0)
		source_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		source_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		source_preview.connect("pose_updated", Callable(self, "_on_source_pose_updated"))
		source_panel.add_child(source_preview)

	status_label = Label.new()
	status_label.text = "Select an animation source."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)


func _open_source_dialog() -> void:
	if host == null:
		return
	var dialog := host.get("file_dialog") as FileDialog
	if dialog != null:
		dialog.popup_centered_ratio(0.78)


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
		source_label.text = path if not path.is_empty() else "No source selected"
		source_label.tooltip_text = path
		_source_info.clear()
		if not path.is_empty():
			_source_info = SourceAdapter.inspect_scene(path)
		_copy_clips_from_host()
		_load_source_preview(path, clip)
		_rebuild_mapping_rows()
		mapping_changed = true

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
	elif path_changed:
		_last_mapping_signature = _host_mapping_signature()

	_update_mode_label()


func _load_source_preview(path: String, clip: String) -> void:
	if source_preview == null:
		return
	if path.is_empty():
		source_preview.call("clear_source")
		_set_local_status("Select a source animation in BONE BRIDGE or Import_Retarget.", false)
		return
	var result_value: Variant = source_preview.call("load_source", path, clip)
	var result: Dictionary = result_value if result_value is Dictionary else {}
	if not bool(result.get("ok", false)):
		_set_local_status(str(result.get("error", "Could not display source Skeleton3D.")), true)
		return
	var skeleton_bones := int(result.get("bone_count", 0))
	var animated_bones := _host_source_bones().size()
	mapping_count_label.text = "%d skeleton / %d animated" % [skeleton_bones, animated_bones]
	_set_local_status("Source skeleton is live. Change a dropdown and the Juno preview on the right rebuilds immediately.", false)
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


func _rebuild_mapping_rows() -> void:
	if mapping_box == null:
		return
	bridge_mapping_controls.clear()
	for child_value in mapping_box.get_children():
		var child := child_value as Node
		if child != null:
			child.queue_free()

	var source_bones := _host_source_bones()
	var host_controls_value: Variant = host.get("mapping_controls") if host != null else {}
	var host_controls: Dictionary = host_controls_value if host_controls_value is Dictionary else {}
	var mapped_count := 0
	for source_bone in source_bones:
		var host_option := host_controls.get(source_bone) as OptionButton
		if host_option == null:
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mapping_box.add_child(row)

		var bone_button := Button.new()
		bone_button.text = _short_bone_name(source_bone)
		bone_button.tooltip_text = source_bone
		bone_button.custom_minimum_size = Vector2(118.0, 0.0)
		bone_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bone_button.pressed.connect(_highlight_source_bone.bind(source_bone))
		row.add_child(bone_button)

		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for index in range(host_option.item_count):
			option.add_item(host_option.get_item_text(index))
			option.set_item_metadata(option.item_count - 1, host_option.get_item_metadata(index))
			option.set_item_tooltip(option.item_count - 1, host_option.get_item_tooltip(index))
		option.select(host_option.selected)
		if option.selected >= 0 and not str(option.get_item_metadata(option.selected)).is_empty():
			mapped_count += 1
		option.item_selected.connect(_on_mapping_selected.bind(source_bone, option))
		row.add_child(option)
		bridge_mapping_controls[source_bone] = option

	mapping_count_label.text = "%d mapped / %d animated" % [mapped_count, source_bones.size()]


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
	var host_option := (controls_value as Dictionary).get(source_bone) as OptionButton
	if host_option == null:
		return
	for index in range(host_option.item_count):
		if str(host_option.get_item_metadata(index)) == target_value:
			host_option.select(index)
			return


func _highlight_source_bone(source_bone: String) -> void:
	if source_preview != null:
		source_preview.call("select_bone", source_bone)


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
	if not data_value is Dictionary or (data_value as Dictionary).is_empty():
		_set_local_status("This mapping did not produce a target animation. RETARGET DEBUG can show which stage rejected it.", true)
		return
	var rig := _target_rig()
	if rig == null or not rig.has_method("install_runtime_animation") or not rig.has_method("set_animation"):
		_set_local_status("The live Juno target rig is unavailable.", true)
		return
	if not bool(rig.call("install_runtime_animation", "__bone_bridge_preview", data_value as Dictionary)):
		_set_local_status("Juno rejected the generated Bone Bridge preview animation.", true)
		return
	rig.call("set_animation", "__bone_bridge_preview")
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)
	_sync_target_to_source_time(source_preview.call("get_time") as float if source_preview != null else 0.0)
	_set_local_status("LIVE: source Skeleton3D and Juno are synchronized. Mapping changes rebuild the target automatically.", false)


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
	if source_preview == null or speed_option == null or index < 0 or index >= speed_option.item_count:
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
		return
	var profile := str(_source_info.get("retarget_profile", "generic"))
	var has_skeleton := bool(_source_info.get("has_skeleton", false))
	var auto_match := _mapping_matches_auto()
	if profile == "mixamo" and has_skeleton and auto_match:
		mode_label.text = "RETARGET PATH: V8 REST→POSE semantic solver · full Skeleton3D · AUTO mapping"
		mode_label.add_theme_color_override("font_color", Color(0.48, 1.0, 0.62))
	elif profile == "mixamo" and has_skeleton:
		mode_label.text = "RETARGET PATH: MANUAL mapping · current adapter uses generic track conversion when V8 auto semantics are overridden"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	elif has_skeleton:
		mode_label.text = "RETARGET PATH: generic humanoid source · Skeleton3D visible, canonical profile adapter still required for V8-quality transfer"
		mode_label.add_theme_color_override("font_color", Color(0.75, 0.86, 1.0))
	else:
		mode_label.text = "RETARGET PATH: track-only fallback · source exposes no Skeleton3D"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.35))


func _mapping_matches_auto() -> bool:
	var bones := _host_source_bones()
	if bones.is_empty():
		return true
	var expected := SourceAdapter.make_auto_retarget(bones)
	var controls_value: Variant = host.get("mapping_controls") if host != null else {}
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
	keys.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	var parts: PackedStringArray = PackedStringArray()
	for key_value in keys:
		var key := str(key_value)
		var option := controls[key_value] as OptionButton
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
	return value as Object if value is Object else null


func _set_local_status(message: String, is_error: bool) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.32) if is_error else Color(0.62, 0.96, 0.72))


func _short_bone_name(source_bone: String) -> String:
	var clean := source_bone
	if clean.contains(":"):
		clean = clean.get_slice(":", clean.get_slice_count(":") - 1)
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
