extends Button

signal slot_selected(slot_index: int, item_id: String, inventory_id: String)
signal slot_right_clicked(slot_index: int, inventory_id: String)
signal slot_drag_dropped(from_index: int, to_index: int, from_inventory_id: String, to_inventory_id: String)

var slot_index := -1
var inventory_id := "player"
var item_id := ""
var amount := 0
var display_name := ""


func setup(index: int, new_item_id: String, new_amount: int, item_data: Dictionary, texture: Texture2D, new_inventory_id := "player") -> void:
	slot_index = index
	inventory_id = new_inventory_id
	item_id = new_item_id
	amount = new_amount
	display_name = str(item_data.get("display_name", item_id.capitalize()))
	var initials := _get_initials(display_name)
	text = "%s\n%d" % [initials, amount]
	tooltip_text = "%s (%s)\nQuantity: %d" % [display_name, item_id, amount]
	icon = texture
	expand_icon = true
	custom_minimum_size = Vector2(64, 64)
	focus_mode = Control.FOCUS_NONE


func clear_slot(index := -1) -> void:
	if index >= 0:
		slot_index = index
	item_id = ""
	amount = 0
	display_name = ""
	text = ""
	tooltip_text = "Empty"
	icon = null
	custom_minimum_size = Vector2(64, 64)
	focus_mode = Control.FOCUS_NONE


func _pressed() -> void:
	slot_selected.emit(slot_index, item_id, inventory_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		slot_right_clicked.emit(slot_index, inventory_id)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty() or amount <= 0:
		return null

	var preview := Button.new()
	preview.text = "x%d" % amount
	preview.icon = icon
	preview.expand_icon = true
	preview.custom_minimum_size = Vector2(56, 48)
	preview.disabled = true
	set_drag_preview(preview)
	return {
		"type": "inventory_slot",
		"slot_index": slot_index,
		"inventory_id": inventory_id,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and str(data.get("type", "")) == "inventory_slot"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return

	slot_drag_dropped.emit(
		int(data.get("slot_index", -1)),
		slot_index,
		str(data.get("inventory_id", "player")),
		inventory_id
	)


func _get_initials(name_text: String) -> String:
	var initials := ""
	for part in name_text.split(" ", false):
		if initials.length() >= 2:
			break
		initials += part.substr(0, 1).to_upper()

	if initials.is_empty():
		return "?"

	return initials
