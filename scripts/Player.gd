extends CharacterBody2D

signal health_changed(current_health: int, max_health: int)
signal tool_changed(current_tool: String)
signal attack_started
signal attack_hit_frame
signal attack_finished
signal xp_changed(current_xp, xp_to_next_level, level)
signal level_changed(level)

const AnimationSetLoaderScript = preload("res://scripts/systems/AnimationSetLoader.gd")
const PlayerAnimationControllerScript = preload("res://scripts/systems/PlayerAnimationController.gd")
const CombatCalculatorScript = preload("res://scripts/systems/CombatCalculator.gd")
const FloatingCombatTextSpawner := preload("res://scripts/ui/FloatingCombatTextSpawner.gd")
const ItemInstanceHelper = preload("res://scripts/systems/ItemInstanceHelper.gd")
const PlayerStatsResolverScript = preload("res://scripts/systems/PlayerStatsResolver.gd")
const SmokePuffScene := preload("res://scenes/effects/SmokePuff.tscn")
const WALK_FOOTSTEP_PATHS := [
	"res://assets/audio/sfx/footsteps/Dirt Walk 1.wav",
	"res://assets/audio/sfx/footsteps/Dirt Walk 2.wav",
	"res://assets/audio/sfx/footsteps/Dirt Walk 3.wav",
	"res://assets/audio/sfx/footsteps/Dirt Walk 4.wav",
	"res://assets/audio/sfx/footsteps/Dirt Walk 5.wav",
]
const RUN_FOOTSTEP_PATHS := [
	"res://assets/audio/sfx/footsteps/Dirt Run 1.wav",
	"res://assets/audio/sfx/footsteps/Dirt Run 2.wav",
	"res://assets/audio/sfx/footsteps/Dirt Run 3.wav",
	"res://assets/audio/sfx/footsteps/Dirt Run 4.wav",
	"res://assets/audio/sfx/footsteps/Dirt Run 5.wav",
]
const TOOL_HANDS := "Hands"
const TOOL_AXE := "Axe"
const TOOL_PICKAXE := "Pickaxe"
const TOOLS := [
	TOOL_HANDS,
	TOOL_AXE,
	TOOL_PICKAXE,
]
const BASE_RESOURCE_DAMAGE := 5
const TOOL_RESOURCE_DAMAGE := 15

@export var speed: float = 180.0
@export var walk_speed: float = 80.0
@export var run_speed: float = 130.0
@export var acceleration: float = 720.0
@export var deceleration: float = 980.0
@export var run_stop_slide_time: float = 0.18
@export var run_stop_slide_strength: float = 0.50
@export var smoke_puff_enabled := true
@export var smoke_puff_cooldown: float = 0.28
@export var max_health: int = 100
@export var attack_damage: int = 10
@export var attack_range: float = 48.0
@export var character_id: String = "player"
@export var show_floating_damage := true
@export var enable_hit_flash := true
@export var attack_timing_enabled := false
@export var attack_windup_time: float = 0.0
@export var attack_hit_time: float = 0.0
@export var attack_recovery_time: float = 0.0

var level := 1
var current_xp := 0
var xp_to_next_level := 30
var health: int = 100
var spawn_position := Vector2.ZERO
var initial_spawn_position := Vector2.ZERO
var has_respawn_point := false
var current_tool_index := 0
var last_direction := "down"
var was_running := false
var is_running := false
var run_slide_timer := 0.0
var smoke_puff_timer := 0.0
var last_move_direction := Vector2.DOWN
var animation_controller := PlayerAnimationControllerScript.new()
var animation_set_loader := AnimationSetLoaderScript.new()
var combat_calculator := CombatCalculatorScript.new()
var player_stats_resolver := PlayerStatsResolverScript.new()
var debug_base_stats_override := {}
var unlocked_tools := [
	TOOL_HANDS,
]
var _attack_in_progress := false
var _walk_footstep_streams: Array[AudioStream] = []
var _run_footstep_streams: Array[AudioStream] = []
var _footstep_player: AudioStreamPlayer2D
var _footstep_timer := 0.0
var _last_walk_footstep_index := -1
var _last_run_footstep_index := -1

