extends "res://scripts/ui/InventorySlot.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")

var _refinement_source_data: Dictionary = {}


func setup(index: int, new_item_id: String, new_amount: int, item_data: Dictionary, texture: Texture2D, new_inventory_id := "player", new_metadata := {}) -> void:
	var slot := {
		"item_id": new_item_id,
		"amount": new_amount,
		"metadata": new_metadata.duplicate(true) if new_metadata is Dictionary else {},
	}
	_refinement_source_data = item_data.duplicate(true)
	var refined_data := RefinementCalculatorScript.apply_refinement_to_item_data(item_data, slot)
	super.setup(index, new_item_id, new_amount, refined_data, texture, new_inventory_id, new_metadata)


func clear_slot(index := -1) -> void:
	_refinement_source_data.clear()
	super.clear_slot(index)


func _make_tooltip(item_data: Dictionary) -> String:
	var text := super._make_tooltip(item_data)
	var slot := {
		"item_id": item_id,
		"amount": amount,
		"metadata": metadata,
	}
	var level := RefinementCalculatorScript.get_refinement_level(slot)
	if level <= 0:
		return text
	var max_level := int(_refinement_source_data.get("max_refinement_level", 10))
	return "%s\nRefinement: +%d / +%d" % [text, level, max_level]
