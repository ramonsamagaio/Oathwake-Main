@tool
extends Node2D

@export_group("Shape")
@export_range(4.0, 512.0, 1.0) var outer_radius: float = 88.0
@export_range(0.0, 512.0, 1.0) var inner_radius: float = 26.0
@export_range(0.1, 1.0, 0.01) var perspective_y: float = 0.42
@export_range(16, 160, 1) var segment_count: int = 72
@export_range(1, 8, 1) var ring_count: int = 3
@export_range(0.5, 8.0, 0.5) var line_width: float = 2.0

@export_group("Runes / Spokes")
@export_range(0, 32, 1) var spoke_count: int = 8
@export_range(0, 32, 1) var rune_count: int = 12
@export_range(1.0, 24.0, 0.5) var rune_size: float = 6.0
@export_range(0.0, 1.0, 0.01) var rune_radius_ratio: float = 0.82
@export var draw_rune_diamonds: bool = true
@export var draw_inner_star: bool = true

@export_group("Color")
@export var main_color: Color = Color(0.72, 0.28, 1.0, 1.0)
@export var accent_color: Color = Color(1.0, 0.44, 0.95, 1.0)
@export var core_color: Color = Color(0.36, 0.16, 0.86, 1.0)
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.72
@export_range(0.0, 1.0, 0.01) var accent_alpha: float = 0.62
@export_range(0.0, 1.0, 0.01) var core_alpha: float = 0.18

@export_group("Animation")
@export var pulse_enabled: bool = true
@export_range(0.0, 0.5, 0.01) var pulse_amount: float = 0.06
@export_range(0.05, 10.0, 0.05) var pulse_speed: float = 1.2
@export_range(-6.0, 6.0, 0.01) var rotation_speed: float = 0.12
@export_range(-6.0, 6.0, 0.01) var rune_rotation_speed: float = -0.08
@export_range(0.0, 1.0, 0.01) var shimmer_amount: float = 0.08
@export_range(0.0, 10.0, 0.05) var shimmer_speed: float = 2.4

@export_group("Render")
@export var additive_blend: bool = true
@export var z_index_value: int = 0
@export var visible_in_editor: bool = true

var _time: float = 0.0
var _additive_material: CanvasItemMaterial


func _ready() -> void:
	_ensure_material()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	z_index = z_index_value
	_apply_material()
	queue_redraw()


func _draw() -> void:
	if Engine.is_editor_hint() and not visible_in_editor:
		return

	var pulse := 1.0
	if pulse_enabled:
		pulse += sin(_time * pulse_speed) * pulse_amount

	var shimmer := 1.0 + (sin(_time * shimmer_speed) * shimmer_amount)
	var draw_outer_radius := outer_radius * pulse
	var draw_inner_radius := minf(inner_radius * pulse, draw_outer_radius - 1.0)
	var draw_rotation := _time * rotation_speed
	var rune_rotation := _time * rune_rotation_speed

	_draw_core(draw_inner_radius, shimmer)
	_draw_rings(draw_inner_radius, draw_outer_radius, draw_rotation, shimmer)
	_draw_spokes(draw_inner_radius, draw_outer_radius, draw_rotation, shimmer)
	if draw_inner_star:
		_draw_star(draw_inner_radius, draw_rotation - rune_rotation, shimmer)
	if draw_rune_diamonds:
		_draw_runes(draw_outer_radius, draw_rotation + rune_rotation, shimmer)


func _draw_core(radius: float, shimmer: float) -> void:
	if core_alpha <= 0.0 or radius <= 0.0:
		return
	var points := _make_ellipse_points(radius, 0.0, false)
	draw_colored_polygon(points, _with_alpha(core_color, core_alpha * alpha * shimmer))


func _draw_rings(start_radius: float, end_radius: float, rotation_offset: float, shimmer: float) -> void:
	var safe_ring_count := maxi(ring_count, 1)
	for index in range(safe_ring_count):
		var ratio := 0.0 if safe_ring_count == 1 else float(index) / float(safe_ring_count - 1)
		var radius := lerpf(start_radius, end_radius, ratio)
		var color_value := main_color.lerp(accent_color, ratio * 0.55)
		var ring_alpha := alpha * lerpf(0.75, 1.0, ratio) * shimmer
		draw_polyline(
			_make_ellipse_points(radius, rotation_offset * (0.35 + ratio), true),
			_with_alpha(color_value, ring_alpha),
			line_width,
			false
		)


func _draw_spokes(start_radius: float, end_radius: float, rotation_offset: float, shimmer: float) -> void:
	if spoke_count <= 0:
		return
	var local_color := _with_alpha(accent_color, accent_alpha * shimmer)
	for index in range(spoke_count):
		var angle := (TAU * float(index) / float(spoke_count)) + rotation_offset
		var points := PackedVector2Array([
			_ellipse_point(angle, start_radius),
			_ellipse_point(angle, end_radius),
		])
		draw_polyline(points, local_color, maxf(1.0, line_width * 0.75), false)


func _draw_runes(radius: float, rotation_offset: float, shimmer: float) -> void:
	if rune_count <= 0:
		return
	var rune_radius := radius * rune_radius_ratio
	var local_color := _with_alpha(accent_color, accent_alpha * shimmer)
	for index in range(rune_count):
		var angle := (TAU * float(index) / float(rune_count)) + rotation_offset
		var center := _ellipse_point(angle, rune_radius)
		var tangent := Vector2(-sin(angle), cos(angle) * perspective_y).normalized()
		var radial := Vector2(cos(angle), sin(angle) * perspective_y).normalized()
		var size := rune_size * (0.82 + (0.18 * sin(_time * shimmer_speed + float(index))))
		var points := PackedVector2Array([
			center + radial * size,
			center + tangent * size * 0.62,
			center - radial * size,
			center - tangent * size * 0.62,
		])
		draw_colored_polygon(points, local_color)


func _draw_star(radius: float, rotation_offset: float, shimmer: float) -> void:
	var points := PackedVector2Array()
	var safe_radius := maxf(radius, 4.0)
	for index in range(8):
		var point_radius := safe_radius if index % 2 == 0 else safe_radius * 0.42
		var angle := (TAU * float(index) / 8.0) + rotation_offset
		points.append(_ellipse_point(angle, point_radius))
	draw_colored_polygon(points, _with_alpha(accent_color, accent_alpha * 0.38 * shimmer))


func _make_ellipse_points(radius: float, rotation_offset: float, closed: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_segments := maxi(segment_count, 8)
	for index in range(safe_segments):
		var angle := (TAU * float(index) / float(safe_segments)) + rotation_offset
		points.append(_ellipse_point(angle, radius))
	if closed and points.size() > 0:
		points.append(points[0])
	return points


func _ellipse_point(angle: float, radius: float) -> Vector2:
	return Vector2(cos(angle) * radius, sin(angle) * radius * perspective_y)


func _with_alpha(color_value: Color, alpha_value: float) -> Color:
	return Color(
		color_value.r,
		color_value.g,
		color_value.b,
		clampf(alpha_value, 0.0, 1.0)
	)


func _ensure_material() -> void:
	if _additive_material == null:
		_additive_material = CanvasItemMaterial.new()
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_apply_material()


func _apply_material() -> void:
	if additive_blend:
		material = _additive_material
	else:
		material = null