@onready var body_visual: CanvasItem = $Body
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("player")
	_load_player_tuning()
	_setup_character_visual()
	_setup_footstep_audio()
	spawn_position = global_position
	initial_spawn_position = global_position
	health = max_health
	health_changed.emit(health, max_health)
	xp_changed.emit(current_xp, xp_to_next_level, level)
	tool_changed.emit(get_current_tool())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		take_damage(10)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_select_previous_tool()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if _is_storage_open() or _is_crafting_open():
			return

		if _try_interact_with_nearby_npc():
			get_viewport().set_input_as_handled()
			return

		if _try_interact_with_nearby_storage():
			get_viewport().set_input_as_handled()
			return

		if _try_interact_with_nearby_workbench():
			get_viewport().set_input_as_handled()
			return

		_select_next_tool()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if _is_storage_open() or _is_crafting_open():
			return

		_attack()
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_storage_open() or _is_crafting_open():
			return
		if _is_build_mode_enabled():
			return

		_attack()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0

	var has_input := direction.length_squared() > 0.0
	if has_input:
		direction = direction.normalized()

	var wants_to_run := Input.is_key_pressed(KEY_SHIFT)
	is_running = has_input and wants_to_run

	if has_input:
		var current_speed := run_speed if is_running else walk_speed
		var target_velocity := direction * current_speed
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
		last_move_direction = direction
		run_slide_timer = 0.0

		if is_running:
			if not was_running:
				_spawn_smoke_puff()
				smoke_puff_timer = smoke_puff_cooldown
			else:
				smoke_puff_timer -= delta
				if smoke_puff_timer <= 0.0:
					_spawn_smoke_puff()
					smoke_puff_timer = smoke_puff_cooldown
		else:
			smoke_puff_timer = 0.0
	else:
		if was_running:
			run_slide_timer = run_stop_slide_time
			_spawn_smoke_puff()

		var stop_deceleration := deceleration
		if run_slide_timer > 0.0:
			stop_deceleration *= run_stop_slide_strength
			run_slide_timer = max(run_slide_timer - delta, 0.0)

		velocity = velocity.move_toward(Vector2.ZERO, stop_deceleration * delta)
		if velocity.length() < 1.0:
			velocity = Vector2.ZERO

	move_and_slide()

	var animation_direction := Vector2.ZERO
	if has_input:
		animation_direction = direction
	elif velocity.length() > 3.0:
		animation_direction = velocity.normalized()

	_update_movement_animation(animation_direction)
	_update_footsteps(delta, has_input)
	was_running = is_running


func _load_player_tuning() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return
	if not content_db.has_method("has_player_tuning"):
		return
	if not content_db.has_player_tuning("default"):
		return

	var tuning: Dictionary = content_db.get_player_tuning("default")
	walk_speed = float(tuning.get("walk_speed", walk_speed))
	run_speed = float(tuning.get("run_speed", run_speed))
	acceleration = float(tuning.get("acceleration", acceleration))
	deceleration = float(tuning.get("deceleration", deceleration))
	run_stop_slide_time = float(tuning.get("run_stop_slide_time", run_stop_slide_time))
	run_stop_slide_strength = float(tuning.get("run_stop_slide_strength", run_stop_slide_strength))
	smoke_puff_enabled = bool(tuning.get("smoke_puff_enabled", smoke_puff_enabled))
	smoke_puff_cooldown = float(tuning.get("smoke_puff_cooldown", smoke_puff_cooldown))


func _spawn_smoke_puff() -> void:
	if not smoke_puff_enabled:
		return

	var parent := get_parent()
	if parent == null:
		return

	var puff := SmokePuffScene.instantiate()
	parent.add_child(puff)

	var foot_offset := Vector2(0, 12)
	var side_jitter := Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0))
	puff.global_position = global_position + foot_offset + side_jitter

	if puff is Node2D:
		puff.z_index = z_index - 1


func _setup_footstep_audio() -> void:
	_walk_footstep_streams = _load_audio_streams(WALK_FOOTSTEP_PATHS)
	_run_footstep_streams = _load_audio_streams(RUN_FOOTSTEP_PATHS)
	_footstep_player = AudioStreamPlayer2D.new()
	_footstep_player.bus = "Master"
	add_child(_footstep_player)


