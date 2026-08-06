extends "res://scripts/ui/InventoryUI.gd"

const FULL_INVENTORY_SLOT_COUNT := 60
const OPTIONAL_EQUIPMENT_SLOT_IDS := ["gloves", "trinket"]
const OptionalEquipmentSlotScene := preload("res://scenes/ui/EquipmentSlot.tscn")
const OptionalUILayoutApplier := preload("res://scripts/ui/UILayoutApplier.gd")

var _bound_equipment_system: Object


func _ready() -> void:
	slot_count = FULL_INVENTORY_SLOT_COUNT
	_resize_backing_inventory()
	super._ready()
	_tag_authored_equipment_slots()
	_add_optional_equipment_slots_from_layout()
	call_deferred("_resize_backing_inventory")
	call_deferred("refresh")


func set_inventory(new_inventory) -> void:
	if new_inventory != null and new_inventory.has_method("resize_slots"):
		new_inventory.call("resize_slots", FULL_INVENTORY_SLOT_COUNT)
	super.set_inventory(new_inventory)


func set_equipment_system(new_equipment_system) -> void:
	_unbind_equipment_refresh()
	_bound_equipment_system = new_equipment_system
	super.set_equipment_system(new_equipment_system)
	if _bound_equipment_system != null and _bound_equipment_system.has_signal("changed"):
		var callback := Callable(self, "refresh")
		if not _bound_equipment_system.is_connected("changed", callback):
			_bound_equipment_system.connect("changed", callback)


func _exit_tree() -> void:
	_unbind_equipment_refresh()


func _unbind_equipment_refresh() -> void:
	if _bound_equipment_system == null:
		return
	var callback := Callable(self, "refresh")
	if _bound_equipment_system.has_signal("changed") and _bound_equipment_system.is_connected("changed", callback):
		_bound_equipment_system.disconnect("changed", callback)
	_bound_equipment_system = null


func _tag_authored_equipment_slots() -> void:
	for eq_slot in equipment_slot_nodes:
		eq_slot.set_meta("layout_slot_id", str(eq_slot.slot_id))


func _add_optional_equipment_slots_from_layout() -> void:
	if _window_panel == null:
		return
	for slot_id in OPTIONAL_EQUIPMENT_SLOT_IDS:
		if _find_layout_equipment_slot(slot_id) != null:
			continue
		var element_id := "equipment.%s" % slot_id
		var rect := OptionalUILayoutApplier.get_element_rect(_layout, element_id)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var eq_slot = OptionalEquipmentSlotScene.instantiate()
		eq_slot.slot_id = slot_id
		eq_slot.set_meta("layout_slot_id", slot_id)
		eq_slot.position = rect.position - _window_rect.position
		eq_slot.size = rect.size
		eq_slot.equip_selected.connect(_on_equip_slot_selected)
		eq_slot.equip_right_clicked.connect(_on_equip_right_clicked)
		eq_slot.equip_drag_dropped.connect(_on_equip_drag_dropped)
		_window_panel.add_child(eq_slot)
		equipment_slot_nodes.append(eq_slot)
		_apply_transparent_button_style(eq_slot)


func _find_layout_equipment_slot(layout_slot_id: String) -> Object:
	for eq_slot in equipment_slot_nodes:
		if str(eq_slot.get_meta("layout_slot_id", eq_slot.slot_id)) == layout_slot_id:
			return eq_slot
	return null


func _has_dedicated_trinket_layout() -> bool:
	return _find_layout_equipment_slot("trinket") != null


func _refresh_equipment_slots() -> void:
	if equipment_system == null:
		return
	var equip_slots: Dictionary = equipment_system.get_equipment_slots()
	var has_dedicated_trinket := _has_dedicated_trinket_layout()
	for eq_slot in equipment_slot_nodes:
		var layout_slot_id := str(eq_slot.get_meta("layout_slot_id", eq_slot.slot_id))
		var runtime_slot_id := layout_slot_id
		# Until the user authors a dedicated trinket rectangle, the Back artwork is
		# a compatibility display for an equipped pet trinket. Once equipment.trinket
		# exists in ui_layout.json, Back and Trinket become fully independent.
		if layout_slot_id == "back" and not has_dedicated_trinket:
			var back_data: Dictionary = equip_slots.get("back", {})
			var trinket_data: Dictionary = equip_slots.get("trinket", {})
			if not _slot_data_has_item(back_data) and _slot_data_has_item(trinket_data):
				runtime_slot_id = "trinket"
		eq_slot.slot_id = runtime_slot_id
		var slot_data: Dictionary = equip_slots.get(runtime_slot_id, {})
		eq_slot.setup(runtime_slot_id, slot_data)
		_apply_transparent_button_style(eq_slot)


func _slot_data_has_item(slot_data: Variant) -> bool:
	if not slot_data is Dictionary:
		return false
	return not str(slot_data.get("item_id", "")).is_empty() and int(slot_data.get("amount", 0)) > 0


func _resize_backing_inventory() -> void:
	var game := get_parent()
	if game != null and game is CanvasLayer:
		game = game.get_parent()
	if game == null:
		return
	var inventory_value: Variant = game.get("inventory")
	if inventory_value != null and inventory_value.has_method("resize_slots"):
		inventory_value.call("resize_slots", FULL_INVENTORY_SLOT_COUNT)
	set_meta("full_inventory_slot_count", FULL_INVENTORY_SLOT_COUNT)
