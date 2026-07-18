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

var _frames: Array[Texture2D] = []
var _sequence: Array[int] = []
var _sequence_index := 0
var _timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_frames()
	_build_sequence()
	_apply_current_cursor()
	_start_timer()


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW, Vector2.ZERO)


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


func _start_timer() -> void:
	if _timer != null:
		_timer.queue_free()
		_timer = null

	if _sequence.size() <= 1:
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
	if _frames.is_empty() or _sequence.is_empty():
		return
	var frame_index := _sequence[_sequence_index]
	if frame_index < 0 or frame_index >= _frames.size():
		frame_index = 0
	var texture := _frames[frame_index]
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, Vector2.ZERO)
