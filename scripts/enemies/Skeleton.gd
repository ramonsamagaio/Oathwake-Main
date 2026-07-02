extends "res://scripts/enemies/EnemyBase.gd"


func _ready() -> void:
	super._ready()


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	_update_movement()
	_update_damage(delta)


func _update_movement() -> void:
	if player == null or not can_chase_player():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := global_position.direction_to(player.global_position)
	velocity = direction * speed
	move_and_slide()
