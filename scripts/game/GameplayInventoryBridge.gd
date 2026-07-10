## Connects shared inventory/equipment state to gameplay UI without owning a scene.
class_name GameplayInventoryBridge
extends Node

var inventory
var equipment_system
var player: Node
var inventory_ui
var storage_ui
var hotbar_ui
var character_status_ui
var workbench_ui
var controller: Node


func setup(context: Dictionary) -> void:
	inventory = context.get("inventory")
	equipment_system = context.get("equipment_system")
	player = context.get("player") as Node
	inventory_ui = context.get("inventory_ui")
	storage_ui = context.get("storage_ui")
	hotbar_ui = context.get("hotbar_ui")
	character_status_ui = context.get("character_status_ui")
	workbench_ui = context.get("workbench_ui")
	controller = context.get("controller") as Node
	if inventory_ui != null:
		inventory_ui.set_inventory(inventory)
		inventory_ui.set_equipment_system(equipment_system)
	if storage_ui != null:
		storage_ui.setup(inventory, player)
	if hotbar_ui != null:
		hotbar_ui.setup(inventory, player)
	if character_status_ui != null:
		character_status_ui.setup(player)
		character_status_ui.set_equipment_system(equipment_system)
	if workbench_ui != null:
		workbench_ui.setup(controller, player)


func add_item(item_id: String, amount: int, metadata: Dictionary = {}) -> int:
	return inventory.add_item(item_id, amount, metadata) if inventory != null else amount


func can_spend(item_id: String, amount: int) -> bool:
	return inventory != null and inventory.has_item(item_id, amount)


func spend(item_id: String, amount: int) -> bool:
	return inventory != null and inventory.remove_item(item_id, amount)


func open_storage(storage_node: Node) -> void:
	if storage_ui != null and storage_ui.has_method("open_storage"):
		storage_ui.open_storage(storage_node)
