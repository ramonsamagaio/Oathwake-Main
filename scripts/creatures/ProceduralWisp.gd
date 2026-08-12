class_name ProceduralWisp
extends ProceduralCreature

@export_group("Field / Trail")
@export_range(3, 24, 1) var trail_points := 12
@export_range(2.0, 24.0, 0.5) var core_radius := 9.0
@export_range(0.0, 24.0, 0.5) var drift_amplitude := 8.0
@export_range(0.1, 8.0, 0.05) var drift_speed := 1.6
@export_range(0.0, 30.0, 0.5) var trail_spacing := 7.0
@export_range(0.0, 1.0, 0.01) var trail_follow := 0.62
@export_range(0, 12, 1) var mote_count := 5
@export_range(0.0, 40.0, 0.5) var mote_orbit_radius := 18.0
@export_range(0.0, 8.0, 0.05) var mote_orbit_speed := 1.7

var _trail: PackedVector2Array = PackedVector2Array()
var _phase := 0.0
var _origin := Vector2.ZERO


func _ready() -> void:
	creature_id = &"wisp"
	super._ready()
	_origin = position
	_rebuild_trail()


func _reset_simulation() -> void:
	super._reset_simulation()
	_origin = position
	_rebuild_trail()


func _rebuild_trail() -> void:
	_trail = PackedVector2Array()
	for i in range(trail_points):
		_trail.append(Vector2(0.0, float(i) * trail_spacing))


func _simulate_creature(delta: float) -> void:
	if _trail.size() != trail_points:
		_rebuild_trail()
	_phase += delta * drift_speed * motion_intensity

	var desired := _origin + Vector2(
		sin(_phase * 0.91) * drift_amplitude,
		cos(_phase * 1.23) * drift_amplitude * 0.65
	)
	position = position.lerp(desired, clampf(delta * 2.0, 0.0, 1.0))
	_trail[0] = Vector2.ZERO
	for i in range(1, trail_points):
		var previous := _trail[i - 1]
		var current := _trail[i]
		var noise := Vector2(
			sin(_phase * 1.7 + i * 0.8),
			cos(_phase * 1.25 + i * 0.57)
		) * drift_amplitude * 0.08
		var target := previous + Vector2(0.0, trail_spacing) + noise
		_trail[i] = current.lerp(target, trail_follow)


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	_origin += impulse * 0.12


func _draw() -> void:
	for i in range(_trail.size() - 1, 0, -1):
		var t := float(i) / float(maxi(1, _trail.size() - 1))
		var radius := lerpf(core_radius * 0.7, maxf(1.0, pixel_size * 0.65), t) * global_scale_factor
		var color := secondary_color
		color.a = lerpf(0.75, 0.16, t)
		_draw_pixel_disc(_trail[i] * global_scale_factor, radius, color)

	_draw_pixel_disc(Vector2.ZERO, core_radius * global_scale_factor, primary_color)
	_draw_pixel_disc(Vector2.ZERO, core_radius * 0.52 * global_scale_factor, accent_color)
	_draw_pixel_disc(Vector2.ZERO, maxf(1.0, core_radius * 0.2) * global_scale_factor, Color(1, 1, 1, 0.95))

	for i in range(mote_count):
		var angle := _phase * mote_orbit_speed + TAU * float(i) / float(maxi(1, mote_count))
		var wobble := 0.75 + 0.25 * sin(_phase * 1.3 + i * 2.1)
		var p := Vector2(cos(angle), sin(angle)) * mote_orbit_radius * wobble * global_scale_factor
		_draw_pixel_disc(p, maxf(float(pixel_size), 2.0 * global_scale_factor), accent_color)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"core_radius": core_radius = clampf(float(value), 2.0, 24.0)
		&"drift_amplitude": drift_amplitude = clampf(float(value), 0.0, 24.0)
		&"drift_speed": drift_speed = clampf(float(value), 0.1, 8.0)
		&"trail_spacing": trail_spacing = clampf(float(value), 0.0, 30.0)
		&"trail_follow": trail_follow = clampf(float(value), 0.0, 1.0)
		&"mote_count": mote_count = clampi(int(value), 0, 12)
		&"mote_orbit_radius": mote_orbit_radius = clampf(float(value), 0.0, 40.0)
		&"mote_orbit_speed": mote_orbit_speed = clampf(float(value), 0.0, 8.0)
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
		&"mote_count": return mote_count
		&"mote_orbit_radius": return mote_orbit_radius
		&"mote_orbit_speed": return mote_orbit_speed
	return null


func _get_creature_editor_schema() -> Array[Dictionary]:
	return [
		{"key": &"core_radius", "label": "Core Size", "type": "float", "min": 3.0, "max": 20.0, "step": 0.5},
		{"key": &"drift_amplitude", "label": "Hover Drift", "type": "float", "min": 0.0, "max": 22.0, "step": 0.5},
		{"key": &"drift_speed", "label": "Hover Speed", "type": "float", "min": 0.1, "max": 5.0, "step": 0.05},
		{"key": &"trail_spacing", "label": "Trail Length", "type": "float", "min": 1.0, "max": 24.0, "step": 0.5},
		{"key": &"trail_follow", "label": "Trail Elasticity", "type": "float", "min": 0.05, "max": 1.0, "step": 0.01},
		{"key": &"mote_count", "label": "Orbit Motes", "type": "int", "min": 0, "max": 10, "step": 1},
		{"key": &"mote_orbit_radius", "label": "Orbit Radius", "type": "float", "min": 0.0, "max": 36.0, "step": 0.5},
		{"key": &"mote_orbit_speed", "label": "Orbit Speed", "type": "float", "min": 0.0, "max": 6.0, "step": 0.05},
	]
