extends Button

const ItemInstanceHelper = preload("res://scripts/systems/ItemInstanceHelper.gd")

signal slot_selected(slot_index: int, item_id: String, inventory_id: String)
signal slot_right_clicked(slot_index: int, inventory_id: String, shift_pressed: bool, ctrl_pressed: bool)
signal slot_drag_dropped(from_index: int, to_index: int, from_inventory_id: String, to_inventory_id: String)
signal equipment_drag_dropped(from_slot_id: String, to_slot_index: int, to_inventory_id: String)
signal drag_started(slot_index: int, inventory_id: String)

var slot_index := -1
var inventory_id := "player"
var item_id := ""
var amount := 0
var display_name := ""
var metadata := {}
var is_broken := false


func setup(index: int, new_item_id: String, new_amount: int, item_data: Dictionary, texture: Texture2D, new_inventory_id := "player", new_metadata := {}) -> void:
	slot_index = index
	inventory_id = new_inventory_id
	item_id = new_item_id
	amount = new_amount
	metadata = new_metadata.duplicate(true) if new_metadata is Dictionary else {}
	display_name = str(item_data.get("display_name", item_id.capitalize()))
	is_broken = false
	if ItemInstanceHelper != null:
		var max_dura := ItemInstanceHelper.get_max_durability(item_id)
		if max_dura > 0 and slot_index >= 0:
			var current_dura := ItemInstanceHelper.get_current_durability({"item_id": item_id, "metadata": metadata})
			if current_dura <= 0:
				is_broken = true
	var initials := _get_initials(display_name)
	text = "%s\n%d" % [initials, amount]
	tooltip_text = _make_tooltip(item_data)
	icon = texture
	expand_icon = true
	custom_minimum_size = Vector2(64, 64)
	focus_mode = Control.FOCUS_NONE
	_apply_slot_style()


func clear_slot(index := -1) -> void:
	if index >= 0:
		slot_index = index
	item_id = ""
	amount = 0
	display_name = ""
	is_broken = false
	text = ""
	tooltip_text = "Empty"
	icon = null
	custom_minimum_size = Vector2(64, 64)
	focus_mode = Control.FOCUS_NONE
	_apply_slot_style()


func _pressed() -> void:
	slot_selected.emit(slot_index, item_id, inventory_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var mouse_event := event as InputEventMouseButton
		slot_right_clicked.emit(
			slot_index,
			inventory_id,
			mouse_event.shift_pressed,
			mouse_event.ctrl_pressed
		)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty() or amount <= 0:
		return null

	drag_started.emit(slot_index, inventory_id)

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
	if not data is Dictionary:
		return false
	var drop_type := str(data.get("type", ""))
	return drop_type == "inventory_slot" or drop_type == "equipment_slot"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return

	var drop_type := str(data.get("type", ""))
	if drop_type == "equipment_slot":
		equipment_drag_dropped.emit(
			str(data.get("slot_id", "")),
			slot_index,
			inventory_id
		)
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


func _make_tooltip(item_data: Dictionary) -> String:
	var lines := [
		"%s (%s)" % [display_name, item_id],
		"Amount: %d" % amount,
		"Stack: %d" % int(item_data.get("stack_size", 99)),
		"Tier: %s" % str(item_data.get("tier", "N/A")),
		"Type: %s" % str(item_data.get("item_type", "N/A")),
		"Family: %s" % str(item_data.get("material_family", "N/A")),
	]

	var description := str(item_data.get("description", ""))
	if not description.is_empty():
		lines.append(description)

	var item_type := str(item_data.get("item_type", ""))
	if item_type == "tool":
		lines.append("Tool: %s" % str(item_data.get("tool_type", "N/A")))
		lines.append("Tool Tier: %s" % str(item_data.get("tool_tier", "N/A")))
		lines.append("Tool Damage: %s" % str(item_data.get("tool_damage", "N/A")))

	if item_type == "armor" or item_type == "accessory" or item_type == "weapon" or item_type == "tool":
		var equip_slot := str(item_data.get("equipment_slot", ""))
		if not equip_slot.is_empty():
			lines.append("Slot: %s" % equip_slot.capitalize())

	var defense := int(item_data.get("defense", 0))
	if defense > 0:
		lines.append("Defense: %d" % defense)
	var magic_defense := int(item_data.get("magic_defense", 0))
	if magic_defense > 0:
		lines.append("Magic Def: %d" % magic_defense)

	var stats_bonus_val: Variant = item_data.get("stats_bonus", {})
	if stats_bonus_val is Dictionary and not stats_bonus_val.is_empty():
		for stat in stats_bonus_val.keys():
			var val := int(stats_bonus_val[stat])
			if val != 0:
				lines.append("+%d %s" % [val, stat.capitalize()])

	var combat_value: Variant = item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		lines.append("Attack: %s" % str(combat.get("attack_power", "N/A")))
		lines.append("Damage Type: %s" % str(combat.get("damage_type", "N/A")))
		lines.append("Crit Bonus: %s" % str(combat.get("crit_chance_bonus", "N/A")))

	var max_dura := ItemInstanceHelper.get_max_durability(item_id)
	if max_dura > 0:
		var current_dura := ItemInstanceHelper.get_current_durability({"item_id": item_id, "metadata": metadata})
		if current_dura <= 0:
			lines.append("Durability: BROKEN")
		else:
			lines.append("Durability: %d / %d" % [current_dura, max_dura])

	return "\n".join(lines)


func _apply_slot_style() -> void:
	if is_broken:
		var broken_style := StyleBoxFlat.new()
		broken_style.bg_color = Color(0.45, 0.08, 0.07, 0.92)
		broken_style.border_color = Color(0.95, 0.22, 0.18, 1.0)
		broken_style.set_border_width_all(2)
		broken_style.corner_radius_top_left = 4
		broken_style.corner_radius_top_right = 4
		broken_style.corner_radius_bottom_left = 4
		broken_style.corner_radius_bottom_right = 4
		add_theme_stylebox_override("normal", broken_style)
		add_theme_stylebox_override("hover", broken_style)
		add_theme_stylebox_override("pressed", broken_style)
		return

	remove_theme_stylebox_override("normal")
	remove_theme_stylebox_override("hover")
	remove_theme_stylebox_override("pressed")
