class_name ProceduralSlime
extends ProceduralCreature

@export_group("Blob")
@export_range(10, 32, 1) var point_count := 20
@export_range(8.0, 64.0, 1.0) var radius_x := 28.0
@export_range(8.0, 64.0, 1.0) var radius_y := 21.0
@export_range(1.0, 80.0, 0.5) var stiffness := 19.0
@export_range(0.0, 20.0, 0.1) var damping := 5.4
@export_range(0.0, 1.0, 0.01) var volume_preservation := 0.86
@export_range(0.0, 2.0, 0.05) var wobble := 0.52
@export_range(0.0, 2.0, 0.05) var locomotion_squash := 1.0
@export_range(0.45, 0.95, 0.01) var body_opacity := 0.74
@export_range(0.0, 2.0, 0.05) var liquid_spread := 1.15

@export_group("Top-down Hop Roaming")
@export var locomotion_enabled := true
@export_range(10.0, 280.0, 1.0) var move_speed := 108.0
@export_range(0.25, 3.0, 0.05) var hop_interval := 0.92
@export_range(0.15, 1.5, 0.05) var hop_duration := 0.50
@export_range(2.0, 80.0, 1.0) var hop_height := 28.0
@export_range(0.08, 0.8, 0.01) var landing_settle_time := 0.34
@export_range(0.05, 0.6, 0.01) var pre_jump_gather_time := 0.24
@export_range(0.0, 1.0, 0.01) var wander_strength := 0.34
@export var auto_roam := true
@export_range(64.0, 680.0, 8.0) var roam_radius := 430.0
@export_range(16.0, 360.0, 4.0) var minimum_route_distance := 240.0
@export var movement_direction := Vector2(0.85, 0.35)

@export_group("Slime Shedding")
@export var trail_enabled := true
@export_range(0.0, 24.0, 1.0) var trail_droplets_per_hop := 6.0
@export_range(0.25, 12.0, 0.25) var trail_lifetime := 3.25
@export_range(1.0, 8.0, 0.5) var trail_pixel_radius := 2.0
@export_range(0.0, 2.0, 0.05) var landing_splash := 1.0
@export_range(0.0, 2.0, 0.05) var airborne_shedding := 0.68

var _offsets: PackedVector2Array = PackedVector2Array()
var _point_velocities: PackedVector2Array = PackedVector2Array()
var _phase := 0.0
var _hop_clock := 0.0
var _hop_phase := 0.0
var _jump_height_current := 0.0
var _is_airborne := false
var _landing_deformation := 0.0
var _gather_deformation := 0.0
var _takeoff_deformation := 0.0
var _trail_emit_accumulator := 0.0
var _ground_trail: Array[Dictionary] = []
var _air_droplets: Array[Dictionary] = []
var _home_position := Vector2.ZERO
var _roam_target := Vector2.ZERO
var _route_watchdog := 0.0


func _ready() -> void:
	creature_id = &"slime"
	primary_color = Color("43b9ad")
	secondary_color = Color("187f8f")
	accent_color = Color("b8f0c9")
	shadow_color = Color("163f56")
	movement_direction = movement_direction.normalized()
	_home_position = position
	super._ready()
	_rebuild_points()
	_choose_roam_target()


func _reset_simulation() -> void:
	super._reset_simulation()
	_home_position = position
	_rebuild_points()
	_hop_clock = 0.0
	_hop_phase = 0.0
	_jump_height_current = 0.0
	_is_airborne = false
	_landing_deformation = 0.0
	_gather_deformation = 0.0
	_takeoff_deformation = 0.0
	_trail_emit_accumulator = 0.0
	_ground_trail.clear()
	_air_droplets.clear()
	_choose_roam_target()


func set_move_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		movement_direction = direction.normalized()


func _choose_roam_target() -> void:
	var margin := maxf(radius_x, radius_y) * global_scale_factor + 16.0
	_roam_target = _pick_roam_target_far(
		position,
		_home_position,
		roam_radius,
		margin,
		minimum_route_distance
	)
	var route_distance := position.distance_to(_roam_target)
	_route_watchdog = _roam_watchdog_time(route_distance, move_speed * 0.72, 5.0, 3.0)


