extends Node2D

const Inventory = preload("res://scripts/Inventory.gd")
const SAVE_PATH := "user://savegame.json"

var inventory := Inventory.new()
var collected_resource_ids := {}

@onready var resources_root: Node2D = $World/Resources
@onready var wood_label: Label = $UI/WoodLabel
@onready var stone_label: Label = $UI/StoneLabel
@onready var health_label: Label = $UI/HealthLabel
@onready var player = $Player
@onready var build_system = $BuildSystem


func _ready() -> void:
	inventory.changed.connect(_update_resource_labels)
	player.health_changed.connect(_update_health_label)
	_connect_resource_nodes()
	_update_resource_labels()
	_update_health_label(player.health, player.max_health)
	load_game()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			save_game()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			load_game()
			get_viewport().set_input_as_handled()


func _connect_resource_nodes() -> void:
	for resource_node in resources_root.get_children():
		if resource_node.has_signal("collected"):
			resource_node.connect("collected", _on_resource_collected)


func _on_resource_collected(resource_id: String, resource_name: String, amount: int) -> void:
	if not resource_id.is_empty():
		collected_resource_ids[resource_id] = true

	add_resource(resource_name, amount)


func add_resource(resource_name: String, amount: int) -> void:
	inventory.add_resource(resource_name, amount)


func can_spend_resource(resource_name: String, amount: int) -> bool:
	return inventory.can_spend_resource(resource_name, amount)


func spend_resource(resource_name: String, amount: int) -> bool:
	return inventory.spend_resource(resource_name, amount)


func save_game() -> void:
	var save_data := {
		"inventory": {
			"Wood": inventory.get_resource_amount("Wood"),
			"Stone": inventory.get_resource_amount("Stone"),
		},
		"walls": build_system.get_built_wall_cells(),
		"buildings": build_system.get_built_buildings(),
		"collected_resources": collected_resource_ids.keys(),
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

	inventory.set_resource_amount("Wood", int(inventory_data.get("Wood", 0)))
	inventory.set_resource_amount("Stone", int(inventory_data.get("Stone", 0)))

	var buildings = save_data.get("buildings", [])
	if save_data.has("buildings") and buildings is Array:
		build_system.load_built_buildings(buildings)
	else:
		var wall_cells = save_data.get("walls", [])
		if not wall_cells is Array:
			wall_cells = []

		build_system.load_built_wall_cells(wall_cells)

	var collected_resources = save_data.get("collected_resources", [])
	if not collected_resources is Array:
		collected_resources = []

	_load_collected_resources(collected_resources)
	print("Loaded game from %s" % SAVE_PATH)


func _update_resource_labels() -> void:
	wood_label.text = "Wood: %d" % inventory.get_resource_amount("Wood")
	stone_label.text = "Stone: %d" % inventory.get_resource_amount("Stone")


func _update_health_label(current_health: int, max_health: int) -> void:
	health_label.text = "Health: %d/%d" % [current_health, max_health]


func _load_collected_resources(resource_ids: Array) -> void:
	collected_resource_ids.clear()

	for resource_id in resource_ids:
		collected_resource_ids[str(resource_id)] = true

	for resource_node in resources_root.get_children():
		if not resource_node.has_method("get_resource_id"):
			continue

		resource_node.set_collected(collected_resource_ids.has(resource_node.get_resource_id()))
