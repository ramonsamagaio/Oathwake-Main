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
var hotbar_shortcuts := []
var sprite_resolver := SpriteResolver.new()
var _layout: Dictionary = {}
var _hotbar_panel: Control
var _selected_overlay: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process_unhandled_input(true)
	add_to_group("hotbar_ui")
	_ensure_shortcut_count()
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
	_ensure_shortcut_count()
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
	_ensure_shortcut_count()
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


func get_hotbar_shortcuts() -> Array:
	_ensure_shortcut_count()
	return hotbar_shortcuts.duplicate(true)


func set_hotbar_shortcuts(shortcuts: Variant) -> void:
	_ensure_shortcut_count()
	for index in range(slot_count):
		hotbar_shortcuts[index] = {}

	if shortcuts is Array:
		for index in range(min(shortcuts.size(), slot_count)):
			var raw_entry: Variant = shortcuts[index]
			if raw_entry is Dictionary:
				var item_id := str(raw_entry.get("item_id", ""))
				var source_slot := int(raw_entry.get("source_slot_index", -1))
				if not item_id.is_empty():
					hotbar_shortcuts[index] = {
						"item_id": item_id,
						"source_slot_index": source_slot,
					}
			elif raw_entry is String and not str(raw_entry).is_empty():
				hotbar_shortcuts[index] = {
					"item_id": str(raw_entry),
					"source_slot_index": -1,
				}
	refresh()