func _update_roam_heading() -> void:
	if not auto_roam:
		return
	var to_target := _roam_target - position
	if to_target.length() <= maxf(22.0, radius_x * 0.75) or _route_watchdog <= 0.0:
		_choose_roam_target()
		to_target = _roam_target - position
	if to_target.length_squared() <= 0.001:
		return

	var desired := to_target.normalized()
	# Each jump is aimed primarily at the route target, with a small organic
	# deviation. This gives exploration instead of a single permanent heading.
	var jitter := _rng.randf_range(-0.52, 0.52) * wander_strength
	desired = desired.rotated(jitter)
	movement_direction = movement_direction.lerp(desired, 0.78)
	if movement_direction.length_squared() > 0.001:
		movement_direction = movement_direction.normalized()


func _rebuild_points() -> void:
	_offsets = PackedVector2Array()
	_point_velocities = PackedVector2Array()
	for i in range(point_count):
		_offsets.append(Vector2.ZERO)
		_point_velocities.append(Vector2.ZERO)


func _simulate_creature(delta: float) -> void:
	if _offsets.size() != point_count:
		_rebuild_points()

	_phase += delta * (2.1 + move_speed * 0.005)
	_route_watchdog -= delta
	_update_locomotion(delta)
	_update_blob_springs(delta)
	_update_shedding(delta)
	_update_trail(delta)
	queue_redraw()


func _update_locomotion(delta: float) -> void:
	if not locomotion_enabled:
		_jump_height_current = move_toward(_jump_height_current, 0.0, delta * 120.0)
		_landing_deformation = move_toward(_landing_deformation, 0.0, delta * 3.5)
		_gather_deformation = 0.0
		_takeoff_deformation = move_toward(_takeoff_deformation, 0.0, delta * 5.0)
		return

	if _is_airborne:
		_hop_phase += delta / maxf(0.05, hop_duration)
		var clamped_phase := clampf(_hop_phase, 0.0, 1.0)
		_jump_height_current = sin(clamped_phase * PI) * hop_height
		_takeoff_deformation = maxf(0.0, 1.0 - clamped_phase * 3.2)
		_gather_deformation = 0.0
		_landing_deformation = 0.0

		var travel_curve := lerpf(0.78, 1.08, sin(clamped_phase * PI))
		_move_on_ground(movement_direction * move_speed * travel_curve * delta)
		if _hop_phase >= 1.0:
			_land_hop()
		return

	_hop_clock += delta
	_landing_deformation = landing_splash * (1.0 - smoothstep(0.0, maxf(0.05, landing_settle_time), _hop_clock))

	var gather_start := maxf(0.0, hop_interval - pre_jump_gather_time)
	_gather_deformation = smoothstep(gather_start, maxf(gather_start + 0.01, hop_interval), _hop_clock)
	_takeoff_deformation = 0.0
	_jump_height_current = 0.0

	if _hop_clock >= hop_interval:
		_start_hop()


func _start_hop() -> void:
	_hop_clock = 0.0
	_hop_phase = 0.0
	_is_airborne = true
	_takeoff_deformation = 1.0
	_gather_deformation = 0.0
	_update_roam_heading()

	if trail_enabled:
		_spawn_ground_mark(global_position, trail_pixel_radius * 1.25, 0.76)
		_spawn_air_droplets(maxi(1, int(round(trail_droplets_per_hop * 0.30))))


func _land_hop() -> void:
	_is_airborne = false
	_hop_phase = 0.0
	_jump_height_current = 0.0
	_landing_deformation = landing_splash
	_gather_deformation = 0.0
	_takeoff_deformation = 0.0
	_hop_clock = 0.0

	if auto_roam and position.distance_to(_roam_target) <= maxf(22.0, radius_x * 0.75):
		_choose_roam_target()

	if trail_enabled:
		_spawn_ground_mark(global_position, trail_pixel_radius * (1.6 + landing_splash * 0.5), 0.92)
		_spawn_landing_splash()


