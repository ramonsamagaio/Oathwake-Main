extends Button

signal slot_selected(item_id: String)

var item_id := ""


func setup(new_item_id: String, amount: int, item_data: Dictionary, texture: Texture2D) -> void:
	item_id = new_item_id
	var display_name := str(item_data.get("display_name", item_id.capitalize()))
	var initials := _get_initials(display_name)
	text = "%s\n%d" % [initials, amount]
	tooltip_text = "%s (%s)\nQuantity: %d" % [display_name, item_id, amount]
	icon = texture
	expand_icon = true
	custom_minimum_size = Vector2(64, 64)
	focus_mode = Control.FOCUS_NONE


func clear_slot() -> void:
	item_id = ""
	text = ""
	tooltip_text = ""
	icon = null
	custom_minimum_size = Vector2(64, 64)
	focus_mode = Control.FOCUS_NONE


func _pressed() -> void:
	if item_id.is_empty():
		return

	slot_selected.emit(item_id)


func _get_initials(display_name: String) -> String:
	var initials := ""
	for part in display_name.split(" ", false):
		if initials.length() >= 2:
			break
		initials += part.substr(0, 1).to_upper()

	if initials.is_empty():
		return "?"

	return initials
