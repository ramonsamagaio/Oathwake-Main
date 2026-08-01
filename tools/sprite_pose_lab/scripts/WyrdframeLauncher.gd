extends Node

const CURSOR_REQUEST_ID: StringName = &"wyrdframe_standalone"

@onready var app_window: Window = $WyrdframeWindow

var _cursor_request_active: bool = false


func _ready() -> void:
	_request_system_cursor()
	app_window.force_native = true
	app_window.transient = false
	app_window.exclusive = false
	app_window.unresizable = false
	app_window.min_size = Vector2i(1100, 700)
	app_window.show()
	app_window.mode = Window.MODE_MAXIMIZED
	if OS.get_environment("WYRD_FRAME_SMOKE_TEST") == "1":
		call_deferred("_report_cursor_smoke_state")


func _exit_tree() -> void:
	_release_system_cursor()


func _request_system_cursor() -> void:
	var animated_cursor: Node = get_node_or_null("/root/AnimatedCursor")
	if animated_cursor != null and animated_cursor.has_method("request_system_cursor"):
		animated_cursor.call("request_system_cursor", CURSOR_REQUEST_ID)
		_cursor_request_active = true
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW, Vector2.ZERO)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _release_system_cursor() -> void:
	if not _cursor_request_active:
		return
	var animated_cursor: Node = get_node_or_null("/root/AnimatedCursor")
	if animated_cursor != null and animated_cursor.has_method("release_system_cursor"):
		animated_cursor.call("release_system_cursor", CURSOR_REQUEST_ID)
	_cursor_request_active = false


func _report_cursor_smoke_state() -> void:
	var animated_cursor: Node = get_node_or_null("/root/AnimatedCursor")
	if animated_cursor == null:
		print("WYRD_FRAME_SYSTEM_CURSOR_FALLBACK_OK")
		return
	if animated_cursor.has_method("is_system_cursor_forced") and bool(animated_cursor.call("is_system_cursor_forced")):
		print("WYRD_FRAME_SYSTEM_CURSOR_OK")
		return
	push_error("WYRD_FRAME_SYSTEM_CURSOR_FAILURE: artistic cursor was not disabled for the native tool window.")
