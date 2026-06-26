extends Control

const InventorySlotScene = preload("res://scenes/ui/InventorySlot.tscn")
const SpriteResolver = preload("res://scripts/systems/SpriteResolver.gd")

@export var player_columns: int = 5
@export var storage_columns: int = 5

var player_inventory
var player_node: Node2D
var storage_node
var storage_inventory
var player_slots: Array = []
var storage_slots: Array = []
var player_grid: GridContainer
var storage_grid: GridContainer
var title_label: Label
var message_label: Label
var sprite_resolver := SpriteResolver.new()


func _ready() -> void:
	add_to_group("storage_ui")
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()


func setup(new_player_inventory, new_player_node: Node2D) -> void:
	player_inventory = new_player_inventory
	player_node = new_player_node
	if player_inventory != null and player_inventory.has_signal("changed"):
		player_inventory.changed.connect(refresh)
	refresh()


func open_storage(new_storage_node) -> void:
	storage_node = new_storage_node
	if storage_node == null or not storage_node.has_method("get_inventory"):
		return

	storage_inventory = storage_node.get_inventory()
	if storage_inventory != null and storage_inventory.has_signal("changed") and not storage_inventory.changed.is_connected(refresh):
		storage_inventory.changed.connect(refresh)

	visible = true
	refresh()


func close() -> void:
	visible = false
	storage_node = null
	storage_inventory = null


func is_open() -> bool:
	return visible


func refresh() -> void:
	if player_grid == null:
		return

	if title_label != null:
		var display_name := "Storage"
		if storage_node != null and storage_node.has_method("get_display_name"):
			display_name = str(storage_node.get_display_name())
		title_label.text = "%s" % display_name

	_refresh_slot_list(player_slots, player_inventory, "player")
	_refresh_slot_list(storage_slots, storage_inventory, "storage")


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -390.0
	panel.offset_top = -230.0
	panel.offset_right = 390.0
	panel.offset_bottom = 230.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	title_label = Label.new()
	title_label.text = "Storage"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)

	player_grid = _add_inventory_column(columns, "Player", player_columns, player_slots)
	storage_grid = _add_inventory_column(columns, "Chest", storage_columns, storage_slots)

	message_label = Label.new()
	message_label.text = "Drag items between inventories. Right-click moves 1 item."
	layout.add_child(message_label)


func _add_inventory_column(parent: Node, label_text: String, columns: int, slot_list: Array) -> GridContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var label := Label.new()
	label.text = label_text
	box.add_child(label)

	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	for _index in range(20):
		var slot = InventorySlotScene.instantiate()
		slot.slot_selected.connect(_on_slot_selected)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.slot_drag_dropped.connect(_on_slot_drag_dropped)
		grid.add_child(slot)
		slot_list.append(slot)

	return grid


func _refresh_slot_list(slot_list: Array, inventory, inventory_id: String) -> void:
	for index in range(slot_list.size()):
		var slot = slot_list[index]
		if inventory == null:
			slot.clear_slot(index)
			slot.inventory_id = inventory_id
			continue

		var item_entry: Dictionary = inventory.get_slot(index)
		var item_id := str(item_entry.get("item_id", ""))
		var amount := int(item_entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			slot.clear_slot(index)
			slot.inventory_id = inventory_id
			continue

		var item_data: Dictionary = _get_item_data(item_id)
		var texture: Texture2D = sprite_resolver.get_texture_for_item(item_id)
		slot.setup(index, item_id, amount, item_data, texture, inventory_id)


func _on_slot_selected(slot_index: int, item_id: String, inventory_id: String) -> void:
	if item_id.is_empty():
		message_label.text = "Empty %s slot %d." % [inventory_id, slot_index + 1]
		return

	var item_data: Dictionary = _get_item_data(item_id)
	message_label.text = "%s slot %d: %s x%d" % [
		inventory_id.capitalize(),
		slot_index + 1,
		str(item_data.get("display_name", item_id.capitalize())),
		_get_inventory_by_id(inventory_id).get_slot(slot_index).get("amount", 0),
	]


func _on_slot_right_clicked(slot_index: int, inventory_id: String) -> void:
	var source_inventory = _get_inventory_by_id(inventory_id)
	var target_inventory = storage_inventory if inventory_id == "player" else player_inventory
	if source_inventory == null or target_inventory == null:
		return

	var removed: Dictionary = source_inventory.remove_from_slot(slot_index, 1)
	var item_id := str(removed.get("item_id", ""))
	var amount := int(removed.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return

	var leftover: int = target_inventory.add_item(item_id, amount)
	if leftover > 0:
		source_inventory.add_item(item_id, leftover)
		message_label.text = "No room to move %s." % item_id
	else:
		message_label.text = "Moved 1 %s." % item_id
	refresh()


func _on_slot_drag_dropped(from_index: int, to_index: int, from_inventory_id: String, to_inventory_id: String) -> void:
	var source_inventory = _get_inventory_by_id(from_inventory_id)
	var target_inventory = _get_inventory_by_id(to_inventory_id)
	if source_inventory == null or target_inventory == null:
		return

	if source_inventory == target_inventory:
		source_inventory.move_slot(from_index, to_index)
	else:
		_move_between_inventories(source_inventory, target_inventory, from_index, to_index)

	refresh()


func _move_between_inventories(source_inventory, target_inventory, from_index: int, to_index: int) -> void:
	var from_slot: Dictionary = source_inventory.get_slot(from_index)
	var to_slot: Dictionary = target_inventory.get_slot(to_index)
	var from_item := str(from_slot.get("item_id", ""))
	var to_item := str(to_slot.get("item_id", ""))
	var from_amount := int(from_slot.get("amount", 0))
	var to_amount := int(to_slot.get("amount", 0))
	if from_item.is_empty() or from_amount <= 0:
		return

	if to_item.is_empty():
		target_inventory.set_slot(to_index, from_item, from_amount)
		source_inventory.clear_slot(from_index)
		return

	if to_item == from_item:
		var stack_size := _get_stack_size(from_item)
		var transfer_amount: int = min(stack_size - to_amount, from_amount)
		if transfer_amount <= 0:
			return

		target_inventory.set_slot(to_index, to_item, to_amount + transfer_amount)
		from_amount -= transfer_amount
		if from_amount <= 0:
			source_inventory.clear_slot(from_index)
		else:
			source_inventory.set_slot(from_index, from_item, from_amount)
		return

	source_inventory.set_slot(from_index, to_item, to_amount)
	target_inventory.set_slot(to_index, from_item, from_amount)


func _get_inventory_by_id(inventory_id: String):
	if inventory_id == "storage":
		return storage_inventory
	return player_inventory


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}

	return content_db.get_item(item_id)


func _get_stack_size(item_id: String) -> int:
	var item_data: Dictionary = _get_item_data(item_id)
	return max(int(item_data.get("stack_size", 99)), 1)
