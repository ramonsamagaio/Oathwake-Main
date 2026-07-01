extends Control

const InventorySlotScene = preload("res://scenes/ui/InventorySlot.tscn")
const SpriteResolver = preload("res://scripts/systems/SpriteResolver.gd")

@export var player_columns: int = 5

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
var sprite_resolver: SpriteResolver = SpriteResolver.new()


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
		var display_name: String = "Storage"
		if storage_node != null and storage_node.has_method("get_display_name"):
			display_name = str(storage_node.get_display_name())
		title_label.text = "%s" % display_name

	var slot_count := _get_inventory_slot_count(storage_inventory)
	var new_columns := _calculate_storage_columns(slot_count)
	if storage_grid.columns != new_columns:
		storage_grid.columns = new_columns

	_ensure_slot_count(player_slots, player_grid, _get_inventory_slot_count(player_inventory))
	_ensure_slot_count(storage_slots, storage_grid, slot_count)
	_refresh_slot_list(player_slots, player_inventory, "player")
	_refresh_slot_list(storage_slots, storage_inventory, "storage")


func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
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

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(layout)

	var header: HBoxContainer = HBoxContainer.new()
	layout.add_child(header)

	title_label = Label.new()
	title_label.text = "Storage"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)

	player_grid = _add_inventory_column(columns, "Player", player_columns, player_slots)
	storage_grid = _add_inventory_column(columns, "Chest", 5, storage_slots, true)

	var controls := HBoxContainer.new()
	layout.add_child(controls)

	var sort_player_button: Button = Button.new()
	sort_player_button.text = "Sort Inventory"
	sort_player_button.focus_mode = Control.FOCUS_NONE
	sort_player_button.pressed.connect(_on_sort_player_pressed)
	controls.add_child(sort_player_button)

	var sort_chest_button: Button = Button.new()
	sort_chest_button.text = "Sort Chest"
	sort_chest_button.focus_mode = Control.FOCUS_NONE
	sort_chest_button.pressed.connect(_on_sort_storage_pressed)
	controls.add_child(sort_chest_button)

	var quick_stack_button: Button = Button.new()
	quick_stack_button.text = "Quick Stack"
	quick_stack_button.focus_mode = Control.FOCUS_NONE
	quick_stack_button.pressed.connect(_on_quick_stack_pressed)
	controls.add_child(quick_stack_button)

	message_label = Label.new()
	message_label.text = "Drag items. Right-click moves 1, Shift moves stack, Ctrl splits."
	layout.add_child(message_label)


func _add_inventory_column(parent: Node, label_text: String, columns: int, slot_list: Array, scrollable := false) -> GridContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var label: Label = Label.new()
	label.text = label_text
	box.add_child(label)

	var container: Node = box
	if scrollable:
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(scroll)
		container = scroll

	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not scrollable:
		grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(grid)

	_ensure_slot_count(slot_list, grid, 20)

	return grid


func _ensure_slot_count(slot_list: Array, grid: GridContainer, wanted_count: int) -> void:
	var safe_count: int = max(wanted_count, 1)
	while slot_list.size() < safe_count:
		var slot: Node = InventorySlotScene.instantiate()
		slot.slot_selected.connect(_on_slot_selected)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.slot_drag_dropped.connect(_on_slot_drag_dropped)
		grid.add_child(slot)
		slot_list.append(slot)

	while slot_list.size() > safe_count:
		var slot = slot_list.pop_back()
		if slot is Node:
			slot.queue_free()


func _get_inventory_slot_count(inventory) -> int:
	if inventory != null and inventory.has_method("get_slot_count"):
		return int(inventory.get_slot_count())

	return 20


func _calculate_storage_columns(slot_count: int) -> int:
	if slot_count <= 24:
		return 5
	return clampi(5 + (slot_count - 20) / 8, 5, 6)


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
		var metadata = item_entry.get("metadata", {})
		slot.setup(index, item_id, amount, item_data, texture, inventory_id, metadata)


func _on_slot_selected(slot_index: int, item_id: String, inventory_id: String) -> void:
	if item_id.is_empty():
		message_label.text = "Empty %s slot %d." % [inventory_id, slot_index + 1]
		return

	var item_data: Dictionary = _get_item_data(item_id)
	var quantity := int(_get_inventory_by_id(inventory_id).get_slot(slot_index).get("amount", 0))
	message_label.text = _get_item_details_text(item_id, quantity, slot_index, inventory_id)


