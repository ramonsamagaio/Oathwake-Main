extends Node

@export var slime_scene: PackedScene
@export var max_alive_slimes: int = 5
@export var spawn_interval_seconds: float = 5.0
@export var min_spawn_distance: float = 180.0
@export var max_spawn_distance: float = 280.0
@export var campfire_safe_radius: float = 160.0
@export var player_path: NodePath = "../Player"
@export var day_night_cycle_path: NodePath = "../DayNightCycle"
@export var enemies_root_path: NodePath = "../World/Enemies"
@export var build_system_path: NodePath = "../BuildSystem"

var spawn_timer := 0.0
var rng := RandomNumberGenerator.new()

@onready var player: CharacterBody2D = get_node(player_path)
@onready var day_night_cycle: Node = get_node(day_night_cycle_path)
@onready var enemies_root: Node2D = get_node(enemies_root_path)
@onready var build_system = get_node(build_system_path)


func _ready() -> void:
	rng.randomize()


func _process(delta: float) -> void:
	if day_night_cycle.is_day():
		spawn_timer = 0.0
		return

	spawn_timer += delta
	if spawn_timer < spawn_interval_seconds:
		return

	spawn_timer = 0.0
	_try_spawn_slime()


func _try_spawn_slime() -> bool:
	if slime_scene == null:
		return false

	if get_alive_slime_count() >= max_alive_slimes:
		return false

	var spawn_position := _get_spawn_position()
	var slime := slime_scene.instantiate() as Node2D
	enemies_root.add_child(slime)
	slime.global_position = spawn_position
	print("Spawned Slime at %s" % slime.global_position)
	return true


func get_alive_slime_count() -> int:
	var count := 0

	for enemy in enemies_root.get_children():
		if enemy.is_in_group("enemy") and not enemy.is_queued_for_deletion():
			count += 1

	return count


func _get_spawn_position() -> Vector2:
	for _attempt in range(12):
		var spawn_position := _get_random_spawn_position()
		if not _is_position_near_campfire(spawn_position):
			return spawn_position

	return _get_random_spawn_position()


func _get_random_spawn_position() -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(min_spawn_distance, max_spawn_distance)
	return player.global_position + Vector2.RIGHT.rotated(angle) * distance


func _is_position_near_campfire(spawn_position: Vector2) -> bool:
	if not build_system.has_method("get_campfire_positions"):
		return false

	for campfire_position in build_system.get_campfire_positions():
		if spawn_position.distance_to(campfire_position) < campfire_safe_radius:
			return true

	return false
