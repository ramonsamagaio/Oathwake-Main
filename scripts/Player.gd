extends CharacterBody2D

signal health_changed(current_health: int, max_health: int)
signal tool_changed(current_tool: String)

const AnimationSetLoaderScript = preload("res://scripts/systems/AnimationSetLoader.gd")
const PlayerAnimationControllerScript = preload("res://scripts/systems/PlayerAnimationController.gd")
const CombatCalculatorScript = preload("res://scripts/systems/CombatCalculator.gd")
const FloatingCombatTextSpawner := preload("res://scripts/ui/FloatingCombatTextSpawner.gd")
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
@export var max_health: int = 100
@export var attack_damage: int = 10
@export var attack_range: float = 48.0
@export var character_id: String = "player"
@export var show_floating_damage := true
@export var enable_hit_flash := true

var health: int = 100
var spawn_position := Vector2.ZERO
var initial_spawn_position := Vector2.ZERO
var has_respawn_point := false
var current_tool_index := 0
var last_direction := "down"
var animation_controller := PlayerAnimationControllerScript.new()
var animation_set_loader := AnimationSetLoaderScript.new()
var combat_calculator := CombatCalculatorScript.new()
var debug_base_stats_override := {}
var unlocked_tools := [
	TOOL_HANDS,
]

@onready var body_visual: CanvasItem = $Body
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("player")
	_setup_character_visual()
	spawn_position = global_position
	initial_spawn_position = global_position
	health = max_health
	health_changed.emit(health, max_health)
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
		if _try_interact_with_nearby_npc():
			get_viewport().set_input_as_handled()
			return

		_select_next_tool()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_attack()
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_build_mode_enabled():
			return

		_attack()
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
	_update_movement_animation(direction)


func take_damage(amount: int) -> void:
	if amount <= 0:
		return

	health = max(health - amount, 0)
	health_changed.emit(health, max_health)
	_play_hit_flash(Color(1.0, 0.35, 0.35, 1.0))
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), false, "player")

	if health == 0:
		_die()


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
	_play_hit_flash(Color(1.0, 0.35, 0.35, 1.0))
	if show_floating_damage:
		FloatingCombatTextSpawner.show_damage(amount, global_position + Vector2(0, -28), bool(combat_result.get("is_critical", false)), "player")

	if health == 0:
		_die()


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
	for target in _find_nearby_attack_targets("enemy"):
		if _current_item_can_hit("can_hit_monsters", true):
			_attack_enemy(target)

	for target in _find_nearby_attack_targets("resource_node"):
		if _current_item_can_hit("can_hit_resources", true):
			_attack_resource(target)


func _attack_enemy(target: Node) -> void:
	var target_data := {}
	if target.has_method("get_combat_data"):
		target_data = target.call("get_combat_data")

	var combat_result := combat_calculator.calculate_damage(_get_combat_data(), target_data, _get_current_held_item_data())
	if target.has_method("apply_combat_result"):
		target.call("apply_combat_result", combat_result)
	else:
		target.call("take_damage", int(combat_result.get("damage", attack_damage)))


func _attack_resource(target: Node) -> void:
	if target.has_method("apply_gather_hit"):
		target.call("apply_gather_hit", _get_current_held_item_data(), _get_combat_data(), {})
		return

	target.call("take_damage", _get_resource_attack_damage(target))


func _get_combat_data() -> Dictionary:
	var character_data := {}
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_character") and content_db.has_character(character_id):
		character_data = content_db.get_character(character_id)

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


func _try_interact_with_nearby_npc() -> bool:
	for npc in get_tree().get_nodes_in_group("npc"):
		if not npc.has_method("try_interact_with_player"):
			continue

		if npc.call("try_interact_with_player", self):
			return true

	return false


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

	var current_tool := get_current_tool()
	var resource_type_id := _get_target_resource_type_id(resource_node)
	var drop_item_id := _get_target_drop_item_id(resource_node)
	if current_tool == TOOL_AXE:
		return TOOL_RESOURCE_DAMAGE if resource_type_id == "tree" or drop_item_id == "wood" else BASE_RESOURCE_DAMAGE
	if current_tool == TOOL_PICKAXE:
		return TOOL_RESOURCE_DAMAGE if resource_type_id == "rock" or drop_item_id == "stone" else BASE_RESOURCE_DAMAGE

	return BASE_RESOURCE_DAMAGE


func _current_item_can_hit(flag_name: String, default_value: bool) -> bool:
	var held_item_data := _get_current_held_item_data()
	var combat_value: Variant = held_item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		return bool(combat.get(flag_name, default_value))
	return default_value


func _get_current_tool_item_id() -> String:
	return get_current_tool().to_lower()


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
