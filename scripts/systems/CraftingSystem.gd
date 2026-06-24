extends Node

const TOOL_AXE := "Axe"
const TOOL_PICKAXE := "Pickaxe"

@export var main_path: NodePath = ".."
@export var player_path: NodePath = "../Player"
@export var build_system_path: NodePath = "../BuildSystem"
@export var crafting_label_path: NodePath = "../UI/CraftingLabel"
@export var workbench_range: float = 72.0

var crafting_open := false
var last_message := ""
var recipes := {
	1: {
		"tool": TOOL_AXE,
		"display_name": "Axe",
		"cost": [
			{"resource": "Wood", "amount": 3},
			{"resource": "Stone", "amount": 1},
		],
	},
	2: {
		"tool": TOOL_PICKAXE,
		"display_name": "Pickaxe",
		"cost": [
			{"resource": "Wood", "amount": 2},
			{"resource": "Stone", "amount": 3},
		],
	},
}

@onready var main = get_node(main_path)
@onready var player = get_node(player_path)
@onready var build_system = get_node(build_system_path)
@onready var crafting_label: Label = get_node(crafting_label_path)


func _ready() -> void:
	add_to_group("crafting_system")
	crafting_label.visible = false
	_update_crafting_label()


func _process(_delta: float) -> void:
	if crafting_open and not _is_player_near_workbench():
		_set_crafting_open(false)

	if crafting_open:
		_update_crafting_label()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_C:
		_toggle_crafting()
		get_viewport().set_input_as_handled()
		return

	if not crafting_open:
		return

	if event.keycode == KEY_1:
		_try_craft_recipe(1)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_2:
		_try_craft_recipe(2)
		get_viewport().set_input_as_handled()


func is_crafting_open() -> bool:
	return crafting_open


func _toggle_crafting() -> void:
	if crafting_open:
		_set_crafting_open(false)
		return

	if not _is_player_near_workbench():
		print("Need a Workbench nearby.")
		return

	if build_system.has_method("set_build_mode_enabled"):
		build_system.set_build_mode_enabled(false)

	last_message = ""
	_set_crafting_open(true)


func _set_crafting_open(is_open: bool) -> void:
	crafting_open = is_open
	crafting_label.visible = crafting_open
	_update_crafting_label()


func _try_craft_recipe(recipe_index: int) -> bool:
	if not recipes.has(recipe_index):
		return false

	var recipe: Dictionary = recipes[recipe_index]
	var tool_name := str(recipe.get("tool", ""))
	var display_name := str(recipe.get("display_name", tool_name))
	var cost: Array = recipe.get("cost", [])

	if player.has_tool(tool_name):
		_set_message("Already have %s" % display_name)
		return false

	if not _can_spend_cost(cost):
		_set_message("Not enough resources")
		return false

	_spend_cost(cost)
	player.unlock_tool(tool_name)
	_set_message("Crafted %s" % display_name)
	return true


func _set_message(message: String) -> void:
	last_message = message
	print(message)
	_update_crafting_label()


func _is_player_near_workbench() -> bool:
	if not build_system.has_method("is_workbench_near_position"):
		return false

	return build_system.is_workbench_near_position(player.global_position, workbench_range)


func _can_spend_cost(cost: Array) -> bool:
	for cost_entry in cost:
		var resource_name := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if not main.can_spend_resource(resource_name, amount):
			return false

	return true


func _spend_cost(cost: Array) -> void:
	for cost_entry in cost:
		var resource_name := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		main.spend_resource(resource_name, amount)


func _update_crafting_label() -> void:
	var lines := [
		"Workbench Crafting",
		"C Close",
	]

	for recipe_index in recipes.keys():
		var recipe: Dictionary = recipes[recipe_index]
		var tool_name := str(recipe.get("tool", ""))
		var display_name := str(recipe.get("display_name", tool_name))
		var owned_text := " (owned)" if player != null and player.has_tool(tool_name) else ""
		lines.append("%d %s - %s%s" % [
			int(recipe_index),
			display_name,
			_get_cost_text(recipe.get("cost", [])),
			owned_text,
		])

	if not last_message.is_empty():
		lines.append(last_message)

	crafting_label.text = _join_lines(lines)


func _get_cost_text(cost: Array) -> String:
	var parts := []

	for cost_entry in cost:
		var resource_name := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if resource_name.is_empty() or amount <= 0:
			continue

		parts.append("%d %s" % [amount, resource_name])

	if parts.is_empty():
		return "Free"

	return _join_lines_with_separator(parts, ", ")


func _join_lines(lines: Array) -> String:
	return _join_lines_with_separator(lines, "\n")


func _join_lines_with_separator(lines: Array, separator: String) -> String:
	var text := ""

	for line in lines:
		if not text.is_empty():
			text += separator

		text += str(line)

	return text
