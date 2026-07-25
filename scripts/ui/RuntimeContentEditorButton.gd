extends Button

const CONTENT_EDITOR_SCENE := preload("res://tools/content_editor/ContentEditor.tscn")
const ContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")
const CONTENT_REFRESH_INTERVAL := 0.35

var _editor_window: Window
var _editor_instance: Control
var _content_hashes: Dictionary = {}
var _refresh_elapsed := 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = "⚙"
	tooltip_text = "Open the live Content Editor"
	visible = OS.is_debug_build()
	pressed.connect(_toggle_content_editor)
	_snapshot_content_hashes()
	set_process(true)


func _process(delta: float) -> void:
	if _editor_window == null or not is_instance_valid(_editor_window) or not _editor_window.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < CONTENT_REFRESH_INTERVAL:
		return
	_refresh_elapsed = 0.0
	if _content_files_changed():
		_reload_runtime_content()


func _exit_tree() -> void:
	_close_content_editor()


func _toggle_content_editor() -> void:
	if _editor_window != null and is_instance_valid(_editor_window):
		if _editor_window.visible:
			_editor_window.grab_focus()
			return
		_editor_window.popup_centered()
		return
	_open_content_editor()


func _open_content_editor() -> void:
	if CONTENT_EDITOR_SCENE == null:
		push_error("Runtime Content Editor scene is unavailable.")
		return

	_editor_window = Window.new()
	_editor_window.name = "RuntimeContentEditorWindow"
	_editor_window.title = "Oathwake Content Editor • Live"
	_editor_window.size = Vector2i(1440, 900)
	_editor_window.min_size = Vector2i(1024, 650)
	_editor_window.unresizable = false
	_editor_window.exclusive = false
	_editor_window.transient = false
	_editor_window.close_requested.connect(_close_content_editor)
	get_tree().root.add_child(_editor_window)

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
	call_deferred("_open_default_vfx_profile")


func _close_content_editor() -> void:
	if _editor_window != null and is_instance_valid(_editor_window):
		_editor_window.queue_free()
	_editor_window = null
	_editor_instance = null
	_refresh_elapsed = 0.0


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
