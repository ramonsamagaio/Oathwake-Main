extends "res://scripts/enemies/EnemyBase.gd"

@export var hop_enabled := true
@export var hop_interval: float = 0.55
@export var hop_move_time: float = 0.20
@export var hop_pause_time: float = 0.20
@export var hop_squash_scale: Vector2 = Vector2(1.15, 0.85)
@export var hop_stretch_scale: Vector2 = Vector2(0.92, 1.12)

var _hop_timer := 0.0
var _hop_phase_timer := 0.0
var _hop_phase := "pause"
var _hop_direction := Vector2.ZERO

func _ready() -> void:
	super._ready()


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	_update_movement(delta)
	_update_damage(delta)


func _update_movement(delta: float) -> void:
	if not hop_enabled:
		_move_toward_player()
		return

	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		scale = original_scale
		_hop_timer = 0.0
		_hop_phase_timer = 0.0
		_hop_phase = "pause"
		return

	_hop_timer -= delta
	if _hop_timer <= 0.0 and _hop_phase == "pause":
		_start_hop()

	_update_hop_phase(delta)
	move_and_slide()


func _move_toward_player() -> void:
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := global_position.direction_to(player.global_position)
	velocity = direction * speed
	move_and_slide()


func _start_hop() -> void:
	_hop_timer = hop_interval
	_hop_phase = "pause"
	_hop_phase_timer = hop_pause_time
	_hop_direction = global_position.direction_to(player.global_position) if player != null else Vector2.ZERO
	if _hop_direction == Vector2.ZERO:
		_hop_direction = Vector2.RIGHT


func _update_hop_phase(delta: float) -> void:
	if _hop_phase == "pause":
		velocity = Vector2.ZERO
		scale = original_scale
		_hop_phase_timer -= delta
		if _hop_phase_timer <= 0.0:
			_hop_phase = "move"
			_hop_phase_timer = hop_move_time
			scale = Vector2(original_scale.x * hop_squash_scale.x, original_scale.y * hop_squash_scale.y)
		return

	if _hop_phase == "move":
		velocity = _hop_direction.normalized() * speed
		scale = Vector2(original_scale.x * hop_stretch_scale.x, original_scale.y * hop_stretch_scale.y)
		_hop_phase_timer -= delta
		if _hop_phase_timer <= 0.0:
			_hop_phase = "recover"
			_hop_phase_timer = 0.08
		return

	velocity = Vector2.ZERO
	scale = original_scale
	_hop_phase_timer -= delta
	if _hop_phase_timer <= 0.0:
		_hop_phase = "pause"

