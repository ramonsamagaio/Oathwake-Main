extends "res://scripts/ui/WorkbenchUI.gd"

var _connected_inventory: Object


func setup(new_main, new_player) -> void:
	_disconnect_inventory_signal()
	main = new_main
	player = new_player

	var inventory: Object = null
	if main != null:
		inventory = main.get("inventory")

	if inventory != null and inventory.has_signal("changed"):
		var refresh_callable := Callable(self, "refresh")
		if not inventory.is_connected("changed", refresh_callable):
			inventory.connect("changed", refresh_callable)
		_connected_inventory = inventory

	refresh()


func _exit_tree() -> void:
	_disconnect_inventory_signal()


func _disconnect_inventory_signal() -> void:
	if _connected_inventory == null or not is_instance_valid(_connected_inventory):
		_connected_inventory = null
		return

	var refresh_callable := Callable(self, "refresh")
	if _connected_inventory.has_signal("changed") and _connected_inventory.is_connected("changed", refresh_callable):
		_connected_inventory.disconnect("changed", refresh_callable)
	_connected_inventory = null