func _update_footsteps(delta: float, has_input: bool) -> void:
	if _footstep_player == null:
		return

	if not has_input or velocity.length() <= 1.0 or _is_ui_blocking_footsteps():
		_footstep_timer = 0.0
		return

	_footstep_timer -= delta
	if _footstep_timer > 0.0:
		return

	if is_running:
		_play_footstep(_run_footstep_streams, true)
		_footstep_timer = 0.26
	else:
		_play_footstep(_walk_footstep_streams, false)
		_footstep_timer = 0.42


func _play_footstep(streams: Array[AudioStream], running: bool) -> void:
	if streams.is_empty() or _footstep_player == null:
		return

	var stream_index := _pick_audio_index(streams.size(), _last_run_footstep_index if running else _last_walk_footstep_index)
	if stream_index < 0:
		return

	_footstep_player.stream = streams[stream_index]
	_footstep_player.volume_db = -7.0 if running else -10.0
	_footstep_player.play()
	if running:
		_last_run_footstep_index = stream_index
	else:
		_last_walk_footstep_index = stream_index


func _load_audio_streams(paths: Array) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path_value in paths:
		var path := str(path_value)
		if not ResourceLoader.exists(path):
			push_warning("Player missing footstep audio: %s" % path)
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			push_warning("Player could not load footstep audio: %s" % path)
			continue
		streams.append(stream)
	return streams


func _pick_audio_index(count: int, previous_index: int) -> int:
	if count <= 0:
		return -1
	if count == 1:
		return 0

	var random_index := randi() % count
	if random_index == previous_index:
		random_index = (random_index + 1 + int(randi() % (count - 1))) % count
	return random_index


func _is_ui_blocking_footsteps() -> bool:
	return _is_inventory_open() or _is_storage_open() or _is_crafting_open()


func take_damage(amount: int) -> void:
	if amount <= 0:
		return

	health = max(health - amount, 0)
	health_changed.emit(health, max_health)
	FloatingCombatTextSpawner.show_hit_impact(global_position + Vector2(0, -18), false)
	_play_hit_flash(Color(1.0, 0.35, 0.35, 1.0))
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), false, "player")

	if health == 0:
		_die()


func gain_xp(amount: int) -> void:
	if amount <= 0:
		return

	var leveled_up := false
	current_xp += amount
	while current_xp >= xp_to_next_level:
		current_xp -= xp_to_next_level
		_level_up()
		leveled_up = true

	if not leveled_up:
		xp_changed.emit(current_xp, xp_to_next_level, level)


func _level_up() -> void:
	level += 1
	xp_to_next_level = int(30 + level * 18)
	max_health += 5
	health = max_health
	attack_damage += 1
	health_changed.emit(health, max_health)
	level_changed.emit(level)
	xp_changed.emit(current_xp, xp_to_next_level, level)
	FloatingCombatTextSpawner.show_text("LEVEL UP", global_position + Vector2(0, -34), Color(0.55, 0.9, 1.0, 1.0), false, "xp_number")


func heal(amount: int) -> void:
	if amount <= 0:
		return

	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)
	if show_floating_damage:
		FloatingCombatTextSpawner.show_heal(amount, global_position + Vector2(0, -28))


func apply_combat_result(combat_result: Dictionary) -> void:
	if bool(combat_result.get("miss", false)):
		if show_floating_damage:
			FloatingCombatTextSpawner.show_miss(global_position + Vector2(0, -28))
		return

	var amount := int(combat_result.get("damage", 0))
	if amount <= 0:
		return

	health = max(health - amount, 0)
	health_changed.emit(health, max_health)
	FloatingCombatTextSpawner.show_hit_impact(global_position + Vector2(0, -18), bool(combat_result.get("is_critical", false)))
	_play_hit_flash(Color(1.0, 0.35, 0.35, 1.0))
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), bool(combat_result.get("is_critical", false)), "player")

	if health == 0:
		_die()


func get_progression_data() -> Dictionary:
	return {
		"level": level,
		"current_xp": current_xp,
		"xp_to_next_level": xp_to_next_level,
	}


