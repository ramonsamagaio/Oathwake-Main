extends Control

const InventorySlotScene = preload("res://scenes/ui/InventorySlot.tscn")
const EquipmentSlotScene = preload("res://scenes/ui/EquipmentSlot.tscn")
const SpriteResolver = preload("res://scripts/systems/SpriteResolver.gd")
const TrashSlotScript = preload("res://scripts/ui/TrashSlot.gd")
const UILayoutConfig = preload("res://scripts/ui/UILayoutConfig.gd")
const UILayoutApplier = preload("res://scripts/ui/UILayoutApplier.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const OathwakeUISkin := preload("res://scripts/ui/OathwakeUISkin.gd")

const INVENTORY_TEXTURE_PATH := "res://assets/ui/HUDUI/INVENTORY.png"
const INVENTORY_HOVER_TEXTURE_PATH := "res://assets/ui/HUDUI/INVENTORY_HOVER.png"
const INVENTORY_SELECT_TEXTURE_PATH := "res://assets/ui/HUDUI/INVENTORY_SELECT.png"
const USE_BUTTON_TEXTURE_PATH := "res://assets/ui/HUDUI/USE_ON.png"
const SPLIT_BUTTON_TEXTURE_PATH := "res://assets/ui/HUDUI/SPLIT_ON.png"
const DROP_BUTTON_TEXTURE_PATH := "res://assets/ui/HUDUI/DROP_ON.png"
const CLOSE_BUTTON_TEXTURE_PATH := "res://assets/ui/HUDUI/Xzinho ON.png"
const EQUIPMENT_SLOT_IDS := [
	"helm",
	"armor",
	"legs",
	"boots",
	"neck",
	"hand_left",
	"hand_right",
	"ring_left",
	"ring_right",
	"back",
]

@export var slot_count: int = 20
@export var columns: int = 5

var inventory
var equipment_system
var slots := []
var equipment_slot_nodes := []
var grid: GridContainer
var details_label: Label
var selected_slot_index := -1
var selected_equip_slot_id := ""
var sprite_resolver := SpriteResolver.new()
var _drag_source_slot := -1
var _window_panel: Control
var _dragging_window := false
var _drag_last_mouse_position := Vector2.ZERO
var _layout: Dictionary = {}
var _hover_frame: TextureRect
var _select_frame: TextureRect
var _drag_handle: Control
var _hover_offset := Vector2.ZERO
var _select_offset := Vector2.ZERO


func set_equipment_system(new_equipment_system) -> void:
	equipment_system = new_equipment_system
	refresh()


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		visible = not visible
		if visible:
			refresh()
		elif _hover_frame != null:
			_hover_frame.visible = false
		get_viewport().set_input_as_handled()


func set_inventory(new_inventory) -> void:
	inventory = new_inventory
	if inventory != null and inventory.has_signal("changed"):
		inventory.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if slots.is_empty() or inventory == null:
		return

	for index in range(slots.size()):
		var slot = slots[index]
		var item_entry: Dictionary = inventory.get_slot(index)
		var item_id := str(item_entry.get("item_id", ""))
		var amount := int(item_entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			slot.clear_slot(index)
			_apply_transparent_button_style(slot)
			continue

		var item_data: Dictionary = _get_item_data(item_id)
		var metadata = item_entry.get("metadata", {})
		slot.setup(index, item_id, amount, item_data, sprite_resolver.get_texture_for_item(item_id), "player", metadata)
		_apply_transparent_button_style(slot)

	_refresh_equipment_slots()


func _build_ui() -> void:
	_layout = UILayoutConfig.load_layout()
	var window_rect := _get_layout_rect("inventory.window", Rect2(315, 196, 947, 560))

	_window_panel = Control.new()
	_window_panel.name = "InventoryWindow"
	_window_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_rect(_window_panel, window_rect)
	add_child(_window_panel)

	var background := TextureRect.new()
	background.name = "InventoryBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.texture = _load_texture(INVENTORY_TEXTURE_PATH)
	background.position = Vector2.ZERO
	background.size = window_rect.size
	_window_panel.add_child(background)

	_drag_handle = Control.new()
	_drag_handle.name = "WindowDragHandle"
	_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_drag_handle.gui_input.connect(_on_window_drag_handle_gui_input)
	_window_panel.add_child(_drag_handle)
	var drag_fallback_rect := Rect2(window_rect.position + Vector2(11, 10), Vector2(window_rect.size.x - 32, 42))
	var drag_rect := _get_layout_rect("inventory.drag_handle", drag_fallback_rect)
	_drag_handle.position = drag_rect.position - window_rect.position
	_drag_handle.size = drag_rect.size

	for _index in range(slot_count):
		var slot = InventorySlotScene.instantiate()
		var slot_rect := _get_inventory_slot_rect(_index, window_rect)
		slot.position = slot_rect.position - window_rect.position
		slot.size = slot_rect.size
		slot.slot_selected.connect(_on_slot_selected)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slot.slot_drag_dropped.connect(_on_slot_drag_dropped)
		slot.equipment_drag_dropped.connect(_on_equipment_drag_dropped_to_inventory)
		slot.drag_started.connect(_on_slot_drag_started)
		slot.mouse_entered.connect(_on_inventory_slot_hovered.bind(_index))
		slot.mouse_exited.connect(_on_inventory_slot_unhovered.bind(_index))
		_window_panel.add_child(slot)
		slots.append(slot)
		_apply_transparent_button_style(slot)

	var trash := _make_trash_slot()
	trash.trash_dropped.connect(_on_trash_dropped)
	var trash_rect := _get_layout_rect("inventory.trash_area", Rect2(window_rect.position + Vector2(32, 452), Vector2(58, 61)))
	trash.position = trash_rect.position - window_rect.position
	trash.size = trash_rect.size
	_window_panel.add_child(trash)

	details_label = Label.new()
	details_label.name = "TooltipText"
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.clip_text = true
	details_label.text = "Select an item."
	var tooltip_rect := _get_layout_rect("inventory.tooltip_area", Rect2(window_rect.position + Vector2(751, 62), Vector2(163, 269)))
	details_label.position = tooltip_rect.position - window_rect.position
	details_label.size = tooltip_rect.size
	_window_panel.add_child(details_label)

	for slot_id in EQUIPMENT_SLOT_IDS:
		var eq_slot = EquipmentSlotScene.instantiate()
		eq_slot.slot_id = slot_id
		var eq_rect := _get_layout_rect("equipment.%s" % slot_id, Rect2(window_rect.position + Vector2(40, 80 + equipment_slot_nodes.size() * 46), Vector2(42, 42)))
		eq_slot.position = eq_rect.position - window_rect.position
		eq_slot.size = eq_rect.size
		eq_slot.equip_selected.connect(_on_equip_slot_selected)
		eq_slot.equip_right_clicked.connect(_on_equip_right_clicked)
		eq_slot.equip_drag_dropped.connect(_on_equip_drag_dropped)
		_window_panel.add_child(eq_slot)
		equipment_slot_nodes.append(eq_slot)
		_apply_transparent_button_style(eq_slot)

	_add_texture_action_button("inventory.use_button_clickbox", USE_BUTTON_TEXTURE_PATH, _on_use_selected_pressed, Rect2(window_rect.position + Vector2(783, 347), Vector2(104, 42)), window_rect)
	_add_texture_action_button("inventory.split_button_clickbox", SPLIT_BUTTON_TEXTURE_PATH, _on_split_half_pressed, Rect2(window_rect.position + Vector2(783, 409), Vector2(104, 42)), window_rect)
	_add_texture_action_button("inventory.drop_button_clickbox", DROP_BUTTON_TEXTURE_PATH, _on_drop_stack_pressed, Rect2(window_rect.position + Vector2(783, 472), Vector2(104, 42)), window_rect)
	_add_texture_action_button("inventory.close_hitbox", CLOSE_BUTTON_TEXTURE_PATH, _on_close_inventory_pressed, Rect2(window_rect.position + Vector2(1202, 216), Vector2(26, 27)), window_rect)

	_hover_frame = _make_frame_texture(INVENTORY_HOVER_TEXTURE_PATH, "inventory.hover_frame")
	_hover_frame.visible = false
	var hover_rect := _get_layout_rect("inventory.hover_frame", Rect2(window_rect.position + Vector2(245, 374), Vector2(53, 51)))
	var reference_slot_rect := _get_layout_rect("inventory.slot_01_clickbox", _get_inventory_slot_rect(0, window_rect))
	_hover_offset = hover_rect.position - reference_slot_rect.position
	_hover_frame.size = hover_rect.size
	_window_panel.add_child(_hover_frame)

	_select_frame = _make_frame_texture(INVENTORY_SELECT_TEXTURE_PATH, "inventory.select_frame")
	_select_frame.visible = false
	var select_rect := _get_layout_rect("inventory.select_frame", Rect2(window_rect.position + Vector2(236, 57), Vector2(71, 71)))
	_select_offset = select_rect.position - reference_slot_rect.position
	_select_frame.size = select_rect.size
	_window_panel.add_child(_select_frame)

	_apply_inventory_ui_fonts()


func _make_inventory_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(74, 38)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	OathwakeUISkin.apply_button(button, "medium")
	OathwakeTextStyle.apply_profile_to_control(button, "ui_button")
	return button


func _add_texture_action_button(element_id: String, texture_path: String, callback: Callable, fallback_rect: Rect2, window_rect: Rect2) -> TextureButton:
	var button := TextureButton.new()
	button.name = element_id
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.texture_normal = null
	button.texture_hover = _load_texture(texture_path)
	button.texture_pressed = _load_texture(texture_path)
	button.texture_focused = _load_texture(texture_path)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.pressed.connect(callback)
	var rect := _get_layout_rect(element_id, fallback_rect)
	button.position = rect.position - window_rect.position
	button.size = rect.size
	_window_panel.add_child(button)
	return button


func _make_frame_texture(texture_path: String, name_value: String) -> TextureRect:
	var frame := TextureRect.new()
	frame.name = name_value
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture = _load_texture(texture_path)
	return frame


func _get_inventory_slot_rect(index: int, window_rect: Rect2) -> Rect2:
	var slot_id := "inventory.slot_%02d_clickbox" % (index + 1)
	var fallback_col := index % 10
	var fallback_row := int(index / 10)
	var fallback_position := window_rect.position + Vector2(248 + fallback_col * 49, 66 + fallback_row * 52)
	var fallback_rect := Rect2(fallback_position, Vector2(46, 49))
	return _get_layout_rect(slot_id, fallback_rect)


func _on_inventory_slot_hovered(slot_index: int) -> void:
	if _hover_frame == null or slot_index < 0 or slot_index >= slots.size():
		return
	if slot_index == selected_slot_index:
		_hover_frame.visible = false
		return
	var slot: Control = slots[slot_index]
	_place_frame_on_slot(_hover_frame, slot)
	_hover_frame.visible = true


func _on_inventory_slot_unhovered(_slot_index: int) -> void:
	if _hover_frame != null:
		_hover_frame.visible = false


func _update_selected_slot_frame() -> void:
	if _select_frame == null:
		return
	if selected_slot_index < 0 or selected_slot_index >= slots.size():
		_select_frame.visible = false
		return
	var slot: Control = slots[selected_slot_index]
	_place_frame_on_slot(_select_frame, slot)
	_select_frame.visible = true


func _place_frame_on_slot(frame: TextureRect, slot: Control) -> void:
	if frame == null or slot == null:
		return
	var offset := _hover_offset if frame == _hover_frame else _select_offset
	frame.position = slot.position + offset


func _on_use_selected_pressed() -> void:
	if selected_equip_slot_id != "":
		_on_equip_right_clicked(selected_equip_slot_id)
		return
	if selected_slot_index < 0:
		return
	var slot_data: Dictionary = inventory.get_slot(selected_slot_index) if inventory != null else {}
	var item_id := str(slot_data.get("item_id", ""))
	var amount := int(slot_data.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return
	var equip_sys = _get_equipment_system()
	if equip_sys != null and equip_sys.has_method("equip_from_inventory") and equip_sys.equip_from_inventory(inventory, selected_slot_index):
		details_label.text = "Equipped %s." % str(_get_item_data(item_id).get("display_name", item_id.capitalize()))
		refresh()
	else:
		details_label.text = "No use action for %s." % str(_get_item_data(item_id).get("display_name", item_id.capitalize()))


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


func _on_window_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_window = event.pressed
		_drag_last_mouse_position = get_viewport().get_mouse_position()
		accept_event()
		return

	if event is InputEventMouseMotion and _dragging_window:
		var mouse_position := get_viewport().get_mouse_position()
		var delta := mouse_position - _drag_last_mouse_position
		_drag_last_mouse_position = mouse_position
		_move_window_panel(delta)
		accept_event()


func _move_window_panel(delta: Vector2) -> void:
	if _window_panel == null:
		return
	_window_panel.offset_left += delta.x
	_window_panel.offset_right += delta.x
	_window_panel.offset_top += delta.y
	_window_panel.offset_bottom += delta.y
	_clamp_window_panel_to_viewport()


func _clamp_window_panel_to_viewport() -> void:
	if _window_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var rect := _window_panel.get_global_rect()
	var correction := Vector2.ZERO
	if rect.position.x < 0.0:
		correction.x = -rect.position.x
	elif rect.position.x + rect.size.x > viewport_size.x:
		correction.x = viewport_size.x - (rect.position.x + rect.size.x)
	if rect.position.y < 0.0:
		correction.y = -rect.position.y
	elif rect.position.y + rect.size.y > viewport_size.y:
		correction.y = viewport_size.y - (rect.position.y + rect.size.y)
	if correction != Vector2.ZERO:
		_window_panel.offset_left += correction.x
		_window_panel.offset_right += correction.x
		_window_panel.offset_top += correction.y
		_window_panel.offset_bottom += correction.y


func _apply_inventory_ui_fonts() -> void:
	_apply_inventory_ui_fonts_recursive(self)
	if details_label != null:
		OathwakeTextStyle.apply_profile_to_label(details_label, "item_tooltip")


func _apply_inventory_ui_fonts_recursive(node: Node) -> void:
	if node is Label:
		var label := node as Label
		if label.text == "Inventory" or label.text == "Equipment":
			OathwakeTextStyle.apply_profile_to_label(label, "ui_title")
		else:
			OathwakeTextStyle.apply_profile_to_label(label, "base_ui")
	elif node is Button:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "ui_button")
	elif node is LineEdit:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "base_ui")
	elif node is OptionButton:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "base_ui")
	elif node is SpinBox:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "base_ui")

	for child in node.get_children():
		_apply_inventory_ui_fonts_recursive(child)


