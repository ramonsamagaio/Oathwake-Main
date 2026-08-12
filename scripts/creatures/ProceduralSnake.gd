class_name ProceduralSnake
extends ProceduralCreature

@export_group("Chain")
@export_range(5, 40, 1) var segment_count := 18
@export_range(3.0, 16.0, 0.5) var segment_spacing := 7.0
@export_range(2.0, 16.0, 0.5) var head_radius := 8.0
@export_range(0.0, 20.0, 0.25) var wave_amplitude := 7.0
@export_range(0.1, 8.0, 0.05) var wave_frequency := 2.2
@export_range(0.0, 8.0, 0.05) var wave_speed := 3.0
@export_range(0.0, 1.0, 0.01) var follow_tightness := 0.78

@export_group("Top-down Roaming")
@export_range(0.0, 120.0, 1.0) var crawl_speed := 34.0
@export var auto_crawl := true
@export_range(48.0, 520.0, 8.0) var roam_radius := 250.0
@export_range(4.0, 80.0, 1.0) var target_reach_distance := 20.0
@export_range(0.2, 12.0, 0.1) var turn_speed := 4.0
@export_range(0.5, 8.0, 0.1) var retarget_min_time := 2.0
@export_range(0.5, 12.0, 0.1) var retarget_max_time := 5.0

var _segments: PackedVector2Array = PackedVector2Array()
var _phase := 0.0
var _heading := Vector2.RIGHT
var _home_position := Vector2.ZERO
var _roam_target := Vector2.ZERO
var _retarget_clock := 0.0


func _ready() -> void:
	creature_id = &"snake"
	_home_position = position
	super._ready()
	_rebuild_chain()
	_choose_roam_target()


func _reset_simulation() -> void:
	super._reset_simulation()
	_home_position = position
	_rebuild_chain()
	_choose_roam_target()


func _rebuild_chain() -> void:
	_segments = PackedVector2Array()
	for i in range(segment_count):
		_segments.append(Vector2(-i * segment_spacing, 0.0))


func _choose_roam_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := sqrt(_rng.randf()) * roam_radius
	_roam_target = _home_position + Vector2(cos(angle), sin(angle)) * radius
	_retarget_clock = _rng.randf_range(retarget_min_time, maxf(retarget_min_time, retarget_max_time))


func _update_roaming(delta: float) -> void:
	if not auto_crawl or crawl_speed <= 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, crawl_speed * delta * 4.0)
		return

	_retarget_clock -= delta
	var to_target := _roam_target - position
	if to_target.length() <= target_reach_distance or _retarget_clock <= 0.0:
		_choose_roam_target()
		to_target = _roam_target - position

	if position.distance_to(_home_position) > roam_radius * 1.08:
		_roam_target = _home_position
		to_target = _home_position - position

	if to_target.length_squared() > 0.001:
		var desired := to_target.normalized()
		_heading = _heading.lerp(desired, clampf(delta * turn_speed, 0.0, 1.0)).normalized()
	velocity = _heading * crawl_speed


func _simulate_creature(delta: float) -> void:
	if _segments.size() != segment_count:
		_rebuild_chain()
	_phase += delta * wave_speed * motion_intensity
	_update_roaming(delta)

	_segments[0] = Vector2.ZERO
	for i in range(1, segment_count):
		var previous := _segments[i - 1]
		var current := _segments[i]
		var to_current := current - previous
		var direction := to_current.normalized() if to_current.length_squared() > 0.001 else -_heading
		var target := previous + direction * segment_spacing
		var tangent := Vector2(-direction.y, direction.x)
		var wave := sin(_phase + float(i) * wave_frequency * 0.32) * wave_amplitude
		var taper := 1.0 - float(i) / float(maxi(1, segment_count - 1))
		target += tangent * wave * taper * 0.25
		_segments[i] = current.lerp(target, follow_tightness)


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	if impulse.length_squared() > 4.0:
		_heading = impulse.normalized()
		_roam_target = position + _heading * minf(roam_radius, impulse.length() * 0.8)
		_retarget_clock = 0.8