func _move_on_ground(displacement: Vector2) -> void:
	var next_position := position + displacement
	if has_movement_bounds():
		var margin := maxf(radius_x, radius_y) * global_scale_factor + 12.0
		var inner := get_movement_bounds().grow(-margin)
		if next_position.x < inner.position.x or next_position.x > inner.end.x or next_position.y < inner.position.y or next_position.y > inner.end.y:
			next_position.x = clampf(next_position.x, inner.position.x, inner.end.x)
			next_position.y = clampf(next_position.y, inner.position.y, inner.end.y)
			position = _snap_vec(next_position) if quantize_motion else next_position
			_choose_roam_target()
			_update_roam_heading()
			return
	position = _snap_vec(next_position) if quantize_motion else next_position


func _update_blob_springs(delta: float) -> void:
	var mean_radial: float = 0.0
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		var normal: Vector2 = Vector2(cos(angle), sin(angle))
		var wave_a: float = sin(_phase * 1.75 + angle * 3.0)
		var wave_b: float = sin(_phase * 2.35 - angle * 2.0) * 0.45
		var wave: float = (wave_a + wave_b) * wobble * 1.85
		var target_offset: Vector2 = normal * wave

		# Landing pushes lower/lateral membrane points outward. Gathering pulls the
		# membrane inward before the next leap, creating a real liquid mass cycle.
		var lateral_weight: float = absf(cos(angle))
		var lower_weight: float = maxf(0.0, sin(angle))
		target_offset.x += signf(cos(angle)) * lateral_weight * _landing_deformation * liquid_spread * 2.8
		target_offset.y += lower_weight * _landing_deformation * liquid_spread * 1.6
		target_offset -= normal * _gather_deformation * 1.6

		var offset: Vector2 = _offsets[i]
		var point_velocity: Vector2 = _point_velocities[i]
		var spring: Vector2 = (target_offset - offset) * stiffness
		point_velocity += spring * delta
		point_velocity *= exp(-damping * delta)
		offset += point_velocity * delta
		_offsets[i] = offset
		_point_velocities[i] = point_velocity
		mean_radial += offset.length()

	if point_count > 0 and volume_preservation > 0.0:
		var correction: float = mean_radial / float(point_count) * volume_preservation
		for i in range(point_count):
			var angle: float = TAU * float(i) / float(point_count)
			_offsets[i] -= Vector2(cos(angle), sin(angle)) * correction * 0.028


func _update_shedding(delta: float) -> void:
	if not trail_enabled or not _is_airborne or trail_droplets_per_hop <= 0.0:
		return
	var emit_rate := (trail_droplets_per_hop / maxf(0.1, hop_duration)) * airborne_shedding
	_trail_emit_accumulator += delta * emit_rate
	while _trail_emit_accumulator >= 1.0:
		_trail_emit_accumulator -= 1.0
		_spawn_air_droplets(1)


func _spawn_air_droplets(count: int) -> void:
	for _i in range(count):
		var lateral := Vector2(-movement_direction.y, movement_direction.x)
		var world_pos := global_position + lateral * _rng.randf_range(-radius_x * 0.45, radius_x * 0.45)
		var droplet_velocity := -movement_direction * _rng.randf_range(4.0, 22.0) + lateral * _rng.randf_range(-16.0, 16.0)
		_air_droplets.append({
			"position": world_pos,
			"velocity": droplet_velocity,
			"height": maxf(2.0, _jump_height_current * _rng.randf_range(0.45, 0.95) + 4.0),
			"vertical_velocity": _rng.randf_range(6.0, 18.0),
			"size": trail_pixel_radius * _rng.randf_range(0.55, 1.2),
			"age": 0.0,
			"lifetime": _rng.randf_range(0.35, 0.75),
		})


func _spawn_landing_splash() -> void:
	var count := maxi(3, int(round(4.0 + landing_splash * 4.0)))
	for i in range(count):
		var angle := TAU * float(i) / float(count) + _rng.randf_range(-0.25, 0.25)
		var outward := Vector2(cos(angle), sin(angle))
		_air_droplets.append({
			"position": global_position + outward * _rng.randf_range(3.0, 11.0),
			"velocity": outward * _rng.randf_range(18.0, 54.0),
			"height": _rng.randf_range(2.0, 7.0),
			"vertical_velocity": _rng.randf_range(12.0, 30.0),
			"size": trail_pixel_radius * _rng.randf_range(0.7, 1.4),
			"age": 0.0,
			"lifetime": _rng.randf_range(0.35, 0.7),
		})


