extends CharacterBody2D

signal health_changed(current_health: int, max_health: int)
signal tool_changed(current_tool: String)

const TOOL_HANDS := "Hands"
const TOOL_AXE := "Axe"
const TOOL_PICKAXE := "Pickaxe"
const TOOLS := [
	TOOL_HANDS,
	TOOL_AXE,
	TOOL_PICKAXE,
]
const BASE_RESOURCE_DAMAGE := 10
const TOOL_RESOURCE_DAMAGE := 20

@export var speed: float = 180.0
@export var max_health: int = 100
@export var attack_damage: int = 10
@export var attack_range: float = 48.0

var health: int = 100
var spawn_position := Vector2.ZERO
var current_tool_index := 0
var unlocked_tools := [
	TOOL_HANDS,
]


func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
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


func get_current_tool() -> String:
	return unlocked_tools[current_tool_index]


func has_tool(tool_name: String) -> bool:
	return unlocked_tools.has(tool_name)


func unlock_tool(tool_name: String) -> bool:
	if not _is_known_tool(tool_name):
		return false

	if has_tool(tool_name):
		return false

	unlocked_tools.append(tool_name)
	tool_changed.emit(get_current_tool())
	return true


func get_unlocked_tools() -> Array:
	return unlocked_tools.duplicate()


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


func _attack() -> void:
	for target in _find_nearby_attack_targets("enemy"):
		target.call("take_damage", attack_damage)

	for target in _find_nearby_attack_targets("resource_node"):
		target.call("take_damage", _get_resource_attack_damage(target))


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
	var current_tool := get_current_tool()
	if current_tool == TOOL_HANDS:
		return BASE_RESOURCE_DAMAGE

	var resource_type_id := _get_target_resource_type_id(resource_node)
	var drop_item_id := _get_target_drop_item_id(resource_node)
	if current_tool == TOOL_AXE:
		return TOOL_RESOURCE_DAMAGE if resource_type_id == "tree" or drop_item_id == "wood" else BASE_RESOURCE_DAMAGE
	if current_tool == TOOL_PICKAXE:
		return TOOL_RESOURCE_DAMAGE if resource_type_id == "rock" or drop_item_id == "stone" else BASE_RESOURCE_DAMAGE

	return BASE_RESOURCE_DAMAGE


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
	return TOOLS.has(tool_name)


func _add_unlocked_tool(tool_name: String) -> void:
	if not _is_known_tool(tool_name):
		return

	if has_tool(tool_name):
		return

	unlocked_tools.append(tool_name)


func _is_build_mode_enabled() -> bool:
	var build_system = get_tree().get_first_node_in_group("build_system")
	if build_system == null:
		return false

	return build_system.is_build_mode_enabled()


func _die() -> void:
	print("Player died")
	global_position = spawn_position
	velocity = Vector2.ZERO
	health = max_health
	health_changed.emit(health, max_health)
