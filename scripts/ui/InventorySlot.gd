extends Button

const ItemInstanceHelper = preload("res://scripts/systems/ItemInstanceHelper.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const OathwakeUISkin := preload("res://scripts/ui/OathwakeUISkin.gd")

signal slot_selected(slot_index: int, item_id: String, inventory_id: String)
signal slot_right_clicked(slot_index: int, inventory_id: String, shift_pressed: bool, ctrl_pressed: bool)
signal slot_drag_dropped(from_index: int, to_index: int, from_inventory_id: String, to_inventory_id: String)
signal equipment_drag_dropped(from_slot_id: String, to_slot_index: int, to_inventory_id: String)
signal drag_started(slot_index: int, inventory_id: String)

const ITEM_ICON_SCALE := 0.58
const ITEM_ICON_OFFSET := Vector2(-4.0, -4.0)
const QUANTITY_FONT_SIZE := 14
const SLOT_VISUAL_INSET_LEFT := 0.0
const SLOT_VISUAL_INSET_TOP := 0.0
const SLOT_VISUAL_INSET_RIGHT := 0.0
const SLOT_VISUAL_INSET_BOTTOM := 0.0
const QUANTITY_INSET_LEFT := 2.0
const QUANTITY_INSET_TOP := 1.0
const QUANTITY_INSET_RIGHT := 24.0
const QUANTITY_INSET_BOTTOM := 18.0

var slot_index := -1
var inventory_id := "player"
var item_id := ""
var amount := 0
var display_name := ""
var metadata := {}
var is_broken := false
var _item_icon: TextureRect
var _quantity_label: Label


func setup(index: int, new_item_id: String, new_amount: int, item_data: Dictionary, texture: Texture2D, new_inventory_id := "player", new_metadata := {}) -> void:
	_ensure_overlay_controls()
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
	text = ""
	icon = null
	expand_icon = false
	tooltip_text = _make_tooltip(item_data)
	custom_minimum_size = Vector2.ZERO
	focus_mode = Control.FOCUS_NONE
	_apply_slot_style()
	_set_item_texture(texture)
	_set_quantity_label(amount)
	_layout_overlay_controls()


func clear_slot(index := -1) -> void:
	_ensure_overlay_controls()
	if index >= 0:
		slot_index = index
	item_id = ""
	amount = 0
	display_name = ""
	is_broken = false
	text = ""
	tooltip_text = "Empty"
	icon = null
	expand_icon = false
	custom_minimum_size = Vector2.ZERO
	focus_mode = Control.FOCUS_NONE
	_apply_slot_style()
	_set_item_texture(null)
	_set_quantity_label(0)
	_layout_overlay_controls()


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

	var preview_texture := _item_icon.texture if _item_icon != null else null
	var preview := TextureRect.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = preview_texture
	preview.custom_minimum_size = Vector2(48, 48)
	preview.size = Vector2(48, 48)
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_overlay_controls()


func _ensure_overlay_controls() -> void:
	clip_contents = true
	if _item_icon == null:
		_item_icon = TextureRect.new()
		_item_icon.name = "ItemIcon"
		_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_item_icon.z_index = 5
		add_child(_item_icon)

	if _quantity_label == null:
		_quantity_label = Label.new()
		_quantity_label.name = "QuantityLabel"
		_quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_quantity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_quantity_label.clip_text = true
		_quantity_label.z_index = 999
		_quantity_label.clip_contents = false
		add_child(_quantity_label)
		OathwakeTextStyle.apply_profile_to_label(_quantity_label, "inventory_quantity_text", null, QUANTITY_FONT_SIZE, 1)
		_quantity_label.add_theme_font_size_override("font_size", QUANTITY_FONT_SIZE)
		_quantity_label.set_anchors_preset(Control.PRESET_TOP_LEFT)


func _layout_overlay_controls() -> void:
	if _item_icon == null or _quantity_label == null:
		return

	var slot_size := size
	if slot_size.x <= 0.0 or slot_size.y <= 0.0:
		return

	var visual_rect := _get_visual_rect(slot_size)
	var icon_edge := minf(visual_rect.size.x, visual_rect.size.y) * ITEM_ICON_SCALE
	var icon_size := Vector2(icon_edge, icon_edge)
	_item_icon.size = icon_size
	_item_icon.position = visual_rect.position + (visual_rect.size - icon_size) * 0.5 + ITEM_ICON_OFFSET

	var quantity_visible := amount > 1
	_quantity_label.visible = quantity_visible
	if quantity_visible:
		_quantity_label.text = str(amount)
		_quantity_label.add_theme_font_size_override("font_size", QUANTITY_FONT_SIZE)
		_quantity_label.position = visual_rect.position + Vector2(QUANTITY_INSET_LEFT, QUANTITY_INSET_TOP)
		_quantity_label.size = Vector2(
			maxf(1.0, visual_rect.size.x - QUANTITY_INSET_LEFT - QUANTITY_INSET_RIGHT),
			maxf(1.0, visual_rect.size.y - QUANTITY_INSET_TOP - QUANTITY_INSET_BOTTOM)
		)
		_quantity_label.clip_text = true
		_quantity_label.move_to_front()
	else:
		_quantity_label.text = ""


func _get_visual_rect(slot_size: Vector2) -> Rect2:
	return Rect2(
		Vector2(SLOT_VISUAL_INSET_LEFT, SLOT_VISUAL_INSET_TOP),
		Vector2(
			maxf(1.0, slot_size.x - SLOT_VISUAL_INSET_LEFT - SLOT_VISUAL_INSET_RIGHT),
			maxf(1.0, slot_size.y - SLOT_VISUAL_INSET_TOP - SLOT_VISUAL_INSET_BOTTOM)
		)
	)


func _set_item_texture(texture: Texture2D) -> void:
	if _item_icon == null:
		return
	_item_icon.texture = texture
	_item_icon.visible = texture != null


func _set_quantity_label(value: int) -> void:
	if _quantity_label == null:
		return
	amount = value
	_quantity_label.text = str(value) if value > 1 else ""
	_quantity_label.visible = value > 1
	_layout_overlay_controls()


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

	OathwakeUISkin.apply_slot_button(self, "empty")