func _on_slot_selected(slot_index: int, item_id: String, _inventory_id := "player") -> void:
	selected_slot_index = slot_index
	selected_equip_slot_id = ""
	_update_selected_slot_frame()
	if _hover_frame != null and selected_slot_index == slot_index:
		_hover_frame.visible = false
	if item_id.is_empty():
		details_label.text = "Empty slot %d." % (slot_index + 1)
		return

	var slot_data: Dictionary = inventory.get_slot(slot_index) if inventory != null else {}
	var quantity := int(slot_data.get("amount", 0))
	details_label.text = _get_item_details_text(item_id, quantity, slot_index)


func _on_slot_right_clicked(slot_index: int, _inventory_id := "player", shift_pressed := false, ctrl_pressed := false) -> void:
	if inventory == null:
		return

	if ctrl_pressed:
		if inventory.split_half_to_empty_slot(slot_index):
			details_label.text = "Split stack."
		else:
			details_label.text = "No empty slot."
		refresh()
		return

	var slot_data: Dictionary = inventory.get_slot(slot_index)
	var item_id := str(slot_data.get("item_id", ""))
	var amount := int(slot_data.get("amount", 0))

	if not shift_pressed and not ctrl_pressed and not item_id.is_empty() and amount == 1:
		var equip_sys = _get_equipment_system()
		if equip_sys != null and equip_sys.has_method("get_valid_slot_for_item"):
			var valid_slot = equip_sys.get_valid_slot_for_item(item_id)
			if not valid_slot.is_empty():
				var storage_ui: Node = get_tree().get_first_node_in_group("storage_ui")
				if storage_ui == null or not storage_ui.is_open():
					if equip_sys.equip_from_inventory(inventory, slot_index):
						details_label.text = "Equipped %s." % str(_get_item_data(item_id).get("display_name", item_id.capitalize()))
						refresh()
						return

	var remove_amount := int(amount) if shift_pressed else 1
	var removed: Dictionary = inventory.remove_from_slot(slot_index, remove_amount)
	item_id = str(removed.get("item_id", ""))
	amount = int(removed.get("amount", 0))
	var drop_metadata: Variant = removed.get("metadata")
	if item_id.is_empty():
		return

	_drop_removed_item(item_id, amount, drop_metadata if drop_metadata is Dictionary else {})
	var item_data: Dictionary = _get_item_data(item_id)
	details_label.text = "Dropped %d %s." % [amount, str(item_data.get("display_name", item_id.capitalize()))]


