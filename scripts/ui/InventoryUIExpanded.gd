extends "res://scripts/ui/InventoryUI.gd"

const FULL_INVENTORY_SLOT_COUNT := 60


func _ready() -> void:
	slot_count = FULL_INVENTORY_SLOT_COUNT
	_resize_backing_inventory()
	super._ready()
	call_deferred("_resize_backing_inventory")


func set_inventory(new_inventory) -> void:
	if new_inventory != null and new_inventory.has_method("resize_slots"):
		new_inventory.call("resize_slots", FULL_INVENTORY_SLOT_COUNT)
	super.set_inventory(new_inventory)


func _resize_backing_inventory() -> void:
	var game := get_parent()
	if game != null and game is CanvasLayer:
		game = game.get_parent()
	if game == null:
		return
	var inventory_value: Variant = game.get("inventory")
	if inventory_value != null and inventory_value.has_method("resize_slots"):
		inventory_value.call("resize_slots", FULL_INVENTORY_SLOT_COUNT)
	set_meta("full_inventory_slot_count", FULL_INVENTORY_SLOT_COUNT)
