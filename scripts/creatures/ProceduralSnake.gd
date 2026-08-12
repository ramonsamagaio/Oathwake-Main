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
var _move_heading := Vector2.RIGHT
var _home_position := Vector2.ZERO
var _roam_target := Vector2.ZERO
var _retarget_clock := 0.0
var _last_head_world := Vector2.ZERO


func _ready() -> void:
	creature_id = &"snake"
	_home_position = position
	super._ready()
	_rebuild_chain()
	_last_head_world = global_position
	_choose_roam_target()


func _reset_simulation() -> void:
	super._reset_simulation()
	_home_position = position
	_rebuild_chain()
	_last_head_world = global_position
	_choose_roam_target()


func _rebuild_chain() -> void:
	_segments = PackedVector2Array()
	for i in range(segment_count):
		_segments.append(Vector2(-i * segment_spacing, 0.0))


func _choose_roam_target() -> void:
	_roam_target = _pick_roam_target(_home_position, roam_radius, head_radius * global_scale_factor + 8.0)
	_retarget_clock = _rng.randf_range(retarget_min_time, maxf(retarget_min_time, retarget_max_time))


func _update_roaming(delta: float) -> void:
	if not auto_crawl or crawl_speed <= 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, maxf(1.0, crawl_speed) * delta * 6.0)
		return

	_retarget_clock -= delta
	var to_target := _roam_target - position
	if to_target.length() <= target_reach_distance or _retarget_clock <= 0.0:
		_choose_roam_target()
		to_target = _roam_target - position

	if position.distance_to(_home_position) > roam_radius * 1.08:
		_roam_target = _clamp_point_to_movement_bounds(_home_position, head_radius * global_scale_factor + 8.0)
		to_target = _roam_target - position

	if to_target.length_squared() > 0.001:
		var desired := to_target.normalized()
		var blend := clampf(delta * turn_speed, 0.0, 1.0)
		_heading = _heading.lerp(desired, blend)
		if _heading.length_squared() > 0.001:
			_heading = _heading.normalized()

	# The head itself follows a sinusoid around the steering direction. The body
	# then follows the real path left by that head instead of being procedurally
	# re-solved around it, which produces an actual serpentine trajectory.
	var max_turn := deg_to_rad(clampf(wave_amplitude * 2.4, 0.0, 42.0))
	var serpentine := sin(_phase * wave_frequency) * max_turn
	_move_heading = _heading.rotated(serpentine).normalized()
	velocity = _move_heading * crawl_speed


func _update_chain_from_motion() -> void:
	var current_head_world := global_position
	var displacement := current_head_world - _last_head_world
	_last_head_world = current_head_world
	if displacement.length_squared() <= 0.0001:
		return

	# Segment coordinates are local to the moving head node. Counter-translate
	# them first so their WORLD positions remain where they were. Only segments
	# whose leash is stretched are advanced. Therefore when the snake stops,
	# nothing collapses or gets reeled into the head.
	for i in range(1, _segments.size()):
		_segments[i] -= displacement
	_segments[0] = Vector2.ZERO

	for i in range(1, _segments.size()):
		var previous := _segments[i - 1]
		var current := _segments[i]
		var delta_to_segment := current - previous
		var distance := delta_to_segment.length()
		if distance <= segment_spacing or distance <= 0.0001:
			continue
		var target := previous + delta_to_segment / distance * segment_spacing
		_segments[i] = current.lerp(target, follow_tightness)


func _simulate_creature(delta: float) -> void:
	if _segments.size() != segment_count:
		_rebuild_chain()
	_phase += delta * wave_speed * motion_intensity
	_update_roaming(delta)
	_update_chain_from_motion()


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	if impulse.length_squared() > 4.0:
		_heading = impulse.normalized()
		_move_heading = _heading
		_roam_target = _clamp_point_to_movement_bounds(
			position + _heading * minf(roam_radius, impulse.length() * 0.8),
			head_radius * global_scale_factor + 8.0
		)
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
	var facing := _move_heading.normalized() if _move_heading.length_squared() > 0.001 else _heading.normalized()
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
		{"key": &"wave_amplitude", "label": "Serpentine Width", "type": "float", "min": 0.0, "max": 16.0, "step": 0.25},
		{"key": &"wave_frequency", "label": "Serpentine Frequency", "type": "float", "min": 0.2, "max": 6.0, "step": 0.05},
		{"key": &"wave_speed", "label": "Serpentine Speed", "type": "float", "min": 0.0, "max": 7.0, "step": 0.05},
		{"key": &"follow_tightness", "label": "Body Tightness", "type": "float", "min": 0.15, "max": 1.0, "step": 0.01},
		{"key": &"crawl_speed", "label": "Move Speed", "type": "float", "min": 0.0, "max": 100.0, "step": 1.0},
		{"key": &"auto_crawl", "label": "Auto Roam", "type": "bool"},
		{"key": &"roam_radius", "label": "Roam Radius", "type": "float", "min": 64.0, "max": 420.0, "step": 8.0},
		{"key": &"turn_speed", "label": "Turn Speed", "type": "float", "min": 0.2, "max": 10.0, "step": 0.1},
		{"key": &"retarget_min_time", "label": "Min Target Time", "type": "float", "min": 0.5, "max": 6.0, "step": 0.1},
		{"key": &"retarget_max_time", "label": "Max Target Time", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
	]
