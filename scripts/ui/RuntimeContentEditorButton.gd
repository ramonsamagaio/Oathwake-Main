extends Button

const CONTENT_EDITOR_SCENE := preload("res://tools/content_editor/ContentEditor.tscn")
const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")
const CONTENT_REFRESH_INTERVAL := 0.35
const EDITOR_MIN_SIZE := Vector2i(960, 620)
const EDITOR_DEFAULT_SCREEN_RATIO := 0.90
const EDITOR_SCREEN_MARGIN := 32
const EDITOR_GEOMETRY_PATH := "user://content_editor_window.json"

var _editor_window: Window
var _editor_instance: Control
var _content_hashes: Dictionary = {}
var _refresh_elapsed := 0.0
var _previous_embed_subwindows := true


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = "⚙"
	tooltip_text = "Open or close the live Content Editor"
	visible = OS.is_debug_build()
	pressed.connect(_toggle_content_editor)
	_snapshot_content_hashes()
	set_process(true)
	set_process_unhandled_key_input(true)


func _process(delta: float) -> void:
	if _editor_window == null or not is_instance_valid(_editor_window) or not _editor_window.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < CONTENT_REFRESH_INTERVAL:
		return
	_refresh_elapsed = 0.0
	if _content_files_changed():
		_reload_runtime_content()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		if _editor_window != null and is_instance_valid(_editor_window) and _editor_window.visible:
			_close_content_editor()
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_close_content_editor()


func _toggle_content_editor() -> void:
	if _editor_window != null and is_instance_valid(_editor_window):
		if _editor_window.visible:
			_close_content_editor()
			return
		_editor_window.show()
		_editor_window.grab_focus()
		return
	_open_content_editor()


func _open_content_editor() -> void:
	if CONTENT_EDITOR_SCENE == null:
		push_error("Runtime Content Editor scene is unavailable.")
		return

	var root_window := get_tree().root
	_previous_embed_subwindows = root_window.gui_embed_subwindows
	root_window.gui_embed_subwindows = false

	_editor_window = Window.new()
	_editor_window.name = "RuntimeContentEditorWindow"
	_editor_window.title = "Oathwake Content Editor • Live"
	_editor_window.unresizable = false
	_editor_window.borderless = false
	_editor_window.exclusive = false
	_editor_window.transient = false
	_editor_window.always_on_top = false
	_editor_window.close_requested.connect(_close_content_editor)
	_configure_editor_window_geometry()
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
	_snapshot_content_hashes()
	call_deferred("_finish_opening_runtime_editor")
	call_deferred("_open_default_post_effects")


func _finish_opening_runtime_editor() -> void:
	if _editor_window == null or not is_instance_valid(_editor_window):
		return
	_editor_window.unresizable = false
	_editor_window.borderless = false
	_editor_window.grab_focus()


func _configure_editor_window_geometry() -> void:
	if _editor_window == null:
		return
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		usable_rect = Rect2i(Vector2i.ZERO, Vector2i(1600, 900))

	var effective_min := Vector2i(
		mini(EDITOR_MIN_SIZE.x, usable_rect.size.x),
		mini(EDITOR_MIN_SIZE.y, usable_rect.size.y)
	)
	_editor_window.min_size = effective_min

	var geometry := _load_editor_geometry()
	var default_size := Vector2i(
		int(round(float(usable_rect.size.x) * EDITOR_DEFAULT_SCREEN_RATIO)),
		int(round(float(usable_rect.size.y) * EDITOR_DEFAULT_SCREEN_RATIO))
	)
	var target_size := _dictionary_vector2i(geometry, "size", default_size)
	var maximum_size := Vector2i(
		maxi(effective_min.x, usable_rect.size.x - EDITOR_SCREEN_MARGIN * 2),
		maxi(effective_min.y, usable_rect.size.y - EDITOR_SCREEN_MARGIN * 2)
	)
	target_size = Vector2i(
		clampi(target_size.x, effective_min.x, maximum_size.x),
		clampi(target_size.y, effective_min.y, maximum_size.y)
	)

	var centered_position := usable_rect.position + (usable_rect.size - target_size) / 2
	var target_position := _dictionary_vector2i(geometry, "position", centered_position)
	var max_position := usable_rect.position + usable_rect.size - target_size
	target_position = Vector2i(
		clampi(target_position.x, usable_rect.position.x, maxi(usable_rect.position.x, max_position.x)),
		clampi(target_position.y, usable_rect.position.y, maxi(usable_rect.position.y, max_position.y))
	)

	_editor_window.size = target_size
	_editor_window.position = target_position


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
	if _editor_window.mode != Window.MODE_WINDOWED:
		return
	var file := FileAccess.open(EDITOR_GEOMETRY_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"size": {
			"x": _editor_window.size.x,
			"y": _editor_window.size.y,
		},
		"position": {
			"x": _editor_window.position.x,
			"y": _editor_window.position.y,
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
	_save_editor_geometry()
	if _editor_window != null and is_instance_valid(_editor_window):
		_editor_window.queue_free()
	_editor_window = null
	_editor_instance = null
	_refresh_elapsed = 0.0
	var root_window := get_tree().root if get_tree() != null else null
	if root_window != null:
		root_window.gui_embed_subwindows = _previous_embed_subwindows


func _open_default_post_effects() -> void:
	if _editor_instance == null or not is_instance_valid(_editor_instance):
		return
	if _editor_instance.has_method("_select_section"):
		_editor_instance.call("_select_section", "post_effects", true)


func _snapshot_content_hashes() -> void:
	_content_hashes.clear()
	for path_value in ContentEditorData.SECTION_PATHS.values():
		var path := str(path_value)
		_content_hashes[path] = _content_file_hash(path)


func _content_files_changed() -> bool:
	var changed := false
	for path_value in ContentEditorData.SECTION_PATHS.values():
		var path := str(path_value)
		var current_hash := _content_file_hash(path)
		var previous_hash := str(_content_hashes.get(path, ""))
		if not previous_hash.is_empty() and current_hash != previous_hash:
			changed = true
		_content_hashes[path] = current_hash
	return changed


func _content_file_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_md5(path)


func _reload_runtime_content() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("load_all"):
		content_db.call("load_all")
