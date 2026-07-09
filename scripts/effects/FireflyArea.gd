@tool
extends Node2D

@export var area_size: Vector2 = Vector2(256, 256)
@export_range(0, 128, 1) var firefly_count: int = 8
@export_range(1.0, 8.0, 0.5) var pixel_size_min: float = 1.0
@export_range(1.0, 8.0, 0.5) var pixel_size_max: float = 2.0
@export_range(0.0, 120.0, 1.0) var speed_min: float = 8.0
@export_range(0.0, 160.0, 1.0) var speed_max: float = 24.0
@export_range(0.0, 80.0, 1.0) var drift_strength: float = 18.0
@export var glow_enabled: bool = true
@export_range(1.0, 24.0, 0.5) var glow_size: float = 7.0
@export var trail_enabled: bool = true
@export_range(0, 24, 1) var trail_length: int = 8
@export_range(0.0, 1.0, 0.01) var trail_fade: float = 0.55
@export var color_palette: PackedColorArray = PackedColorArray([
	Color(1.0, 0.95, 0.58, 1.0),
	Color(1.0, 0.78, 0.25, 1.0),
	Color(1.0, 0.58, 0.22, 1.0),
	Color(0.95, 0.68, 0.32, 1.0),
])
@export_range(0.0, 1.0, 0.01) var alpha_min: float = 0.35
@export_range(0.0, 1.0, 0.01) var alpha_max: float = 0.9
@export_range(0.05, 12.0, 0.05) var flicker_speed: float = 2.0
@export var additive_blend: bool = true
@export var debug_draw_area: bool = false
@export var z_index_value: int = 0

var _rng := RandomNumberGenerator.new()
var _fireflies: Array = []
var _time: float = 0.0
var _additive_material: CanvasItemMaterial


func _ready() -> void:
	_rng.randomize()
	_ensure_material()
	_reset_fireflies()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	z_index = z_index_value
	_apply_material()
	_ensure_firefly_count()
	_update_fireflies(delta)
	queue_redraw()


func apply_warm_fireflies_preset() -> void:
	area_size = Vector2(256, 256)
	firefly_count = 8
	speed_min = 6.0
	speed_max = 18.0
	drift_strength = 15.0
	glow_enabled = true
	glow_size = 7.0
	trail_enabled = true
	trail_length = 7
	trail_fade = 0.5
	color_palette = PackedColorArray([
		Color(1.0, 0.95, 0.58, 1.0),
		Color(1.0, 0.76, 0.26, 1.0),
		Color(1.0, 0.55, 0.20, 1.0),
	])
	alpha_min = 0.35
	alpha_max = 0.85
	flicker_speed = 1.8
	_reset_fireflies()


func apply_magic_wisps_preset() -> void:
	area_size = Vector2(256, 256)
	firefly_count = 6
	speed_min = 4.0
	speed_max = 13.0
	drift_strength = 22.0
	glow_enabled = true
	glow_size = 10.0
	trail_enabled = true
	trail_length = 12
	trail_fade = 0.7
	color_palette = PackedColorArray([
		Color(0.55, 0.78, 1.0, 1.0),
		Color(0.68, 0.46, 1.0, 1.0),
		Color(1.0, 0.9, 0.55, 1.0),
	])
	alpha_min = 0.28
	alpha_max = 0.78
	flicker_speed = 0.9
	_reset_fireflies()


func apply_low_density_preset() -> void:
	firefly_count = 4
	speed_min = 4.0
	speed_max = 12.0
	trail_length = 5
	glow_size = 6.0
	_reset_fireflies()


func apply_dense_forest_preset() -> void:
	firefly_count = 16
	speed_min = 6.0
	speed_max = 20.0
	trail_length = 9
	glow_size = 8.0
	_reset_fireflies()