func _on_slot_drag_dropped(from_index: int, to_index: int, _from_inventory_id := "player", _to_inventory_id := "player") -> void:
	if inventory == null:
		return

	inventory.move_slot(from_index, to_index)
	refresh()


func _refresh_equipment_slots() -> void:
	if equipment_system == null:
		return
	var equip_slots: Dictionary = equipment_system.get_equipment_slots()
	for eq_slot in equipment_slot_nodes:
		var slot_data: Dictionary = equip_slots.get(eq_slot.slot_id, {})
		eq_slot.setup(eq_slot.slot_id, slot_data)
		_apply_transparent_button_style(eq_slot)


func _get_equipment_system():
	return equipment_system


func _on_equip_slot_selected(slot_id: String) -> void:
	selected_equip_slot_id = slot_id
	selected_slot_index = -1
	_update_selected_slot_frame()
	if equipment_system == null:
		details_label.text = "Equipment system not available."
		return
	var equip_data: Dictionary = equipment_system.get_equipped_slot(slot_id)
	var item_id := str(equip_data.get("item_id", ""))
	if item_id.is_empty():
		details_label.text = "Empty %s slot." % slot_id.capitalize()
		return
	var item_data: Dictionary = _get_item_data(item_id)
	var quantity := int(equip_data.get("amount", 0))
	var meta: Dictionary = equip_data.get("metadata", {})
	details_label.text = _get_equip_details_text(item_id, quantity, slot_id, item_data, meta)


