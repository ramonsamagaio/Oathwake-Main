class_name ProceduralWisp
extends ProceduralCreature

@export_group("Field / Trail")
@export_range(3, 32, 1) var trail_points := 16
@export_range(2.0, 24.0, 0.5) var core_radius := 9.0
@export_range(0.0, 24.0, 0.5) var drift_amplitude := 7.0
@export_range(0.1, 8.0, 0.05) var drift_speed := 1.8
@export_range(0.0, 30.0, 0.5) var trail_spacing := 6.0
@export_range(0.0, 1.0, 0.01) var trail_follow := 0.66
@export_range(0.1, 4.0, 0.05) var trail_lifetime := 0.82
@export_range(0, 12, 1) var mote_count := 6
@export_range(0.0, 40.0, 0.5) var mote_orbit_radius := 20.0
@export_range(0.0, 8.0, 0.05) var mote_orbit_speed := 1.55

@export_group("Top-down Roaming")
@export var auto_roam := true
@export_range(0.0, 160.0, 1.0) var roam_speed := 60.0
@export_range(64.0, 680.0, 8.0) var roam_radius := 430.0
@export_range(8.0, 360.0, 4.0) var minimum_route_distance := 240.0
@export_range(4.0, 80.0, 1.0) var target_reach_distance := 14.0
@export_range(0.2, 12.0, 0.1) var turn_speed := 2.35
@export_range(0.5, 12.0, 0.1) var retarget_min_time := 4.0
@export_range(0.5, 12.0, 0.1) var retarget_max_time := 5.0

var _trail: Array[Dictionary] = []
var _phase := 0.0
var _home_position := Vector2.ZERO
var _roam_target := Vector2.ZERO
var _heading := Vector2.RIGHT
var _retarget_clock := 0.0
var _visual_drift := Vector2.ZERO
var _last_body_world := Vector2.ZERO
var _last_trail_sample_world := Vector2.ZERO


func _ready() -> void:
	creature_id = &"wisp"
	primary_color = Color("7895b7")
	secondary_color = Color("4f607c")
	accent_color = Color("c6d8ca")
	shadow_color = Color("252b3f")
	_home_position = position
	super._ready()
	_rebuild_trail()
	_last_body_world = global_position
	_last_trail_sample_world = global_position
	_choose_roam_target()


func _reset_simulation() -> void:
	super._reset_simulation()
	_home_position = position
	_visual_drift = Vector2.ZERO
	_rebuild_trail()
	_last_body_world = global_position
	_last_trail_sample_world = global_position
	_choose_roam_target()


func _rebuild_trail() -> void:
	# A Wisp trail is history, not anatomy. Idle begins with no hanging tail.
	_trail.clear()


func _choose_roam_target() -> void:
	var margin := core_radius * global_scale_factor + 14.0
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
		roam_speed,
		retarget_min_time,
		_rng.randf_range(1.5, maxf(1.5, retarget_max_time))
	)


func _update_roaming(delta: float) -> void:
	if not auto_roam or roam_speed <= 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, maxf(1.0, roam_speed) * delta * 8.0)
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
		_roam_target = _clamp_point_to_movement_bounds(_home_position, core_radius * global_scale_factor + 14.0)
		to_target = _roam_target - position

	if to_target.length_squared() > 0.001:
		var desired := to_target.normalized()
		_heading = _heading.lerp(desired, clampf(delta * turn_speed, 0.0, 1.0))
		if _heading.length_squared() > 0.001:
			_heading = _heading.normalized()
	velocity = _heading * roam_speed


func _update_trail(delta: float) -> void:
	for i in range(_trail.size() - 1, -1, -1):
		var sample: Dictionary = _trail[i]
		sample["age"] = float(sample.get("age", 0.0)) + delta
		if float(sample["age"]) >= trail_lifetime:
			_trail.remove_at(i)
		else:
			_trail[i] = sample

	var body_world := global_position
	var body_displacement := body_world - _last_body_world
	_last_body_world = body_world

	# Hover motion animates the spirit without generating a false tail. Only the
	# actual Node2D translation emits trail samples.
	if body_displacement.length_squared() <= 0.01:
		return

	var min_sample_distance := maxf(1.0, trail_spacing * 0.5)
	if body_world.distance_to(_last_trail_sample_world) < min_sample_distance:
		return

	var core_world := body_world + _visual_drift * global_scale_factor
	_trail.append({"position": core_world, "age": 0.0})
	_last_trail_sample_world = body_world
	while _trail.size() > trail_points:
		_trail.pop_front()


