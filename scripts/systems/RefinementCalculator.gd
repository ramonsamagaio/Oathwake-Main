extends RefCounted

const RecipeBookScript := preload("res://scripts/systems/RecipeBook.gd")
const ItemInstanceHelper := preload("res://scripts/systems/ItemInstanceHelper.gd")

const DEFAULT_MAX_REFINEMENT_LEVEL := 10
const REFINABLE_TYPES := ["weapon", "armor"]
const WEAPON_ATTACK_BONUS_PER_LEVEL := 0.05
const ARMOR_STAT_BONUS_PER_LEVEL := 0.04
const COST_BASE_MULTIPLIER := 0.25
const COST_LEVEL_MULTIPLIER := 0.15

const FALLBACK_COST := {
	1: [{"resource": "stone", "amount": 2}],
	2: [{"resource": "basic_gem", "amount": 1}, {"resource": "stone", "amount": 2}],
	3: [{"resource": "bronze_ingot", "amount": 2}],
	4: [{"resource": "iron_ingot", "amount": 2}],
	5: [{"resource": "steel_ingot", "amount": 2}],
	6: [{"resource": "titanium_ingot", "amount": 2}],
	7: [{"resource": "adamantite_ingot", "amount": 2}],
}

var recipe_book := RecipeBookScript.new()


func is_refinable(slot: Dictionary) -> bool:
	if not slot is Dictionary:
		return false
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty() or int(slot.get("amount", 0)) <= 0:
		return false
	var item_data := _get_item_data(item_id)
	if item_data.is_empty():
		return false
	if not bool(item_data.get("can_refine", true)):
		return false
	return REFINABLE_TYPES.has(str(item_data.get("item_type", "")).to_lower())


func can_refine(slot: Dictionary) -> bool:
	if not is_refinable(slot):
		return false
	return get_refinement_level(slot) < get_max_refinement_level(slot)


func get_max_refinement_level(slot: Dictionary) -> int:
	var item_id := str(slot.get("item_id", ""))
	var item_data := _get_item_data(item_id)
	return maxi(int(item_data.get("max_refinement_level", DEFAULT_MAX_REFINEMENT_LEVEL)), 0)


func get_refinement_cost(slot: Dictionary) -> Array:
	if not can_refine(slot):
		return []

	var item_id := str(slot.get("item_id", ""))
	var target_level := get_refinement_level(slot) + 1
	var item_data := _get_item_data(item_id)
	var source_cost := _get_original_recipe_cost(item_id)
	if source_cost.is_empty():
		var tier := maxi(int(item_data.get("tier", 1)), 1)
		source_cost = FALLBACK_COST.get(tier, FALLBACK_COST[1]).duplicate(true)

	var multiplier := COST_BASE_MULTIPLIER + float(target_level) * COST_LEVEL_MULTIPLIER
	var cost_map := {}
	for entry_variant in source_cost:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var resource := str(entry.get("resource", entry.get("item_id", "")))
		var amount := int(entry.get("amount", 0))
		if resource.is_empty() or resource == item_id or amount <= 0:
			continue
		var calculated := maxi(int(ceil(float(amount) * multiplier)), 1)
		cost_map[resource] = int(cost_map.get(resource, 0)) + calculated

	var result: Array = []
	var resources: Array = cost_map.keys()
	resources.sort()
	for resource_variant in resources:
		var resource := str(resource_variant)
		result.append({"resource": resource, "amount": int(cost_map[resource])})
	return result


func can_afford_refinement(slot: Dictionary, inventory) -> bool:
	if inventory == null or not can_refine(slot):
		return false
	var cost := get_refinement_cost(slot)
	if cost.is_empty():
		return false
	for entry_variant in cost:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var resource := str(entry.get("resource", ""))
		var amount := int(entry.get("amount", 0))
		if resource.is_empty() or amount <= 0:
			continue
		if not inventory.has_item(resource, amount):
			return false
	return true