func _on_equip_right_clicked(slot_id: String) -> void:
	if inventory == null or equipment_system == null:
		return
	if equipment_system.unequip_to_inventory(inventory, slot_id):
		details_label.text = "Unequipped %s." % slot_id.capitalize()
		refresh()
	else:
		details_label.text = "Inventory full."


func _on_equip_drag_dropped(slot_id: String, from_slot_index: int, from_inventory_id: String) -> void:
	if inventory == null or equipment_system == null:
		return
	if from_inventory_id != "player":
		return
	if equipment_system.equip_from_inventory(inventory, from_slot_index, slot_id):
		details_label.text = "Equipped."
		refresh()
	else:
		details_label.text = "Cannot equip."


func _on_equipment_drag_dropped_to_inventory(from_slot_id: String, _to_slot_index: int, to_inventory_id: String) -> void:
	if inventory == null or equipment_system == null:
		return
	if to_inventory_id != "player":
		return
	if equipment_system.unequip_to_inventory(inventory, from_slot_id):
		details_label.text = "Unequipped."
		refresh()


func _get_equip_details_text(item_id: String, quantity: int, slot_id: String, item_data: Dictionary, metadata: Dictionary) -> String:
	var lines := [
		str(item_data.get("display_name", item_id.capitalize())),
		"Slot: %s" % slot_id.capitalize(),
		"Type: %s | Tier: %s" % [str(item_data.get("item_type", "N/A")), str(item_data.get("tier", "N/A"))],
	]
	if quantity > 0:
		lines.append("Amount: %d" % quantity)
	if item_data.has("durability"):
		var max_dura := float(item_data.get("durability", 0.0))
		var current_dura := float(metadata.get("current_durability", max_dura))
		lines.append("Durability: %.0f / %.0f" % [current_dura, max_dura])
	if str(item_data.get("item_type", "")) == "tool":
		lines.append("Tool: %s T%s | Damage: %s" % [str(item_data.get("tool_type", "N/A")), str(item_data.get("tool_tier", "N/A")), str(item_data.get("tool_damage", "N/A"))])
	var combat_value: Variant = item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		lines.append("Attack: %s | %s" % [str(combat.get("attack_power", "N/A")), str(combat.get("damage_type", "N/A"))])
	return "\n".join(lines.slice(0, 6))


