extends CharacterBody2D

signal health_changed(current_health: int, max_health: int)

@export var speed: float = 180.0
@export var max_health: int = 100

var health: int = 100
var spawn_position := Vector2.ZERO


func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
	health = max_health
	health_changed.emit(health, max_health)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		take_damage(10)
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0

	velocity = direction.normalized() * speed
	move_and_slide()


func take_damage(amount: int) -> void:
	if amount <= 0:
		return

	health = max(health - amount, 0)
	health_changed.emit(health, max_health)

	if health == 0:
		_die()


func heal(amount: int) -> void:
	if amount <= 0:
		return

	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)


func _die() -> void:
	print("Player died")
	global_position = spawn_position
	velocity = Vector2.ZERO
	health = max_health
	health_changed.emit(health, max_health)