func _spawn_ground_mark(world_position: Vector2, radius: float, opacity: float) -> void:
	_ground_trail.append({
		"position": world_position,
		"age": 0.0,
		"lifetime": trail_lifetime * _rng.randf_range(0.82, 1.15),
		"radius": radius * _rng.randf_range(0.75, 1.25),
		"opacity": opacity,
		"variant": _rng.randf(),
	})
	while _ground_trail.size() > 96:
		_ground_trail.pop_front()


func _update_trail(delta: float) -> void:
	for i in range(_ground_trail.size() - 1, -1, -1):
		var mark: Dictionary = _ground_trail[i]
		mark["age"] = float(mark["age"]) + delta
		if float(mark["age"]) >= float(mark["lifetime"]):
			_ground_trail.remove_at(i)
		else:
			_ground_trail[i] = mark

	for i in range(_air_droplets.size() - 1, -1, -1):
		var droplet: Dictionary = _air_droplets[i]
		var droplet_pos: Vector2 = droplet["position"] as Vector2
		var droplet_velocity: Vector2 = droplet["velocity"] as Vector2
		var height: float = float(droplet["height"])
		var vertical_velocity: float = float(droplet["vertical_velocity"])
		var age: float = float(droplet["age"]) + delta
		droplet_pos += droplet_velocity * delta
		droplet_velocity *= exp(-3.0 * delta)
		height += vertical_velocity * delta
		vertical_velocity -= 90.0 * delta
		if height <= 0.0 or age >= float(droplet["lifetime"]):
			_spawn_ground_mark(droplet_pos, float(droplet["size"]), 0.66)
			_air_droplets.remove_at(i)
			continue
		droplet["position"] = droplet_pos
		droplet["velocity"] = droplet_velocity
		droplet["height"] = height
		droplet["vertical_velocity"] = vertical_velocity
		droplet["age"] = age
		_air_droplets[i] = droplet


func apply_impulse(impulse: Vector2) -> void:
	if impulse.length_squared() > 0.001:
		set_move_direction(impulse.normalized())
		_roam_target = _clamp_point_to_movement_bounds(position + movement_direction * minf(roam_radius, impulse.length()), radius_x + 12.0)
		_route_watchdog = 2.0
	if _offsets.is_empty():
		return
	var direction := impulse.normalized()
	var strength := minf(18.0, impulse.length() * 0.08) * motion_intensity
	for i in range(_offsets.size()):
		var angle := TAU * float(i) / float(_offsets.size())
		var normal := Vector2(cos(angle), sin(angle))
		var facing := maxf(0.0, normal.dot(direction))
		_point_velocities[i] += direction * strength * (0.25 + facing)
	if not _is_airborne and locomotion_enabled:
		_start_hop()


func _draw() -> void:
	_draw_ground_trail()
	_draw_shadow()
	_draw_landing_puddle()
	_draw_body()
	_draw_air_droplets()


func _draw_ground_trail() -> void:
	for mark: Dictionary in _ground_trail:
		var age: float = float(mark["age"])
		var lifetime: float = maxf(0.01, float(mark["lifetime"]))
		var life_ratio := clampf(1.0 - age / lifetime, 0.0, 1.0)
		var opacity := float(mark["opacity"]) * life_ratio
		var color := secondary_color.lerp(primary_color, float(mark["variant"]) * 0.35)
		color.a = opacity * 0.52
		var local_pos := to_local(mark["position"] as Vector2)
		_draw_pixel_disc(_snap_vec(local_pos), float(mark["radius"]) * global_scale_factor, color)


func _draw_shadow() -> void:
	var height_ratio := clampf(_jump_height_current / maxf(1.0, hop_height), 0.0, 1.0)
	var shadow_scale := lerpf(1.0, 0.58, height_ratio)
	var shadow_alpha := lerpf(0.30, 0.12, height_ratio)
	var shadow := Color(0.02, 0.05, 0.06, shadow_alpha)
	var shadow_center := Vector2(0.0, radius_y * 0.48) * global_scale_factor
	var shadow_size := Vector2(radius_x * 1.62, radius_y * 0.52) * global_scale_factor * shadow_scale
	_px_rect(shadow_center, shadow_size, shadow)