func assign_shortcut_from_inventory_slot(source_slot_index: int, target_hotbar_index: int, select_after_assign := true) -> bool:
	_ensure_shortcut_count()
	if inventory == null:
		return false
	if target_hotbar_index < 0 or target_hotbar_index >= slot_count:
		return false
	if source_slot_index < 0 or source_slot_index >= int(inventory.get_slot_count()):
		return false

	var source_slot: Dictionary = inventory.get_slot(source_slot_index)
	var item_id := str(source_slot.get("item_id", ""))
	var amount := int(source_slot.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return false

	hotbar_shortcuts[target_hotbar_index] = {
		"item_id": item_id,
		"source_slot_index": source_slot_index,
	}
	if select_after_assign:
		select_slot(target_hotbar_index)
	else:
		refresh()
	return true


func assign_shortcut_to_first_available(source_slot_index: int, select_after_assign := true) -> int:
	_ensure_shortcut_count()
	if inventory == null:
		return -1
	var source_slot: Dictionary = inventory.get_slot(source_slot_index)
	var item_id := str(source_slot.get("item_id", ""))
	if item_id.is_empty() or int(source_slot.get("amount", 0)) <= 0:
		return -1

	var existing_index := find_shortcut_for_item(item_id)
	if existing_index >= 0:
		if select_after_assign:
			select_slot(existing_index)
		return existing_index

	for index in range(slot_count):
		if _get_shortcut_item_id(index).is_empty():
			if assign_shortcut_from_inventory_slot(source_slot_index, index, select_after_assign):
				return index
	return -1


func find_shortcut_for_item(item_id: String) -> int:
	_ensure_shortcut_count()
	var normalized_item_id := str(item_id)
	if normalized_item_id.is_empty():
		return -1
	for index in range(slot_count):
		if _get_shortcut_item_id(index) == normalized_item_id:
			return index
	return -1


func clear_hotbar_slot(slot_index: int) -> void:
	_ensure_shortcut_count()
	if slot_index < 0 or slot_index >= slot_count:
		return
	hotbar_shortcuts[slot_index] = {}
	refresh()


func _build_ui() -> void:
	_layout = UILayoutConfig.load_layout()
	var panel_rect := _get_layout_rect("hotbar.panel", Rect2(386, 820, 824, 78))

	_hotbar_panel = Control.new()
	_hotbar_panel.name = "HotbarPanel"
	_hotbar_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_rect(_hotbar_panel, panel_rect)
	add_child(_hotbar_panel)

	var background := TextureRect.new()
	background.name = "HotbarBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = 0
	background.texture = _load_texture(HOTBAR_TEXTURE_PATH)
	_hotbar_panel.add_child(background)
	UILayoutApplier.apply_texture_rect_from_layout(background, _layout, "hotbar.panel", panel_rect)

	for index in range(slot_count):
		var button: Button = HotbarSlotScript.new() as Button
		button.name = "Slot%02d" % (index + 1)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_NONE
		button.z_index = 20
		button.clip_contents = true
		button.text = ""
		button.icon = null
		button.expand_icon = false
		button.call("setup", self, index)
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
	_selected_overlay.z_index = 30
	_hotbar_panel.add_child(_selected_overlay)


func _setup_empty_slot(slot: Button) -> void:
	slot.text = ""
	slot.tooltip_text = "Empty"
	_set_slot_icon(slot, null)
	_set_slot_quantity_text(slot, "")


func _setup_slot(slot: Button, entry: Dictionary) -> void:
	if entry.is_empty():
		_setup_empty_slot(slot)
		return
	var entry_id := str(entry.get("id", ""))
	var label := str(entry.get("label", entry_id.capitalize()))
	var amount := int(entry.get("amount", 0))
	slot.text = ""
	slot.tooltip_text = "%s Shortcut" % label
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
	_ensure_shortcut_count()
	for index in range(slot_count):
		var shortcut_data := _get_shortcut_resolved_data(index)
		var item_id := str(shortcut_data.get("item_id", ""))
		if item_id.is_empty():
			entries.append({})
			continue
		entries.append({
			"type": "shortcut",
			"id": item_id,
			"amount": _get_inventory_item_count(item_id),
			"label": _get_item_display_name(item_id),
			"source_slot_index": int(shortcut_data.get("source_slot_index", -1)),
		})
	return entries


func _apply_selected_hotbar_item_to_player() -> void:
	if player == null:
		return
	if not player.has_method("set_current_hotbar_item"):
		if player.has_method("set_current_tool"):
			player.set_current_tool("Hands")
		return

	var shortcut_data := _get_shortcut_resolved_data(selected_slot)
	var item_id := str(shortcut_data.get("item_id", ""))
	var source_slot_index := int(shortcut_data.get("source_slot_index", -1))
	if item_id.is_empty():
		player.set_current_hotbar_item("", -1)
		return

	var item_data := _get_item_data(item_id)
	if not _is_tool_or_weapon(item_data):
		player.set_current_hotbar_item("", -1)
		return
	player.set_current_hotbar_item(item_id, source_slot_index)


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
	if slot_index < 0 or slot_index >= slot_count:
		return {}
	var shortcut_data := _get_shortcut_resolved_data(slot_index)
	var item_id := str(shortcut_data.get("item_id", ""))
	if item_id.is_empty():
		return {}
	return {
		"type": "shortcut",
		"id": item_id,
		"amount": _get_inventory_item_count(item_id),
		"label": _get_item_display_name(item_id),
		"source_slot_index": int(shortcut_data.get("source_slot_index", -1)),
	}


func _get_hotbar_drag_data(slot_index: int) -> Variant:
	var entry := _get_hotbar_entry(slot_index)
	if entry.is_empty():
		return null
	return {
		"type": "hotbar_shortcut",
		"hotbar_slot_index": slot_index,
		"item_id": str(entry.get("id", "")),
		"source_slot_index": int(entry.get("source_slot_index", -1)),
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
	return _get_hotbar_drop_reject_reason(slot_index, data).is_empty()


func _get_hotbar_drop_reject_reason(slot_index: int, data: Variant) -> String:
	if slot_index < 0 or slot_index >= slot_count:
		return "target slot out of range"
	if not data is Dictionary:
		return "drag data is not Dictionary"
	var drop_data: Dictionary = data as Dictionary
	var drop_type := str(drop_data.get("type", ""))
	if drop_type == "hotbar_shortcut":
		return ""
	if drop_type != "inventory_slot":
		return "type is not inventory_slot"
	if inventory == null:
		return "inventory is null"
	if str(drop_data.get("inventory_id", "")) != "player":
		return "inventory_id is not player"
	if not inventory.has_method("get_slot") or not inventory.has_method("get_slot_count"):
		return "inventory API missing"
	var from_index := int(drop_data.get("slot_index", -1))
	if from_index < 0 or from_index >= int(inventory.get_slot_count()):
		return "source slot out of range"
	var source_slot: Dictionary = inventory.get_slot(from_index)
	if str(source_slot.get("item_id", "")).is_empty() or int(source_slot.get("amount", 0)) <= 0:
		return "source slot empty"
	return ""


func _drop_on_hotbar_slot(slot_index: int, data: Variant) -> void:
	if not _can_drop_on_hotbar_slot(slot_index, data):
		return

	var drop_data: Dictionary = data as Dictionary
	var drop_type := str(drop_data.get("type", ""))
	if drop_type == "hotbar_shortcut":
		var from_hotbar_index := int(drop_data.get("hotbar_slot_index", -1))
		if from_hotbar_index < 0 or from_hotbar_index >= slot_count:
			return
		if from_hotbar_index == slot_index:
			select_slot(slot_index)
			return
		var temp = hotbar_shortcuts[slot_index]
		hotbar_shortcuts[slot_index] = hotbar_shortcuts[from_hotbar_index]
		hotbar_shortcuts[from_hotbar_index] = temp
		select_slot(slot_index)
		refresh()
		return

	var from_index := int(drop_data.get("slot_index", -1))
	if assign_shortcut_from_inventory_slot(from_index, slot_index, true):
		refresh()


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
	# Tool label changes should not mutate hotbar shortcuts.
	pass


func _is_build_mode_enabled() -> bool:
	var build_system = get_tree().get_first_node_in_group("build_system")
	return build_system != null and build_system.has_method("is_build_mode_enabled") and build_system.is_build_mode_enabled()


func _is_crafting_open() -> bool:
	var crafting_system = get_tree().get_first_node_in_group("crafting_system")
	return crafting_system != null and crafting_system.has_method("is_crafting_open") and crafting_system.is_crafting_open()


func _ensure_shortcut_count() -> void:
	while hotbar_shortcuts.size() < slot_count:
		hotbar_shortcuts.append({})
	while hotbar_shortcuts.size() > slot_count:
		hotbar_shortcuts.pop_back()


func _get_shortcut_item_id(slot_index: int) -> String:
	var data := _get_shortcut_resolved_data(slot_index)
	return str(data.get("item_id", ""))


func _get_shortcut_resolved_data(slot_index: int) -> Dictionary:
	_ensure_shortcut_count()
	if inventory == null or slot_index < 0 or slot_index >= slot_count:
		return {}
	var shortcut = hotbar_shortcuts[slot_index]
	if not shortcut is Dictionary:
		return {}
	var item_id := str(shortcut.get("item_id", ""))
	if item_id.is_empty():
		return {}

	var source_slot_index := int(shortcut.get("source_slot_index", -1))
	if _inventory_slot_contains_item(source_slot_index, item_id):
		return {
			"item_id": item_id,
			"source_slot_index": source_slot_index,
		}

	var found_index := _find_inventory_slot_with_item(item_id)
	if found_index >= 0:
		hotbar_shortcuts[slot_index] = {
			"item_id": item_id,
			"source_slot_index": found_index,
		}
		return {
			"item_id": item_id,
			"source_slot_index": found_index,
		}

	return {}


func _inventory_slot_contains_item(slot_index: int, item_id: String) -> bool:
	if inventory == null or slot_index < 0 or slot_index >= int(inventory.get_slot_count()):
		return false
	var slot_data: Dictionary = inventory.get_slot(slot_index)
	return str(slot_data.get("item_id", "")) == item_id and int(slot_data.get("amount", 0)) > 0


func _find_inventory_slot_with_item(item_id: String) -> int:
	if inventory == null or item_id.is_empty():
		return -1
	for index in range(int(inventory.get_slot_count())):
		if _inventory_slot_contains_item(index, item_id):
			return index
	return -1


func _get_inventory_item_count(item_id: String) -> int:
	if inventory == null or item_id.is_empty():
		return 0
	if inventory.has_method("get_count"):
		return int(inventory.get_count(item_id))
	return 1 if _find_inventory_slot_with_item(item_id) >= 0 else 0


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