func load_progression_data(save_data) -> void:
	if not save_data is Dictionary:
		return

	level = max(int(save_data.get("level", level)), 1)
	current_xp = max(int(save_data.get("current_xp", current_xp)), 0)
	xp_to_next_level = max(int(save_data.get("xp_to_next_level", xp_to_next_level)), 1)
	xp_changed.emit(current_xp, xp_to_next_level, level)
	level_changed.emit(level)


func get_current_tool() -> String:
	return unlocked_tools[current_tool_index]


func has_tool(tool_name: String) -> bool:
	return unlocked_tools.has(_normalize_tool_name(tool_name))


func unlock_tool(tool_name: String) -> bool:
	var normalized_tool_name := _normalize_tool_name(tool_name)
	if not _is_known_tool(normalized_tool_name):
		return false

	if has_tool(normalized_tool_name):
		return false

	unlocked_tools.append(normalized_tool_name)
	tool_changed.emit(get_current_tool())
	return true


func get_unlocked_tools() -> Array:
	return unlocked_tools.duplicate()


func set_current_tool(tool_name: String) -> void:
	var normalized_tool_name := _normalize_tool_name(tool_name)
	var tool_index := unlocked_tools.find(normalized_tool_name)
	if tool_index == -1:
		return

	current_tool_index = tool_index
	tool_changed.emit(get_current_tool())


func set_unlocked_tools(tool_names: Array) -> void:
	var previous_tool := get_current_tool()
	unlocked_tools = [
		TOOL_HANDS,
	]

	for tool_name in tool_names:
		_add_unlocked_tool(str(tool_name))

	current_tool_index = unlocked_tools.find(previous_tool)
	if current_tool_index == -1:
		current_tool_index = 0

	tool_changed.emit(get_current_tool())


func set_respawn_point(respawn_position: Vector2) -> void:
	spawn_position = respawn_position
	has_respawn_point = true


func clear_respawn_point() -> void:
	spawn_position = initial_spawn_position
	has_respawn_point = false


func has_custom_respawn_point() -> bool:
	return has_respawn_point


func get_respawn_point() -> Vector2:
	return spawn_position


func get_debug_base_stats() -> Dictionary:
	var combat_data := _get_combat_data()
	var base_stats = combat_data.get("base_stats", {})
	if base_stats is Dictionary:
		return base_stats.duplicate(true)

	return {}


func set_debug_base_stat(stat_name: String, value: int) -> void:
	debug_base_stats_override[stat_name] = max(value, 0)


func get_combat_data() -> Dictionary:
	return _get_combat_data()


func get_current_held_item_data() -> Dictionary:
	return _get_current_held_item_data()


func _attack() -> void:
	if not attack_timing_enabled:
		attack_started.emit()
		_play_attack_feedback()
		_perform_attack_hits()
		attack_finished.emit()
		return

	if _attack_in_progress:
		return

	_attack_in_progress = true
	attack_started.emit()
	_play_attack_feedback()
	await _wait_attack_step(attack_windup_time)
	await _wait_attack_step(attack_hit_time)
	_perform_attack_hits()
	await _wait_attack_step(attack_recovery_time)
	attack_finished.emit()
	_attack_in_progress = false


func _perform_attack_hits() -> void:
	for target in _find_nearby_attack_targets("enemy"):
		if _current_item_can_hit("can_hit_monsters", true):
			_attack_enemy(target)

	for target in _find_nearby_attack_targets("resource_node"):
		if _current_item_can_hit("can_hit_resources", true):
			_attack_resource(target)


func _attack_enemy(target: Node) -> void:
	if _is_equipped_weapon_broken():
		FloatingCombatTextSpawner.show_text("Weapon is broken!", global_position + Vector2(0, -28), Color(0.8, 0.2, 0.2, 1.0))
		return

	var target_data := {}
	if target.has_method("get_combat_data"):
		target_data = target.call("get_combat_data")

	var eq_system = _get_equipment_system()
	var attacker_data := player_stats_resolver.get_total_player_data(self, eq_system)
	var weapon_data := player_stats_resolver.get_equipped_weapon_data(eq_system)
	var held_item_data := weapon_data if not weapon_data.is_empty() else _get_current_held_item_data()

	var combat_result := combat_calculator.calculate_damage(attacker_data, target_data, held_item_data)
	attack_hit_frame.emit()
	if target.has_method("apply_combat_result"):
		target.call("apply_combat_result", combat_result)
	else:
		target.call("take_damage", int(combat_result.get("damage", attack_damage)))
	_reduce_equipped_weapon_durability()


