extends Button

const CONTENT_EDITOR_SCENE := preload("res://tools/content_editor/ContentEditor.tscn")
const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")
const CONTENT_REFRESH_INTERVAL := 0.35
const EDITOR_INITIAL_SIZE := Vector2i(1440, 900)
const EDITOR_MIN_SIZE := Vector2i(860, 540)

var _editor_window: Window
var _editor_instance: Control
var _content_hashes: Dictionary = {}
var _refresh_elapsed := 0.0
var _previous_embed_subwindows := true
var _game_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var _game_window_size := Vector2i.ZERO
var _game_window_position := Vector2i.ZERO


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
		_editor_window.popup_centered()
		_editor_window.grab_focus()
		return
	_open_content_editor()


func _open_content_editor() -> void:
	if CONTENT_EDITOR_SCENE == null:
		push_error("Runtime Content Editor scene is unavailable.")
		return

	_capture_game_window_state()
	var root_window := get_tree().root
	_previous_embed_subwindows = root_window.gui_embed_subwindows
	root_window.gui_embed_subwindows = false

	_editor_window = Window.new()
	_editor_window.name = "RuntimeContentEditorWindow"
	_editor_window.title = "Oathwake Content Editor • Live"
	_editor_window.size = EDITOR_INITIAL_SIZE
	_editor_window.min_size = EDITOR_MIN_SIZE
	_editor_window.unresizable = false
	_editor_window.borderless = false
	_editor_window.exclusive = false
	_editor_window.transient = false
	_editor_window.always_on_top = false
	_editor_window.close_requested.connect(_close_content_editor)
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
	_editor_window.popup_centered()
	_snapshot_content_hashes()
	call_deferred("_finish_opening_runtime_editor")
	call_deferred("_open_default_vfx_profile")


func _finish_opening_runtime_editor() -> void:
	if _editor_window == null or not is_instance_valid(_editor_window):
		return
	# ContentEditor can also run as the main scene and therefore configures the
	# default DisplayServer window. Restore the gameplay window after embedding
	# it in this dedicated native subwindow.
	_editor_window.min_size = EDITOR_MIN_SIZE
	_editor_window.unresizable = false
	_editor_window.borderless = false
	_restore_game_window_state()
	_editor_window.grab_focus()


func _capture_game_window_state() -> void:
	_game_window_mode = DisplayServer.window_get_mode()
	_game_window_size = DisplayServer.window_get_size()
	_game_window_position = DisplayServer.window_get_position()


func _restore_game_window_state() -> void:
	DisplayServer.window_set_mode(_game_window_mode)
	if _game_window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		if _game_window_size.x > 0 and _game_window_size.y > 0:
			DisplayServer.window_set_size(_game_window_size)
		DisplayServer.window_set_position(_game_window_position)


func _close_content_editor() -> void:
	if _editor_window != null and is_instance_valid(_editor_window):
		_editor_window.queue_free()
	_editor_window = null
	_editor_instance = null
	_refresh_elapsed = 0.0
	var root_window := get_tree().root if get_tree() != null else null
	if root_window != null:
		root_window.gui_embed_subwindows = _previous_embed_subwindows
	_restore_game_window_state()


func _open_default_vfx_profile() -> void:
	if _editor_instance == null or not is_instance_valid(_editor_instance):
		return
	if _editor_instance.has_method("_select_section"):
		_editor_instance.call("_select_section", ContentEditorData.SECTION_VFX_PROFILES, true)


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