func _on_slot_right_clicked(slot_index: int, inventory_id: String, shift_pressed := false, ctrl_pressed := false) -> void:
	var source_inventory = _get_inventory_by_id(inventory_id)
	var target_inventory = storage_inventory if inventory_id == "player" else player_inventory
	if source_inventory == null:
		return

	if ctrl_pressed:
		if source_inventory.split_half_to_empty_slot(slot_index):
			message_label.text = "Split stack."
		else:
			message_label.text = "No empty slot."
		refresh()
		return

	if target_inventory == null:
		return

	var slot_data: Dictionary = source_inventory.get_slot(slot_index)
	var move_amount := int(slot_data.get("amount", 0)) if shift_pressed else 1
	var moved_amount := _move_amount_between_inventories(source_inventory, target_inventory, slot_index, move_amount)
	if moved_amount <= 0:
		message_label.text = "No room."
		return

	message_label.text = "Moved %d %s." % [moved_amount, str(slot_data.get("item_id", ""))]
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

	var from_metadata: Variant = from_slot.get("metadata")

	if to_item.is_empty():
		target_inventory.set_slot(to_index, from_item, from_amount)
		if from_metadata is Dictionary:
			target_inventory.set_slot_metadata(to_index, from_metadata)
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

	var to_metadata: Variant = to_slot.get("metadata")
	source_inventory.set_slot(from_index, to_item, to_amount)
	if to_metadata is Dictionary:
		source_inventory.set_slot_metadata(from_index, to_metadata)
	target_inventory.set_slot(to_index, from_item, from_amount)
	if from_metadata is Dictionary:
		target_inventory.set_slot_metadata(to_index, from_metadata)


func _move_amount_between_inventories(source_inventory, target_inventory, from_index: int, amount: int) -> int:
	if amount <= 0:
		return 0

	var removed: Dictionary = source_inventory.remove_from_slot(from_index, amount)
	var item_id := str(removed.get("item_id", ""))
	var removed_amount := int(removed.get("amount", 0))
	var removed_metadata: Variant = removed.get("metadata")
	if item_id.is_empty() or removed_amount <= 0:
		return 0

	var meta_dict: Dictionary = removed_metadata if removed_metadata is Dictionary else {}
	var leftover: int = target_inventory.add_item(item_id, removed_amount, meta_dict)
	if leftover > 0:
		source_inventory.add_item(item_id, leftover, meta_dict)

	return removed_amount - leftover


func _on_sort_player_pressed() -> void:
	if player_inventory == null:
		return

	player_inventory.sort_items()
	refresh()
	message_label.text = "Inventory sorted."


func _on_sort_storage_pressed() -> void:
	if storage_inventory == null:
		return

	storage_inventory.sort_items()
	refresh()
	message_label.text = "Chest sorted."


func _on_quick_stack_pressed() -> void:
	if player_inventory == null or storage_inventory == null:
		return

	var moved_total := 0
	for index in range(player_slots.size()):
		var slot_data: Dictionary = player_inventory.get_slot(index)
		var item_id := str(slot_data.get("item_id", ""))
		var amount := int(slot_data.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		if storage_inventory.count_item(item_id) <= 0:
			continue

		moved_total += _move_amount_between_inventories(player_inventory, storage_inventory, index, amount)

	refresh()
	message_label.text = "Quick stacked %d item(s)." % moved_total


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


func _get_item_details_text(item_id: String, quantity: int, slot_index: int, inventory_id: String) -> String:
	var item_data: Dictionary = _get_item_data(item_id)
	var inventory = _get_inventory_by_id(inventory_id)
	var slot_data: Dictionary = inventory.get_slot(slot_index) if inventory != null else {}
	var metadata: Dictionary = slot_data.get("metadata", {}) if slot_data.get("metadata", {}) is Dictionary else {}
	var lines := [
		"%s slot %d" % [inventory_id.capitalize(), slot_index + 1],
		str(item_data.get("display_name", item_id.capitalize())),
		"ID: %s" % item_id,
		"Amount: %d" % quantity,
		"Stack: %d" % int(item_data.get("stack_size", 99)),
		"Tier: %s" % str(item_data.get("tier", "N/A")),
		"Type: %s" % str(item_data.get("item_type", "N/A")),
		"Family: %s" % str(item_data.get("material_family", "N/A")),
	]

	var description := str(item_data.get("description", ""))
	if not description.is_empty():
		lines.append(description)

	if str(item_data.get("item_type", "")) == "tool":
		lines.append("Tool: %s T%s" % [str(item_data.get("tool_type", "N/A")), str(item_data.get("tool_tier", "N/A"))])
		lines.append("Damage: %s" % str(item_data.get("tool_damage", "N/A")))

	var max_dura := int(item_data.get("durability", 0))
	if max_dura > 0:
		var current_dura := int(metadata.get("current_durability", max_dura))
		if current_dura <= 0:
			lines.append("Durability: BROKEN")
		else:
			lines.append("Durability: %d / %d" % [current_dura, max_dura])

	var combat_value: Variant = item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		lines.append("Attack: %s" % str(combat.get("attack_power", "N/A")))
		lines.append("Damage Type: %s" % str(combat.get("damage_type", "N/A")))
		lines.append("Crit Bonus: %s" % str(combat.get("crit_chance_bonus", "N/A")))

	return "\n".join(lines)
