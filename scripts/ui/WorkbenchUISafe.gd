extends "res://scripts/ui/WorkbenchUI.gd"

var _connected_inventory: Object


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "ModalBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.012, 0.01, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	super._build_ui()
	move_child(backdrop, 0)
	var panel := get_node_or_null("Panel") as PanelContainer
	if panel != null:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP


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


func _get_workbench_recipes() -> Array:
	var source: Array = super._get_workbench_recipes()
	var result: Array = []
	for recipe_variant in source:
		if not recipe_variant is Dictionary:
			continue
		var recipe: Dictionary = recipe_variant
		if not bool(recipe.get("craftable", true)):
			continue
		if bool(recipe.get("build_direct", false)):
			continue
		result.append(recipe)
	return result


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
