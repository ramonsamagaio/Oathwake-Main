class_name ProceduralSnake
extends ProceduralCreature

const SNAKE_VISUAL_SHADER: Shader = preload("res://shaders/creatures/snake_scale_pixel.gdshader")

@export_group("Chain")
@export_range(12, 36, 1) var segment_count := 26
@export_range(3.0, 16.0, 0.5) var segment_spacing := 5.5
@export_range(2.0, 16.0, 0.5) var head_radius := 8.0
@export_range(0.0, 20.0, 0.25) var wave_amplitude := 8.0
@export_range(0.1, 8.0, 0.05) var wave_frequency := 2.0
@export_range(0.0, 8.0, 0.05) var wave_speed := 3.4
@export_range(0.0, 1.0, 0.01) var follow_tightness := 0.82
@export_range(0.0, 1.0, 0.01) var dorsal_pattern_strength := 0.72
@export_range(0.2, 0.8, 0.01) var dorsal_band_width := 0.46

@export_group("Top-down Roaming")
@export_range(0.0, 140.0, 1.0) var crawl_speed := 58.0
@export var auto_crawl := true
@export_range(64.0, 620.0, 8.0) var roam_radius := 390.0
@export_range(8.0, 320.0, 4.0) var minimum_route_distance := 220.0
@export_range(4.0, 80.0, 1.0) var target_reach_distance := 14.0
@export_range(0.2, 12.0, 0.1) var turn_speed := 3.2
@export_range(0.5, 12.0, 0.1) var retarget_min_time := 4.0
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
	primary_color = Color("6f7f46")
	secondary_color = Color("3f5338")
	accent_color = Color("c7b96b")
	shadow_color = Color("27342b")
	palette_band_strength = 0.90
	material_detail_strength = 0.44
	_home_position = position
	super._ready()
	_install_visual_shader(SNAKE_VISUAL_SHADER)
	_rebuild_chain()
	_last_head_world = global_position
	_choose_roam_target()
	_sync_snake_material()


func _reset_simulation() -> void:
	super._reset_simulation()
	_home_position = position
	_rebuild_chain()
	_last_head_world = global_position
	_choose_roam_target()


func _rebuild_chain() -> void:
	_segments = PackedVector2Array()
	for i in range(segment_count):
		_segments.append(Vector2(-float(i) * segment_spacing, 0.0))


func _choose_roam_target() -> void:
	var margin := head_radius * global_scale_factor + 12.0
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
		_roam_target = _clamp_point_to_movement_bounds(_home_position, head_radius * global_scale_factor + 12.0)
		to_target = _roam_target - position

	if to_target.length_squared() > 0.001:
		var desired := to_target.normalized()
		var blend := clampf(delta * turn_speed, 0.0, 1.0)
		_heading = _heading.lerp(desired, blend)
		if _heading.length_squared() > 0.001:
			_heading = _heading.normalized()

	var max_turn := deg_to_rad(clampf(wave_amplitude * 2.5, 0.0, 46.0))
	var serpentine := sin(_phase * wave_frequency) * max_turn
	_move_heading = _heading.rotated(serpentine).normalized()
	velocity = _move_heading * crawl_speed


func _update_chain_from_motion() -> void:
	var current_head_world := global_position
	var displacement := current_head_world - _last_head_world
	_last_head_world = current_head_world
	if displacement.length_squared() <= 0.0001:
		return

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
	_sync_snake_material()


func _sync_snake_material() -> void:
	if _visual_material != null:
		_visual_material.set_shader_parameter(&"scale_phase", _phase * 0.18)


func apply_impulse(impulse: Vector2) -> void:
	super.apply_impulse(impulse)
	if impulse.length_squared() > 4.0:
		_heading = impulse.normalized()
		_move_heading = _heading
		_roam_target = _clamp_point_to_movement_bounds(
			position + _heading * minf(roam_radius, impulse.length() * 0.8),
			head_radius * global_scale_factor + 12.0
		)
		_retarget_clock = _roam_watchdog_time(position.distance_to(_roam_target), crawl_speed, 2.0, 1.0)


func _segment_radius(index: int) -> float:
	var t := float(index) / float(maxi(1, segment_count - 1))
	var taper := lerpf(head_radius * 0.76, maxf(1.0, head_radius * 0.16), t)
	var torso_fullness := sin(t * PI) * head_radius * 0.13
	var body := taper + torso_fullness
	if index >= 1 and index <= 4:
		body *= 1.08
	return maxf(1.0, round(body * global_scale_factor))


func _segment_tangent(index: int) -> Vector2:
	if _segments.size() <= 1:
		return _move_heading.normalized()
	var before_index := maxi(0, index - 1)
	var after_index := mini(_segments.size() - 1, index + 1)
	var tangent := _segments[before_index] - _segments[after_index]
	if tangent.length_squared() <= 0.0001:
		return _move_heading.normalized()
	return tangent.normalized()