func _attack_resource(target: Node) -> void:
	if _is_equipped_tool_broken():
		FloatingCombatTextSpawner.show_text("Tool is broken!", global_position + Vector2(0, -28), Color(0.8, 0.2, 0.2, 1.0))
		return

	var eq_system = _get_equipment_system()
	var actor_data := player_stats_resolver.get_total_player_data(self, eq_system)

	if target.has_method("apply_gather_hit"):
		attack_hit_frame.emit()
		target.call("apply_gather_hit", _get_current_held_item_data(), actor_data, {})
		_reduce_equipped_tool_durability()
		return

	attack_hit_frame.emit()
	target.call("take_damage", _get_resource_attack_damage(target))
	_reduce_equipped_tool_durability()


func _get_combat_data() -> Dictionary:
	var character_data := {}
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_character") and content_db.has_character(character_id):
		character_data = content_db.get_character(character_id)
		attack_timing_enabled = bool(character_data.get("attack_timing_enabled", attack_timing_enabled))
		attack_windup_time = float(character_data.get("attack_windup_time", attack_windup_time))
		attack_hit_time = float(character_data.get("attack_hit_time", attack_hit_time))
		attack_recovery_time = float(character_data.get("attack_recovery_time", attack_recovery_time))

	var combat_data: Dictionary = character_data.duplicate(true) if character_data is Dictionary else {}
	combat_data["max_health"] = max_health
	if not combat_data.has("base_combat"):
		combat_data["base_combat"] = {
			"base_attack": attack_damage,
			"attack_cooldown": 0.6,
		}
	var base_stats = combat_data.get("base_stats", {})
	if not base_stats is Dictionary:
		base_stats = {}
	var clean_base_stats: Dictionary = (base_stats as Dictionary).duplicate(true)
	for stat_name in debug_base_stats_override.keys():
		clean_base_stats[str(stat_name)] = int(debug_base_stats_override[stat_name])
	combat_data["base_stats"] = clean_base_stats
	return combat_data


func _get_current_held_item_data() -> Dictionary:
	var tool_id := _get_current_tool_item_id()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_item") and content_db.has_item(tool_id):
		return content_db.get_item(tool_id)

	return {
		"id": tool_id,
		"combat": {
			"attack_power": 4 if get_current_tool() == TOOL_AXE or get_current_tool() == TOOL_PICKAXE else 0,
			"attack_variance": 0.15,
			"can_hit_monsters": true,
			"can_hit_resources": true,
		},
	}


func _wait_attack_step(duration: float) -> void:
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout


func _try_interact_with_nearby_npc() -> bool:
	for npc in get_tree().get_nodes_in_group("npc"):
		if not npc.has_method("try_interact_with_player"):
			continue

		if npc.call("try_interact_with_player", self):
			return true

	return false


func _try_interact_with_nearby_storage() -> bool:
	var nearest_storage: Node = null
	var nearest_distance := 56.0

	for storage in get_tree().get_nodes_in_group("storage"):
		if not storage is Node2D:
			continue
		if not storage.has_method("try_interact_with_player"):
			continue

		var storage_node := storage as Node2D
		var distance := global_position.distance_to(storage_node.global_position)
		if distance > nearest_distance:
			continue

		nearest_storage = storage
		nearest_distance = distance

	if nearest_storage == null:
		return false

	return bool(nearest_storage.call("try_interact_with_player", self))


func _try_interact_with_nearby_workbench() -> bool:
	var crafting_system = get_tree().get_first_node_in_group("crafting_system")
	if crafting_system == null or not crafting_system.has_method("try_open_workbench_for_player"):
		return false

	return bool(crafting_system.call("try_open_workbench_for_player", self))


func _is_storage_open() -> bool:
	var storage_ui := get_tree().get_first_node_in_group("storage_ui")
	if storage_ui == null or not storage_ui.has_method("is_open"):
		return false

	return bool(storage_ui.call("is_open"))


