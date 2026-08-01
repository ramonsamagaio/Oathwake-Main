extends Node

const CURSOR_REQUEST_ID: StringName = &"content_editor_standalone"
const CONTENT_EDITOR_SCENE_PREFIX: String = "res://tools/content_editor/"

var _cursor_request_active: bool = false


func _ready() -> void:
	call_deferred("_configure_cursor_for_launch_mode")


func _exit_tree() -> void:
	_release_system_cursor()


func _configure_cursor_for_launch_mode() -> void:
	if not _is_standalone_content_editor():
		return
	var animated_cursor: Node = get_node_or_null("/root/AnimatedCursor")
	if animated_cursor != null and animated_cursor.has_method("request_system_cursor"):
		animated_cursor.call("request_system_cursor", CURSOR_REQUEST_ID)
		_cursor_request_active = true
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW, Vector2.ZERO)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _is_standalone_content_editor() -> bool:
	var current_scene: Node = get_tree().current_scene
	var content_editor_root: Node = get_parent()
	if current_scene == null or content_editor_root == null:
		return false
	if current_scene == content_editor_root:
		return true
	var current_scene_path: String = current_scene.scene_file_path
	return not current_scene_path.is_empty() and current_scene_path.begins_with(CONTENT_EDITOR_SCENE_PREFIX)


func _release_system_cursor() -> void:
	if not _cursor_request_active:
		return
	var animated_cursor: Node = get_node_or_null("/root/AnimatedCursor")
	if animated_cursor != null and animated_cursor.has_method("release_system_cursor"):
		animated_cursor.call("release_system_cursor", CURSOR_REQUEST_ID)
	_cursor_request_active = false
