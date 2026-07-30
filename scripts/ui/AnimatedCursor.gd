extends Node

const CURSOR_FRAMES := [
	"res://assets/ui/CURSOR/c1.png",
	"res://assets/ui/CURSOR/c2.png",
	"res://assets/ui/CURSOR/c3.png",
	"res://assets/ui/CURSOR/c4.png",
]

const CURSOR_SEQUENCE := [0, 1, 2, 3, 2, 1]
const CURSOR_INTERVAL := 0.1
const MAX_CURSOR_DIMENSION := 64
const AUTHORED_HOTSPOT := Vector2(8.0, 2.0)
const SOFTWARE_CURSOR_LAYER := 4096

var _frames: Array[Texture2D] = []
var _sequence: Array[int] = []
var _sequence_index := 0
var _timer: Timer
var _cursor_hotspot := AUTHORED_HOTSPOT
var _cursor_layer: CanvasLayer
var _cursor_sprite: Sprite2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_frames()
	_build_sequence()
	_apply_authored_hotspot()
	_create_software_cursor()
	_apply_current_cursor()
	_start_timer()
	set_process(true)


func _process(_delta: float) -> void:
	if _cursor_sprite == null or not is_instance_valid(_cursor_sprite):
		return
	_cursor_sprite.position = get_viewport().get_mouse_position() - _cursor_hotspot
	_cursor_sprite.visible = get_window() == null or get_window().has_focus()


func _exit_tree() -> void:
	if not _is_headless_display():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _load_frames() -> void:
	_frames.clear()
	for path_value in CURSOR_FRAMES:
		var path := str(path_value)
		if not ResourceLoader.exists(path):
			continue
		var texture := ResourceLoader.load(path) as Texture2D
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			push_warning("AnimatedCursor: ignored invalid cursor texture '%s'." % path)
			continue
		if texture.get_width() > MAX_CURSOR_DIMENSION or texture.get_height() > MAX_CURSOR_DIMENSION:
			push_warning("AnimatedCursor: cursor texture '%s' exceeds %d pixels and was ignored." % [path, MAX_CURSOR_DIMENSION])
			continue
		_frames.append(texture)


func _build_sequence() -> void:
	_sequence.clear()
	if _frames.is_empty():
		return
	if _frames.size() >= 4:
		_add_sequence_values(CURSOR_SEQUENCE)
	elif _frames.size() == 3:
		_add_sequence_values([0, 1, 2, 1])
	elif _frames.size() == 2:
		_add_sequence_values([0, 1, 0])
	else:
		_sequence.append(0)


func _add_sequence_values(values: Array) -> void:
	for value in values:
		_sequence.append(int(value))


func _apply_authored_hotspot() -> void:
	_cursor_hotspot = AUTHORED_HOTSPOT
	if _frames.is_empty():
		return
	var texture := _frames[0]
	_cursor_hotspot = Vector2(
		clampf(AUTHORED_HOTSPOT.x, 0.0, float(maxi(texture.get_width() - 1, 0))),
		clampf(AUTHORED_HOTSPOT.y, 0.0, float(maxi(texture.get_height() - 1, 0)))
	)


func _create_software_cursor() -> void:
	if _is_headless_display() or _frames.is_empty():
		return
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.name = "AnimatedCursorLayer"
	_cursor_layer.layer = SOFTWARE_CURSOR_LAYER
	add_child(_cursor_layer)

	_cursor_sprite = Sprite2D.new()
	_cursor_sprite.name = "AnimatedCursorSprite"
	_cursor_sprite.centered = false
	_cursor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_sprite.z_index = 1
	_cursor_sprite.position = get_viewport().get_mouse_position() - _cursor_hotspot
	_cursor_layer.add_child(_cursor_sprite)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func get_cursor_hotspot() -> Vector2:
	return _cursor_hotspot


func _start_timer() -> void:
	if _timer != null:
		_timer.queue_free()
		_timer = null

	if _sequence.size() <= 1 or _cursor_sprite == null:
		return

	_timer = Timer.new()
	_timer.wait_time = CURSOR_INTERVAL
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_advance_cursor_frame)
	add_child(_timer)


func _advance_cursor_frame() -> void:
	if _frames.is_empty() or _sequence.is_empty():
		return
	_sequence_index = (_sequence_index + 1) % _sequence.size()
	_apply_current_cursor()


func _apply_current_cursor() -> void:
	if _cursor_sprite == null or not is_instance_valid(_cursor_sprite) or _frames.is_empty() or _sequence.is_empty():
		return
	var frame_index := _sequence[_sequence_index]
	if frame_index < 0 or frame_index >= _frames.size():
		frame_index = 0
	var texture := _frames[frame_index]
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return
	_cursor_sprite.texture = texture


func _is_headless_display() -> bool:
	return DisplayServer.get_name().to_lower() == "headless"