func _is_inventory_open() -> bool:
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return false
	var inventory_ui = main.get("inventory_ui")
	return inventory_ui != null and bool(inventory_ui.visible)


func _is_crafting_open() -> bool:
	var crafting_system = get_tree().get_first_node_in_group("crafting_system")
	if crafting_system == null or not crafting_system.has_method("is_crafting_open"):
		return false

	return bool(crafting_system.call("is_crafting_open"))


func _find_nearby_attack_targets(group_name: String) -> Array:
	var targets := []

	for node in get_tree().get_nodes_in_group(group_name):
		if not node is Node2D:
			continue

		if not node.has_method("take_damage"):
			continue

		var target := node as Node2D
		if global_position.distance_to(target.global_position) > attack_range:
			continue

		targets.append(target)

	return targets


func _get_resource_attack_damage(resource_node: Node) -> int:
	var held_item_data := _get_current_held_item_data()
	var combat_value: Variant = held_item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		var resource_damage_value: Variant = combat.get("resource_damage", {})
		if resource_damage_value is Dictionary:
			var resource_damage: Dictionary = resource_damage_value
			var resource_type_id := _get_target_resource_type_id(resource_node)
			var drop_item_id := _get_target_drop_item_id(resource_node)
			if resource_damage.has(resource_type_id):
				return int(resource_damage[resource_type_id])
			if drop_item_id == "wood" and resource_damage.has("tree"):
				return int(resource_damage["tree"])
			if drop_item_id == "stone" and resource_damage.has("rock"):
				return int(resource_damage["rock"])

	var item_tool_damage := int(held_item_data.get("tool_damage", 0))
	if item_tool_damage > 0:
		return item_tool_damage

	var current_tool := get_current_tool()
	var resource_type_id := _get_target_resource_type_id(resource_node)
	var drop_item_id := _get_target_drop_item_id(resource_node)
	if current_tool == TOOL_AXE:
		return TOOL_RESOURCE_DAMAGE if resource_type_id == "tree" or drop_item_id == "wood" else BASE_RESOURCE_DAMAGE
	if current_tool == TOOL_PICKAXE:
		return TOOL_RESOURCE_DAMAGE if resource_type_id == "rock" or drop_item_id == "stone" else BASE_RESOURCE_DAMAGE

	return BASE_RESOURCE_DAMAGE


func _current_item_can_hit(flag_name: String, default_value: bool) -> bool:
	var eq_system = _get_equipment_system()
	if eq_system != null:
		var slot_id := "weapon" if flag_name.find("monster") >= 0 else "tool"
		var slot_data = eq_system.get_equipped_slot(slot_id)
		var item_id := str(slot_data.get("item_id", ""))
		if not item_id.is_empty():
			var content_db := get_node_or_null("/root/ContentDB")
			if content_db != null and content_db.has_method("has_item") and content_db.has_item(item_id):
				var item_data: Dictionary = content_db.get_item(item_id)
				var combat_value: Variant = item_data.get("combat", {})
				if combat_value is Dictionary:
					var combat: Dictionary = combat_value
					return bool(combat.get(flag_name, default_value))
	var held_item_data := _get_current_held_item_data()
	var combat_value: Variant = held_item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		return bool(combat.get(flag_name, default_value))
	return default_value


func _get_current_tool_item_id() -> String:
	var hotbar_item_id := _get_selected_hotbar_tool_item_id()
	if not hotbar_item_id.is_empty():
		return hotbar_item_id

	var main := get_tree().get_first_node_in_group("main")
	if main != null:
		var eq_system = main.get("equipment_system")
		if eq_system != null and eq_system.has_method("get_equipped_slot"):
			var tool_slot: Dictionary = eq_system.get_equipped_slot("tool")
			var item_id := str(tool_slot.get("item_id", ""))
			if not item_id.is_empty():
				return item_id
	return get_current_tool().to_lower()