func _draw_landing_puddle() -> void:
	if _is_airborne or _landing_deformation <= 0.02:
		return
	var spread := clampf(_landing_deformation * liquid_spread, 0.0, 2.0)
	var puddle := secondary_color
	puddle.a = body_opacity * 0.24 * spread
	var width := radius_x * (1.15 + spread * 0.52) * global_scale_factor
	var y := radius_y * (0.45 - spread * 0.10) * global_scale_factor
	_px_rect(Vector2(0.0, y), Vector2(width, 3.0), puddle)
	_px_rect(Vector2(-width * 0.18, y + 2.0), Vector2(width * 0.55, 2.0), puddle)
	_px_rect(Vector2(width * 0.23, y + 1.0), Vector2(width * 0.38, 2.0), puddle)


func _body_deformation() -> Dictionary:
	var air_stretch := sin(clampf(_hop_phase, 0.0, 1.0) * PI) if _is_airborne else 0.0
	var landing := _landing_deformation * locomotion_squash * liquid_spread
	var gather := _gather_deformation * locomotion_squash
	var takeoff := _takeoff_deformation * locomotion_squash
	var width_scale := 1.0 + landing * 0.50 - gather * 0.20 - air_stretch * 0.17 + takeoff * 0.10
	var height_scale := 1.0 - landing * 0.40 + gather * 0.22 + air_stretch * 0.38 - takeoff * 0.08
	return {
		"width": maxf(0.48, width_scale),
		"height": maxf(0.46, height_scale),
		"air": air_stretch,
	}


func _draw_body() -> void:
	var deformation := _body_deformation()
	var width_scale := float(deformation["width"])
	var height_scale := float(deformation["height"])
	var air_stretch := float(deformation["air"])
	var jump_ratio := clampf(_jump_height_current / maxf(1.0, hop_height), 0.0, 1.0)
	var body_lag := -movement_direction * (2.0 + jump_ratio * 2.5) * global_scale_factor
	var visual_origin := Vector2(0.0, -_jump_height_current) + body_lag

	var points := PackedVector2Array()
	for i in range(point_count):
		var angle := TAU * float(i) / float(point_count)
		var sin_angle := sin(angle)
		var perspective_width := lerpf(0.88, 1.08, clampf((sin_angle + 1.0) * 0.5, 0.0, 1.0))
		var base := Vector2(
			cos(angle) * radius_x * width_scale * perspective_width,
			sin_angle * radius_y * height_scale
		)
		var p := visual_origin + (base + _offsets[i]) * global_scale_factor
		points.append(_snap_vec(p))

	if points.size() >= 3:
		var shell := primary_color
		shell.a = body_opacity
		draw_colored_polygon(points, shell)

	var lower := secondary_color
	lower.a = body_opacity * 0.46
	var rim_center := visual_origin + Vector2(0.0, radius_y * 0.50 * height_scale) * global_scale_factor
	var rim_size := Vector2(radius_x * 1.44 * width_scale, maxf(2.0, radius_y * 0.30 * height_scale)) * global_scale_factor
	_px_rect(rim_center, rim_size, lower)

	var lateral := Vector2(-movement_direction.y, movement_direction.x)
	var nucleus_offset := -movement_direction * (3.0 + jump_ratio * 2.0) + lateral * sin(_phase * 1.35) * 2.0
	var nucleus_center := visual_origin + nucleus_offset * global_scale_factor
	var nucleus := secondary_color.lerp(shadow_color, 0.24)
	nucleus.a = 0.58
	_draw_pixel_disc(_snap_vec(nucleus_center), radius_x * 0.20 * global_scale_factor, nucleus)
	var nucleus_light := accent_color
	nucleus_light.a = 0.38
	_draw_pixel_disc(_snap_vec(nucleus_center + Vector2(-2.0, -2.0)), maxf(2.0, radius_x * 0.08 * global_scale_factor), nucleus_light)

	var highlight := accent_color
	highlight.a = 0.66
	var h1 := visual_origin + Vector2(-radius_x * 0.34 * width_scale, -radius_y * 0.42 * height_scale) * global_scale_factor
	_px_rect(_snap_vec(h1), Vector2(2.0, 5.0), highlight)
	_px_rect(_snap_vec(h1 + Vector2(2.0, 1.0)), Vector2(2.0, 2.0), highlight)
	var h2 := visual_origin + Vector2(radius_x * 0.18 * width_scale, -radius_y * 0.12 * height_scale) * global_scale_factor
	var h2_color := accent_color
	h2_color.a = 0.40 + air_stretch * 0.20
	_px_rect(_snap_vec(h2), Vector2(4.0, 1.0), h2_color)
	_px_rect(_snap_vec(h2 + Vector2(1.0, -1.0)), Vector2(2.0, 1.0), h2_color)

	for i in range(3):
		var bubble := visual_origin + Vector2(
			sin(_phase * (0.8 + i * 0.17) + i * 2.1) * radius_x * 0.24,
			cos(_phase * (0.7 + i * 0.13) + i * 1.7) * radius_y * 0.23
		) * global_scale_factor
		var bubble_color := accent_color
		bubble_color.a = 0.34
		_px_rect(_snap_vec(bubble), Vector2.ONE, bubble_color)


