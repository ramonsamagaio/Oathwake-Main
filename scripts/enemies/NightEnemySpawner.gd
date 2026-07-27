extends Node

@export var slime_scene: PackedScene
@export var slime_monster_id: String = "slime"
@export var max_alive_slimes: int = 5
@export var spawn_interval_seconds: float = 5.0
@export var spawn_attempts: int = 10
@export var min_spawn_distance: float = 180.0
@export var max_spawn_distance: float = 280.0
@export var campfire_safe_radius: float = 160.0
@export var natural_spawn_enabled := true
@export var player_path: NodePath = "../World/Player"
@export var day_night_cycle_path: NodePath = "../DayNightCycle"
@export var enemies_root_path: NodePath = "../World/Enemies"
@export var build_system_path: NodePath = "../BuildSystem"
@export var world_path: NodePath = "../World"

var spawn_timer := 0.0
var rng := RandomNumberGenerator.new()

var player: CharacterBody2D
var day_night_cycle: Node
var enemies_root: Node2D
var build_system: Node
var world: Node


func _ready() -> void:
	add_to_group("natural_monster_spawn_controller")
	rng.randomize()
	setup({})


func setup(context: Dictionary) -> void:
	player = context.get("player", player) as CharacterBody2D
	day_night_cycle = context.get("day_night_cycle", day_night_cycle) as Node
	enemies_root = context.get("enemies_root", enemies_root) as Node2D
	build_system = context.get("build_system", build_system) as Node
	world = context.get("world", world) as Node
	if player == null:
		player = get_node_or_null(player_path) as CharacterBody2D
	if day_night_cycle == null:
		day_night_cycle = get_node_or_null(day_night_cycle_path)
	if enemies_root == null:
		enemies_root = get_node_or_null(enemies_root_path) as Node2D
	if build_system == null:
		build_system = get_node_or_null(build_system_path)
	if world == null:
		world = get_node_or_null(world_path)


func set_natural_spawn_enabled(is_enabled: bool) -> void:
	natural_spawn_enabled = is_enabled
	spawn_timer = 0.0


func _process(delta: float) -> void:
	if player == null or day_night_cycle == null or enemies_root == null:
		return
	if not natural_spawn_enabled:
		spawn_timer = 0.0
		return

	if day_night_cycle.is_day():
		spawn_timer = 0.0
		return

	spawn_timer += delta
	if spawn_timer < spawn_interval_seconds:
		return

	spawn_timer = 0.0
	_try_spawn_slime()


func _try_spawn_slime() -> bool:
	if not natural_spawn_enabled or slime_scene == null:
		return false

	if get_alive_slime_count() >= max_alive_slimes:
		return false

	var spawn_result := _get_valid_spawn_position(slime_monster_id)
	if not bool(spawn_result.get("is_valid", false)):
		print("Could not find a valid spawn position for %s." % slime_monster_id)
		return false

	var spawn_position: Vector2 = spawn_result["position"]
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


func get_tile_type_at_position(position: Vector2) -> String:
	if world != null and world.has_method("get_tile_type_at_position"):
		return str(world.get_tile_type_at_position(position))

	# Safe fallback until the world exposes real TileMap terrain data.
	return "grass"


func _get_valid_spawn_position(monster_id: String) -> Dictionary:
	for _attempt in range(spawn_attempts):
		var spawn_position := _get_random_spawn_position()
		if _is_position_near_campfire(spawn_position):
			continue

		if not _is_spawn_tile_allowed(monster_id, spawn_position):
			continue

		return {
			"is_valid": true,
			"position": spawn_position,
		}

	return {
		"is_valid": false,
		"position": Vector2.ZERO,
	}


func _get_random_spawn_position() -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(min_spawn_distance, max_spawn_distance)
	return player.global_position + Vector2.RIGHT.rotated(angle) * distance


func _is_position_near_campfire(spawn_position: Vector2) -> bool:
	if build_system == null or not build_system.has_method("get_campfire_positions"):
		return false

	for campfire_position in build_system.get_campfire_positions():
		if spawn_position.distance_to(campfire_position) < campfire_safe_radius:
			return true

	return false


func _is_spawn_tile_allowed(monster_id: String, spawn_position: Vector2) -> bool:
	var spawn_tiles := _get_monster_spawn_tiles(monster_id)
	var tile_type := get_tile_type_at_position(spawn_position)
	if not _terrain_allows_monster_spawn(tile_type):
		return false

	if spawn_tiles.is_empty():
		return true

	return spawn_tiles.has(tile_type)


func _terrain_allows_monster_spawn(tile_type: String) -> bool:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return true

	if not content_db.has_method("has_terrain_type") or not content_db.has_terrain_type(tile_type):
		return true

	var terrain_data: Dictionary = content_db.get_terrain_type(tile_type)
	return bool(terrain_data.get("allows_monster_spawn", true))


func _get_monster_spawn_tiles(monster_id: String) -> Array:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		print("ContentDB not found. Allowing %s spawn without tile validation." % monster_id)
		return []

	var monster_data: Dictionary = content_db.get_monster(monster_id)
	if monster_data.is_empty():
		print("No monster data found for %s. Allowing spawn without tile validation." % monster_id)
		return []

	var spawn_tiles = monster_data.get("spawn_tiles", [])
	if not spawn_tiles is Array:
		print("Invalid spawn_tiles for %s. Allowing spawn without tile validation." % monster_id)
		return []

	return spawn_tiles