func _simulate_creature(delta: float) -> void:
	_phase += delta * drift_speed * motion_intensity
	_update_roaming(delta)

	_visual_drift = Vector2(
		sin(_phase * 0.91) * drift_amplitude,
		cos(_phase * 1.23) * drift_amplitude * 0.62
	)
	_update_trail(delta)


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	if impulse.length_squared() > 4.0:
		_heading = impulse.normalized()
		_roam_target = _clamp_point_to_movement_bounds(
			position + _heading * minf(roam_radius, impulse.length() * 0.8),
			core_radius * global_scale_factor + 14.0
		)
		_retarget_clock = _roam_watchdog_time(position.distance_to(_roam_target), roam_speed, 2.0, 1.0)


func _draw() -> void:
	_draw_trail()
	_draw_core()
	_draw_motes()


func _draw_trail() -> void:
	for i in range(_trail.size()):
		var sample: Dictionary = _trail[i]
		var age := float(sample.get("age", 0.0))
		var life := clampf(1.0 - age / maxf(0.01, trail_lifetime), 0.0, 1.0)
		var index_t := float(i) / float(maxi(1, _trail.size() - 1))
		var persistence_curve := lerpf(2.0, 0.62, trail_follow)
		var alpha := pow(life, persistence_curve) * lerpf(0.16, 0.66, index_t)
		var radius := lerpf(1.0, core_radius * 0.58, index_t) * global_scale_factor
		var world_pos: Vector2 = sample.get("position", global_position)
		var local_pos := _snap_vec(to_local(world_pos))

		var outer := secondary_color
		outer.a = alpha
		_draw_pixel_disc(local_pos, radius, outer)
		if radius >= 3.0 and life > 0.24:
			var inner := primary_color.lerp(accent_color, 0.18)
			inner.a = alpha * 0.48
			_draw_pixel_disc(local_pos, maxf(1.0, radius * 0.42), inner)


func _draw_core() -> void:
	var core_pos := _snap_vec(_visual_drift * global_scale_factor)
	var r := maxf(3.0, round(core_radius * global_scale_factor))

	# Soft spectral silhouette built from translucent one-pixel clusters.
	var halo := secondary_color
	halo.a = 0.20
	_draw_pixel_disc(core_pos, r + 4.0, halo)
	var halo_inner := primary_color
	halo_inner.a = 0.30
	_draw_pixel_disc(core_pos, r + 2.0, halo_inner)
	_draw_pixel_disc(core_pos, r, primary_color)

	# Dark inner void + luminous seed gives the Wisp more depth than a flat orb.
	_draw_pixel_disc(core_pos + Vector2(0.0, 1.0), maxf(2.0, r * 0.55), shadow_color)
	var inner := primary_color.lerp(accent_color, 0.58)
	_draw_pixel_disc(core_pos - Vector2(1.0, 1.0), maxf(2.0, r * 0.38), inner)
	_draw_pixel_disc(core_pos - Vector2(2.0, 2.0), maxf(1.0, r * 0.15), Color(1.0, 1.0, 0.94, 0.95))

	# Three animated flame-like tips alter the silhouette using only 1 px cells.
	var tip_height := 3 + int(round((sin(_phase * 2.1) + 1.0) * 1.5))
	for i in range(3):
		var x := float((i - 1) * 4)
		var wobble := int(round(sin(_phase * 2.7 + i * 1.9) * 1.5))
		for y in range(tip_height - i % 2):
			var tip_pos := core_pos + Vector2(x + wobble, -r - 1.0 - float(y))
			_px_rect(tip_pos, Vector2.ONE, primary_color.lerp(accent_color, 0.24))

	# Tiny lower wisps break the perfect-circle silhouette.
	_px_rect(core_pos + Vector2(-r * 0.45, r * 0.78), Vector2(2.0, 2.0), secondary_color)
	_px_rect(core_pos + Vector2(r * 0.40, r * 0.86), Vector2(2.0, 1.0), secondary_color)