func _build_body_ribbon(radius_scale: float = 1.0, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(1, _segments.size()):
		var center := _segments[i] * global_scale_factor + offset
		var tangent := _segment_tangent(i)
		var normal := Vector2(-tangent.y, tangent.x)
		var radius := maxf(1.0, _segment_radius(i) * radius_scale)
		left.append(_snap_vec(center + normal * radius))
		right.append(_snap_vec(center - normal * radius))

	var ribbon := PackedVector2Array()
	for p in left:
		ribbon.append(p)
	for i in range(right.size() - 1, -1, -1):
		ribbon.append(right[i])
	return ribbon


func _draw_scale_mark(center: Vector2, tangent: Vector2, normal: Vector2, size: float, color: Color) -> void:
	var half_length := maxf(1.0, round(size))
	var half_width := maxf(1.0, round(size * 0.52))
	var mark := PackedVector2Array([
		_snap_vec(center + tangent * half_length),
		_snap_vec(center + normal * half_width),
		_snap_vec(center - tangent * half_length),
		_snap_vec(center - normal * half_width),
	])
	if mark.size() >= 3:
		draw_colored_polygon(mark, color)


func _draw() -> void:
	if _segments.size() < 3:
		return

	var shadow_color_local := shadow_color
	shadow_color_local.a = 0.34
	var shadow_ribbon := _build_body_ribbon(0.95, Vector2(1.0, 2.0))
	if shadow_ribbon.size() >= 3:
		draw_colored_polygon(shadow_ribbon, shadow_color_local)

	# The simulation remains segment-based, but the player sees one continuous
	# silhouette. No bead/circle structure is exposed by the renderer anymore.
	var body_ribbon := _build_body_ribbon(1.0)
	var body_color := _palette_mid().lerp(primary_color, 0.45)
	if body_ribbon.size() >= 3:
		draw_colored_polygon(body_ribbon, body_color)

	var dorsal_ribbon := _build_body_ribbon(dorsal_band_width)
	var dorsal_color := secondary_color.lerp(primary_color, 0.18)
	if dorsal_ribbon.size() >= 3:
		draw_colored_polygon(dorsal_ribbon, dorsal_color)

	# Hand-authored-looking scale rhythm. Seeded phase comes from the material;
	# these larger motifs intentionally skip and alternate along the body.
	for i in range(3, _segments.size() - 2):
		if i % 3 != 0:
			continue
		var center := _segments[i] * global_scale_factor
		var tangent := _segment_tangent(i)
		var normal := Vector2(-tangent.y, tangent.x)
		var side_offset := normal * (1.0 if (i / 3) % 2 == 0 else -1.0) * maxf(1.0, _segment_radius(i) * 0.18)
		var mark_color := _palette_light().lerp(accent_color, 0.22)
		mark_color.a = 0.55 + dorsal_pattern_strength * 0.45
		_draw_scale_mark(center + side_offset, tangent, normal, 1.0 + dorsal_pattern_strength, mark_color)

	var facing := _move_heading.normalized() if _move_heading.length_squared() > 0.001 else _heading.normalized()
	var side := Vector2(-facing.y, facing.x)
	var head_radius_px := maxf(2.0, round(head_radius * global_scale_factor))
	var head := Vector2.ZERO

	_draw_pixel_disc(head + Vector2(1.0, 2.0), head_radius_px, shadow_color_local)
	_draw_pixel_disc(head, head_radius_px, primary_color)
	var cheek_color := _palette_mid()
	_draw_pixel_disc(head - facing * head_radius_px * 0.20, head_radius_px * 0.72, cheek_color)

	# Broad wedge snout and a darker neck break the generic circular head.
	var snout_center := head + facing * head_radius_px * 0.62
	var snout := PackedVector2Array([
		_snap_vec(snout_center + facing * head_radius_px * 0.52),
		_snap_vec(snout_center + side * head_radius_px * 0.58),
		_snap_vec(snout_center - facing * head_radius_px * 0.34 + side * head_radius_px * 0.42),
		_snap_vec(snout_center - facing * head_radius_px * 0.34 - side * head_radius_px * 0.42),
		_snap_vec(snout_center - side * head_radius_px * 0.58),
	])
	if snout.size() >= 3:
		draw_colored_polygon(snout, primary_color)
	_px_rect(_snap_vec(head - facing * head_radius_px * 0.46), Vector2(3.0, 2.0), secondary_color)

	# Crown markings echo the dorsal pattern and make the head recognizable at a glance.
	var crown := head - facing * head_radius_px * 0.06
	_draw_scale_mark(crown, facing, side, 2.0, _palette_light())
	_px_rect(_snap_vec(crown - facing * 2.0), Vector2.ONE, accent_color)

	var eye_base := head + facing * head_radius_px * 0.34
	var eye_spacing := maxf(2.0, head_radius_px * 0.49)
	var eye_a := _snap_vec(eye_base + side * eye_spacing)
	var eye_b := _snap_vec(eye_base - side * eye_spacing)
	_px_rect(eye_a, Vector2(2.0, 2.0), accent_color)
	_px_rect(eye_b, Vector2(2.0, 2.0), accent_color)
	_px_rect(eye_a + facing, Vector2.ONE, shadow_color)
	_px_rect(eye_b + facing, Vector2.ONE, shadow_color)
	_px_rect(eye_a - side, Vector2.ONE, _palette_glint())
	_px_rect(eye_b + side, Vector2.ONE, _palette_glint())

	var mouth := _snap_vec(snout_center + facing * head_radius_px * 0.74)
	_px_rect(mouth, Vector2(2.0, 1.0), shadow_color)
	var tongue_color := accent_color.lerp(primary_color, 0.18)
	_px_rect(_snap_vec(mouth + facing * 2.0), Vector2(2.0, 1.0), tongue_color)
	_px_rect(_snap_vec(mouth + facing * 3.0 + side), Vector2.ONE, tongue_color)
	_px_rect(_snap_vec(mouth + facing * 3.0 - side), Vector2.ONE, tongue_color)


func _set_creature_parameter(key: StringName, value: Variant) -> bool:
	match key:
		&"segment_count":
			segment_count = clampi(int(value), 12, 36)
			_rebuild_chain()
		&"segment_spacing": segment_spacing = clampf(float(value), 3.0, 16.0)
		&"head_radius": head_radius = clampf(float(value), 2.0, 16.0)
		&"wave_amplitude": wave_amplitude = clampf(float(value), 0.0, 20.0)
		&"wave_frequency": wave_frequency = clampf(float(value), 0.1, 8.0)
		&"wave_speed": wave_speed = clampf(float(value), 0.0, 8.0)
		&"follow_tightness": follow_tightness = clampf(float(value), 0.0, 1.0)
		&"dorsal_pattern_strength": dorsal_pattern_strength = clampf(float(value), 0.0, 1.0)
		&"dorsal_band_width": dorsal_band_width = clampf(float(value), 0.2, 0.8)
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
		&"segment_count": return segment_count
		&"segment_spacing": return segment_spacing
		&"head_radius": return head_radius
		&"wave_amplitude": return wave_amplitude
		&"wave_frequency": return wave_frequency
		&"wave_speed": return wave_speed
		&"follow_tightness": return follow_tightness
		&"dorsal_pattern_strength": return dorsal_pattern_strength
		&"dorsal_band_width": return dorsal_band_width
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
		{"key": &"segment_count", "label": "Body Segments", "type": "int", "min": 12, "max": 36, "step": 1},
		{"key": &"segment_spacing", "label": "Segment Length", "type": "float", "min": 3.0, "max": 14.0, "step": 0.5},
		{"key": &"head_radius", "label": "Head Size", "type": "float", "min": 3.0, "max": 14.0, "step": 0.5},
		{"key": &"dorsal_pattern_strength", "label": "Scale Pattern", "type": "float", "min": 0.0, "max": 1.0, "step": 0.01},
		{"key": &"dorsal_band_width", "label": "Dorsal Band", "type": "float", "min": 0.2, "max": 0.8, "step": 0.01},
		{"key": &"wave_amplitude", "label": "Serpentine Width", "type": "float", "min": 0.0, "max": 16.0, "step": 0.25},
		{"key": &"wave_frequency", "label": "Serpentine Frequency", "type": "float", "min": 0.2, "max": 6.0, "step": 0.05},
		{"key": &"wave_speed", "label": "Serpentine Speed", "type": "float", "min": 0.0, "max": 7.0, "step": 0.05},
		{"key": &"follow_tightness", "label": "Body Tightness", "type": "float", "min": 0.15, "max": 1.0, "step": 0.01},
		{"key": &"crawl_speed", "label": "Move Speed", "type": "float", "min": 0.0, "max": 130.0, "step": 1.0},
		{"key": &"auto_crawl", "label": "Auto Roam", "type": "bool"},
		{"key": &"roam_radius", "label": "Roam Radius", "type": "float", "min": 96.0, "max": 560.0, "step": 8.0},
		{"key": &"minimum_route_distance", "label": "Min Route", "type": "float", "min": 32.0, "max": 300.0, "step": 4.0},
		{"key": &"turn_speed", "label": "Turn Speed", "type": "float", "min": 0.2, "max": 10.0, "step": 0.1},
		{"key": &"retarget_min_time", "label": "Watchdog Min", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
		{"key": &"retarget_max_time", "label": "Watchdog Slack", "type": "float", "min": 1.0, "max": 10.0, "step": 0.1},
	]
