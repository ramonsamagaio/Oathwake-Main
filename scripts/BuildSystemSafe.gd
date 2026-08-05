extends "res://scripts/BuildSystem.gd"

const CAMPFIRE_ITEM_ID := "campfire"


func _get_building_cost(building_type: String) -> Array:
	building_type = _normalize_building_type(building_type)
	if building_type == BUILD_TYPE_CAMPFIRE and main != null and main.has_method("can_spend_resource"):
		if bool(main.call("can_spend_resource", CAMPFIRE_ITEM_ID, 1)):
			return [{"resource": CAMPFIRE_ITEM_ID, "amount": 1}]
	return super._get_building_cost(building_type)


func _refund_building_cost(building_type: String) -> void:
	building_type = _normalize_building_type(building_type)
	if building_type == BUILD_TYPE_CAMPFIRE:
		_return_retrieved_item(CAMPFIRE_ITEM_ID, 1)
		return
	super._refund_building_cost(building_type)


func _return_retrieved_item(item_id: String, amount: int) -> void:
	if main == null or amount <= 0:
		return
	var leftover := amount
	if main.has_method("add_item_to_inventory"):
		leftover = int(main.call("add_item_to_inventory", item_id, amount))
	elif main.has_method("add_resource"):
		main.call("add_resource", item_id, amount)
		leftover = 0
	if leftover > 0 and main.has_method("drop_item_near_player"):
		main.call("drop_item_near_player", item_id, leftover)
	print("Retrieved %s x%d" % [item_id.capitalize(), amount])
