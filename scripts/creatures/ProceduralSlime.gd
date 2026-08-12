class_name ProceduralSlime
extends ProceduralCreature

@export_group("Blob")
@export_range(8, 32, 1) var point_count := 16
@export_range(8.0, 64.0, 1.0) var radius_x := 27.0
@export_range(8.0, 64.0, 1.0) var radius_y := 21.0
@export_range(1.0, 80.0, 0.5) var stiffness := 24.0
@export_range(0.0, 20.0, 0.1) var damping := 7.0
@export_range(0.0, 1.0, 0.01) var volume_preservation := 0.78
@export_range(0.0, 2.0, 0.05) var wobble := 0.34
@export_range(0.0, 2.0, 0.05) var locomotion_squash := 0.9

@export_group("Top-down Locomotion")
@export var locomotion_enabled := true
@export_range(10.0, 260.0, 1.0) var move_speed := 92.0
@export_range(0.25, 3.0, 0.05) var hop_interval := 0.78
@export_range(0.15, 1.5, 0.05) var hop_duration := 0.52
@export_range(2.0, 80.0, 1.0) var hop_height := 26.0
@export_range(0.0, 1.0, 0.01) var wander_strength := 0.22
@export var movement_direction := Vector2(0.85, 0.35)

@export_group("Slime Shedding")
@export var trail_enabled := true
@export_range(0.0, 24.0, 1.0) var trail_droplets_per_hop := 5.0
@export_range(0.25, 12.0, 0.25) var trail_lifetime := 3.25
@export_range(1.0, 8.0, 0.5) var trail_pixel_radius := 2.0
@export_range(0.0, 2.0, 0.05) var landing_splash := 0.85
@export_range(0.0, 2.0, 0.05) var airborne_shedding := 0.65

var _offsets: PackedVector2Array = PackedVector2Array()
var _point_velocities: PackedVector2Array = PackedVector2Array()
var _phase := 0.0
var _hop_clock := 0.0
var _hop_phase := 0.0
var _jump_height_current := 0.0
var _is_airborne := false
var _landing_deformation := 0.0
var _takeoff_deformation := 0.0
var _movement_bounds := Rect2()
var _has_movement_bounds := false
var _trail_emit_accumulator := 0.0
var _ground_trail: Array[Dictionary] = []
var _air_droplets: Array[Dictionary] = []


func _ready() -> void:
	creature_id = &"slime"
	primary_color = Color("43b9ad")
	secondary_color = Color("187f8f")
	accent_color = Color("b8f0c9")
	shadow_color = Color("163f56")
	movement_direction = movement_direction.normalized()
	super._ready()
	_rebuild_points()


func _reset_simulation() -> void:
	super._reset_simulation()
	_rebuild_points()
	_hop_clock = 0.0
	_hop_phase = 0.0
	_jump_height_current = 0.0
	_is_airborne = false
	_landing_deformation = 0.0
	_takeoff_deformation = 0.0
	_trail_emit_accumulator = 0.0
	_ground_trail.clear()
	_air_droplets.clear()


func set_movement_bounds(bounds: Rect2) -> void:
	_movement_bounds = bounds
	_has_movement_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0


func set_move_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		movement_direction = direction.normalized()


func _rebuild_points() -> void:
	_offsets = PackedVector2Array()
	_point_velocities = PackedVector2Array()
	for i in range(point_count):
		_offsets.append(Vector2.ZERO)
		_point_velocities.append(Vector2.ZERO)


func _simulate_creature(delta: float) -> void:
	if _offsets.size() != point_count:
		_rebuild_points()

	_phase += delta * (2.0 + move_speed * 0.006)
	_update_locomotion(delta)
	_update_blob_springs(delta)
	_update_shedding(delta)
	_update_trail(delta)
	queue_redraw()


func _update_locomotion(delta: float) -> void:
	_landing_deformation = move_toward(_landing_deformation, 0.0, delta * 4.8)
	_takeoff_deformation = move_toward(_takeoff_deformation, 0.0, delta * 5.8)

	if not locomotion_enabled:
		_jump_height_current = move_toward(_jump_height_current, 0.0, delta * 120.0)
		return

	if _is_airborne:
		_hop_phase += delta / maxf(0.05, hop_duration)
		var clamped_phase := clampf(_hop_phase, 0.0, 1.0)
		_jump_height_current = sin(clamped_phase * PI) * hop_height
		var travel_curve := 0.72 + sin(clamped_phase * PI) * 0.28
		_move_on_ground(movement_direction * move_speed * travel_curve * delta)
		if _hop_phase >= 1.0:
			_land_hop()
		return

	_hop_clock += delta
	if _hop_clock >= hop_interval:
		_start_hop()


func _start_hop() -> void:
	_hop_clock = 0.0
	_hop_phase = 0.0
	_is_airborne = true
	_takeoff_deformation = 1.0

	if wander_strength > 0.0:
		var angle_jitter := _rng.randf_range(-0.8, 0.8) * wander_strength
		movement_direction = movement_direction.rotated(angle_jitter).normalized()

	if trail_enabled:
		_spawn_ground_mark(global_position, trail_pixel_radius * 1.15, 0.82)
		_spawn_air_droplets(maxi(1, int(round(trail_droplets_per_hop * 0.35))))