func _on_sort_inventory_pressed() -> void:
	if inventory == null:
		return

	inventory.sort_items()
	refresh()
	details_label.text = "Inventory sorted."


func _on_split_half_pressed() -> void:
	if inventory == null or selected_slot_index < 0:
		return

	if inventory.split_half_to_empty_slot(selected_slot_index):
		details_label.text = "Split stack."
	else:
		details_label.text = "No empty slot."
	refresh()


func _on_drop_stack_pressed() -> void:
	if inventory == null or selected_slot_index < 0:
		return

	var slot_data: Dictionary = inventory.get_slot(selected_slot_index)
	var amount := int(slot_data.get("amount", 0))
	if amount <= 0:
		return

	var removed: Dictionary = inventory.remove_from_slot(selected_slot_index, amount)
	var item_id := str(removed.get("item_id", ""))
	var removed_amount := int(removed.get("amount", 0))
	var drop_metadata: Variant = removed.get("metadata")
	if item_id.is_empty() or removed_amount <= 0:
		return

	_drop_removed_item(item_id, removed_amount, drop_metadata if drop_metadata is Dictionary else {})
	details_label.text = "Dropped %d %s." % [removed_amount, str(_get_item_data(item_id).get("display_name", item_id.capitalize()))]
	refresh()


func _on_close_inventory_pressed() -> void:
	if _hover_frame != null:
		_hover_frame.visible = false
	visible = false