func _draw() -> void:
	if _segments.is_empty():
		return
	for i in range(segment_count - 1, -1, -1):
		var t := float(i) / float(maxi(1, segment_count - 1))
		var radius := lerpf(head_radius, maxf(2.0, head_radius * 0.3), t) * global_scale_factor
		var color := primary_color.lerp(secondary_color, t * 0.75)
		_draw_pixel_disc(_segments[i] * global_scale_factor, radius, color)

	var head := _segments[0] * global_scale_factor
	var facing := _heading.normalized()
	var side := Vector2(-facing.y, facing.x)
	var eye_base := head + facing * head_radius * 0.35 * global_scale_factor
	_draw_pixel_disc(eye_base + side * head_radius * 0.45 * global_scale_factor, 2.0 * global_scale_factor, shadow_color)
	_draw_pixel_disc(eye_base - side * head_radius * 0.45 * global_scale_factor, 2.0 * global_scale_factor, shadow_color)
	_px_rect(head + facing * head_radius * 0.9 * global_scale_factor, Vector2(pixel_size * 2, pixel_size) * global_scale_factor, accent_color)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"segment_spacing": segment_spacing = clampf(float(value), 3.0, 16.0)
		&"head_radius": head_radius = clampf(float(value), 2.0, 16.0)
		&"wave_amplitude": wave_amplitude = clampf(float(value), 0.0, 20.0)
		&"wave_frequency": wave_frequency = clampf(float(value), 0.1, 8.0)
		&"wave_speed": wave_speed = clampf(float(value), 0.0, 8.0)
		&"follow_tightness": follow_tightness = clampf(float(value), 0.0, 1.0)
		&"crawl_speed": crawl_speed = clampf(float(value), 0.0, 120.0)
		&"auto_crawl": auto_crawl = bool(value)
		&"roam_radius": roam_radius = clampf(float(value), 48.0, 520.0)
		&"turn_speed": turn_speed = clampf(float(value), 0.2, 12.0)
		&"retarget_min_time": retarget_min_time = clampf(float(value), 0.5, 8.0)
		&"retarget_max_time": retarget_max_time = clampf(float(value), 0.5, 12.0)
		_:
			return false
	return true


func _get_creature_parameter(key: StringName) -> Variant:
	match key:
		&"segment_spacing": return segment_spacing
		&"head_radius": return head_radius
		&"wave_amplitude": return wave_amplitude
		&"wave_frequency": return wave_frequency
		&"wave_speed": return wave_speed
		&"follow_tightness": return follow_tightness
		&"crawl_speed": return crawl_speed
		&"auto_crawl": return auto_crawl
		&"roam_radius": return roam_radius
		&"turn_speed": return turn_speed
		&"retarget_min_time": return retarget_min_time
		&"retarget_max_time": return retarget_max_time
	return null


func _get_creature_editor_schema() -> Array[Dictionary]:
	return [
		{"key": &"segment_spacing", "label": "Segment Length", "type": "float", "min": 3.0, "max": 14.0, "step": 0.5},
		{"key": &"head_radius", "label": "Head Size", "type": "float", "min": 3.0, "max": 14.0, "step": 0.5},
		{"key": &"wave_amplitude", "label": "Body Wave", "type": "float", "min": 0.0, "max": 16.0, "step": 0.25},
		{"key": &"wave_frequency", "label": "Wave Frequency", "type": "float", "min": 0.2, "max": 6.0, "step": 0.05},
		{"key": &"wave_speed", "label": "Wave Speed", "type": "float", "min": 0.0, "max": 7.0, "step": 0.05},
		{"key": &"follow_tightness", "label": "Body Tightness", "type": "float", "min": 0.15, "max": 1.0, "step": 0.01},
		{"key": &"crawl_speed", "label": "Move Speed", "type": "float", "min": 0.0, "max": 100.0, "step": 1.0},
		{"key": &"auto_crawl", "label": "Auto Roam", "type": "bool"},
		{"key": &"roam_radius", "label": "Roam Radius", "type": "float", "min": 64.0, "max": 420.0, "step": 8.0},
		{"key": &"turn_speed", "label": "Turn Speed", "type": "float", "min": 0.2, "max": 10.0, "step": 0.1},
		{"key": &"retarget_min_time", "label": "Min Target Time", "type": "float", "min": 0.5, "max": 6.0, "step": 0.1},
		{"key": &"retarget_max_time", "label": "Max Target Time", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
	]