func _draw_air_droplets() -> void:
	for droplet: Dictionary in _air_droplets:
		var local_pos := to_local(droplet["position"] as Vector2)
		local_pos.y -= float(droplet["height"])
		var age_ratio := clampf(float(droplet["age"]) / maxf(0.01, float(droplet["lifetime"])), 0.0, 1.0)
		var color := primary_color.lerp(accent_color, 0.18)
		color.a = body_opacity * (1.0 - age_ratio * 0.55)
		_draw_pixel_disc(_snap_vec(local_pos), float(droplet["size"]) * global_scale_factor, color)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"radius_x": radius_x = clampf(float(value), 8.0, 64.0)
		&"radius_y": radius_y = clampf(float(value), 8.0, 64.0)
		&"stiffness": stiffness = clampf(float(value), 1.0, 80.0)
		&"damping": damping = clampf(float(value), 0.0, 20.0)
		&"wobble": wobble = clampf(float(value), 0.0, 2.0)
		&"volume_preservation": volume_preservation = clampf(float(value), 0.0, 1.0)
		&"locomotion_squash": locomotion_squash = clampf(float(value), 0.0, 2.0)
		&"body_opacity": body_opacity = clampf(float(value), 0.45, 0.95)
		&"liquid_spread": liquid_spread = clampf(float(value), 0.0, 2.0)
		&"locomotion_enabled": locomotion_enabled = bool(value)
		&"move_speed": move_speed = clampf(float(value), 10.0, 280.0)
		&"hop_interval": hop_interval = clampf(float(value), 0.25, 3.0)
		&"hop_duration": hop_duration = clampf(float(value), 0.15, 1.5)
		&"hop_height": hop_height = clampf(float(value), 2.0, 80.0)
		&"landing_settle_time": landing_settle_time = clampf(float(value), 0.08, 0.8)
		&"pre_jump_gather_time": pre_jump_gather_time = clampf(float(value), 0.05, 0.6)
		&"wander_strength": wander_strength = clampf(float(value), 0.0, 1.0)
		&"auto_roam": auto_roam = bool(value)
		&"roam_radius": roam_radius = clampf(float(value), 64.0, 680.0)
		&"minimum_route_distance": minimum_route_distance = clampf(float(value), 16.0, 360.0)
		&"trail_enabled": trail_enabled = bool(value)
		&"trail_droplets_per_hop": trail_droplets_per_hop = clampf(float(value), 0.0, 24.0)
		&"trail_lifetime": trail_lifetime = clampf(float(value), 0.25, 12.0)
		&"trail_pixel_radius": trail_pixel_radius = clampf(float(value), 1.0, 8.0)
		&"landing_splash": landing_splash = clampf(float(value), 0.0, 2.0)
		&"airborne_shedding": airborne_shedding = clampf(float(value), 0.0, 2.0)
		_:
			return false
	return true