func _draw_motes() -> void:
	var core_pos := _snap_vec(_visual_drift * global_scale_factor)
	for i in range(mote_count):
		var angle := _phase * mote_orbit_speed + TAU * float(i) / float(maxi(1, mote_count))
		var wobble := 0.72 + 0.28 * sin(_phase * 1.3 + i * 2.1)
		var p := core_pos + Vector2(cos(angle), sin(angle)) * mote_orbit_radius * wobble * global_scale_factor
		p = _snap_vec(p)
		var mote_size := 1.0 if i % 3 == 0 else 2.0
		_draw_pixel_disc(p, mote_size, accent_color)
		if i % 2 == 0:
			var mote_tail := p - Vector2(cos(angle), sin(angle)) * 2.0
			var faded := primary_color
			faded.a = 0.55
			_px_rect(_snap_vec(mote_tail), Vector2.ONE, faded)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"core_radius": core_radius = clampf(float(value), 2.0, 24.0)
		&"drift_amplitude": drift_amplitude = clampf(float(value), 0.0, 24.0)
		&"drift_speed": drift_speed = clampf(float(value), 0.1, 8.0)
		&"trail_spacing": trail_spacing = clampf(float(value), 0.0, 30.0)
		&"trail_follow": trail_follow = clampf(float(value), 0.0, 1.0)
		&"trail_lifetime": trail_lifetime = clampf(float(value), 0.1, 4.0)
		&"mote_count": mote_count = clampi(int(value), 0, 12)
		&"mote_orbit_radius": mote_orbit_radius = clampf(float(value), 0.0, 40.0)
		&"mote_orbit_speed": mote_orbit_speed = clampf(float(value), 0.0, 8.0)
		&"auto_roam": auto_roam = bool(value)
		&"roam_speed": roam_speed = clampf(float(value), 0.0, 160.0)
		&"roam_radius": roam_radius = clampf(float(value), 64.0, 680.0)
		&"minimum_route_distance": minimum_route_distance = clampf(float(value), 8.0, 360.0)
		&"turn_speed": turn_speed = clampf(float(value), 0.2, 12.0)
		&"retarget_min_time": retarget_min_time = clampf(float(value), 0.5, 12.0)
		&"retarget_max_time": retarget_max_time = clampf(float(value), 0.5, 12.0)
		_:
			return false
	return true


func _get_creature_parameter(key: StringName) -> Variant:
	match key:
		&"core_radius": return core_radius
		&"drift_amplitude": return drift_amplitude
		&"drift_speed": return drift_speed
		&"trail_spacing": return trail_spacing
		&"trail_follow": return trail_follow
		&"trail_lifetime": return trail_lifetime
		&"mote_count": return mote_count
		&"mote_orbit_radius": return mote_orbit_radius
		&"mote_orbit_speed": return mote_orbit_speed
		&"auto_roam": return auto_roam
		&"roam_speed": return roam_speed
		&"roam_radius": return roam_radius
		&"minimum_route_distance": return minimum_route_distance
		&"turn_speed": return turn_speed
		&"retarget_min_time": return retarget_min_time
		&"retarget_max_time": return retarget_max_time
	return null


func _get_creature_editor_schema() -> Array[Dictionary]:
	return [
		{"key": &"core_radius", "label": "Core Size", "type": "float", "min": 3.0, "max": 20.0, "step": 0.5},
		{"key": &"drift_amplitude", "label": "Hover Drift", "type": "float", "min": 0.0, "max": 22.0, "step": 0.5},
		{"key": &"drift_speed", "label": "Hover Speed", "type": "float", "min": 0.1, "max": 5.0, "step": 0.05},
		{"key": &"trail_spacing", "label": "Trail Spacing", "type": "float", "min": 1.0, "max": 24.0, "step": 0.5},
		{"key": &"trail_follow", "label": "Trail Persistence", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"trail_lifetime", "label": "Trail Lifetime", "type": "float", "min": 0.1, "max": 3.0, "step": 0.05},
		{"key": &"mote_count", "label": "Orbit Motes", "type": "int", "min": 0, "max": 10, "step": 1},
		{"key": &"mote_orbit_radius", "label": "Orbit Radius", "type": "float", "min": 0.0, "max": 36.0, "step": 0.5},
		{"key": &"mote_orbit_speed", "label": "Orbit Speed", "type": "float", "min": 0.0, "max": 6.0, "step": 0.05},
		{"key": &"auto_roam", "label": "Auto Roam", "type": "bool"},
		{"key": &"roam_speed", "label": "Move Speed", "type": "float", "min": 0.0, "max": 140.0, "step": 1.0},
		{"key": &"roam_radius", "label": "Roam Radius", "type": "float", "min": 96.0, "max": 620.0, "step": 8.0},
		{"key": &"minimum_route_distance", "label": "Min Route", "type": "float", "min": 32.0, "max": 340.0, "step": 4.0},
		{"key": &"turn_speed", "label": "Turn Speed", "type": "float", "min": 0.2, "max": 10.0, "step": 0.1},
		{"key": &"retarget_min_time", "label": "Watchdog Min", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
		{"key": &"retarget_max_time", "label": "Watchdog Slack", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
	]
