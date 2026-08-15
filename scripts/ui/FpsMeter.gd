class_name FpsMeter
extends Label

const SAMPLE_INTERVAL := 0.25

var _elapsed := 0.0
var _frames := 0
var _slowest_frame_ms := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_text(60.0, 16.7)


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	_slowest_frame_ms = maxf(_slowest_frame_ms, delta * 1000.0)
	if _elapsed < SAMPLE_INTERVAL:
		return
	var measured_fps := float(_frames) / maxf(_elapsed, 0.001)
	_update_text(measured_fps, _slowest_frame_ms)
	_elapsed = 0.0
	_frames = 0
	_slowest_frame_ms = 0.0


func _update_text(measured_fps: float, slowest_ms: float) -> void:
	text = "FPS %d  |  pico %.1f ms" % [roundi(measured_fps), slowest_ms]
	if measured_fps >= 55.0 and slowest_ms <= 22.0:
		modulate = Color(0.72, 1.0, 0.72, 1.0)
	elif measured_fps >= 45.0 and slowest_ms <= 30.0:
		modulate = Color(1.0, 0.88, 0.46, 1.0)
	else:
		modulate = Color(1.0, 0.48, 0.42, 1.0)
