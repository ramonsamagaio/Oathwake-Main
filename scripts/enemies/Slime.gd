extends CharacterBody2D

@export var speed: float = 45.0
@export var damage: int = 10
@export var damage_cooldown: float = 1.0

var player: CharacterBody2D
var player_in_contact := false
var damage_timer := 0.0

@onready var damage_area: Area2D = $DamageArea


func _ready() -> void:
	damage_area.body_entered.connect(_on_damage_area_body_entered)
	damage_area.body_exited.connect(_on_damage_area_body_exited)
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	_move_toward_player()
	_update_damage(delta)


func _move_toward_player() -> void:
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := global_position.direction_to(player.global_position)
	velocity = direction * speed
	move_and_slide()


func _update_damage(delta: float) -> void:
	if damage_timer > 0.0:
		damage_timer -= delta

	if player_in_contact and damage_timer <= 0.0 and player != null:
		player.take_damage(damage)
		damage_timer = damage_cooldown


func _on_damage_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player = body as CharacterBody2D
		player_in_contact = true


func _on_damage_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_contact = false
