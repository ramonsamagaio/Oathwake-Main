extends Control

const SpriteResolver = preload("res://scripts/systems/SpriteResolver.gd")
const UILayoutConfig = preload("res://scripts/ui/UILayoutConfig.gd")
const UILayoutApplier = preload("res://scripts/ui/UILayoutApplier.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")

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
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if _is_build_mode_enabled() or _is_crafting_open():
		return

	var slot_index := _get_slot_index_for_key(event.keycode)
	if slot_index == -1:
		return

	select_slot(slot_index)
	get_viewport().set_input_as_handled()


func setup(new_inventory, new_player) -> void:
	inventory = new_inventory
	player = new_player
	if inventory != null and inventory.has_signal("changed"):
		inventory.changed.connect(refresh)
	if player != null and player.has_signal("tool_changed"):
		player.tool_changed.connect(_on_player_tool_changed)
	refresh()


func select_slot(slot_index: int) -> void:
	selected_slot = clampi(slot_index, 0, slot_count - 1)
	var entries := _get_hotbar_entries()
	if selected_slot < entries.size():
		var entry: Dictionary = entries[selected_slot]
		if str(entry.get("type", "")) == "tool" and player != null and player.has_method("set_current_tool"):
			player.set_current_tool(str(entry.get("id", "")))
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
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture = _load_texture(HOTBAR_TEXTURE_PATH)
	background.position = Vector2.ZERO
	background.size = panel_rect.size
	_hotbar_panel.add_child(background)

	for index in range(slot_count):
		var button := Button.new()
		button.name = "Slot%02d" % (index + 1)
		button.focus_mode = Control.FOCUS_NONE
		button.clip_contents = true
		button.text = ""
		button.icon = null
		button.expand_icon = false
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
	_hotbar_panel.add_child(_selected_overlay)


func _setup_empty_slot(slot: Button) -> void:
	slot.text = ""
	slot.tooltip_text = "Empty"
	_set_slot_icon(slot, null)
	_set_slot_quantity_text(slot, "")


func _setup_slot(slot: Button, entry: Dictionary) -> void:
	var entry_type := str(entry.get("type", "item"))
	var entry_id := str(entry.get("id", ""))
	var label := str(entry.get("label", entry_id.capitalize()))
	var amount := int(entry.get("amount", 0))
	slot.text = ""
	slot.tooltip_text = label

	if entry_type == "item":
		_set_slot_icon(slot, sprite_resolver.get_texture_for_item(entry_id))
		_set_slot_quantity_text(slot, str(amount) if amount > 1 else "")
	else:
		_set_slot_icon(slot, sprite_resolver.get_placeholder_texture())
		_set_slot_quantity_text(slot, "")


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

	if player != null and player.has_method("get_unlocked_tools"):
		for tool_name in player.get_unlocked_tools():
			entries.append({
				"type": "tool",
				"id": str(tool_name),
				"label": str(tool_name),
			})

	if inventory != null:
		var inventory_slots: Array = inventory.get_hotbar_slots(slot_count)
		for slot in inventory_slots:
			if not slot is Dictionary:
				continue
			var item_id := str(slot.get("item_id", ""))
			var amount := int(slot.get("amount", 0))
			if amount <= 0:
				continue
			entries.append({
				"type": "item",
				"id": item_id,
				"amount": amount,
				"label": _get_item_display_name(item_id),
			})

	return entries.slice(0, slot_count)


func _get_item_display_name(item_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return item_id.capitalize()

	var item_data: Dictionary = content_db.get_item(item_id)
	return str(item_data.get("display_name", item_id.capitalize()))


func _get_slot_index_for_key(keycode: Key) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return int(keycode - KEY_1)
	if keycode == KEY_0:
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
	quantity_label.clip_text = false
	quantity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	quantity_label.z_index = 6
	slot.add_child(quantity_label)
	OathwakeTextStyle.apply_profile_to_label(quantity_label, "item_quantity", null, 14, 1)
	quantity_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
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
		var label_width := minf(maxf(28.0, slot.size.x * 0.52), maxf(28.0, slot.size.x - 6.0))
		quantity_label.size = Vector2(label_width, 16.0)
		quantity_label.position = Vector2(maxf(3.0, slot.size.x - label_width - 3.0), maxf(2.0, slot.size.y - 18.0))


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
