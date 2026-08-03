class_name WyrdframeSmartStudio
extends "res://tools/sprite_pose_lab/scripts/WyrdframePixelStudio.gd"

const SmartCanvasScript: Script = preload("res://tools/sprite_pose_lab/scripts/WyrdframeSmartPixelCanvas.gd")

const KEYFRAME_ADD: int = 1
const KEYFRAME_REMOVE: int = 2

var cleanup_check: CheckBox
var tween_check: CheckBox
var keyframe_menu: PopupMenu
var _context_frame: int = 0
var _context_bone: String = ""


func _build_preview_panel() -> Control:
	var result: Control = super._build_preview_panel()
	var column: VBoxContainer = result as VBoxContainer
	if column.get_child_count() > 0:
		var toolbar_scroll: ScrollContainer = column.get_child(0) as ScrollContainer
		if toolbar_scroll != null and toolbar_scroll.get_child_count() > 0:
			var toolbar: HBoxContainer = toolbar_scroll.get_child(0) as HBoxContainer
			cleanup_check = _check("Cleanup", false, Callable(self, "_on_view_setting_changed"))
			cleanup_check.tooltip_text = "Remove bicos, espinhos curtos e pixels órfãos gerados pela rotação. Compara cada pixel com a silhueta original e preserva detalhes que realmente existiam no PNG."
			toolbar.add_child(cleanup_check)
			var outline_index: int = toolbar.get_children().find(preserve_outline_check)
			if outline_index >= 0:
				toolbar.move_child(cleanup_check, outline_index + 1)
	return result


func _build_timeline_panel() -> Control:
	var result: Control = super._build_timeline_panel()
	var column: VBoxContainer = result as VBoxContainer
	if column.get_child_count() > 0:
		var toolbar_scroll: ScrollContainer = column.get_child(0) as ScrollContainer
		if toolbar_scroll != null and toolbar_scroll.get_child_count() > 0:
			var toolbar: HBoxContainer = toolbar_scroll.get_child(0) as HBoxContainer
			tween_check = _check("Tween", false, Callable(self, "_on_tween_changed"))
			tween_check.tooltip_text = "Interpola posição, pivô e rotação entre os keyframes verdes de cada bone. Ctrl+K adiciona ou remove uma key no quadro selecionado."
			toolbar.add_child(tween_check)
			if frame_label != null:
				toolbar.move_child(tween_check, mini(frame_label.get_index() + 1, toolbar.get_child_count() - 1))
	return result


func _build_rendering() -> void:
	render_viewport = SubViewport.new()
	render_viewport.transparent_bg = true
	render_viewport.disable_3d = true
	render_viewport.msaa_2d = Viewport.MSAA_DISABLED
	render_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(render_viewport)
	canvas_renderer = SmartCanvasScript.new()
	render_viewport.add_child(canvas_renderer)
	preview.texture = render_viewport.get_texture()
	_apply_render()


func _build_runtime_helpers() -> void:
	super._build_runtime_helpers()
	keyframe_menu = PopupMenu.new()
	keyframe_menu.add_item("Add Keyframe", KEYFRAME_ADD)
	keyframe_menu.add_item("Remove Keyframe", KEYFRAME_REMOVE)
	keyframe_menu.id_pressed.connect(Callable(self, "_on_keyframe_menu_selected"))
	add_child(keyframe_menu)


func _view_settings() -> Dictionary:
	var settings: Dictionary = super._view_settings()
	settings["cleanup_pixels"] = cleanup_check != null and cleanup_check.button_pressed
	return settings


func _ensure_advanced_editor_data() -> void:
	super._ensure_advanced_editor_data()
	if document.is_empty():
		return
	var playback_data: Dictionary = _playback_section()
	if not playback_data.has("tween_enabled"):
		playback_data["tween_enabled"] = false


func _refresh_controls() -> void:
	super._refresh_controls()
	if tween_check == null:
		return
	updating_ui = true
	tween_check.button_pressed = bool(_playback_section().get("tween_enabled", false))
	updating_ui = false


func _on_tween_changed(value: bool) -> void:
	if updating_ui:
		return
	_record_history()
	_playback_section()["tween_enabled"] = value
	_mark_changed("Motion tween ativado entre keyframes." if value else "Motion tween desativado.", false)


