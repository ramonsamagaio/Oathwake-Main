extends Control

const SpriteResolver = preload("res://scripts/systems/SpriteResolver.gd")
const UILayoutConfig = preload("res://scripts/ui/UILayoutConfig.gd")
const UILayoutApplier = preload("res://scripts/ui/UILayoutApplier.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const HotbarSlotScript := preload("res://scripts/ui/HotbarSlot.gd")

@export var slot_count: int = 10

const HOTBAR_TEXTURE_PATH := "res://assets/ui/HUDUI/HOTBAR.png"
var inventory
var player
var selected_slot := 0
var slots := []
var sprite_resolver := SpriteResolver.new()
var _layout: Dictionary = {}
var _hotbar_panel: Control
var _selected_overlay: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process_unhandled_input(true)
	add_to_group("hotbar_ui")
	_build_ui()


func _input(event: InputEvent) -> void:
	_handle_hotbar_key_event(event)


func _unhandled_input(event: InputEvent) -> void:
	_handle_hotbar_key_event(event)


func _handle_hotbar_key_event(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if _is_build_mode_enabled() or _is_crafting_open():
		return

	var key_event := event as InputEventKey
	var slot_index := _get_slot_index_for_key(key_event.keycode)
	if slot_index == -1 and key_event.physical_keycode != key_event.keycode:
		slot_index = _get_slot_index_for_key(key_event.physical_keycode)
	if slot_index == -1:
		return

	select_slot(slot_index)
	get_viewport().set_input_as_handled()


func setup(new_inventory, new_player) -> void:
	inventory = new_inventory
	player = new_player
	if inventory != null and inventory.has_signal("changed") and not inventory.changed.is_connected(refresh):
		inventory.changed.connect(refresh)
	if player != null and player.has_signal("tool_changed") and not player.tool_changed.is_connected(_on_player_tool_changed):
		player.tool_changed.connect(_on_player_tool_changed)
	refresh()


func select_slot(slot_index: int) -> void:
	selected_slot = clampi(slot_index, 0, slot_count - 1)
	_apply_selected_hotbar_item_to_player()
	_update_selection()


func refresh() -> void:
	if slots.is_empty():
		return

	var entries := _get_hotbar_entries()
	for index in range(slots.size()):
		var slot: Button = slots[index]
		if index >= entries.size():
			_setup_empty_slot(slot)
			continue

		_setup_slot(slot, entries[index])

	_update_selection()
	_apply_selected_hotbar_item_to_player()


func _build_ui() -> void:
	_layout = UILayoutConfig.load_layout()
	var panel_rect := _get_layout_rect("hotbar.panel", Rect2(386, 820, 824, 78))

	_hotbar_panel = Control.new()
	_hotbar_panel.name = "HotbarPanel"
	_hotbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_rect(_hotbar_panel, panel_rect)
	add_child(_hotbar_panel)

	var background := TextureRect.new()
	background.name = "HotbarBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = _load_texture(HOTBAR_TEXTURE_PATH)
	_hotbar_panel.add_child(background)
	UILayoutApplier.apply_texture_rect_from_layout(background, _layout, "hotbar.panel", panel_rect)

	for index in range(slot_count):
		var button = HotbarSlotScript.new()
		button.name = "Slot%02d" % (index + 1)
		button.focus_mode = Control.FOCUS_NONE
		button.clip_contents = true
		button.text = ""
		button.icon = null
		button.expand_icon = false
		button.setup(self, index)
		button.pressed.connect(select_slot.bind(index))
		var fallback_rect := Rect2(13 + index * 82, 9, 66, 60)
		var slot_rect := _get_layout_rect("hotbar.slot_%02d" % (index + 1), fallback_rect)
		if slot_rect == fallback_rect:
			slot_rect = _get_layout_rect("hotbar.slot_%d" % (index + 1), fallback_rect)
		button.position = slot_rect.position - panel_rect.position
		button.size = slot_rect.size
		_hotbar_panel.add_child(button)
		_add_slot_overlay_children(button)
		slots.append(button)
		_apply_transparent_button_style(button)

	_selected_overlay = ColorRect.new()
	_selected_overlay.name = "SelectedSlotOverlay"
	_selected_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_overlay.color = Color(1.0, 0.92, 0.45, 0.11)
	_selected_overlay.z_index = 10
	_hotbar_panel.add_child(_selected_overlay)


func _setup_empty_slot(slot: Button) -> void:
	slot.text = ""
	slot.tooltip_text = "Empty"
	_set_slot_icon(slot, null)
	_set_slot_quantity_text(slot, "")


func _setup_slot(slot: Button, entry: Dictionary) -> void:
	var entry_id := str(entry.get("id", ""))
	var label := str(entry.get("label", entry_id.capitalize()))
	var amount := int(entry.get("amount", 0))
	slot.text = ""
	slot.tooltip_text = label
	_set_slot_icon(slot, sprite_resolver.get_texture_for_item(entry_id))
	_set_slot_quantity_text(slot, str(amount) if amount > 1 else "")


func _update_selection() -> void:
	if _selected_overlay != null:
		_selected_overlay.visible = false
	for index in range(slots.size()):
		var slot: Button = slots[index]
		if index == selected_slot:
			if _selected_overlay != null:
				_selected_overlay.position = slot.position
				_selected_overlay.size = slot.size
				_selected_overlay.visible = true


func _get_hotbar_entries() -> Array:
	var entries := []
	if inventory == null:
		return entries

	var inventory_slots: Array = inventory.get_hotbar_slots(slot_count)
	for slot in inventory_slots:
		if not slot is Dictionary:
			entries.append({})
			continue
		var item_id := str(slot.get("item_id", ""))
		var amount := int(slot.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			entries.append({})
			continue
		entries.append({
			"type": "item",
			"id": item_id,
			"amount": amount,
			"label": _get_item_display_name(item_id),
		})

	while entries.size() < slot_count:
		entries.append({})
	return entries.slice(0, slot_count)


func _apply_selected_hotbar_item_to_player() -> void:
	if player == null:
		return
	var entry := _get_hotbar_entry(selected_slot)
	var item_id := str(entry.get("id", "")).to_lower()
	if not player.has_method("set_current_hotbar_item"):
		if player.has_method("set_current_tool"):
			player.set_current_tool("Hands")
		return
	if item_id.is_empty():
		player.set_current_hotbar_item("", selected_slot)
		return
	var item_data := _get_item_data(item_id)
	if not _is_tool_or_weapon(item_data):
		player.set_current_hotbar_item("", selected_slot)
		return
	player.set_current_hotbar_item(item_id, selected_slot)


func _get_item_display_name(item_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return item_id.capitalize()

	var item_data: Dictionary = content_db.get_item(item_id)
	return str(item_data.get("display_name", item_id.capitalize()))


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}
	return content_db.get_item(item_id)


func _is_tool_or_weapon(item_data: Dictionary) -> bool:
	var item_type := str(item_data.get("item_type", "")).to_lower()
	return item_type == "tool" or item_type == "weapon"


func _get_hotbar_entry(slot_index: int) -> Dictionary:
	if inventory == null or slot_index < 0 or slot_index >= slot_count:
		return {}
	var slot_data: Dictionary = inventory.get_slot(slot_index)
	if not slot_data is Dictionary:
		return {}

	var item_id := str(slot_data.get("item_id", ""))
	var amount := int(slot_data.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return {}

	return {
		"type": "item",
		"id": item_id,
		"amount": amount,
		"label": _get_item_display_name(item_id),
	}


func _get_hotbar_drag_data(slot_index: int) -> Variant:
	var entry := _get_hotbar_entry(slot_index)
	if entry.is_empty():
		return null
	return {
		"type": "inventory_slot",
		"slot_index": slot_index,
		"inventory_id": "player",
	}


func _make_hotbar_drag_preview(slot_index: int) -> TextureRect:
	var entry := _get_hotbar_entry(slot_index)
	var item_id := str(entry.get("id", ""))
	if item_id.is_empty():
		return null

	var preview := TextureRect.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = sprite_resolver.get_texture_for_item(item_id)
	preview.custom_minimum_size = Vector2(48, 48)
	preview.size = Vector2(48, 48)
	return preview


func _can_drop_on_hotbar_slot(slot_index: int, data: Variant) -> bool:
	if inventory == null or slot_index < 0 or slot_index >= slot_count:
		return false
	if not data is Dictionary:
		return false
	if str(data.get("type", "")) != "inventory_slot":
		return false

	var from_inventory_id := str(data.get("inventory_id", ""))
	if from_inventory_id != "player":
		return false

	var from_index := int(data.get("slot_index", -1))
	return inventory.has_method("get_slot") and from_index >= 0 and from_index < inventory.get_slot_count()


func _drop_on_hotbar_slot(slot_index: int, data: Variant) -> void:
	if not _can_drop_on_hotbar_slot(slot_index, data):
		return

	var from_index := int((data as Dictionary).get("slot_index", -1))
	if from_index == slot_index:
		return

	inventory.move_slot(from_index, slot_index)


func _get_slot_index_for_key(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return int(keycode - KEY_1)
	if keycode == KEY_0:
		return 9
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_9:
		return int(keycode - KEY_KP_1)
	if keycode == KEY_KP_0:
		return 9
	return -1


func _on_player_tool_changed(_tool_name: String) -> void:
	refresh()


func _is_build_mode_enabled() -> bool:
	var build_system = get_tree().get_first_node_in_group("build_system")
	return build_system != null and build_system.has_method("is_build_mode_enabled") and build_system.is_build_mode_enabled()


func _is_crafting_open() -> bool:
	var crafting_system = get_tree().get_first_node_in_group("crafting_system")
	return crafting_system != null and crafting_system.has_method("is_crafting_open") and crafting_system.is_crafting_open()


func _get_layout_rect(element_id: String, fallback: Rect2) -> Rect2:
	var rect := UILayoutApplier.get_element_rect(_layout, element_id)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return fallback
	return rect


func _apply_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


func _apply_transparent_button_style(button: Button) -> void:
	var empty_style := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty_style)
	button.add_theme_stylebox_override("hover", empty_style)
	button.add_theme_stylebox_override("pressed", empty_style)
	button.add_theme_stylebox_override("focus", empty_style)
	button.add_theme_stylebox_override("disabled", empty_style)
	button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.82, 1.0))


func _add_slot_overlay_children(slot: Button) -> void:
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.z_index = 5
	slot.add_child(icon)

	var quantity_label := Label.new()
	quantity_label.name = "QuantityLabel"
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.clip_text = true
	quantity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	quantity_label.z_index = 6
	slot.add_child(quantity_label)
	OathwakeTextStyle.apply_profile_to_label(quantity_label, "inventory_quantity_text", null, 11, 1)
	_layout_slot_overlay(slot)


func _layout_slot_overlay(slot: Button) -> void:
	var icon := slot.get_node_or_null("ItemIcon") as TextureRect
	if icon != null:
		var icon_edge := minf(slot.size.x, slot.size.y) * 0.55
		var icon_size := Vector2(icon_edge, icon_edge)
		icon.size = icon_size
		icon.position = (slot.size - icon_size) * 0.5

	var quantity_label := slot.get_node_or_null("QuantityLabel") as Label
	if quantity_label != null:
		quantity_label.position = Vector2(2.0, 1.0)
		quantity_label.size = Vector2(maxf(1.0, slot.size.x - 5.0), maxf(1.0, slot.size.y - 9.0))


func _set_slot_icon(slot: Button, texture: Texture2D) -> void:
	var icon := slot.get_node_or_null("ItemIcon") as TextureRect
	if icon == null:
		return
	icon.texture = texture
	icon.visible = texture != null


func _set_slot_quantity_text(slot: Button, value: String) -> void:
	var quantity_label := slot.get_node_or_null("QuantityLabel") as Label
	if quantity_label == null:
		return
	quantity_label.text = value
	quantity_label.visible = not value.is_empty()
	_layout_slot_overlay(slot)
