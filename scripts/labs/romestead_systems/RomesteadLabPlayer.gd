class_name RomesteadLabPlayer
extends CharacterBody2D

@export var walk_speed := 90.0
@export var run_multiplier := 1.65
@export var movement_bounds := Rect2(-1500.0, -990.0, 3000.0, 1980.0)

var _facing := Vector2.DOWN
var _walk_time := 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("grass_displacer")
	queue_redraw()


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1.0

	if input_vector.length_squared() > 0.0:
		input_vector = input_vector.normalized()
		_facing = input_vector
		_walk_time += delta * 10.0
	else:
		_walk_time = 0.0

	var speed := walk_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= run_multiplier
	velocity = input_vector * speed
	move_and_slide()
	global_position.x = clampf(global_position.x, movement_bounds.position.x, movement_bounds.end.x)
	global_position.y = clampf(global_position.y, movement_bounds.position.y, movement_bounds.end.y)
	queue_redraw()


func _draw() -> void:
	var bob := sin(_walk_time) * 1.5 if _walk_time > 0.0 else 0.0
	_draw_pixel_ellipse(Vector2(0.0, 9.0), Vector2(12.0, 5.0), Color(0.05, 0.04, 0.035, 0.42))
	draw_rect(Rect2(-8.0, -3.0 + bob, 16.0, 18.0), Color("293b43"))
	draw_rect(Rect2(-10.0, -13.0 + bob, 20.0, 13.0), Color("d2ad83"))
	draw_rect(Rect2(-8.0, -17.0 + bob, 16.0, 6.0), Color("563c32"))
	draw_rect(Rect2(-11.0, -10.0 + bob, 3.0, 8.0), Color("563c32"))
	var eye_offset := _facing.normalized() * 2.0
	draw_circle(Vector2(-3.0, -7.0 + bob) + eye_offset, 1.1, Color("1d2426"))
	draw_circle(Vector2(3.0, -7.0 + bob) + eye_offset, 1.1, Color("1d2426"))


func _draw_pixel_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(20):
		var angle := TAU * float(index) / 20.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
