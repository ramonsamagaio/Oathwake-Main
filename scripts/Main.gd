extends Node2D

const Inventory = preload("res://scripts/Inventory.gd")
const SAVE_PATH := "user://savegame.json"

var inventory := Inventory.new()
var collected_resource_ids := {}

@onready var resources_root: Node2D = $World/Resources
@onready var wood_label: Label = $UI/WoodLabel
@onready var stone_label: Label = $UI/StoneLabel
@onready var gel_label: Label = $UI/GelLabel
@onready var tool_label: Label = $UI/ToolLabel
@onready var health_label: Label = $UI/HealthLabel
@onready var save_button: Button = $UI/SaveButton
@onready var load_button: Button = $UI/LoadButton
@onready var player = $Player
@onready var build_system = $BuildSystem


func _ready() -> void:
	add_to_group("main")
	_configure_save_buttons()
	inventory.changed.connect(_update_resource_labels)
	player.health_changed.connect(_update_health_label)
	player.tool_changed.connect(_update_tool_label)
	save_button.pressed.connect(save_game)
	load_button.pressed.connect(load_game)
	_connect_resource_nodes()
	_update_resource_labels()
	_update_tool_label(player.get_current_tool())
	_update_health_label(player.health, player.max_health)
	load_game()


func _connect_resource_nodes() -> void:
	for resource_node in resources_root.get_children():
		if resource_node.has_signal("collected"):
			resource_node.connect("collected", _on_resource_collected)


func _on_resource_collected(resource_id: String, item_id: String, amount: int) -> void:
	if not resource_id.is_empty():
		collected_resource_ids[resource_id] = true

	add_resource(item_id, amount)


func add_resource(resource_name: String, amount: int) -> void:
	inventory.add_item(resource_name, amount)


func can_spend_resource(resource_name: String, amount: int) -> bool:
	return inventory.has_item(resource_name, amount)


func spend_resource(resource_name: String, amount: int) -> bool:
	return inventory.remove_item(resource_name, amount)


func save_game() -> void:
	var save_data := {
		"inventory": {
			"wood": inventory.get_count("wood"),
			"stone": inventory.get_count("stone"),
			"gel": inventory.get_count("gel"),
		},
		"walls": build_system.get_built_wall_cells(),
		"buildings": build_system.get_built_buildings(),
		"respawning_resources": _get_respawning_resources(),
		"unlocked_tools": player.get_unlocked_tools(),
	}

	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file == null:
		print("Could not save game to %s" % SAVE_PATH)
		return

	save_file.store_string(JSON.stringify(save_data, "\t"))
	print("Saved game to %s" % SAVE_PATH)


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save file found at %s" % SAVE_PATH)
		return

	var save_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if save_file == null:
		print("Could not load game from %s" % SAVE_PATH)
		return

	var json := JSON.new()
	var parse_error := json.parse(save_file.get_as_text())
	if parse_error != OK:
		print("Could not parse save file at %s" % SAVE_PATH)
		return

	if not json.data is Dictionary:
		print("Save file has invalid data.")
		return

	var save_data: Dictionary = json.data
	var inventory_data = save_data.get("inventory", {})
	if not inventory_data is Dictionary:
		inventory_data = {}

	_load_inventory(inventory_data)

	var buildings = save_data.get("buildings", [])
	if save_data.has("buildings") and buildings is Array:
		build_system.load_built_buildings(buildings)
	else:
		var wall_cells = save_data.get("walls", [])
		if not wall_cells is Array:
			wall_cells = []

		build_system.load_built_wall_cells(wall_cells)

	var respawning_resources = save_data.get("respawning_resources", [])
	if not respawning_resources is Array:
		respawning_resources = []

	_load_respawning_resources(respawning_resources)

	var unlocked_tools = save_data.get("unlocked_tools", [])
	if not unlocked_tools is Array:
		unlocked_tools = []

	player.set_unlocked_tools(unlocked_tools)
	print("Loaded game from %s" % SAVE_PATH)


func _update_resource_labels() -> void:
	wood_label.text = "%s: %d" % [_get_item_display_name("wood"), inventory.get_count("wood")]
	stone_label.text = "%s: %d" % [_get_item_display_name("stone"), inventory.get_count("stone")]
	gel_label.text = "%s: %d" % [_get_item_display_name("gel"), inventory.get_count("gel")]


func _update_health_label(current_health: int, max_health: int) -> void:
	health_label.text = "Health: %d/%d" % [current_health, max_health]


func _update_tool_label(current_tool: String) -> void:
	tool_label.text = "Tool: %s" % current_tool


func _configure_save_buttons() -> void:
	save_button.focus_mode = Control.FOCUS_NONE
	load_button.focus_mode = Control.FOCUS_NONE


func _load_inventory(inventory_data: Dictionary) -> void:
	inventory.set_resource_amount("wood", int(inventory_data.get("wood", inventory_data.get("Wood", 0))))
	inventory.set_resource_amount("stone", int(inventory_data.get("stone", inventory_data.get("Stone", 0))))
	inventory.set_resource_amount("gel", int(inventory_data.get("gel", inventory_data.get("Gel", 0))))


func _get_item_display_name(item_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return item_id.capitalize()

	var item_data: Dictionary = content_db.get_item(item_id)
	return str(item_data.get("display_name", item_id.capitalize()))


func _get_respawning_resources() -> Array:
	var respawning_resources := []

	for resource_node in resources_root.get_children():
		if not resource_node.has_method("is_collected"):
			continue

		if not resource_node.is_collected():
			continue

		if not resource_node.has_method("get_resource_id"):
			continue

		var resource_id := str(resource_node.get_resource_id())
		if resource_id.is_empty():
			continue

		var respawn_time_left := 0.0
		if resource_node.has_method("get_respawn_time_left"):
			respawn_time_left = float(resource_node.get_respawn_time_left())
		if respawn_time_left <= 0.0:
			continue

		respawning_resources.append({
			"id": resource_id,
			"respawn_time_left": respawn_time_left,
		})

	return respawning_resources


func _load_respawning_resources(respawning_resources: Array) -> void:
	collected_resource_ids.clear()
	var respawn_time_by_id := {}

	for respawning_resource in respawning_resources:
		if not respawning_resource is Dictionary:
			continue

		var resource_id := str(respawning_resource.get("id", ""))
		var respawn_time_left := float(respawning_resource.get("respawn_time_left", 0.0))
		if resource_id.is_empty() or respawn_time_left <= 0.0:
			continue

		respawn_time_by_id[resource_id] = respawn_time_left

	for resource_node in resources_root.get_children():
		if not resource_node.has_method("get_resource_id"):
			continue

		var resource_id := str(resource_node.get_resource_id())
		if respawn_time_by_id.has(resource_id):
			resource_node.set_collected(true, float(respawn_time_by_id[resource_id]))
			collected_resource_ids[resource_id] = true
		else:
			resource_node.set_collected(false)


func _load_collected_resources(resource_ids: Array) -> void:
	collected_resource_ids.clear()

	for resource_id in resource_ids:
		collected_resource_ids[str(resource_id)] = true

	for resource_node in resources_root.get_children():
		if not resource_node.has_method("get_resource_id"):
			continue

		resource_node.set_collected(collected_resource_ids.has(resource_node.get_resource_id()))