func _get_selected_hotbar_tool_item_id() -> String:
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return ""

	var hotbar_ui = main.get("hotbar_ui")
	if hotbar_ui == null:
		return ""

	var inventory = hotbar_ui.get("inventory")
	if inventory == null or not inventory.has_method("get_slot"):
		return ""

	var selected_slot := int(hotbar_ui.get("selected_slot"))
	if selected_slot < 0 or selected_slot >= inventory.get_slot_count():
		return ""

	var slot_data = inventory.get_slot(selected_slot)
	if not slot_data is Dictionary:
		return ""

	var item_id := str(slot_data.get("item_id", ""))
	if item_id.is_empty():
		return ""

	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return ""

	var item_data: Dictionary = content_db.get_item(item_id)
	var tool_type := str(item_data.get("tool_type", ""))
	if str(item_data.get("item_type", "")).to_lower() != "tool" and tool_type.is_empty():
		return ""

	return item_id


func _get_equipment_system():
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return null
	return main.get("equipment_system")


func _get_equipped_slot_metadata(slot_id: String) -> Dictionary:
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return {}
	var eq_system = main.get("equipment_system")
	if eq_system == null or not eq_system.has_method("get_equipped_slot"):
		return {}
	var slot_data = eq_system.get_equipped_slot(slot_id)
	if not slot_data is Dictionary:
		return {}
	var meta = slot_data.get("metadata", {})
	return meta if meta is Dictionary else {}


func _is_equipped_tool_broken() -> bool:
	var meta := _get_equipped_slot_metadata("tool")
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return false
	var eq_system = main.get("equipment_system")
	if eq_system == null:
		return false
	var tool_slot = eq_system.get_equipped_slot("tool")
	if not tool_slot is Dictionary:
		return false
	var item_id := str(tool_slot.get("item_id", ""))
	if item_id.is_empty():
		return false
	return ItemInstanceHelper.is_broken({"item_id": item_id, "metadata": meta})


func _is_equipped_weapon_broken() -> bool:
	var meta := _get_equipped_slot_metadata("weapon")
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return false
	var eq_system = main.get("equipment_system")
	if eq_system == null:
		return false
	var weapon_slot = eq_system.get_equipped_slot("weapon")
	if not weapon_slot is Dictionary:
		return false
	var item_id := str(weapon_slot.get("item_id", ""))
	if item_id.is_empty():
		return false
	return ItemInstanceHelper.is_broken({"item_id": item_id, "metadata": meta})


func _get_slot_metadata_from_dict(slot: Dictionary) -> Dictionary:
	var raw = slot.get("metadata", {})
	return raw if raw is Dictionary else {}


func _reduce_equipped_tool_durability() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return
	var eq_system = main.get("equipment_system")
	if eq_system == null or not eq_system.has_method("get_equipped_slot") or not eq_system.has_method("set_equipped_slot"):
		return
	var tool_slot = eq_system.get_equipped_slot("tool")
	if not tool_slot is Dictionary:
		return
	var item_id := str(tool_slot.get("item_id", ""))
	if item_id.is_empty():
		return
	var max_dura := ItemInstanceHelper.get_max_durability(item_id)
	if max_dura <= 0:
		return
	var meta: Dictionary = _get_slot_metadata_from_dict(tool_slot)
	var current_dura: int = meta.get("current_durability", max_dura)
	if current_dura <= 0:
		return
	meta["current_durability"] = max(0, current_dura - 1)
	tool_slot["metadata"] = meta
	eq_system.set_equipped_slot("tool", tool_slot)
	eq_system.changed.emit()


func _reduce_equipped_weapon_durability() -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main == null:
		return
	var eq_system = main.get("equipment_system")
	if eq_system == null or not eq_system.has_method("get_equipped_slot") or not eq_system.has_method("set_equipped_slot"):
		return
	var weapon_slot = eq_system.get_equipped_slot("weapon")
	if not weapon_slot is Dictionary:
		return
	var item_id := str(weapon_slot.get("item_id", ""))
	if item_id.is_empty():
		return
	var max_dura := ItemInstanceHelper.get_max_durability(item_id)
	if max_dura <= 0:
		return
	var meta: Dictionary = _get_slot_metadata_from_dict(weapon_slot)
	var current_dura: int = meta.get("current_durability", max_dura)
	if current_dura <= 0:
		return
	meta["current_durability"] = max(0, current_dura - 1)
	weapon_slot["metadata"] = meta
	eq_system.set_equipped_slot("weapon", weapon_slot)
	eq_system.changed.emit()


