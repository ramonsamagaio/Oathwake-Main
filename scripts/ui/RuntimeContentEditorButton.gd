extends Button

const CONTENT_EDITOR_SCENE := preload("res://tools/content_editor/ContentEditor.tscn")
const EDITOR_MIN_SIZE := Vector2i(760, 500)
const EDITOR_DEFAULT_VIEWPORT_RATIO := 0.88
const EDITOR_EDGE_MARGIN := 12
const EDITOR_TITLE_SAFE_MARGIN := 40
const EDITOR_CLAMP_INTERVAL := 0.08
const EDITOR_GEOMETRY_PATH := "user://content_editor_embedded_window_v2.json"

var _editor_window: Window
var _editor_instance: Control
var _is_closing := false
var _is_exiting := false
var _clamp_elapsed := 0.0


func _ready() -> void:
	add_to_group("runtime_content_editor_launcher")
	focus_mode = Control.FOCUS_NONE
	text = "⚙"
	tooltip_text = "Open or close the live Content Editor"
	visible = OS.is_debug_build()
	pressed.connect(_toggle_content_editor)
	set_process(false)
	set_process_unhandled_key_input(true)


func _process(delta: float) -> void:
	if _editor_window == null or not is_instance_valid(_editor_window) or not _editor_window.visible:
		set_process(false)
		return
	_clamp_elapsed += delta
	if _clamp_elapsed < EDITOR_CLAMP_INTERVAL:
		return
	_clamp_elapsed = 0.0
	_clamp_editor_window_to_viewport()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		if _editor_window != null and is_instance_valid(_editor_window) and _editor_window.visible:
			_close_content_editor()
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_is_exiting = true
	set_process(false)
	if _editor_instance != null and is_instance_valid(_editor_instance) and _editor_instance.has_method("prepare_for_runtime_close"):
		_editor_instance.call("prepare_for_runtime_close")
	if _editor_window != null and is_instance_valid(_editor_window):
		_editor_window.hide()
		_editor_window.process_mode = Node.PROCESS_MODE_DISABLED
		_editor_window.queue_free()
	_editor_window = null
	_editor_instance = null


func _toggle_content_editor() -> void:
	if _is_closing:
		return
	if _editor_window != null and is_instance_valid(_editor_window):
		if _editor_window.visible:
			_close_content_editor()
			return
		_editor_window.show()
		recenter_runtime_editor()
		_editor_window.grab_focus()
		set_process(true)
		return
	_open_content_editor()


func _open_content_editor() -> void:
	if _is_closing:
		return
	if CONTENT_EDITOR_SCENE == null:
		push_error("Runtime Content Editor scene is unavailable.")
		return

	var root_window := get_tree().root
	if root_window == null:
		push_error("Runtime Content Editor could not find the root Window.")
		return

	# Keep the editor in the game's existing viewport. A native secondary Window
	# creates another presentation surface and can destabilize Vulkan when the game
	# itself is embedded in the Godot editor.
	root_window.gui_embed_subwindows = true

	_editor_window = Window.new()
	_editor_window.name = "RuntimeContentEditorWindow"
	_editor_window.title = "Oathwake Content Editor • Live"
	_editor_window.force_native = false
	_editor_window.unresizable = false
	_editor_window.borderless = false
	_editor_window.exclusive = false
	_editor_window.transient = false
	_editor_window.always_on_top = false
	_editor_window.wrap_controls = false
	_editor_window.close_requested.connect(_close_content_editor)
	_configure_editor_window_geometry(root_window)
	root_window.add_child(_editor_window)

	_editor_instance = CONTENT_EDITOR_SCENE.instantiate() as Control
	if _editor_instance == null:
		push_error("Runtime Content Editor could not be instantiated.")
		_close_content_editor()
		return
	_editor_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	_editor_instance.offset_left = 0.0
	_editor_instance.offset_top = 0.0
	_editor_instance.offset_right = 0.0
	_editor_instance.offset_bottom = 0.0
	_editor_window.add_child(_editor_instance)
	_editor_window.show()
	_clamp_elapsed = 0.0
	set_process(true)
	call_deferred("_finish_opening_runtime_editor")
	call_deferred("_open_default_post_effects")


