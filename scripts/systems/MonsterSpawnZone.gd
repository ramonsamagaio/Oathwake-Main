extends Node2D

const MonsterSpawner := preload("res://scripts/systems/MonsterSpawner.gd")

@export var monster_id := "slime"
@export var max_alive := 1
@export var spawn_interval: float = 5.0
@export var spawn_radius: float = 48.0
@export var active := true

var _alive_monsters: Array[Node] = []
var _spawn_timer := 0.0
var _monster_spawner := MonsterSpawner.new()


func _ready() -> void:
	add_child(_monster_spawner)
	_spawn_timer = spawn_interval
	set_process(true)


func _process(delta: float) -> void:
	if not active:
		return

	_cleanup_alive_monsters()
	if _alive_monsters.size() >= max_alive:
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	_spawn_timer = spawn_interval
	_try_spawn_monster()


func _try_spawn_monster() -> void:
	var spawn_parent := get_parent()
	if spawn_parent == null:
		return

	var monster := _monster_spawner.spawn_monster(monster_id, _get_random_spawn_position())
	if monster == null:
		return

	spawn_parent.add_child(monster)
	_alive_monsters.append(monster)


func _cleanup_alive_monsters() -> void:
	var valid_monsters: Array[Node] = []
	for monster in _alive_monsters:
		if is_instance_valid(monster):
			valid_monsters.append(monster)
	_alive_monsters = valid_monsters


func _get_random_spawn_position() -> Vector2:
	if spawn_radius <= 0.0:
		return global_position

	var angle := randf() * TAU
	var distance := sqrt(randf()) * spawn_radius
	return global_position + Vector2.RIGHT.rotated(angle) * distance
