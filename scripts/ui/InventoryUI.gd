extends Control

const InventorySlotScene = preload("res://scenes/ui/InventorySlot.tscn")
const SpriteResolver = preload("res://scripts/systems/SpriteResolver.gd")

@export var slot_count: int = 20
@export var columns: int = 5

var inventory
var slots := []
var grid: GridContainer
var details_label: Label
var sprite_resolver := SpriteResolver.new()


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		visible = not visible
		if visible:
			refresh()
		get_viewport().set_input_as_handled()


func set_inventory(new_inventory) -> void:
	inventory = new_inventory
	if inventory != null and inventory.has_signal("changed"):
		inventory.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if grid == null or inventory == null:
		return

	for index in range(slots.size()):
		var slot = slots[index]
		var item_entry: Dictionary = inventory.get_slot(index)
		var item_id := str(item_entry.get("item_id", ""))
		var amount := int(item_entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			slot.clear_slot(index)
			continue

		var item_data: Dictionary = _get_item_data(item_id)
		slot.setup(index, item_id, amount, item_data, sprite_resolver.get_texture_for_item(item_id), "player")


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230.0
	panel.offset_top = -190.0
	panel.offset_right = 230.0
	panel.offset_bottom = 190.0
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

	var title := Label.new()
	title.text = "Inventory"
	layout.add_child(title)

	grid = GridContainer.new()
	grid.columns = columns
	layout.add_child(grid)

	for _index in range(slot_count):
		var slot = InventorySlotScene.instantiate()
		slot.slot_selected.connect(_on_slot_selected)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.slot_drag_dropped.connect(_on_slot_drag_dropped)
		grid.add_child(slot)
		slots.append(slot)

	details_label = Label.new()
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.custom_minimum_size = Vector2(0, 90)
	details_label.text = "Select an item."
	layout.add_child(details_label)


func _on_slot_selected(slot_index: int, item_id: String, _inventory_id := "player") -> void:
	if item_id.is_empty():
		details_label.text = "Empty slot %d." % (slot_index + 1)
		return

	var item_data: Dictionary = _get_item_data(item_id)
	var display_name := str(item_data.get("display_name", item_id.capitalize()))
	var description := str(item_data.get("description", ""))
	var stack_size := int(item_data.get("stack_size", 999))
	var slot_data: Dictionary = inventory.get_slot(slot_index) if inventory != null else {}
	var quantity := int(slot_data.get("amount", 0))
	details_label.text = "%s\nID: %s\nSlot: %d\nQuantity: %d\nStack: %d\n%s" % [
		display_name,
		item_id,
		slot_index + 1,
		quantity,
		stack_size,
		description,
	]


func _on_slot_right_clicked(slot_index: int, _inventory_id := "player") -> void:
	if inventory == null:
		return

	var removed: Dictionary = inventory.remove_from_slot(slot_index, 1)
	var item_id := str(removed.get("item_id", ""))
	if item_id.is_empty():
		return

	var item_data: Dictionary = _get_item_data(item_id)
	details_label.text = "Removed 1 %s.\nGround item drop will be added later." % str(item_data.get("display_name", item_id.capitalize()))


func _on_slot_drag_dropped(from_index: int, to_index: int, _from_inventory_id := "player", _to_inventory_id := "player") -> void:
	if inventory == null:
		return

	inventory.move_slot(from_index, to_index)
	refresh()


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}

	return content_db.get_item(item_id)