func _draw() -> void:
	var bounds := _get_bounds()
	if debug_draw_area:
		draw_rect(bounds, Color(0.35, 0.75, 1.0, 0.35), false, 1.0)

	for firefly in _fireflies:
		var position_value: Vector2 = firefly.get("position", Vector2.ZERO)
		var color_value: Color = firefly.get("color", Color.WHITE)
		var pixel_size: float = float(firefly.get("size", 1.0))
		var phase: float = float(firefly.get("phase", 0.0))
		var flicker := lerpf(alpha_min, alpha_max, (sin((_time * flicker_speed) + phase) + 1.0) * 0.5)
		var draw_color := Color(color_value.r, color_value.g, color_value.b, flicker)

		if trail_enabled:
			_draw_trail(firefly, pixel_size, draw_color)

		if glow_enabled:
			var glow_color := Color(draw_color.r, draw_color.g, draw_color.b, draw_color.a * 0.18)
			draw_circle(position_value, glow_size, glow_color)

		var half_size := Vector2(pixel_size, pixel_size) * 0.5
		draw_rect(Rect2(position_value - half_size, Vector2(pixel_size, pixel_size)), draw_color, true)


func _draw_trail(firefly: Dictionary, pixel_size: float, color_value: Color) -> void:
	var trail: Array = firefly.get("trail", [])
	if trail.is_empty():
		return
	for index in range(trail.size()):
		var trail_position: Vector2 = trail[index]
		var fade := 1.0 - (float(index + 1) / float(maxi(trail.size(), 1)))
		var trail_alpha := color_value.a * trail_fade * fade
		var trail_color := Color(color_value.r, color_value.g, color_value.b, trail_alpha)
		var trail_size := maxf(1.0, pixel_size * fade)
		draw_rect(Rect2(trail_position - Vector2(trail_size, trail_size) * 0.5, Vector2(trail_size, trail_size)), trail_color, true)


func _update_fireflies(delta: float) -> void:
	var bounds := _get_bounds()
	for firefly in _fireflies:
		var position_value: Vector2 = firefly.get("position", Vector2.ZERO)
		var velocity: Vector2 = firefly.get("velocity", Vector2.RIGHT)
		var phase: float = float(firefly.get("phase", 0.0))
		var speed: float = float(firefly.get("speed", 10.0))

		var drift := Vector2(
			sin((_time * 0.9) + phase),
			cos((_time * 0.73) + (phase * 1.31))
		) * drift_strength
		var desired_velocity := (velocity + (drift * delta)).normalized() * speed
		velocity = velocity.lerp(desired_velocity, clampf(delta * 2.5, 0.0, 1.0))
		position_value += velocity * delta

		if position_value.x < bounds.position.x or position_value.x > bounds.end.x:
			velocity.x *= -1.0
			position_value.x = clampf(position_value.x, bounds.position.x, bounds.end.x)
		if position_value.y < bounds.position.y or position_value.y > bounds.end.y:
			velocity.y *= -1.0
			position_value.y = clampf(position_value.y, bounds.position.y, bounds.end.y)

		var trail: Array = firefly.get("trail", [])
		trail.push_front(position_value)
		while trail.size() > trail_length:
			trail.pop_back()

		firefly["position"] = position_value
		firefly["velocity"] = velocity
		firefly["trail"] = trail


func _ensure_firefly_count() -> void:
	while _fireflies.size() < firefly_count:
		_fireflies.append(_make_firefly())
	while _fireflies.size() > firefly_count:
		_fireflies.pop_back()


func _reset_fireflies() -> void:
	_fireflies.clear()
	_ensure_firefly_count()


func _make_firefly() -> Dictionary:
	var bounds := _get_bounds()
	var angle := _rng.randf_range(0.0, TAU)
	var color_index := _rng.randi_range(0, max(color_palette.size() - 1, 0))
	var color_value := Color(1.0, 0.86, 0.35, 1.0)
	if not color_palette.is_empty():
		color_value = color_palette[color_index]
	return {
		"position": Vector2(
			_rng.randf_range(bounds.position.x, bounds.end.x),
			_rng.randf_range(bounds.position.y, bounds.end.y)
		),
		"velocity": Vector2(cos(angle), sin(angle)) * _rng.randf_range(speed_min, speed_max),
		"speed": _rng.randf_range(speed_min, speed_max),
		"phase": _rng.randf_range(0.0, TAU),
		"color": color_value,
		"size": _rng.randf_range(pixel_size_min, pixel_size_max),
		"trail": [],
	}


func _get_bounds() -> Rect2:
	return Rect2(area_size * -0.5, area_size)


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
