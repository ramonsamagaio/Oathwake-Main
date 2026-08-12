class_name ProceduralSlime
extends ProceduralCreature

@export_group("Blob")
@export_range(8, 32, 1) var point_count := 16
@export_range(8.0, 64.0, 1.0) var radius_x := 30.0
@export_range(8.0, 64.0, 1.0) var radius_y := 24.0
@export_range(1.0, 80.0, 0.5) var stiffness := 26.0
@export_range(0.0, 20.0, 0.1) var damping := 7.5
@export_range(0.0, 1.0, 0.01) var volume_preservation := 0.72
@export_range(0.0, 2.0, 0.05) var wobble := 0.45
@export_range(0.0, 2.0, 0.05) var locomotion_squash := 0.65

var _offsets: PackedVector2Array = PackedVector2Array()
var _point_velocities: PackedVector2Array = PackedVector2Array()
var _phase := 0.0


func _ready() -> void:
	creature_id = &"slime"
	super._ready()
	_rebuild_points()


func _reset_simulation() -> void:
	super._reset_simulation()
	_rebuild_points()


func _rebuild_points() -> void:
	_offsets = PackedVector2Array()
	_point_velocities = PackedVector2Array()
	for i in range(point_count):
		_offsets.append(Vector2.ZERO)
		_point_velocities.append(Vector2.ZERO)


func _simulate_creature(delta: float) -> void:
	if _offsets.size() != point_count:
		_rebuild_points()

	_phase += delta * (2.0 + velocity.length() * 0.015)
	var speed_squash := clampf(absf(velocity.y) * 0.008 + velocity.length() * 0.002, 0.0, 0.35) * locomotion_squash
	var mean_radial := 0.0

	for i in range(point_count):
		var angle := TAU * float(i) / float(point_count)
		var wave := sin(_phase * 2.0 + angle * 3.0) * wobble * 2.0
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
			_offsets[i] -= Vector2(cos(angle), sin(angle)) * correction * 0.04


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	if _offsets.is_empty():
		return
	var direction := impulse.normalized()
	var strength := minf(18.0, impulse.length() * 0.08) * motion_intensity
	for i in range(_offsets.size()):
		var angle := TAU * float(i) / float(_offsets.size())
		var normal := Vector2(cos(angle), sin(angle))
		var facing := maxf(0.0, normal.dot(direction))
		_point_velocities[i] += direction * strength * (0.25 + facing)


func _draw() -> void:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle := TAU * float(i) / float(point_count)
		var speed_squash := clampf(absf(velocity.y) * 0.008 + velocity.length() * 0.002, 0.0, 0.35) * locomotion_squash
		var base := Vector2(
			cos(angle) * radius_x * (1.0 + speed_squash),
			sin(angle) * radius_y * (1.0 - speed_squash)
		)
		var p := (base + _offsets[i]) * global_scale_factor
		points.append(_snap_vec(p))
	if points.size() >= 3:
		draw_colored_polygon(points, primary_color)
	_px_rect(Vector2(0, radius_y * 0.45) * global_scale_factor, Vector2(radius_x * 1.35, pixel_size * 2) * global_scale_factor, secondary_color)
	var eye_y := -radius_y * 0.14 * global_scale_factor
	var eye_x := radius_x * 0.27 * global_scale_factor
	_draw_pixel_disc(Vector2(-eye_x, eye_y), 2.5 * global_scale_factor, shadow_color)
	_draw_pixel_disc(Vector2(eye_x, eye_y), 2.5 * global_scale_factor, shadow_color)
	_px_rect(Vector2(0, radius_y * 0.16) * global_scale_factor, Vector2(pixel_size * 3, pixel_size), accent_color)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"radius_x": radius_x = clampf(float(value), 8.0, 64.0)
		&"radius_y": radius_y = clampf(float(value), 8.0, 64.0)
		&"stiffness": stiffness = clampf(float(value), 1.0, 80.0)
		&"damping": damping = clampf(float(value), 0.0, 20.0)
		&"wobble": wobble = clampf(float(value), 0.0, 2.0)
		&"volume_preservation": volume_preservation = clampf(float(value), 0.0, 1.0)
		&"locomotion_squash": locomotion_squash = clampf(float(value), 0.0, 2.0)
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
	return null


func _get_creature_editor_schema() -> Array[Dictionary]:
	return [
		{"key": &"radius_x", "label": "Width", "type": "float", "min": 10.0, "max": 58.0, "step": 1.0},
		{"key": &"radius_y", "label": "Height", "type": "float", "min": 10.0, "max": 50.0, "step": 1.0},
		{"key": &"stiffness", "label": "Gel Stiffness", "type": "float", "min": 2.0, "max": 60.0, "step": 0.5},
		{"key": &"damping", "label": "Gel Damping", "type": "float", "min": 0.5, "max": 16.0, "step": 0.1},
		{"key": &"wobble", "label": "Wobble", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
		{"key": &"volume_preservation", "label": "Volume Hold", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"locomotion_squash", "label": "Squash / Stretch", "type": "float", "min": 0.0, "max": 1.5, "step": 0.05},
	]
