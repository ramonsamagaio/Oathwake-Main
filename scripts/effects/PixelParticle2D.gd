extends Node2D

var velocity := Vector2.ZERO
var lifetime := 0.35
var fade_out_time := 0.35
var gravity := 0.0
var pixel_size := 3.0
var colors: Array[Color] = [Color.WHITE]
var color_switch_interval := 0.04

var _age := 0.0
var _color_timer := 0.0
var _color_index := 0


func setup(new_velocity: Vector2, new_lifetime: float, new_size: float, new_colors: Array[Color], new_switch_interval: float, new_gravity := 0.0, new_fade_out_time := -1.0) -> void:
	velocity = new_velocity
	lifetime = maxf(new_lifetime, 0.01)
	fade_out_time = clampf(new_fade_out_time if new_fade_out_time >= 0.0 else lifetime, 0.01, lifetime)
	pixel_size = maxf(new_size, 1.0)
	colors = new_colors if not new_colors.is_empty() else [Color.WHITE]
	color_switch_interval = maxf(new_switch_interval, 0.01)
	gravity = new_gravity
	modulate.a = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	velocity.y += gravity * delta
	position += velocity * delta

	_color_timer += delta
	if _color_timer >= color_switch_interval:
		_color_timer = 0.0
		_color_index = (_color_index + 1) % colors.size()

	var fade_start := maxf(lifetime - fade_out_time, 0.0)
	modulate.a = 1.0 - clampf((_age - fade_start) / fade_out_time, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var color := colors[_color_index % colors.size()]
	draw_rect(Rect2(Vector2(-pixel_size * 0.5, -pixel_size * 0.5), Vector2(pixel_size, pixel_size)), color, true)
