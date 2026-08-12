extends "res://scripts/labs/alabaster/AlabasterBoneStudioLiveTuningDefault.gd"

# Interactive workspace layer for Bone Studio. It deliberately composes on top of
# Live Tuning instead of changing gameplay/runtime animation code.
const BoneViewportEditorScript := preload("res://scripts/labs/alabaster/AlabasterBoneViewportEditor.gd")
const WORKSPACE_ZOOM_MIN := 0.25
const WORKSPACE_ZOOM_MAX := 8.0
const WORKSPACE_ZOOM_STEP := 0.10
const WORKSPACE_UNDO_LIMIT := 100
const WORKSPACE_PREVIEW_Y_OFFSET := 24.0

var _workspace_holder: SubViewportContainer = null
var _workspace_viewport: SubViewport = null
var _workspace_editor: Control = null
var _workspace_pan := Vector2.ZERO
var _workspace_rotate_button: Button = null
var _workspace_move_button: Button = null
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _restoring_history := false
var _viewport_drag_active := false


func setup(owner: Control) -> void:
	super.setup(owner)
	_configure_workspace_zoom()
	_install_workspace_toolbar()
	_install_workspace_viewport_editor()
	_clear_workspace_history()
	call_deferred("_maximize_bone_lab")
	call_deferred("_configure_workspace_layout")
	call_deferred("_sync_workspace_viewport_geometry")


func _maximize_bone_lab() -> void:
	var window_mode := DisplayServer.window_get_mode()
	if window_mode == DisplayServer.WINDOW_MODE_WINDOWED or window_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _configure_workspace_layout() -> void:
	if host == null:
		return
	var split := _find_hsplit(host)
	if split != null:
		var desired_left := clampi(roundi(host.size.x * 0.36), 430, 720)
		split.split_offset = desired_left
	var tabs := _find_tabs(host)
	if tabs != null:
		tabs.custom_minimum_size = Vector2(420.0, 520.0)
	if _workspace_holder != null:
		_workspace_holder.custom_minimum_size = Vector2(640.0, 560.0)
	_sync_workspace_viewport_geometry()


func _find_hsplit(node: Node) -> HSplitContainer:
	if node is HSplitContainer:
		return node as HSplitContainer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_hsplit(child)
		if found != null:
			return found
	return null


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


func _configure_workspace_zoom() -> void:
	if _preview_zoom_slider == null:
		return
	_preview_zoom_slider.min_value = WORKSPACE_ZOOM_MIN
	_preview_zoom_slider.max_value = WORKSPACE_ZOOM_MAX
	_preview_zoom_slider.step = WORKSPACE_ZOOM_STEP
	_preview_zoom_slider.tooltip_text = "Animation viewport zoom: 25% to 800%. Mouse wheel over the preview uses the same zoom."
	_preview_zoom_slider.set_value_no_signal(clampf(_preview_zoom, WORKSPACE_ZOOM_MIN, WORKSPACE_ZOOM_MAX))
	_update_preview_zoom_label()


func _on_preview_zoom_changed(value: float) -> void:
	_preview_zoom = clampf(value, WORKSPACE_ZOOM_MIN, WORKSPACE_ZOOM_MAX)
	if _preview_zoom_slider != null and not is_equal_approx(_preview_zoom_slider.value, _preview_zoom):
		_preview_zoom_slider.set_value_no_signal(_preview_zoom)
	_update_preview_zoom_label()
	_apply_preview_zoom()
	_sync_workspace_editor_origin()


