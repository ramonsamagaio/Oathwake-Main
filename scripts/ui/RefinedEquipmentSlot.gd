extends "res://scripts/ui/EquipmentSlot.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")

var _current_refinement_level := 0
var _current_max_refinement_level := 10


func _get_item_data(requested_item_id: String) -> Dictionary:
	var item_data := super._get_item_data(requested_item_id)
	_current_refinement_level = 0
	_current_max_refinement_level = int(item_data.get("max_refinement_level", 10))
	if item_data.is_empty():
		return item_data
	var equipment_system = _get_equipment_system()
	if equipment_system == null or not equipment_system.has_method("get_equipped_slot"):
		return item_data
	var slot_data = equipment_system.get_equipped_slot(slot_id)
	if not slot_data is Dictionary:
		return item_data
	_current_refinement_level = RefinementCalculatorScript.get_refinement_level(slot_data)
	return RefinementCalculatorScript.apply_refinement_to_item_data(item_data, slot_data)


func _make_tooltip(item_data: Dictionary) -> String:
	var text := super._make_tooltip(item_data)
	if _current_refinement_level <= 0:
		return text
	return "%s\nRefinement: +%d / +%d" % [text, _current_refinement_level, _current_max_refinement_level]
