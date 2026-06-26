extends Node

const RecipeBookScript = preload("res://scripts/systems/RecipeBook.gd")

@export var main_path: NodePath = ".."
@export var player_path: NodePath = "../World/Player"
@export var build_system_path: NodePath = "../BuildSystem"
@export var crafting_label_path: NodePath = "../UI/CraftingLabel"
@export var workbench_range: float = 72.0

var crafting_open := false
var last_message := ""
var recipe_book := RecipeBookScript.new()
var workbench_recipe_ids := []

@onready var main = get_node(main_path)
@onready var player = get_node(player_path)
@onready var build_system = get_node(build_system_path)
@onready var crafting_label: Label = get_node(crafting_label_path)


func _ready() -> void:
	add_to_group("crafting_system")
	_refresh_workbench_recipes()
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

	var recipe_slot := _get_recipe_slot_from_key(event.keycode)
	if recipe_slot == -1:
		return

	_try_craft_recipe(recipe_slot)
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

	_refresh_workbench_recipes()
	last_message = ""
	_set_crafting_open(true)


func _set_crafting_open(is_open: bool) -> void:
	crafting_open = is_open
	crafting_label.visible = crafting_open
	_update_crafting_label()


func _try_craft_recipe(recipe_slot: int) -> bool:
	if recipe_slot < 0 or recipe_slot >= workbench_recipe_ids.size():
		return false

	var recipe_id := str(workbench_recipe_ids[recipe_slot])
	var recipe := recipe_book.get_recipe(recipe_id)
	if recipe.is_empty():
		return false

	var tool_name := _recipe_id_to_tool_name(recipe_id)
	var display_name := str(recipe.get("display_name", tool_name))
	var cost: Array = recipe.get("cost", [])

	if _is_tool_recipe(recipe) and player.has_tool(tool_name):
		_set_message("Already have %s" % display_name)
		return false

	if not _can_spend_cost(cost):
		_set_message("Not enough resources")
		return false

	var output_item_id := str(recipe.get("output_item_id", recipe_id))
	var output_amount := int(recipe.get("output_amount", 1))
	if not _is_tool_recipe(recipe):
		if not main.inventory.can_add_item(output_item_id, output_amount):
			_set_message("Inventory full")
			return false

	_spend_cost(cost)
	if _is_tool_recipe(recipe):
		player.unlock_tool(tool_name)
	else:
		var leftover: int = main.add_item_to_inventory(output_item_id, output_amount)
		if leftover > 0:
			_set_message("Inventory full")
			return false

	_set_message("Crafted %s" % display_name)
	return true


func _refresh_workbench_recipes() -> void:
	workbench_recipe_ids.clear()

	for recipe in recipe_book.get_all_recipes():
		var recipe_id := str(recipe.get("id", ""))
		if recipe_id.is_empty():
			continue

		if _is_tool_recipe(recipe) or str(recipe.get("workstation", "")) == "workbench":
			workbench_recipe_ids.append(recipe_id)

	workbench_recipe_ids.sort()


func _get_recipe_slot_from_key(keycode: int) -> int:
	if keycode < KEY_1 or keycode > KEY_9:
		return -1

	var slot := keycode - KEY_1
	if slot >= workbench_recipe_ids.size():
		return -1

	return slot


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
		var item_id := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if not main.can_spend_resource(item_id, amount):
			return false

	return true


func _spend_cost(cost: Array) -> void:
	for cost_entry in cost:
		var item_id := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		main.spend_resource(item_id, amount)


func _update_crafting_label() -> void:
	var lines := [
		"Workbench Crafting",
		"C Close",
	]

	if workbench_recipe_ids.is_empty():
		lines.append("No Workbench recipes found.")

	for index in range(workbench_recipe_ids.size()):
		var recipe_id := str(workbench_recipe_ids[index])
		var recipe := recipe_book.get_recipe(recipe_id)
		var tool_name := _recipe_id_to_tool_name(recipe_id)
		var display_name := str(recipe.get("display_name", tool_name))
		var owned_text := " (owned)" if _is_tool_recipe(recipe) and player != null and player.has_tool(tool_name) else ""
		lines.append("%d %s - %s%s" % [
			index + 1,
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
		var item_id := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue

		parts.append("%d %s" % [amount, _get_item_display_name(item_id)])

	if parts.is_empty():
		return "Free"

	return _join_lines_with_separator(parts, ", ")


func _get_item_display_name(item_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return item_id.capitalize()

	var item_data: Dictionary = content_db.get_item(item_id)
	return str(item_data.get("display_name", item_id.capitalize()))


func _recipe_id_to_tool_name(recipe_id: String) -> String:
	match recipe_id:
		"axe":
			return "Axe"
		"pickaxe":
			return "Pickaxe"
		_:
			return recipe_id.capitalize()


func _is_tool_recipe(recipe: Dictionary) -> bool:
	return str(recipe.get("type", "")) == "tool"


func _join_lines(lines: Array) -> String:
	return _join_lines_with_separator(lines, "\n")


func _join_lines_with_separator(lines: Array, separator: String) -> String:
	var text := ""

	for line in lines:
		if not text.is_empty():
			text += separator

		text += str(line)

	return text