func _install_workspace_toolbar() -> void:
	var box := _main_live_box()
	if box == null:
		return
	var tool_row := HBoxContainer.new()
	tool_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "Direct bone tool"
	label.custom_minimum_size = Vector2(145.0, 0.0)
	tool_row.add_child(label)
	var group := ButtonGroup.new()
	_workspace_rotate_button = Button.new()
	_workspace_rotate_button.text = "ROTATE"
	_workspace_rotate_button.toggle_mode = true
	_workspace_rotate_button.button_group = group
	_workspace_rotate_button.focus_mode = Control.FOCUS_NONE
	_workspace_rotate_button.button_pressed = true
	_workspace_rotate_button.tooltip_text = "Click a bone and drag to rotate it. Shift-drag edits roll."
	_workspace_rotate_button.pressed.connect(_on_workspace_tool_pressed.bind("rotate"))
	tool_row.add_child(_workspace_rotate_button)
	_workspace_move_button = Button.new()
	_workspace_move_button.text = "MOVE"
	_workspace_move_button.toggle_mode = true
	_workspace_move_button.button_group = group
	_workspace_move_button.focus_mode = Control.FOCUS_NONE
	_workspace_move_button.tooltip_text = "Click a bone and drag to move it in X/Z. Alt-drag uses X/Y."
	_workspace_move_button.pressed.connect(_on_workspace_tool_pressed.bind("move"))
	tool_row.add_child(_workspace_move_button)
	var reset_pan := Button.new()
	reset_pan.text = "CENTER VIEW"
	reset_pan.focus_mode = Control.FOCUS_NONE
	reset_pan.tooltip_text = "Reset viewport pan without changing the animation or bone tuning."
	reset_pan.pressed.connect(_center_workspace_view)
	tool_row.add_child(reset_pan)

	var hint := Label.new()
	hint.text = "Wheel = zoom · middle mouse drag = pan · left click = select bone · left drag = edit · Ctrl+Z = undo · Ctrl+Shift+Z / Ctrl+Y = redo"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tool_row)
	box.add_child(hint)
	if _preview_zoom_slider != null and _preview_zoom_slider.get_parent() != null:
		var zoom_row := _preview_zoom_slider.get_parent() as Control
		var insert_index := zoom_row.get_index() + 1
		box.move_child(tool_row, insert_index)
		box.move_child(hint, insert_index + 1)


func _on_workspace_tool_pressed(mode: String) -> void:
	if _workspace_editor != null and _workspace_editor.has_method("set_transform_mode"):
		_workspace_editor.call("set_transform_mode", mode)


func _install_workspace_viewport_editor() -> void:
	if host == null:
		return
	_workspace_holder = _find_subviewport_container(host)
	if _workspace_holder == null:
		_set_status("Bone viewport workspace could not find the animation SubViewportContainer.", true)
		return
	_workspace_viewport = _find_subviewport(_workspace_holder)
	if _workspace_viewport == null:
		_set_status("Bone viewport workspace could not find the animation SubViewport.", true)
		return

	var editor_value: Variant = BoneViewportEditorScript.new()
	if not editor_value is Control:
		_set_status("Bone viewport editor could not be created.", true)
		return
	_workspace_editor = editor_value as Control
	_workspace_editor.name = "InteractiveBoneViewportOverlay"
	_workspace_editor.mouse_filter = Control.MOUSE_FILTER_STOP
	_workspace_editor.z_index = 100
	_workspace_holder.add_child(_workspace_editor)
	_workspace_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workspace_editor.connect("bone_selected", Callable(self, "_on_workspace_bone_selected"))
	_workspace_editor.connect("bone_transform_started", Callable(self, "_on_workspace_bone_transform_started"))
	_workspace_editor.connect("bone_transform_delta", Callable(self, "_on_workspace_bone_transform_delta"))
	_workspace_editor.connect("bone_transform_finished", Callable(self, "_on_workspace_bone_transform_finished"))
	_workspace_editor.connect("zoom_requested", Callable(self, "_on_workspace_zoom_requested"))
	_workspace_editor.connect("pan_requested", Callable(self, "_on_workspace_pan_requested"))
	_workspace_editor.call("set_transform_mode", "rotate")
	if not selected_part.is_empty():
		_workspace_editor.call("set_selected_bone", selected_part)
	if not _workspace_holder.resized.is_connected(_sync_workspace_viewport_geometry):
		_workspace_holder.resized.connect(_sync_workspace_viewport_geometry)
	_refresh_workspace_editor_rig()
	_sync_workspace_viewport_geometry()