func _play_hit_flash(flash_color: Color) -> void:
	if not enable_hit_flash:
		return

	var targets: Array = []
	if animated_sprite != null and animated_sprite.visible:
		targets.append(animated_sprite)
	if body_visual != null and body_visual.visible:
		targets.append(body_visual)

	for target in targets:
		var canvas_item: CanvasItem = target as CanvasItem
		var original_color := canvas_item.modulate
		canvas_item.modulate = flash_color
		var tween := create_tween()
		tween.tween_property(canvas_item, "modulate", original_color, 0.12)


func _play_attack_feedback() -> void:
	var bump_tween := create_tween()
	bump_tween.tween_property(self, "scale", Vector2(1.04, 0.96), 0.05)
	bump_tween.tween_property(self, "scale", Vector2.ONE, 0.08)
	var flash_tween := create_tween()
	flash_tween.tween_property(self, "modulate", Color(1.0, 0.95, 0.95, 1.0), 0.04)
	flash_tween.tween_property(self, "modulate", Color.WHITE, 0.08)


func _get_target_resource_type_id(resource_node: Node) -> String:
	if resource_node.has_method("get_resource_type_id"):
		return str(resource_node.call("get_resource_type_id"))

	return ""


func _get_target_drop_item_id(resource_node: Node) -> String:
	if resource_node.has_method("get_drop_item_id"):
		return str(resource_node.call("get_drop_item_id"))

	if resource_node.has_method("get_resource_name"):
		match str(resource_node.call("get_resource_name")):
			"Wood":
				return "wood"
			"Stone":
				return "stone"

	return ""


func _select_previous_tool() -> void:
	_set_tool_index(current_tool_index - 1)


func _select_next_tool() -> void:
	_set_tool_index(current_tool_index + 1)


func _set_tool_index(tool_index: int) -> void:
	var tool_count := unlocked_tools.size()
	if tool_count == 0:
		return

	while tool_index < 0:
		tool_index += tool_count

	current_tool_index = tool_index % tool_count
	tool_changed.emit(get_current_tool())


func _is_known_tool(tool_name: String) -> bool:
	return TOOLS.has(_normalize_tool_name(tool_name))


func _add_unlocked_tool(tool_name: String) -> void:
	var normalized_tool_name := _normalize_tool_name(tool_name)
	if not _is_known_tool(normalized_tool_name):
		return

	if has_tool(normalized_tool_name):
		return

	unlocked_tools.append(normalized_tool_name)


func _normalize_tool_name(tool_name: String) -> String:
	match tool_name:
		"hands", "Hands":
			return TOOL_HANDS
		"axe", "Axe":
			return TOOL_AXE
		"pickaxe", "Pickaxe":
			return TOOL_PICKAXE
		_:
			return tool_name


func _is_build_mode_enabled() -> bool:
	var build_system = get_tree().get_first_node_in_group("build_system")
	if build_system == null:
		return false

	return build_system.is_build_mode_enabled()


func _setup_character_visual() -> void:
	animation_controller.setup(animated_sprite)
	animated_sprite.sprite_frames = animation_set_loader.load_for_character(character_id)

	if animation_controller.has_any_valid_animation():
		animated_sprite.visible = true
		body_visual.visible = false
		animation_controller.play_if_available("idle_down")
	else:
		animated_sprite.visible = false
		body_visual.visible = true


func _update_movement_animation(input_direction: Vector2) -> void:
	if not animation_controller.has_any_valid_animation():
		return

	if input_direction != Vector2.ZERO:
		_update_last_direction(input_direction)
		animation_controller.play_if_available("walk_%s" % last_direction)
		return

	animation_controller.play_if_available("idle_%s" % last_direction)


func _update_last_direction(input_direction: Vector2) -> void:
	var abs_x: float = abs(input_direction.x)
	var abs_y: float = abs(input_direction.y)
	if abs_x > abs_y:
		last_direction = "right" if input_direction.x > 0.0 else "left"
	elif abs_y > abs_x:
		last_direction = "down" if input_direction.y > 0.0 else "up"


func _die() -> void:
	print("Player died")
	global_position = spawn_position
	velocity = Vector2.ZERO
	health = max_health
	health_changed.emit(health, max_health)
