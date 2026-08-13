class_name DylearnGrassTestWalker
extends CharacterBody2D

@export var move_speed := 150.0
@export var run_multiplier := 1.8
@export var grass_displacement_radius := 42.0
@export var movement_bounds := Rect2(-1540.0, -1040.0, 3080.0, 2080.0)


func _ready() -> void:
	add_to_group("grass_displacer")


func _physics_process(_delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1.0
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= run_multiplier
	velocity = input_vector.normalized() * speed
	move_and_slide()
	global_position.x = clampf(global_position.x, movement_bounds.position.x, movement_bounds.position.x + movement_bounds.size.x)
	global_position.y = clampf(global_position.y, movement_bounds.position.y, movement_bounds.position.y + movement_bounds.size.y)
