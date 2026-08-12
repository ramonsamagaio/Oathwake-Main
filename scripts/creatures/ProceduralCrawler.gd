class_name ProceduralCrawler
extends ProceduralCreature

@export_group("Radial IK")
@export_range(4, 10, 2) var leg_count := 6
@export_range(6.0, 30.0, 0.5) var body_radius := 14.0
@export_range(6.0, 40.0, 0.5) var upper_leg_length := 17.0
@export_range(6.0, 40.0, 0.5) var lower_leg_length := 18.0
@export_range(0.0, 34.0, 0.5) var stance_radius := 26.0
@export_range(0.1, 10.0, 0.05) var step_speed := 4.2
@export_range(0.0, 16.0, 0.25) var step_height := 7.0
@export_range(0.0, 1.0, 0.01) var gait_overlap := 0.38

@export_group("Top-down Roaming")
@export_range(0.0, 140.0, 1.0) var crawl_speed := 48.0
@export var auto_crawl := true
@export_range(64.0, 620.0, 8.0) var roam_radius := 360.0
@export_range(8.0, 320.0, 4.0) var minimum_route_distance := 200.0
@export_range(4.0, 80.0, 1.0) var target_reach_distance := 14.0
@export_range(0.2, 12.0, 0.1) var turn_speed := 4.2
@export_range(0.5, 12.0, 0.1) var retarget_min_time := 4.0
@export_range(0.5, 12.0, 0.1) var retarget_max_time := 5.0

var _phase := 0.0
var _heading := Vector2.RIGHT
var _home_position := Vector2.ZERO
var _roam_target := Vector2.ZERO
var _retarget_clock := 0.0


func _ready() -> void:
	creature_id = &"crawler"
	primary_color = Color("725d4d")
	secondary_color = Color("473d39")
	accent_color = Color("b9a56b")
	shadow_color = Color("282a2b")
	_home_position = position
	super._ready()
	_choose_roam_target()


func _reset_simulation() -> void:
	super._reset_simulation()
	_home_position = position
	_choose_roam_target()


func _choose_roam_target() -> void:
	var margin := (stance_radius + lower_leg_length * 0.35) * global_scale_factor + 12.0
	_roam_target = _pick_roam_target_far(
		position,
		_home_position,
		roam_radius,
		margin,
		minimum_route_distance
	)
	var distance := position.distance_to(_roam_target)
	_retarget_clock = _roam_watchdog_time(
		distance,
		crawl_speed,
		retarget_min_time,
		_rng.randf_range(1.5, maxf(1.5, retarget_max_time))
	)


func _update_roaming(delta: float) -> void:
	if not auto_crawl or crawl_speed <= 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, maxf(1.0, crawl_speed) * delta * 8.0)
		return

	_retarget_clock -= delta
	var to_target := _roam_target - position
	if to_target.length() <= target_reach_distance:
		_choose_roam_target()
		to_target = _roam_target - position
	elif _retarget_clock <= 0.0:
		_choose_roam_target()
		to_target = _roam_target - position

	if position.distance_to(_home_position) > roam_radius * 1.12:
		_roam_target = _clamp_point_to_movement_bounds(_home_position, body_radius * global_scale_factor + 14.0)
		to_target = _roam_target - position

	if to_target.length_squared() > 0.001:
		var desired := to_target.normalized()
		_heading = _heading.lerp(desired, clampf(delta * turn_speed, 0.0, 1.0))
		if _heading.length_squared() > 0.001:
			_heading = _heading.normalized()
	velocity = _heading * crawl_speed


func _simulate_creature(delta: float) -> void:
	_phase += delta * step_speed * motion_intensity
	_update_roaming(delta)


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	if impulse.length_squared() > 4.0:
		_heading = impulse.normalized()
		_roam_target = _clamp_point_to_movement_bounds(
			position + _heading * minf(roam_radius, impulse.length() * 0.8),
			body_radius * global_scale_factor + 14.0
		)
		_retarget_clock = _roam_watchdog_time(position.distance_to(_roam_target), crawl_speed, 2.0, 1.0)


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