func _finish_opening_runtime_editor() -> void:
	if _is_closing or _is_exiting:
		return
	if _editor_window == null or not is_instance_valid(_editor_window) or not _editor_window.is_inside_tree():
		return
	_editor_window.unresizable = false
	_editor_window.borderless = false
	recenter_runtime_editor()
	_editor_window.grab_focus()


func _configure_editor_window_geometry(root_window: Window) -> void:
	if _editor_window == null or root_window == null:
		return
	var available_size := _get_embedder_size(root_window)
	var maximum_size := _maximum_editor_size(available_size)
	var effective_min := Vector2i(
		mini(EDITOR_MIN_SIZE.x, maximum_size.x),
		mini(EDITOR_MIN_SIZE.y, maximum_size.y)
	)
	_editor_window.min_size = effective_min

	var geometry := _load_editor_geometry()
	var default_size := Vector2i(
		int(round(float(available_size.x) * EDITOR_DEFAULT_VIEWPORT_RATIO)),
		int(round(float(available_size.y) * EDITOR_DEFAULT_VIEWPORT_RATIO))
	)
	var target_size := _dictionary_vector2i(geometry, "size", default_size)
	target_size = Vector2i(
		clampi(target_size.x, effective_min.x, maximum_size.x),
		clampi(target_size.y, effective_min.y, maximum_size.y)
	)

	_editor_window.size = target_size
	# Position is intentionally not restored. Saved coordinates become invalid when
	# the game is maximized, moved to another display, or changes aspect ratio.
	_editor_window.position = _centered_editor_position(available_size, target_size)


func _clamp_editor_window_to_viewport() -> void:
	if _editor_window == null or not is_instance_valid(_editor_window) or not _editor_window.is_inside_tree():
		return
	var root_window := get_tree().root
	if root_window == null:
		return
	var available_size := _get_embedder_size(root_window)
	var maximum_size := _maximum_editor_size(available_size)
	var effective_min := Vector2i(
		mini(EDITOR_MIN_SIZE.x, maximum_size.x),
		mini(EDITOR_MIN_SIZE.y, maximum_size.y)
	)
	_editor_window.min_size = effective_min
	var clamped_size := Vector2i(
		clampi(_editor_window.size.x, effective_min.x, maximum_size.x),
		clampi(_editor_window.size.y, effective_min.y, maximum_size.y)
	)
	if clamped_size != _editor_window.size:
		_editor_window.size = clamped_size

	var minimum_position := Vector2i(EDITOR_EDGE_MARGIN, EDITOR_TITLE_SAFE_MARGIN)
	var maximum_position := Vector2i(
		maxi(minimum_position.x, available_size.x - clamped_size.x - EDITOR_EDGE_MARGIN),
		maxi(minimum_position.y, available_size.y - clamped_size.y - EDITOR_EDGE_MARGIN)
	)
	var clamped_position := Vector2i(
		clampi(_editor_window.position.x, minimum_position.x, maximum_position.x),
		clampi(_editor_window.position.y, minimum_position.y, maximum_position.y)
	)
	if clamped_position != _editor_window.position:
		_editor_window.position = clamped_position


func recenter_runtime_editor() -> void:
	if _editor_window == null or not is_instance_valid(_editor_window):
		return
	var root_window := get_tree().root
	if root_window == null:
		return
	var available_size := _get_embedder_size(root_window)
	var maximum_size := _maximum_editor_size(available_size)
	_editor_window.size = Vector2i(
		mini(_editor_window.size.x, maximum_size.x),
		mini(_editor_window.size.y, maximum_size.y)
	)
	_editor_window.position = _centered_editor_position(available_size, _editor_window.size)
	_clamp_editor_window_to_viewport()


