extends SceneTree

const LAYOUT_CONFIG := preload("res://scripts/ui/UILayoutConfig.gd")
const LAYOUT_APPLIER := preload("res://scripts/ui/UILayoutApplier.gd")
const EQUIPMENT_SLOT_SCENE := preload("res://scenes/ui/EquipmentSlot.tscn")
const EQUIPMENT_SYSTEM_SCRIPT := preload("res://scripts/systems/EquipmentSystem.gd")

const CORE_LAYOUT_SLOT_IDS := [
	"helm",
	"neck",
	"hand_right",
	"armor",
	"hand_left",
	"legs",
	"boots",
	"ring_left",
	"ring_right",
	"back",
]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	_validate_authored_layout_rectangles()
	await _validate_equipment_slot_respects_authored_size()
	_validate_equipment_save_repair()
	_validate_optional_slot_contract()

	if failures.is_empty():
		print("INVENTORY_EQUIPMENT_LAYOUT_VALIDATION_PASS")
		quit(0)
		return

	for failure in failures:
		push_error("INVENTORY_EQUIPMENT_LAYOUT_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_authored_layout_rectangles() -> void:
	var layout := LAYOUT_CONFIG.load_layout()
	var rects: Dictionary = {}
	for slot_id in CORE_LAYOUT_SLOT_IDS:
		var element_id := "equipment.%s" % slot_id
		var rect := LAYOUT_APPLIER.get_element_rect(layout, element_id)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			failures.append("UILayoutWorkbench export is missing %s." % element_id)
			continue
		if rect.size.x > 80.0 or rect.size.y > 80.0:
			failures.append("%s is unexpectedly oversized in ui_layout.json: %s." % [element_id, rect])
		rects[slot_id] = rect

	var slot_ids := rects.keys()
	for first_index in range(slot_ids.size()):
		for second_index in range(first_index + 1, slot_ids.size()):
			var first_id := str(slot_ids[first_index])
			var second_id := str(slot_ids[second_index])
			var first_rect: Rect2 = rects[first_id]
			var second_rect: Rect2 = rects[second_id]
			var overlap := first_rect.intersection(second_rect)
			if overlap.size.x > 1.0 and overlap.size.y > 1.0:
				failures.append("Authored equipment slots overlap: %s and %s (%s)." % [first_id, second_id, overlap])


func _validate_equipment_slot_respects_authored_size() -> void:
	var layout := LAYOUT_CONFIG.load_layout()
	var armor_rect := LAYOUT_APPLIER.get_element_rect(layout, "equipment.armor")
	var slot := EQUIPMENT_SLOT_SCENE.instantiate() as Button
	if slot == null:
		failures.append("EquipmentSlot scene could not be instantiated.")
		return
	root.add_child(slot)
	slot.position = armor_rect.position
	slot.size = armor_rect.size
	slot.call("setup", "armor", {})
	await process_frame
	if not slot.size.is_equal_approx(armor_rect.size):
		failures.append("EquipmentSlot expanded from authored %s to runtime %s." % [armor_rect.size, slot.size])
	if not slot.custom_minimum_size.is_equal_approx(Vector2.ZERO):
		failures.append("EquipmentSlot still imposes a custom minimum size: %s." % slot.custom_minimum_size)
	if not slot.clip_contents:
		failures.append("EquipmentSlot does not clip item artwork to its authored rectangle.")
	var icon := slot.get_node_or_null("ItemIcon") as Control
	if icon == null:
		failures.append("EquipmentSlot did not create its ItemIcon overlay.")
	else:
		var icon_rect := Rect2(icon.position, icon.size)
		var slot_rect := Rect2(Vector2.ZERO, slot.size)
		if not slot_rect.encloses(icon_rect):
			failures.append("EquipmentSlot ItemIcon escapes its authored bounds: %s outside %s." % [icon_rect, slot_rect])
	slot.queue_free()
	await process_frame


func _validate_equipment_save_repair() -> void:
	var content_db := root.get_node_or_null("ContentDB")
	if content_db == null or not content_db.has_method("get_all_items"):
		failures.append("ContentDB is unavailable for equipment migration validation.")
		return
	var armor_item_id := _find_item_for_slot(content_db.call("get_all_items"), "armor")
	if armor_item_id.is_empty():
		failures.append("No armor item exists to validate misplaced save repair.")
		return

	var equipment = EQUIPMENT_SYSTEM_SCRIPT.new()
	equipment.call("set_slots_from_save", {
		"hand_right": {
			"item_id": armor_item_id,
			"amount": 1,
			"metadata": {},
		},
		"back": {
			"item_id": "butterfly_pet_trinket",
			"amount": 1,
			"metadata": {},
		},
	})
	var repaired_armor: Dictionary = equipment.call("get_equipped_slot", "armor")
	var repaired_hand: Dictionary = equipment.call("get_equipped_slot", "hand_right")
	if str(repaired_armor.get("item_id", "")) != armor_item_id:
		failures.append("Armor saved under hand_right was not repaired into armor.")
	if not str(repaired_hand.get("item_id", "")).is_empty():
		failures.append("hand_right still contains armor after save repair.")
	var repaired_trinket: Dictionary = equipment.call("get_equipped_slot", "trinket")
	var repaired_back: Dictionary = equipment.call("get_equipped_slot", "back")
	if str(repaired_trinket.get("item_id", "")) != "butterfly_pet_trinket":
		failures.append("Legacy butterfly trinket saved under back was not migrated to trinket.")
	if not str(repaired_back.get("item_id", "")).is_empty():
		failures.append("Back still contains the migrated butterfly trinket.")


func _find_item_for_slot(items_value: Variant, requested_slot: String) -> String:
	if not items_value is Dictionary:
		return ""
	var items: Dictionary = items_value
	for item_id in items.keys():
		var item_value: Variant = items[item_id]
		if not item_value is Dictionary:
			continue
		var item_data: Dictionary = item_value
		if str(item_data.get("equipment_slot", "")).to_lower() == requested_slot:
			return str(item_id)
	for item_id in items.keys():
		var item_value: Variant = items[item_id]
		if item_value is Dictionary and str(item_value.get("item_type", "")).to_lower() == requested_slot:
			return str(item_id)
	return ""


func _validate_optional_slot_contract() -> void:
	var equipment = EQUIPMENT_SYSTEM_SCRIPT.new()
	var canonical_ids: Array = equipment.call("get_canonical_slot_ids")
	if not canonical_ids.has("gloves"):
		failures.append("EquipmentSystem does not expose the canonical gloves slot.")
	if not canonical_ids.has("trinket"):
		failures.append("EquipmentSystem does not expose the canonical trinket slot.")
	var expanded_ui_text := FileAccess.get_file_as_string("res://scripts/ui/InventoryUIExpanded.gd")
	for token in ["equipment.%s", "OPTIONAL_EQUIPMENT_SLOT_IDS", "gloves", "trinket", "layout_slot_id"]:
		if not expanded_ui_text.contains(token):
			failures.append("InventoryUI optional equipment layout contract is missing %s." % token)
