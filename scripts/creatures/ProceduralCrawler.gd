class_name ProceduralCrawler
extends ProceduralCreature

@export_group("Radial IK")
@export_range(4, 10, 2) var leg_count := 6
@export_range(6.0, 30.0, 0.5) var body_radius := 13.0
@export_range(6.0, 40.0, 0.5) var upper_leg_length := 16.0
@export_range(6.0, 40.0, 0.5) var lower_leg_length := 17.0
@export_range(0.0, 30.0, 0.5) var stance_radius := 24.0
@export_range(0.1, 10.0, 0.05) var step_speed := 3.6
@export_range(0.0, 16.0, 0.25) var step_height := 6.0
@export_range(0.0, 1.0, 0.01) var gait_overlap := 0.36

@export_group("Top-down Roaming")
@export_range(0.0, 120.0, 1.0) var crawl_speed := 28.0
@export var auto_crawl := true
@export_range(48.0, 520.0, 8.0) var roam_radius := 230.0
@export_range(4.0, 80.0, 1.0) var target_reach_distance := 18.0
@export_range(0.2, 12.0, 0.1) var turn_speed := 5.0
@export_range(0.5, 8.0, 0.1) var retarget_min_time := 2.0
@export_range(0.5, 12.0, 0.1) var retarget_max_time := 4.5

var _phase := 0.0
var _heading := Vector2.RIGHT
var _home_position := Vector2.ZERO
var _roam_target := Vector2.ZERO
var _retarget_clock := 0.0


func _ready() -> void:
	creature_id = &"crawler"
	_home_position = position
	super._ready()
	_choose_roam_target()


func _reset_simulation() -> void:
	super._reset_simulation()
	_home_position = position
	_choose_roam_target()


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
	_phase += delta * step_speed * motion_intensity
	_update_roaming(delta)


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	if impulse.length_squared() > 4.0:
		_heading = impulse.normalized()
		_roam_target = position + _heading * minf(roam_radius, impulse.length() * 0.8)
		_retarget_clock = 0.8


func _solve_leg(root: Vector2, foot: Vector2, bend_sign: float) -> PackedVector2Array:
	var a := upper_leg_length * global_scale_factor
	var b := lower_leg_length * global_scale_factor
	var delta := foot - root
	var d := clampf(delta.length(), 0.001, maxf(0.001, a + b - 0.001))
	var direction := delta / d
	var cos_angle := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var along := a * cos_angle
	var height := sqrt(maxf(0.0, a * a - along * along))
	var normal := Vector2(-direction.y, direction.x) * bend_sign
	var knee := root + direction * along + normal * height
	return PackedVector2Array([_snap_vec(root), _snap_vec(knee), _snap_vec(foot)])


func _draw() -> void:
	var scale_factor := global_scale_factor
	var facing_angle := _heading.angle()
	for i in range(leg_count):
		var side_sign := -1.0 if i % 2 == 0 else 1.0
		var row := float(floori(float(i) / 2.0))
		var rows := maxf(1.0, float(leg_count / 2 - 1))
		var longitudinal := lerpf(-0.75, 0.75, row / rows)
		var local_root := Vector2(longitudinal * body_radius * 0.8, side_sign * body_radius * 0.62)
		local_root = local_root.rotated(facing_angle) * scale_factor

		var gait_phase := _phase + (0.0 if i % 2 == 0 else PI) + row * gait_overlap
		var stride := sin(gait_phase) * stance_radius * 0.45
		var lift := maxf(0.0, sin(gait_phase)) * step_height
		var forward := _heading.normalized()
		var side := Vector2(-forward.y, forward.x) * side_sign
		var foot := side * stance_radius * scale_factor + forward * (longitudinal * stance_radius + stride) * scale_factor
		foot.y -= lift * scale_factor

		var leg := _solve_leg(local_root, foot, side_sign)
		for j in range(leg.size() - 1):
			draw_line(leg[j], leg[j + 1], secondary_color, maxf(float(pixel_size), 2.0 * scale_factor), false)
			_draw_pixel_disc(leg[j + 1], maxf(float(pixel_size), 2.0 * scale_factor), secondary_color)

	_draw_pixel_disc(Vector2.ZERO, body_radius * scale_factor, primary_color)
	var head := _heading.normalized() * body_radius * 0.7 * scale_factor
	_draw_pixel_disc(head, body_radius * 0.72 * scale_factor, primary_color)
	var side_dir := Vector2(-_heading.y, _heading.x).normalized()
	_draw_pixel_disc(head + side_dir * body_radius * 0.34 * scale_factor, 2.0 * scale_factor, accent_color)
	_draw_pixel_disc(head - side_dir * body_radius * 0.34 * scale_factor, 2.0 * scale_factor, accent_color)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"body_radius": body_radius = clampf(float(value), 6.0, 30.0)
		&"upper_leg_length": upper_leg_length = clampf(float(value), 6.0, 40.0)
		&"lower_leg_length": lower_leg_length = clampf(float(value), 6.0, 40.0)
		&"stance_radius": stance_radius = clampf(float(value), 0.0, 30.0)
		&"step_speed": step_speed = clampf(float(value), 0.1, 10.0)
		&"step_height": step_height = clampf(float(value), 0.0, 16.0)
		&"gait_overlap": gait_overlap = clampf(float(value), 0.0, 1.0)
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
		&"body_radius": return body_radius
		&"upper_leg_length": return upper_leg_length
		&"lower_leg_length": return lower_leg_length
		&"stance_radius": return stance_radius
		&"step_speed": return step_speed
		&"step_height": return step_height
		&"gait_overlap": return gait_overlap
		&"crawl_speed": return crawl_speed
		&"auto_crawl": return auto_crawl
		&"roam_radius": return roam_radius
		&"turn_speed": return turn_speed
		&"retarget_min_time": return retarget_min_time
		&"retarget_max_time": return retarget_max_time
	return null


func _get_creature_editor_schema() -> Array[Dictionary]:
	return [
		{"key": &"body_radius", "label": "Body Size", "type": "float", "min": 7.0, "max": 26.0, "step": 0.5},
		{"key": &"upper_leg_length", "label": "Upper Leg", "type": "float", "min": 8.0, "max": 32.0, "step": 0.5},
		{"key": &"lower_leg_length", "label": "Lower Leg", "type": "float", "min": 8.0, "max": 32.0, "step": 0.5},
		{"key": &"stance_radius", "label": "Stance Width", "type": "float", "min": 8.0, "max": 30.0, "step": 0.5},
		{"key": &"step_speed", "label": "Step Speed", "type": "float", "min": 0.2, "max": 8.0, "step": 0.05},
		{"key": &"step_height", "label": "Step Height", "type": "float", "min": 0.0, "max": 14.0, "step": 0.25},
		{"key": &"gait_overlap", "label": "Gait Offset", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"crawl_speed", "label": "Move Speed", "type": "float", "min": 0.0, "max": 100.0, "step": 1.0},
		{"key": &"auto_crawl", "label": "Auto Roam", "type": "bool"},
		{"key": &"roam_radius", "label": "Roam Radius", "type": "float", "min": 64.0, "max": 420.0, "step": 8.0},
		{"key": &"turn_speed", "label": "Turn Speed", "type": "float", "min": 0.2, "max": 10.0, "step": 0.1},
		{"key": &"retarget_min_time", "label": "Min Target Time", "type": "float", "min": 0.5, "max": 6.0, "step": 0.1},
		{"key": &"retarget_max_time", "label": "Max Target Time", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
	]