func _on_timeline_cell_input(event: InputEvent, frame_index_value: int, bone_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	current_frame = frame_index_value
	selected_bone = bone_id
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_refresh_context()
		_show_keyframe_menu(mouse_event.global_position, frame_index_value, bone_id)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_refresh_context()


func _show_keyframe_menu(global_position: Vector2, frame_index_value: int, bone_id: String) -> void:
	if keyframe_menu == null:
		return
	_context_frame = frame_index_value
	_context_bone = bone_id
	var keyed: bool = _is_keyed(frame_index_value, bone_id)
	var add_index: int = keyframe_menu.get_item_index(KEYFRAME_ADD)
	var remove_index: int = keyframe_menu.get_item_index(KEYFRAME_REMOVE)
	keyframe_menu.set_item_disabled(add_index, keyed)
	keyframe_menu.set_item_disabled(remove_index, not keyed)
	keyframe_menu.position = Vector2i(global_position)
	keyframe_menu.popup()


func _on_keyframe_menu_selected(menu_id: int) -> void:
	current_frame = clampi(_context_frame, 0, maxi(0, _frames().size() - 1))
	if not _bone_by_id(_context_bone).is_empty():
		selected_bone = _context_bone
	if menu_id == KEYFRAME_ADD:
		_set_keyframe(current_frame, selected_bone, true)
	elif menu_id == KEYFRAME_REMOVE:
		_set_keyframe(current_frame, selected_bone, false)


func _toggle_selected_keyframe() -> void:
	_set_keyframe(current_frame, selected_bone, not _is_keyed(current_frame, selected_bone))


func _set_keyframe(frame_index_value: int, bone_id: String, enabled: bool) -> void:
	if _bone_by_id(bone_id).is_empty():
		return
	var frame_data: Dictionary = _frame_data(frame_index_value)
	var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
	if enabled and keys.has(bone_id):
		return
	if not enabled and not keys.has(bone_id):
		return
	_record_history()
	if enabled:
		# Capture the exact displayed pose, including an in-between tweened pose.
		keys[bone_id] = _resolved_transform(frame_index_value, bone_id).duplicate(true)
		_set_status("Keyframe adicionado. Ctrl+K remove.")
	else:
		keys.erase(bone_id)
		_set_status("Keyframe removido. Ctrl+K adiciona.")
	frame_data["keys"] = keys
	dirty = true
	if autosave_timer != null:
		autosave_timer.start()
	_refresh_context()


func _rebuild_timeline() -> void:
	super._rebuild_timeline()
	_style_keyframe_cells()


func _style_keyframe_cells() -> void:
	if timeline_grid == null:
		return
	var frame_count: int = _frames().size()
	var child_index: int = 1 + frame_count
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		child_index += 1 # row label
		for frame_index_value: int in range(frame_count):
			if child_index >= timeline_grid.get_child_count():
				return
			var cell: Button = timeline_grid.get_child(child_index) as Button
			child_index += 1
			if cell == null:
				continue
			var keyed: bool = _is_keyed(frame_index_value, bone_id)
			var selected: bool = frame_index_value == current_frame and bone_id == selected_bone
			cell.text = "◆" if keyed else "·"
			cell.tooltip_text = "Clique: selecionar. Botão direito: Add/Remove Keyframe. Ctrl+K alterna a key."
			if keyed:
				var border_color: Color = Color(0.35, 0.9, 0.63) if selected else Color(0.16, 0.56, 0.36)
				cell.add_theme_stylebox_override("normal", _style_box(Color(0.08, 0.31, 0.2), border_color, 1))
				cell.add_theme_stylebox_override("hover", _style_box(Color(0.1, 0.43, 0.27), Color(0.4, 1.0, 0.69), 1))
				cell.add_theme_stylebox_override("pressed", _style_box(Color(0.12, 0.52, 0.32), Color(0.58, 1.0, 0.78), 2))
				cell.modulate = Color(0.82, 1.0, 0.9)
			elif selected:
				cell.add_theme_stylebox_override("normal", _style_box(Color(0.08, 0.25, 0.36), Color(0.3, 0.8, 1.0), 1))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.ctrl_pressed and key_event.keycode == KEY_K:
			_toggle_selected_keyframe()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_key_input(event)


func _resolved_transform(frame_index_value: int, bone_id: String) -> Dictionary:
	if not bool(_playback_section().get("tween_enabled", false)):
		return super._resolved_transform(frame_index_value, bone_id)
	return _tweened_transform(frame_index_value, bone_id)


func _tweened_transform(frame_index_value: int, bone_id: String) -> Dictionary:
	var bone_data: Dictionary = _bone_by_id(bone_id)
	var rest_data: Dictionary = bone_data.get("rest", {}) as Dictionary
	var frames_value: Array = _frames()
	if frames_value.is_empty():
		return rest_data.duplicate(true)
	var safe_frame: int = clampi(frame_index_value, 0, frames_value.size() - 1)
	var exact_keys: Dictionary = (frames_value[safe_frame] as Dictionary).get("keys", {}) as Dictionary
	if exact_keys.has(bone_id):
		return (exact_keys[bone_id] as Dictionary).duplicate(true)

	var previous_index: int = -1
	var next_index: int = -1
	for index: int in range(safe_frame - 1, -1, -1):
		var keys: Dictionary = (frames_value[index] as Dictionary).get("keys", {}) as Dictionary
		if keys.has(bone_id):
			previous_index = index
			break
	for index: int in range(safe_frame + 1, frames_value.size()):
		var keys: Dictionary = (frames_value[index] as Dictionary).get("keys", {}) as Dictionary
		if keys.has(bone_id):
			next_index = index
			break

	if previous_index < 0:
		return rest_data.duplicate(true)
	var previous_keys: Dictionary = (frames_value[previous_index] as Dictionary).get("keys", {}) as Dictionary
	var previous_data: Dictionary = (previous_keys[bone_id] as Dictionary).duplicate(true)
	if next_index < 0:
		return previous_data
	var next_keys: Dictionary = (frames_value[next_index] as Dictionary).get("keys", {}) as Dictionary
	var next_data: Dictionary = next_keys[bone_id] as Dictionary
	var ratio: float = float(safe_frame - previous_index) / float(next_index - previous_index)
	return _interpolate_transform(previous_data, next_data, ratio)


func _interpolate_transform(from_data: Dictionary, to_data: Dictionary, ratio: float) -> Dictionary:
	var t: float = clampf(ratio, 0.0, 1.0)
	var from_position: Vector2 = _vec(from_data.get("position", [0.0, 0.0]))
	var to_position: Vector2 = _vec(to_data.get("position", [0.0, 0.0]))
	var from_pivot: Vector2 = _vec(from_data.get("pivot", [0.0, 0.0]))
	var to_pivot: Vector2 = _vec(to_data.get("pivot", [0.0, 0.0]))
	var from_angle: float = deg_to_rad(float(from_data.get("rotation_degrees", 0.0)))
	var to_angle: float = deg_to_rad(float(to_data.get("rotation_degrees", 0.0)))
	var angle_delta: float = wrapf(to_angle - from_angle, -PI, PI)
	var position_value: Vector2 = from_position.lerp(to_position, t)
	var pivot_value: Vector2 = from_pivot.lerp(to_pivot, t)
	if pixel_snap_check != null and pixel_snap_check.button_pressed:
		position_value = position_value.round()
		pivot_value = pivot_value.round()
	return {
		"position": [position_value.x, position_value.y],
		"rotation_degrees": rad_to_deg(from_angle + angle_delta * t),
		"pivot": [pivot_value.x, pivot_value.y],
		"z_index": int(from_data.get("z_index", 0)),
		"visible": bool(from_data.get("visible", true)),
	}


func _run_smoke_test() -> void:
	await get_tree().process_frame

	var source: Image = Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	source.fill(Color.TRANSPARENT)
	var output: Image = Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for y_value: int in range(2, 5):
		for x_value: int in range(2, 5):
			source.set_pixel(x_value, y_value, Color(0.2, 0.7, 0.3, 1.0))
			output.set_pixel(x_value, y_value, Color(0.2, 0.7, 0.3, 1.0))
	output.set_pixel(5, 3, Color(0.04, 0.05, 0.06, 1.0))
	canvas_renderer._cleanup_generated_artifacts(output, source, Transform2D.IDENTITY)
	if output.get_pixel(5, 3).a > 0.05:
		push_error("WYRD_FRAME_SMART_FAIL: cleanup kept unsupported spur")
		get_tree().quit(94)
		return

	var test_bone: String = "left_arm" if not _bone_by_id("left_arm").is_empty() else selected_bone
	var frames_value: Array = _frames()
	if frames_value.size() >= 3:
		var first_keys: Dictionary = (frames_value[0] as Dictionary).get("keys", {}) as Dictionary
		var middle_keys: Dictionary = (frames_value[1] as Dictionary).get("keys", {}) as Dictionary
		var last_keys: Dictionary = (frames_value[2] as Dictionary).get("keys", {}) as Dictionary
		var first_pose: Dictionary = _resolved_transform(0, test_bone)
		var last_pose: Dictionary = first_pose.duplicate(true)
		first_pose["position"] = [0.0, 0.0]
		last_pose["position"] = [10.0, 0.0]
		first_keys[test_bone] = first_pose
		middle_keys.erase(test_bone)
		last_keys[test_bone] = last_pose
		_playback_section()["tween_enabled"] = true
		var middle_pose: Dictionary = _tweened_transform(1, test_bone)
		var middle_position: Vector2 = _vec(middle_pose.get("position", [0.0, 0.0]))
		if not is_equal_approx(middle_position.x, 5.0):
			push_error("WYRD_FRAME_SMART_FAIL: tween midpoint is incorrect")
			get_tree().quit(95)
			return

	print("WYRD_FRAME_GRID_LOCK_TWEEN_CLEANUP_OK")
	await super._run_smoke_test()