func _leg_geometry(index: int, facing_angle: float) -> PackedVector2Array:
	var side_sign := -1.0 if index % 2 == 0 else 1.0
	var row := float(floori(float(index) / 2.0))
	var rows := maxf(1.0, float(leg_count / 2 - 1))
	var longitudinal := lerpf(-0.75, 0.75, row / rows)
	var local_root := Vector2(longitudinal * body_radius * 0.8, side_sign * body_radius * 0.62)
	local_root = local_root.rotated(facing_angle) * global_scale_factor

	var gait_phase := _phase + (0.0 if index % 2 == 0 else PI) + row * gait_overlap
	var stride := sin(gait_phase) * stance_radius * 0.46
	var lift := maxf(0.0, sin(gait_phase)) * step_height
	var forward := _heading.normalized()
	var side := Vector2(-forward.y, forward.x) * side_sign
	var foot := side * stance_radius * global_scale_factor + forward * (longitudinal * stance_radius + stride) * global_scale_factor
	foot.y -= lift * global_scale_factor
	return _solve_leg(local_root, foot, side_sign)


func _draw() -> void:
	var scale_factor := global_scale_factor
	var facing_angle := _heading.angle()

	# Legs first. Widths are fixed integer pixel clusters, never scaled pixels.
	for i in range(leg_count):
		var leg := _leg_geometry(i, facing_angle)
		for j in range(leg.size() - 1):
			draw_line(leg[j] + Vector2(1.0, 2.0), leg[j + 1] + Vector2(1.0, 2.0), Color(shadow_color, 0.42), 3.0, false)
			draw_line(leg[j], leg[j + 1], secondary_color, 2.0, false)
			_draw_pixel_disc(leg[j + 1], 2.0, secondary_color)

		# Knee cap and claw tip give every leg readable articulation.
		if leg.size() >= 3:
			_draw_pixel_disc(leg[1], 2.0, primary_color)
			var foot := leg[2]
			var foot_dir := (foot - leg[1]).normalized()
			_px_rect(foot + foot_dir * 2.0, Vector2(3.0, 1.0), shadow_color)
			_px_rect(foot, Vector2.ONE, accent_color)

	var forward := _heading.normalized()
	var side_dir := Vector2(-forward.y, forward.x)
	var body_r := maxf(4.0, round(body_radius * scale_factor))
	var abdomen := -forward * body_r * 0.42
	var thorax := forward * body_r * 0.32

	# Contact shadow underneath the armored body.
	var body_shadow := shadow_color
	body_shadow.a = 0.40
	_draw_pixel_disc(abdomen + Vector2(1.0, 3.0), body_r * 0.92, body_shadow)
	_draw_pixel_disc(thorax + Vector2(1.0, 3.0), body_r * 0.72, body_shadow)

	# Two-part carapace produces a less generic spider-dot silhouette.
	_draw_pixel_disc(abdomen, body_r * 0.92, primary_color)
	_draw_pixel_disc(thorax, body_r * 0.72, primary_color)
	_draw_pixel_disc(abdomen - side_dir * 1.0 - forward * 2.0, body_r * 0.58, secondary_color)
	_draw_pixel_disc(thorax - forward * 1.0, body_r * 0.42, primary_color.lerp(accent_color, 0.13))

	# Dorsal plate and segmented stripe.
	var plate_center := abdomen - forward * body_r * 0.10
	_px_rect(plate_center, Vector2(maxf(3.0, body_r * 0.72), 3.0), secondary_color)
	for stripe in range(3):
		var stripe_pos := abdomen - forward * (body_r * 0.36 - float(stripe) * body_r * 0.34)
		_px_rect(_snap_vec(stripe_pos), Vector2(maxf(2.0, body_r * (0.55 - stripe * 0.07)), 1.0), accent_color.lerp(primary_color, 0.48))

	# Small mandible block and four-eye cluster.
	var face := thorax + forward * body_r * 0.54
	_px_rect(face, Vector2(4.0, 3.0), secondary_color)
	for eye_side in [-1.0, 1.0]:
		for eye_row in [0.0, 3.0]:
			var eye := face + side_dir * eye_side * (2.0 + eye_row * 0.20) - forward * eye_row
			_px_rect(_snap_vec(eye), Vector2.ONE, accent_color)

	var mandible_a := face + forward * 3.0 + side_dir * 2.0
	var mandible_b := face + forward * 3.0 - side_dir * 2.0
	_px_rect(_snap_vec(mandible_a), Vector2(2.0, 1.0), shadow_color)
	_px_rect(_snap_vec(mandible_b), Vector2(2.0, 1.0), shadow_color)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"body_radius": body_radius = clampf(float(value), 6.0, 30.0)
		&"upper_leg_length": upper_leg_length = clampf(float(value), 6.0, 40.0)
		&"lower_leg_length": lower_leg_length = clampf(float(value), 6.0, 40.0)
		&"stance_radius": stance_radius = clampf(float(value), 0.0, 34.0)
		&"step_speed": step_speed = clampf(float(value), 0.1, 10.0)
		&"step_height": step_height = clampf(float(value), 0.0, 16.0)
		&"gait_overlap": gait_overlap = clampf(float(value), 0.0, 1.0)
		&"crawl_speed": crawl_speed = clampf(float(value), 0.0, 140.0)
		&"auto_crawl": auto_crawl = bool(value)
		&"roam_radius": roam_radius = clampf(float(value), 64.0, 620.0)
		&"minimum_route_distance": minimum_route_distance = clampf(float(value), 8.0, 320.0)
		&"turn_speed": turn_speed = clampf(float(value), 0.2, 12.0)
		&"retarget_min_time": retarget_min_time = clampf(float(value), 0.5, 12.0)
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
		&"minimum_route_distance": return minimum_route_distance
		&"turn_speed": return turn_speed
		&"retarget_min_time": return retarget_min_time
		&"retarget_max_time": return retarget_max_time
	return null


