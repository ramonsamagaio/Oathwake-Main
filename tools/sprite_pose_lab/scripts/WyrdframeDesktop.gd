extends "res://tools/sprite_pose_lab/scripts/WyrdframeStudio.gd"

const MIN_DESKTOP_SIZE: Vector2i = Vector2i(1100, 700)

var _canvas_pan_active: bool = false
var _canvas_pan_scroll: ScrollContainer = null
var _canvas_pan_start_mouse: Vector2 = Vector2.ZERO
var _canvas_pan_start_scroll: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_configure_desktop_window()
	_connect_identity_commit_signals()


func _configure_window() -> void:
	_configure_desktop_window()


func _configure_desktop_window() -> void:
	var app_window: Window = get_window()
	app_window.title = PROGRAM_NAME
	app_window.unresizable = false
	app_window.min_size = MIN_DESKTOP_SIZE
	app_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	app_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	app_window.content_scale_factor = 1.0
	if app_window != get_tree().root:
		app_window.force_native = true
		app_window.transient = false
		app_window.exclusive = false
		app_window.mode = Window.MODE_MAXIMIZED
	if not app_window.close_requested.is_connected(_on_desktop_close_requested):
		app_window.close_requested.connect(_on_desktop_close_requested)


func _connect_identity_commit_signals() -> void:
	if project_name_edit != null and not project_name_edit.focus_exited.is_connected(_commit_project_identity):
		project_name_edit.focus_exited.connect(_commit_project_identity)
	if asset_name_edit != null and not asset_name_edit.focus_exited.is_connected(_commit_project_identity):
		asset_name_edit.focus_exited.connect(_commit_project_identity)


func _commit_project_identity() -> void:
	_rebuild_project_tree()
	_update_window_title()


func _on_project_name_changed(value: String) -> void:
	if updating_ui:
		return
	_project_section()["name"] = value
	_mark_identity_dirty()


func _on_asset_name_changed(value: String) -> void:
	if updating_ui:
		return
	_project_section()["asset_name"] = value
	_mark_identity_dirty()


func _mark_identity_dirty() -> void:
	dirty = true
	_update_window_title()
	if autosave_timer != null:
		autosave_timer.start()


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_canvas_at_cursor(1, mouse_event.position)
			preview.accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_canvas_at_cursor(-1, mouse_event.position)
			preview.accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			if mouse_event.pressed:
				_begin_canvas_pan(mouse_event.global_position)
			else:
				_end_canvas_pan()
			preview.accept_event()
			return
	elif event is InputEventMouseMotion and _canvas_pan_active:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		_update_canvas_pan(motion_event.global_position)
		preview.accept_event()
		return
	super._on_preview_input(event)


func _zoom_canvas_at_cursor(step_direction: int, cursor_position: Vector2) -> void:
	if zoom_option == null or zoom_option.item_count <= 0:
		return
	var old_index: int = zoom_option.selected
	var new_index: int = clampi(old_index + step_direction, 0, zoom_option.item_count - 1)
	if new_index == old_index:
		return
	var scroll: ScrollContainer = _find_preview_scroll()
	var old_zoom: float = float(maxi(1, zoom_option.get_selected_id()))
	var old_scroll: Vector2 = Vector2.ZERO
	if scroll != null:
		old_scroll = Vector2(float(scroll.scroll_horizontal), float(scroll.scroll_vertical))
	zoom_option.select(new_index)
	_update_preview_size()
	var new_zoom: float = float(maxi(1, zoom_option.get_selected_id()))
	if scroll != null and old_zoom > 0.0:
		var ratio: float = new_zoom / old_zoom
		var target_scroll: Vector2 = (old_scroll + cursor_position) * ratio - cursor_position
		_set_scroll_deferred(scroll, target_scroll)


func _begin_canvas_pan(mouse_position: Vector2) -> void:
	_canvas_pan_scroll = _find_preview_scroll()
	if _canvas_pan_scroll == null:
		return
	_canvas_pan_active = true
	_canvas_pan_start_mouse = mouse_position
	_canvas_pan_start_scroll = Vector2(
		float(_canvas_pan_scroll.scroll_horizontal),
		float(_canvas_pan_scroll.scroll_vertical)
	)
	preview.mouse_default_cursor_shape = Control.CURSOR_DRAG


func _update_canvas_pan(mouse_position: Vector2) -> void:
	if _canvas_pan_scroll == null:
		return
	var drag_delta: Vector2 = mouse_position - _canvas_pan_start_mouse
	_canvas_pan_scroll.scroll_horizontal = maxi(0, int(round(_canvas_pan_start_scroll.x - drag_delta.x)))
	_canvas_pan_scroll.scroll_vertical = maxi(0, int(round(_canvas_pan_start_scroll.y - drag_delta.y)))


func _end_canvas_pan() -> void:
	_canvas_pan_active = false
	_canvas_pan_scroll = null
	if preview != null:
		preview.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _find_preview_scroll() -> ScrollContainer:
	if preview == null:
		return null
	var cursor: Node = preview.get_parent()
	while cursor != null:
		if cursor is ScrollContainer:
			return cursor as ScrollContainer
		cursor = cursor.get_parent()
	return null


func _set_scroll_deferred(scroll: ScrollContainer, target: Vector2) -> void:
	await get_tree().process_frame
	if not is_instance_valid(scroll):
		return
	scroll.scroll_horizontal = maxi(0, int(round(target.x)))
	scroll.scroll_vertical = maxi(0, int(round(target.y)))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F11:
			_toggle_desktop_fullscreen()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_key_input(event)


func _toggle_desktop_fullscreen() -> void:
	var app_window: Window = get_window()
	if app_window.mode == Window.MODE_FULLSCREEN or app_window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		app_window.mode = Window.MODE_MAXIMIZED
	else:
		app_window.mode = Window.MODE_FULLSCREEN


func _on_desktop_close_requested() -> void:
	get_tree().quit()