func _land_hop() -> void:
	_is_airborne = false
	_hop_phase = 0.0
	_jump_height_current = 0.0
	_landing_deformation = landing_splash
	_hop_clock = 0.0
	if trail_enabled:
		_spawn_ground_mark(global_position, trail_pixel_radius * (1.4 + landing_splash * 0.45), 1.0)
		_spawn_landing_splash()


func _move_on_ground(displacement: Vector2) -> void:
	var next_position := position + displacement
	if _has_movement_bounds:
		var margin := maxf(radius_x, radius_y) * global_scale_factor + 8.0
		var inner := _movement_bounds.grow(-margin)
		if next_position.x < inner.position.x or next_position.x > inner.end.x:
			movement_direction.x *= -1.0
			next_position.x = clampf(next_position.x, inner.position.x, inner.end.x)
		if next_position.y < inner.position.y or next_position.y > inner.end.y:
			movement_direction.y *= -1.0
			next_position.y = clampf(next_position.y, inner.position.y, inner.end.y)
	position = _snap_vec(next_position) if quantize_motion else next_position


func _update_blob_springs(delta: float) -> void:
	var mean_radial := 0.0
	for i in range(point_count):
		var angle := TAU * float(i) / float(point_count)
		var wave := sin(_phase * 2.0 + angle * 3.0) * wobble * 1.7
		var normal := Vector2(cos(angle), sin(angle))
		var target_offset := normal * wave
		var offset := _offsets[i]
		var point_velocity := _point_velocities[i]
		var spring := (target_offset - offset) * stiffness
		point_velocity += spring * delta
		point_velocity *= exp(-damping * delta)
		offset += point_velocity * delta
		_offsets[i] = offset
		_point_velocities[i] = point_velocity
		mean_radial += offset.length()

	if point_count > 0 and volume_preservation > 0.0:
		var correction := mean_radial / float(point_count) * volume_preservation
		for i in range(point_count):
			var angle := TAU * float(i) / float(point_count)
			_offsets[i] -= Vector2(cos(angle), sin(angle)) * correction * 0.035


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
	var count := maxi(2, int(round(3.0 + landing_splash * 4.0)))
	for i in range(count):
		var angle := TAU * float(i) / float(count) + _rng.randf_range(-0.25, 0.25)
		var outward := Vector2(cos(angle), sin(angle))
		_air_droplets.append({
			"position": global_position + outward * _rng.randf_range(3.0, 10.0),
			"velocity": outward * _rng.randf_range(18.0, 52.0),
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
			_spawn_ground_mark(droplet_pos, float(droplet["size"]), 0.72)
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
	_draw_body()
	_draw_air_droplets()


func _draw_ground_trail() -> void:
	for mark: Dictionary in _ground_trail:
		var age: float = float(mark["age"])
		var lifetime: float = maxf(0.01, float(mark["lifetime"]))
		var life_ratio := clampf(1.0 - age / lifetime, 0.0, 1.0)
		var opacity := float(mark["opacity"]) * life_ratio
		var color := secondary_color.lerp(primary_color, float(mark["variant"]) * 0.35)
		color.a = opacity * 0.78
		var local_pos := to_local(mark["position"] as Vector2)
		_draw_pixel_disc(_snap_vec(local_pos), float(mark["radius"]) * global_scale_factor, color)


func _draw_shadow() -> void:
	var height_ratio := clampf(_jump_height_current / maxf(1.0, hop_height), 0.0, 1.0)
	var shadow_scale := lerpf(1.0, 0.62, height_ratio)
	var shadow_alpha := lerpf(0.34, 0.16, height_ratio)
	var shadow := Color(0.02, 0.05, 0.06, shadow_alpha)
	var shadow_center := Vector2(0.0, radius_y * 0.45) * global_scale_factor
	var shadow_size := Vector2(radius_x * 1.55, radius_y * 0.58) * global_scale_factor * shadow_scale
	_px_rect(shadow_center, shadow_size, shadow)


func _draw_body() -> void:
	var jump_ratio := clampf(_jump_height_current / maxf(1.0, hop_height), 0.0, 1.0)
	var midair_stretch := sin(_hop_phase * PI) if _is_airborne else 0.0
	var squash := (_landing_deformation * 0.55 + _takeoff_deformation * 0.28) * locomotion_squash
	var stretch := midair_stretch * 0.26 * locomotion_squash
	var width_scale := 1.0 + squash * 0.34 - stretch * 0.18
	var height_scale := 1.0 - squash * 0.30 + stretch * 0.38
	var body_lag := -movement_direction * (2.5 + jump_ratio * 2.0) * global_scale_factor
	var visual_origin := Vector2(0.0, -_jump_height_current) + body_lag

	var points := PackedVector2Array()
	for i in range(point_count):
		var angle := TAU * float(i) / float(point_count)
		var sin_angle := sin(angle)
		var perspective_width := lerpf(0.86, 1.08, clampf((sin_angle + 1.0) * 0.5, 0.0, 1.0))
		var base := Vector2(
			cos(angle) * radius_x * width_scale * perspective_width,
			sin_angle * radius_y * height_scale
		)
		var p := visual_origin + (base + _offsets[i]) * global_scale_factor
		points.append(_snap_vec(p))
	if points.size() >= 3:
		draw_colored_polygon(points, primary_color)

	# Lower/front rim establishes the Oathwake top-down read without a face pointed at camera.
	var rim_center := visual_origin + Vector2(0.0, radius_y * 0.53 * height_scale) * global_scale_factor
	var rim_size := Vector2(radius_x * 1.42 * width_scale, maxf(2.0, radius_y * 0.34)) * global_scale_factor
	_px_rect(rim_center, rim_size, secondary_color)

	# A smaller raised cap and highlights make the body read as a translucent mound viewed from above.
	var cap_center := visual_origin + Vector2(-radius_x * 0.10, -radius_y * 0.22) * global_scale_factor
	var cap_color := primary_color.lerp(accent_color, 0.20)
	_draw_pixel_disc(_snap_vec(cap_center), radius_x * 0.34 * global_scale_factor, cap_color)
	var highlight := visual_origin + Vector2(-radius_x * 0.34, -radius_y * 0.48) * global_scale_factor
	_px_rect(highlight, Vector2(pixel_size * 2.0, pixel_size * 4.0) * global_scale_factor, accent_color)
	_px_rect(highlight + Vector2(pixel_size * 2.0, pixel_size * 1.0), Vector2(pixel_size * 2.0, pixel_size * 2.0) * global_scale_factor, accent_color)
	var sparkle := visual_origin + Vector2(radius_x * 0.22, -radius_y * 0.16) * global_scale_factor
	_px_rect(sparkle, Vector2(pixel_size * 3.0, pixel_size) * global_scale_factor, accent_color)
	_px_rect(sparkle, Vector2(pixel_size, pixel_size * 3.0) * global_scale_factor, accent_color)


func _draw_air_droplets() -> void:
	for droplet: Dictionary in _air_droplets:
		var local_pos := to_local(droplet["position"] as Vector2)
		local_pos.y -= float(droplet["height"])
		var age_ratio := clampf(float(droplet["age"]) / maxf(0.01, float(droplet["lifetime"])), 0.0, 1.0)
		var color := primary_color.lerp(accent_color, 0.18)
		color.a = 1.0 - age_ratio * 0.45
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
		&"locomotion_enabled": locomotion_enabled = bool(value)
		&"move_speed": move_speed = clampf(float(value), 10.0, 260.0)
		&"hop_interval": hop_interval = clampf(float(value), 0.25, 3.0)
		&"hop_duration": hop_duration = clampf(float(value), 0.15, 1.5)
		&"hop_height": hop_height = clampf(float(value), 2.0, 80.0)
		&"wander_strength": wander_strength = clampf(float(value), 0.0, 1.0)
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
		&"locomotion_enabled": return locomotion_enabled
		&"move_speed": return move_speed
		&"hop_interval": return hop_interval
		&"hop_duration": return hop_duration
		&"hop_height": return hop_height
		&"wander_strength": return wander_strength
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
		{"key": &"move_speed", "label": "Move Speed", "type": "float", "min": 10.0, "max": 220.0, "step": 1.0},
		{"key": &"hop_interval", "label": "Hop Interval", "type": "float", "min": 0.25, "max": 2.5, "step": 0.05},
		{"key": &"hop_duration", "label": "Hop Duration", "type": "float", "min": 0.2, "max": 1.2, "step": 0.05},
		{"key": &"hop_height", "label": "Hop Height", "type": "float", "min": 4.0, "max": 64.0, "step": 1.0},
		{"key": &"wander_strength", "label": "Wander", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"trail_enabled", "label": "Slime Trail", "type": "bool"},
		{"key": &"trail_droplets_per_hop", "label": "Droplets / Hop", "type": "float", "min": 0.0, "max": 18.0, "step": 1.0},
		{"key": &"trail_lifetime", "label": "Trail Lifetime", "type": "float", "min": 0.5, "max": 8.0, "step": 0.25},
		{"key": &"trail_pixel_radius", "label": "Droplet Size", "type": "float", "min": 1.0, "max": 6.0, "step": 0.5},
		{"key": &"airborne_shedding", "label": "Air Shedding", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
		{"key": &"landing_splash", "label": "Landing Splash", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
		{"key": &"radius_x", "label": "Width", "type": "float", "min": 10.0, "max": 58.0, "step": 1.0},
		{"key": &"radius_y", "label": "Depth", "type": "float", "min": 10.0, "max": 50.0, "step": 1.0},
		{"key": &"stiffness", "label": "Gel Stiffness", "type": "float", "min": 2.0, "max": 60.0, "step": 0.5},
		{"key": &"damping", "label": "Gel Damping", "type": "float", "min": 0.5, "max": 16.0, "step": 0.1},
		{"key": &"wobble", "label": "Wobble", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
		{"key": &"volume_preservation", "label": "Volume Hold", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"locomotion_squash", "label": "Squash / Stretch", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
	]
