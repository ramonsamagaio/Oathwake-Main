extends Node

const MonsterSpawnerScript := preload("res://scripts/systems/MonsterSpawner.gd")

@export var slime_scene: PackedScene
@export var slime_monster_id: String = "slime"
@export var max_alive_slimes: int = 5
@export var max_alive_monsters: int = 14
@export var spawn_interval_seconds: float = 4.0
@export var spawn_attempts: int = 36
@export var min_spawn_distance: float = 320.0
@export var max_spawn_distance: float = 820.0
@export var screen_spawn_margin: float = 80.0
@export var campfire_safe_radius: float = 160.0
@export var natural_spawn_enabled := true
@export var player_path: NodePath = "../World/Player"
@export var day_night_cycle_path: NodePath = "../DayNightCycle"
@export var enemies_root_path: NodePath = "../World/Enemies"
@export var build_system_path: NodePath = "../BuildSystem"
@export var world_path: NodePath = "../World"

var spawn_timer := 0.0
var rng := RandomNumberGenerator.new()
var monster_spawner := MonsterSpawnerScript.new()

var player: CharacterBody2D
var day_night_cycle: Node
var enemies_root: Node2D
var build_system: Node
var world: Node


func _ready() -> void:
	add_to_group("natural_monster_spawn_controller")
	rng.randomize()
	add_child(monster_spawner)
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
	if player == null or enemies_root == null:
		return
	if not natural_spawn_enabled:
		spawn_timer = 0.0
		return
	spawn_timer += delta
	if spawn_timer < spawn_interval_seconds:
		return
	spawn_timer = 0.0
	_try_spawn_from_terrain()


func _try_spawn_from_terrain() -> bool:
	if not natural_spawn_enabled or get_alive_monster_count() >= max_alive_monsters:
		return false
	for _attempt in range(spawn_attempts):
		var spawn_position := _get_random_spawn_position()
		if not is_position_outside_player_view(spawn_position):
			continue
		if _is_position_near_campfire(spawn_position):
			continue
		var tile_type := get_tile_type_at_position(spawn_position)
		if not _terrain_allows_monster_spawn(tile_type):
			continue
		var eligible_entries := _get_eligible_spawn_entries(tile_type)
		if eligible_entries.is_empty():
			continue
		var selected_entry := _choose_weighted_spawn(eligible_entries)
		var monster_id := str(selected_entry.get("monster_id", ""))
		if monster_id.is_empty() or not _is_spawn_tile_allowed(monster_id, spawn_position):
			continue
		var monster := monster_spawner.spawn_monster(monster_id, spawn_position)
		if monster == null:
			continue
		enemies_root.add_child(monster)
		if monster is Node2D:
			(monster as Node2D).global_position = spawn_position
		monster.set_meta("natural_spawn_tile", tile_type)
		monster.set_meta("spawned_outside_player_view", true)
		print("Spawned %s on %s outside the player view at %s" % [monster_id, tile_type, spawn_position])
		return true
	return false


func _try_spawn_slime() -> bool:
	# Compatibility entry point retained for older tests and debug controls.
	return _try_spawn_from_terrain()


func get_alive_monster_count(monster_id := "") -> int:
	if enemies_root == null:
		return 0
	var count := 0
	for enemy in enemies_root.get_children():
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.is_in_group("enemy"):
			continue
		if not monster_id.is_empty() and str(enemy.get("monster_id")) != monster_id:
			continue
		count += 1
	return count


func get_alive_slime_count() -> int:
	return get_alive_monster_count(slime_monster_id)


func get_tile_type_at_position(position: Vector2) -> String:
	if world != null and world.has_method("get_tile_type_at_position"):
		return str(world.get_tile_type_at_position(position))
	return "grass"


func _get_random_spawn_position() -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(min_spawn_distance, max_spawn_distance)
	return player.global_position + Vector2.RIGHT.rotated(angle) * distance


func is_position_outside_player_view(world_position: Vector2) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var viewport := player.get_viewport()
	if viewport == null:
		return false
	var screen_position := viewport.get_canvas_transform() * world_position
	var visible_screen_rect := viewport.get_visible_rect().grow(screen_spawn_margin)
	return not visible_screen_rect.has_point(screen_position)


func _get_eligible_spawn_entries(tile_type: String) -> Array[Dictionary]:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_terrain_type") or not content_db.has_terrain_type(tile_type):
		return []
	var terrain_data: Dictionary = content_db.get_terrain_type(tile_type)
	var entries_value: Variant = terrain_data.get("monster_spawns", [])
	if not entries_value is Array:
		return []
	var eligible: Array[Dictionary] = []
	for entry_value in entries_value:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var monster_id := str(entry.get("monster_id", ""))
		if monster_id.is_empty() or not content_db.has_monster(monster_id):
			continue
		if not _is_entry_time_active(str(entry.get("active_time", "any"))):
			continue
		var max_alive := maxi(int(entry.get("max_alive", max_alive_monsters)), 0)
		if max_alive > 0 and get_alive_monster_count(monster_id) >= max_alive:
			continue
		if float(entry.get("weight", 1.0)) <= 0.0:
			continue
		eligible.append(entry.duplicate(true))
	return eligible


func _is_entry_time_active(active_time: String) -> bool:
	if active_time == "any" or day_night_cycle == null:
		return true
	if active_time == "day":
		return day_night_cycle.has_method("is_day") and bool(day_night_cycle.call("is_day"))
	if active_time == "night":
		return day_night_cycle.has_method("is_day") and not bool(day_night_cycle.call("is_day"))
	return true


func _choose_weighted_spawn(entries: Array[Dictionary]) -> Dictionary:
	var total_weight := 0.0
	for entry in entries:
		total_weight += maxf(float(entry.get("weight", 1.0)), 0.0)
	if total_weight <= 0.0:
		return {}
	var roll := rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for entry in entries:
		cursor += maxf(float(entry.get("weight", 1.0)), 0.0)
		if roll <= cursor:
			return entry
	return entries.back()


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
	return spawn_tiles.is_empty() or spawn_tiles.has(tile_type)


func _terrain_allows_monster_spawn(tile_type: String) -> bool:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_terrain_type") or not content_db.has_terrain_type(tile_type):
		return false
	var terrain_data: Dictionary = content_db.get_terrain_type(tile_type)
	return bool(terrain_data.get("allows_monster_spawn", true))


func _get_monster_spawn_tiles(monster_id: String) -> Array:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_monster") or not content_db.has_monster(monster_id):
		return []
	var monster_data: Dictionary = content_db.get_monster(monster_id)
	var spawn_tiles: Variant = monster_data.get("spawn_tiles", [])
	return spawn_tiles if spawn_tiles is Array else []