func refine_item(slot: Dictionary, inventory) -> bool:
	if not can_afford_refinement(slot, inventory):
		return false

	var cost := get_refinement_cost(slot)
	for entry_variant in cost:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var resource := str(entry.get("resource", ""))
		var amount := int(entry.get("amount", 0))
		if not resource.is_empty() and amount > 0:
			inventory.remove_item(resource, amount)

	ItemInstanceHelper.ensure_item_metadata(slot)
	var metadata_variant: Variant = slot.get("metadata", {})
	var metadata: Dictionary = metadata_variant if metadata_variant is Dictionary else {}
	metadata["refinement_level"] = get_refinement_level(slot) + 1
	slot["metadata"] = metadata
	return true


func get_preview(slot: Dictionary) -> Dictionary:
	if not is_refinable(slot):
		return {}
	var item_id := str(slot.get("item_id", ""))
	var item_data := _get_item_data(item_id)
	var current_data := apply_refinement_to_item_data(item_data, slot)
	var next_slot := slot.duplicate(true)
	var next_metadata_variant: Variant = next_slot.get("metadata", {})
	var next_metadata: Dictionary = next_metadata_variant.duplicate(true) if next_metadata_variant is Dictionary else {}
	next_metadata["refinement_level"] = mini(get_refinement_level(slot) + 1, get_max_refinement_level(slot))
	next_slot["metadata"] = next_metadata
	return {
		"current": current_data,
		"next": apply_refinement_to_item_data(item_data, next_slot),
	}


static func get_refinement_level(slot: Dictionary) -> int:
	if not slot is Dictionary:
		return 0
	var metadata_variant: Variant = slot.get("metadata", {})
	if not metadata_variant is Dictionary:
		return 0
	return maxi(int((metadata_variant as Dictionary).get("refinement_level", 0)), 0)


static func get_refined_display_name(item_data: Dictionary, slot: Dictionary) -> String:
	var display_name := str(item_data.get("display_name", str(slot.get("item_id", "")).capitalize()))
	var level := get_refinement_level(slot)
	return "%s +%d" % [display_name, level] if level > 0 else display_name


static func apply_refinement_to_item_data(item_data: Dictionary, slot: Dictionary) -> Dictionary:
	var result := item_data.duplicate(true)
	var level := get_refinement_level(slot)
	if level <= 0 or result.is_empty():
		return result

	result["refinement_level"] = level
	result["display_name"] = get_refined_display_name(item_data, slot)
	var item_type := str(result.get("item_type", "")).to_lower()
	if item_type == "weapon":
		var combat_variant: Variant = result.get("combat", {})
		var combat: Dictionary = combat_variant.duplicate(true) if combat_variant is Dictionary else {}
		var base_attack := float(combat.get("attack_power", 0.0))
		if base_attack > 0.0:
			combat["attack_power"] = int(ceil(base_attack * (1.0 + WEAPON_ATTACK_BONUS_PER_LEVEL * float(level))))
		result["combat"] = combat
	elif item_type == "armor":
		for stat_name in ["defense", "magic_defense", "max_hp_bonus"]:
			var base_value := float(result.get(stat_name, 0.0))
			if base_value > 0.0:
				result[stat_name] = int(ceil(base_value * (1.0 + ARMOR_STAT_BONUS_PER_LEVEL * float(level))))

	return result


func _get_original_recipe_cost(item_id: String) -> Array:
	var recipe := recipe_book.get_recipe(item_id)
	if recipe.is_empty():
		return []
	var cost_variant: Variant = recipe.get("cost", [])
	if cost_variant is Array:
		return (cost_variant as Array).duplicate(true)
	if cost_variant is Dictionary:
		var result: Array = []
		for resource_variant in (cost_variant as Dictionary).keys():
			var resource := str(resource_variant)
			result.append({"resource": resource, "amount": int((cost_variant as Dictionary)[resource_variant])})
		return result
	return []


func _get_item_data(item_id: String) -> Dictionary:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}
	return content_db.get_item(item_id)


func _get_content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")