func _centered_editor_position(available_size: Vector2i, editor_size: Vector2i) -> Vector2i:
	var centered := (available_size - editor_size) / 2
	return Vector2i(
		maxi(EDITOR_EDGE_MARGIN, centered.x),
		maxi(EDITOR_TITLE_SAFE_MARGIN, centered.y)
	)


func _maximum_editor_size(available_size: Vector2i) -> Vector2i:
	return Vector2i(
		maxi(1, available_size.x - EDITOR_EDGE_MARGIN * 2),
		maxi(1, available_size.y - EDITOR_TITLE_SAFE_MARGIN - EDITOR_EDGE_MARGIN)
	)


func _get_embedder_size(root_window: Window) -> Vector2i:
	var visible_size := Vector2i(root_window.get_visible_rect().size)
	if visible_size.x <= 0 or visible_size.y <= 0:
		visible_size = root_window.size
	if visible_size.x <= 0 or visible_size.y <= 0:
		visible_size = Vector2i(1600, 900)
	return visible_size


func _load_editor_geometry() -> Dictionary:
	if not FileAccess.file_exists(EDITOR_GEOMETRY_PATH):
		return {}
	var file := FileAccess.open(EDITOR_GEOMETRY_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary) if parsed is Dictionary else {}


func _save_editor_geometry() -> void:
	if _editor_window == null or not is_instance_valid(_editor_window):
		return
	var file := FileAccess.open(EDITOR_GEOMETRY_PATH, FileAccess.WRITE)
	if file == null:
		return
	# Only size is persistent. Position is always recalculated from the current
	# viewport so a stale monitor or maximized-window coordinate can never strand it.
	file.store_string(JSON.stringify({
		"size": {
			"x": _editor_window.size.x,
			"y": _editor_window.size.y,
		},
	}, "\t") + "\n")


func _dictionary_vector2i(source: Dictionary, key: String, fallback: Vector2i) -> Vector2i:
	var value: Variant = source.get(key, {})
	if value is Dictionary:
		return Vector2i(
			int((value as Dictionary).get("x", fallback.x)),
			int((value as Dictionary).get("y", fallback.y))
		)
	return fallback


func _close_content_editor() -> void:
	if _is_closing:
		return
	if _editor_window == null or not is_instance_valid(_editor_window):
		_editor_window = null
		_editor_instance = null
		set_process(false)
		return

	_is_closing = true
	set_process(false)
	_save_editor_geometry()
	var window_to_close := _editor_window
	var editor_to_close := _editor_instance
	_editor_window = null
	_editor_instance = null

	if editor_to_close != null and is_instance_valid(editor_to_close) and editor_to_close.has_method("prepare_for_runtime_close"):
		editor_to_close.call("prepare_for_runtime_close")

	window_to_close.hide()
	window_to_close.process_mode = Node.PROCESS_MODE_DISABLED
	call_deferred("_finalize_content_editor_close", window_to_close)


func _finalize_content_editor_close(window_to_close: Window) -> void:
	if is_instance_valid(window_to_close):
		if window_to_close.is_inside_tree():
			window_to_close.queue_free()
			await window_to_close.tree_exited
		else:
			window_to_close.free()
	if _is_exiting or not is_inside_tree():
		return
	_is_closing = false


func _open_default_post_effects() -> void:
	if _is_closing or _is_exiting:
		return
	if _editor_instance == null or not is_instance_valid(_editor_instance) or not _editor_instance.is_inside_tree():
		return
	if _editor_instance.has_method("_select_section"):
		_editor_instance.call("_select_section", "post_effects", true)


func get_runtime_editor_window() -> Window:
	return _editor_window if _editor_window != null and is_instance_valid(_editor_window) else null


func is_runtime_editor_closing() -> bool:
	return _is_closing