func _get_creature_parameter(key: StringName) -> Variant:
	match key:
		&"radius_x": return radius_x
		&"radius_y": return radius_y
		&"stiffness": return stiffness
		&"damping": return damping
		&"wobble": return wobble
		&"volume_preservation": return volume_preservation
		&"locomotion_squash": return locomotion_squash
		&"body_opacity": return body_opacity
		&"liquid_spread": return liquid_spread
		&"locomotion_enabled": return locomotion_enabled
		&"move_speed": return move_speed
		&"hop_interval": return hop_interval
		&"hop_duration": return hop_duration
		&"hop_height": return hop_height
		&"landing_settle_time": return landing_settle_time
		&"pre_jump_gather_time": return pre_jump_gather_time
		&"wander_strength": return wander_strength
		&"auto_roam": return auto_roam
		&"roam_radius": return roam_radius
		&"minimum_route_distance": return minimum_route_distance
		&"trail_enabled": return trail_enabled
		&"trail_droplets_per_hop": return trail_droplets_per_hop
		&"trail_lifetime": return trail_lifetime
		&"trail_pixel_radius": return trail_pixel_radius
		&"landing_splash": return landing_splash
		&"airborne_shedding": return airborne_shedding
	return null


func _get_creature_editor_schema() -> Array[Dictionary]:
	return [
		{"key": &"locomotion_enabled", "label": "Auto Hop", "type": "bool"},
		{"key": &"auto_roam", "label": "Hop Roam", "type": "bool"},
		{"key": &"move_speed", "label": "Hop Travel", "type": "float", "min": 20.0, "max": 240.0, "step": 1.0},
		{"key": &"hop_interval", "label": "Ground Cycle", "type": "float", "min": 0.35, "max": 2.5, "step": 0.05},
		{"key": &"hop_duration", "label": "Air Time", "type": "float", "min": 0.2, "max": 1.2, "step": 0.05},
		{"key": &"hop_height", "label": "Hop Height", "type": "float", "min": 4.0, "max": 64.0, "step": 1.0},
		{"key": &"landing_settle_time", "label": "Settle Time", "type": "float", "min": 0.08, "max": 0.7, "step": 0.01},
		{"key": &"pre_jump_gather_time", "label": "Gather Time", "type": "float", "min": 0.05, "max": 0.5, "step": 0.01},
		{"key": &"wander_strength", "label": "Hop Wander", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"roam_radius", "label": "Roam Radius", "type": "float", "min": 96.0, "max": 620.0, "step": 8.0},
		{"key": &"minimum_route_distance", "label": "Min Route", "type": "float", "min": 32.0, "max": 340.0, "step": 4.0},
		{"key": &"body_opacity", "label": "Body Opacity", "type": "float", "min": 0.50, "max": 0.92, "step": 0.01},
		{"key": &"liquid_spread", "label": "Liquid Spread", "type": "float", "min": 0.0, "max": 1.8, "step": 0.05},
		{"key": &"locomotion_squash", "label": "Mass Deform", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
		{"key": &"wobble", "label": "Surface Wobble", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
		{"key": &"stiffness", "label": "Gel Stiffness", "type": "float", "min": 2.0, "max": 60.0, "step": 0.5},
		{"key": &"damping", "label": "Gel Damping", "type": "float", "min": 0.5, "max": 16.0, "step": 0.1},
		{"key": &"volume_preservation", "label": "Volume Hold", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"radius_x", "label": "Body Width", "type": "float", "min": 10.0, "max": 58.0, "step": 1.0},
		{"key": &"radius_y", "label": "Body Depth", "type": "float", "min": 10.0, "max": 50.0, "step": 1.0},
		{"key": &"trail_enabled", "label": "Slime Trail", "type": "bool"},
		{"key": &"trail_droplets_per_hop", "label": "Droplets / Hop", "type": "float", "min": 0.0, "max": 18.0, "step": 1.0},
		{"key": &"trail_lifetime", "label": "Trail Lifetime", "type": "float", "min": 0.5, "max": 8.0, "step": 0.25},
		{"key": &"trail_pixel_radius", "label": "Droplet Cluster", "type": "float", "min": 1.0, "max": 6.0, "step": 0.5},
		{"key": &"airborne_shedding", "label": "Air Shedding", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
		{"key": &"landing_splash", "label": "Landing Splash", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
	]
