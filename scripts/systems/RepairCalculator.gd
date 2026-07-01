extends RefCounted

const RecipeBookScript := preload("res://scripts/systems/RecipeBook.gd")
const ItemInstanceHelper = preload("res://scripts/systems/ItemInstanceHelper.gd")

const FALLBACK_COST := {
	1: [{"resource": "wood", "amount": 2}],
	2: [{"resource": "stone", "amount": 2}, {"resource": "oak_wood", "amount": 1}],
	3: [{"resource": "bronze_ingot", "amount": 2}, {"resource": "ash_wood", "amount": 1}],
	4: [{"resource": "iron_ingot", "amount": 2}, {"resource": "maple_wood", "amount": 1}],
	5: [{"resource": "steel_ingot", "amount": 2}, {"resource": "walnut_wood", "amount": 1}],
	6: [{"resource": "titanium_ingot", "amount": 2}, {"resource": "ebony_wood", "amount": 1}],
	7: [{"resource": "adamantite_ingot", "amount": 2}, {"resource": "ironwood", "amount": 1}],
}

var recipe_book := RecipeBookScript.new()
var repair_multiplier := 0.5


func can_repair(slot: Dictionary) -> bool:
	if not slot is Dictionary:
		return false
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		return false
	var item_data := _get_item_data(item_id)
	if item_data.is_empty():
		return false
	if not bool(item_data.get("can_repair", true)):
		return false
	var max_dura := ItemInstanceHelper.get_max_durability(item_id)
	if max_dura <= 0:
		return false
	var current_dura := ItemInstanceHelper.get_current_durability(slot)
	if current_dura >= max_dura:
		return false
	return true


func get_repair_cost(slot: Dictionary) -> Array:
	if not can_repair(slot):
		return []

	var item_id := str(slot.get("item_id", ""))
	var max_dura := ItemInstanceHelper.get_max_durability(item_id)
	var current_dura := ItemInstanceHelper.get_current_durability(slot)
	var missing: int = max(1, max_dura - current_dura)
	var repair_ratio: float = float(missing) / float(max(max_dura, 1))
	var item_repair_multiplier := _get_item_repair_multiplier(item_id)

	var original_cost: Array = _get_original_recipe_cost(item_id)
	var cost: Array = []

	var cost_map := {}
	for cost_entry in original_cost:
		var resource := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if resource.is_empty() or amount <= 0:
			continue
		if resource == item_id:
			continue
		var calculated := int(ceil(float(amount) * repair_ratio * item_repair_multiplier))
		calculated = max(calculated, 1 if missing > 0 else 0)
		cost_map[resource] = calculated

	for resource in cost_map.keys():
		cost.append({"resource": resource, "amount": cost_map[resource]})

	if cost.is_empty():
		var item_tier := _get_item_tier(item_id)
		var fallback: Array = FALLBACK_COST.get(item_tier, FALLBACK_COST[1])
		for entry in fallback:
			var resource := str(entry.get("resource", ""))
			var amount := int(entry.get("amount", 0))
			var calculated := int(ceil(float(amount) * repair_ratio * item_repair_multiplier))
			calculated = max(calculated, 1 if missing > 0 else 0)
			cost.append({"resource": resource, "amount": calculated})

	return cost


func repair_item(slot: Dictionary, inventory) -> bool:
	if not can_repair(slot):
		return false
	if inventory == null:
		return false

	var item_id := str(slot.get("item_id", ""))
	var cost: Array = get_repair_cost(slot)
	if cost.is_empty():
		var max_dura := ItemInstanceHelper.get_max_durability(item_id)
		if max_dura <= 0:
			return false
		var metadata: Dictionary = slot.get("metadata", {})
		if not metadata is Dictionary:
			metadata = {}
		metadata["current_durability"] = max_dura
		slot["metadata"] = metadata
		return true

	if not _can_afford(cost, inventory):
		return false

	for cost_entry in cost:
		var resource := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if not resource.is_empty() and amount > 0:
			inventory.remove_item(resource, amount)

	var max_dura := ItemInstanceHelper.get_max_durability(item_id)
	var metadata: Dictionary = slot.get("metadata", {})
	if not metadata is Dictionary:
		metadata = {}
	metadata["current_durability"] = max_dura
	slot["metadata"] = metadata
	return true


func _can_afford(cost: Array, inventory) -> bool:
	if inventory == null:
		return false
	for cost_entry in cost:
		var resource := str(cost_entry.get("resource", ""))
		var amount := int(cost_entry.get("amount", 0))
		if not resource.is_empty() and amount > 0:
			if not inventory.has_item(resource, amount):
				return false
	return true


func _get_original_recipe_cost(item_id: String) -> Array:
	var recipe: Dictionary = recipe_book.get_recipe(item_id)
	if recipe.is_empty():
		return []
	var cost_variant: Variant = recipe.get("cost", [])
	if cost_variant is Array:
		return cost_variant
	if cost_variant is Dictionary:
		var cost_array := []
		for resource in cost_variant:
			cost_array.append({"resource": str(resource), "amount": int(cost_variant[resource])})
		return cost_array
	return []


func _get_item_repair_multiplier(item_id: String) -> float:
	var item_data := _get_item_data(item_id)
	if item_data.is_empty():
		return repair_multiplier
	return clamp(float(item_data.get("repair_cost_multiplier", repair_multiplier)), 0.0, 10.0)


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}
	return content_db.get_item(item_id)


func _get_item_tier(item_id: String) -> int:
	var item_data := _get_item_data(item_id)
	if item_data.is_empty():
		return 1
	return max(int(item_data.get("tier", 1)), 1)


func _get_content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")