func _get_creature_editor_schema() -> Array[Dictionary]:
	return [
		{"key": &"body_radius", "label": "Body Size", "type": "float", "min": 7.0, "max": 26.0, "step": 0.5},
		{"key": &"upper_leg_length", "label": "Upper Leg", "type": "float", "min": 8.0, "max": 32.0, "step": 0.5},
		{"key": &"lower_leg_length", "label": "Lower Leg", "type": "float", "min": 8.0, "max": 32.0, "step": 0.5},
		{"key": &"stance_radius", "label": "Stance Width", "type": "float", "min": 8.0, "max": 32.0, "step": 0.5},
		{"key": &"step_speed", "label": "Step Speed", "type": "float", "min": 0.2, "max": 8.0, "step": 0.05},
		{"key": &"step_height", "label": "Step Height", "type": "float", "min": 0.0, "max": 14.0, "step": 0.25},
		{"key": &"gait_overlap", "label": "Gait Offset", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"crawl_speed", "label": "Move Speed", "type": "float", "min": 0.0, "max": 125.0, "step": 1.0},
		{"key": &"auto_crawl", "label": "Auto Roam", "type": "bool"},
		{"key": &"roam_radius", "label": "Roam Radius", "type": "float", "min": 96.0, "max": 560.0, "step": 8.0},
		{"key": &"minimum_route_distance", "label": "Min Route", "type": "float", "min": 32.0, "max": 300.0, "step": 4.0},
		{"key": &"turn_speed", "label": "Turn Speed", "type": "float", "min": 0.2, "max": 10.0, "step": 0.1},
		{"key": &"retarget_min_time", "label": "Watchdog Min", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
		{"key": &"retarget_max_time", "label": "Watchdog Slack", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
	]