func _find_subviewport_container(node: Node) -> SubViewportContainer:
	if node is SubViewportContainer:
		return node as SubViewportContainer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_subviewport_container(child)
		if found != null:
			return found
	return null


func _find_subviewport(node: Node) -> SubViewport:
	if node is SubViewport:
		return node as SubViewport
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_subviewport(child)
		if found != null:
			return found
	return null


func _sync_workspace_viewport_geometry() -> void:
	if _workspace_holder == null or _workspace_viewport == null:
		return
	var width := maxi(1, roundi(_workspace_holder.size.x))
	var height := maxi(1, roundi(_workspace_holder.size.y))
	_workspace_viewport.size = Vector2i(width, height)
	if _workspace_editor != null:
		_workspace_editor.position = Vector2.ZERO
		_workspace_editor.size = Vector2(width, height)
	_sync_workspace_editor_origin()


func _sync_workspace_editor_origin() -> void:
	if _workspace_holder == null or _workspace_viewport == null or host == null:
		return
	var preview_world_value: Variant = host.get("preview_world")
	if not preview_world_value is Node2D:
		return
	var preview_world := preview_world_value as Node2D
	var center := Vector2(float(_workspace_viewport.size.x) * 0.5, float(_workspace_viewport.size.y) * 0.5 + WORKSPACE_PREVIEW_Y_OFFSET)
	preview_world.position = center + _workspace_pan
	if _workspace_editor != null:
		_workspace_editor.call("set_preview_origin", preview_world.position)


func _refresh_workspace_editor_rig() -> void:
	if _workspace_editor == null:
		return
	var rig_value: Variant = _rig()
	if not rig_value is Node2D:
		return
	var origin := Vector2.ZERO
	if host != null:
		var preview_world_value: Variant = host.get("preview_world")
		if preview_world_value is Node2D:
			origin = (preview_world_value as Node2D).position
	_workspace_editor.call("configure", rig_value as Node2D, origin)
	if not selected_part.is_empty():
		_workspace_editor.call("set_selected_bone", selected_part)


func _replace_host_rig(profile_id: String) -> bool:
	var ok := super._replace_host_rig(profile_id)
	if ok and _workspace_editor != null:
		call_deferred("_refresh_workspace_editor_rig")
		call_deferred("_sync_workspace_editor_origin")
	return ok


func _on_workspace_zoom_requested(factor: float) -> void:
	var next_zoom := clampf(_preview_zoom * factor, WORKSPACE_ZOOM_MIN, WORKSPACE_ZOOM_MAX)
	if _preview_zoom_slider != null:
		_preview_zoom_slider.value = next_zoom
	else:
		_on_preview_zoom_changed(next_zoom)


func _on_workspace_pan_requested(delta: Vector2) -> void:
	_workspace_pan += delta
	_sync_workspace_editor_origin()


func _center_workspace_view() -> void:
	_workspace_pan = Vector2.ZERO
	_sync_workspace_editor_origin()


func _on_workspace_bone_selected(bone_name: String) -> void:
	if bone_name.is_empty():
		return
	selected_part = bone_name
	_select_part_in_list(selected_part)
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object := rig_value as Object
		if rig_object.has_method("set_selected_sprite_part"):
			rig_object.call("set_selected_sprite_part", selected_part)
	_sync_adjustment_controls()
	_refresh_live_inspection(true)
	if _workspace_editor != null:
		_workspace_editor.call("set_selected_bone", selected_part)


func _on_part_selected(index: int) -> void:
	super._on_part_selected(index)
	if _workspace_editor != null:
		_workspace_editor.call("set_selected_bone", selected_part)


func _on_visual_layer_selected(index: int) -> void:
	super._on_visual_layer_selected(index)
	if _workspace_editor != null:
		_workspace_editor.call("set_selected_bone", selected_part)