func _drop_removed_item(item_id: String, amount: int, item_metadata: Dictionary = {}) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main != null and main.has_method("drop_item_near_player"):
		main.drop_item_near_player(item_id, amount, item_metadata)


func _on_slot_drag_started(slot_index: int, inventory_id: String) -> void:
	_drag_source_slot = slot_index if inventory_id == "player" else -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not is_drag_successful() and _drag_source_slot >= 0:
		_drop_from_slot(_drag_source_slot)
		_drag_source_slot = -1


func _drop_from_slot(slot_index: int) -> void:
	if inventory == null:
		return
	var slot_data: Dictionary = inventory.get_slot(slot_index)
	var item_id := str(slot_data.get("item_id", ""))
	var amount := int(slot_data.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return
	var removed: Dictionary = inventory.remove_from_slot(slot_index, amount)
	var removed_item_id := str(removed.get("item_id", ""))
	var removed_amount := int(removed.get("amount", 0))
	var drop_metadata: Variant = removed.get("metadata")
	if removed_item_id.is_empty() or removed_amount <= 0:
		return
	_drop_removed_item(removed_item_id, removed_amount, drop_metadata if drop_metadata is Dictionary else {})
	details_label.text = "Dropped %d %s." % [removed_amount, str(_get_item_data(removed_item_id).get("display_name", removed_item_id.capitalize()))]
	refresh()


func _make_trash_slot() -> ColorRect:
	var trash := TrashSlotScript.new()
	trash.name = "TrashSlot"
	trash.color = Color(0.35, 0.06, 0.07, 0.65)
	trash.custom_minimum_size = Vector2(56, 56)
	trash.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	trash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = "TRASH"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trash.add_child(label)
	var confirm := ConfirmationDialog.new()
	confirm.title = "Remove Item"
	confirm.dialog_text = ""
	confirm.confirmed.connect(_on_trash_confirmed)
	confirm.canceled.connect(_on_trash_canceled)
	confirm.hide()
	trash.add_child(confirm)
	confirm.set_name("ConfirmDialog")
	return trash


var _pending_trash_data: Dictionary = {}


func _on_trash_dropped(slot_index: int, inventory_id: String) -> void:
	if inventory == null or inventory_id != "player":
		return
	var slot_data: Dictionary = inventory.get_slot(slot_index)
	var item_id := str(slot_data.get("item_id", ""))
	var amount := int(slot_data.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return
	var item_data := _get_item_data(item_id)
	var display_name := str(item_data.get("display_name", item_id.capitalize()))
	_pending_trash_data = {"slot_index": slot_index, "item_id": item_id, "amount": amount, "display_name": display_name}
	var trash := find_child("TrashSlot", true, false) as ColorRect
	if trash == null:
		return
	var confirm := trash.get_node_or_null("ConfirmDialog") as ConfirmationDialog
	if confirm == null:
		return
	confirm.dialog_text = "Remove %d %s?" % [amount, display_name]
	confirm.popup_centered()


func _on_trash_confirmed() -> void:
	if _pending_trash_data.is_empty():
		return
	var slot_index := int(_pending_trash_data.get("slot_index", -1))
	var item_id := str(_pending_trash_data.get("item_id", ""))
	var amount := int(_pending_trash_data.get("amount", 0))
	_pending_trash_data = {}
	if inventory == null or slot_index < 0:
		return
	var slot_check: Dictionary = inventory.get_slot(slot_index)
	if str(slot_check.get("item_id", "")) != item_id:
		return
	var removed: Dictionary = inventory.remove_from_slot(slot_index, amount)
	var removed_amount := int(removed.get("amount", 0))
	if removed_amount > 0:
		details_label.text = "Removed %d %s." % [removed_amount, str(_get_item_data(item_id).get("display_name", item_id.capitalize()))]
	refresh()


func _on_trash_canceled() -> void:
	_pending_trash_data = {}
	details_label.text = "Cancelled."


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}

	return content_db.get_item(item_id)


func _get_item_details_text(item_id: String, quantity: int, slot_index: int) -> String:
	var item_data: Dictionary = _get_item_data(item_id)
	var slot_data: Dictionary = inventory.get_slot(slot_index) if inventory != null else {}
	var raw_metadata: Variant = slot_data.get("metadata", {})
	var metadata: Dictionary = raw_metadata if raw_metadata is Dictionary else {}
	var lines := [
		str(item_data.get("display_name", item_id.capitalize())),
		"Amount: %d | Stack: %d" % [quantity, int(item_data.get("stack_size", 99))],
		"Tier: %s | Type: %s" % [str(item_data.get("tier", "N/A")), str(item_data.get("item_type", "N/A"))],
	]

	var family := str(item_data.get("material_family", ""))
	if not family.is_empty() and family != "N/A":
		lines.append("Family: %s" % family.capitalize())

	if str(item_data.get("item_type", "")) == "tool":
		lines.append("Tool: %s T%s | Damage: %s" % [str(item_data.get("tool_type", "N/A")), str(item_data.get("tool_tier", "N/A")), str(item_data.get("tool_damage", "N/A"))])

	var max_dura := int(item_data.get("durability", 0))
	if max_dura > 0:
		var current_dura := int(metadata.get("current_durability", max_dura))
		lines.append("Durability: %s" % ("BROKEN" if current_dura <= 0 else "%d / %d" % [current_dura, max_dura]))

	var combat_value: Variant = item_data.get("combat", {})
	if combat_value is Dictionary:
		var combat: Dictionary = combat_value
		lines.append("Attack: %s | %s" % [str(combat.get("attack_power", "N/A")), str(combat.get("damage_type", "N/A"))])

	return "\n".join(lines.slice(0, 6))