func _on_workspace_bone_transform_started(_bone_name: String) -> void:
	if not _viewport_drag_active:
		_push_undo_snapshot()
	_viewport_drag_active = true


func _on_workspace_bone_transform_finished(_bone_name: String) -> void:
	_viewport_drag_active = false


func _on_workspace_bone_transform_delta(bone_name: String, transform_mode: String, delta_value: Vector3) -> void:
	if bone_name.is_empty():
		return
	if selected_part != bone_name:
		_on_workspace_bone_selected(bone_name)
	_suppress_ui = true
	if transform_mode == "move":
		move_x.value += delta_value.x
		move_y.value += delta_value.y
		move_z.value += delta_value.z
	else:
		rot_yaw.value += delta_value.x
		rot_pitch.value += delta_value.y
		rot_roll.value += delta_value.z
	_suppress_ui = false
	super._on_adjustment_changed(0.0)
	_refresh_live_inspection(true)


# Editing scope must never implicitly alter playback state. The legacy panel
# paused whenever CURRENT FRAME ONLY was selected, which made animation editing
# feel broken even though the runtime itself was healthy.
func _on_scope_selected(index: int) -> void:
	var was_playing := _workspace_is_playing()
	super._on_scope_selected(index)
	_set_playback_state(was_playing)


func _on_autoplay_toggled(enabled: bool) -> void:
	_set_playback_state(enabled)


func _toggle_playback() -> void:
	var next_state := not _workspace_is_playing()
	if autoplay_check != null:
		autoplay_check.set_pressed_no_signal(next_state)
	_set_playback_state(next_state)


func _on_tab_changed(_index: int) -> void:
	if not is_visible_in_tree():
		_set_playback_state(false)
		return
	if autoplay_check != null and autoplay_check.button_pressed:
		_set_playback_state(true)


func _load_selected_animation() -> void:
	super._load_selected_animation()
	_clear_workspace_history()
	_refresh_workspace_editor_rig()
	if autoplay_check != null and autoplay_check.button_pressed:
		_set_playback_state(true)


func _workspace_is_playing() -> bool:
	if play_button == null:
		return autoplay_check != null and autoplay_check.button_pressed
	return play_button.text == "Pause"


func _on_adjustment_changed(value: float) -> void:
	if not _suppress_ui and not _restoring_history and not _viewport_drag_active and not selected_part.is_empty():
		_push_undo_snapshot()
	super._on_adjustment_changed(value)


func _reset_selected_correction() -> void:
	if not _restoring_history and not selected_part.is_empty():
		_push_undo_snapshot()
	super._reset_selected_correction()


func _push_undo_snapshot() -> void:
	if _restoring_history:
		return
	_undo_stack.append(working_tuning.duplicate(true))
	while _undo_stack.size() > WORKSPACE_UNDO_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _clear_workspace_history() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_viewport_drag_active = false


func _undo_workspace_edit() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(working_tuning.duplicate(true))
	var previous: Dictionary = _undo_stack.pop_back() as Dictionary
	_restore_workspace_tuning(previous)
	_set_status("Undo bone tuning · Ctrl+Shift+Z or Ctrl+Y to redo.")


func _redo_workspace_edit() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(working_tuning.duplicate(true))
	var next_state: Dictionary = _redo_stack.pop_back() as Dictionary
	_restore_workspace_tuning(next_state)
	_set_status("Redo bone tuning.")


func _restore_workspace_tuning(snapshot: Dictionary) -> void:
	_restoring_history = true
	working_tuning = snapshot.duplicate(true)
	_apply_working_tuning()
	_sync_adjustment_controls()
	_restoring_history = false
	_refresh_live_inspection(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if not key.ctrl_pressed and not key.meta_pressed:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	if key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo_workspace_edit()
		else:
			_undo_workspace_edit()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_Y:
		_redo_workspace_edit()
		get_viewport().set_input_as_handled()
