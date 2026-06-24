extends RefCounted

const WALL_ID := "wall"
const CAMPFIRE_ID := "campfire"
const WORKBENCH_ID := "workbench"
const BED_ID := "bed"

const FALLBACK_RECIPES := {
	WALL_ID: {
		"display_name": "Wall",
		"type": "building",
		"cost": {
			"wood": 1,
		},
	},
	CAMPFIRE_ID: {
		"display_name": "Campfire",
		"type": "building",
		"cost": {
			"wood": 3,
			"stone": 1,
		},
	},
	WORKBENCH_ID: {
		"display_name": "Workbench",
		"type": "building",
		"cost": {
			"wood": 5,
			"stone": 2,
		},
	},
	BED_ID: {
		"display_name": "Bed",
		"type": "building",
		"cost": {
			"wood": 6,
			"gel": 2,
		},
	},
	"axe": {
		"display_name": "Axe",
		"type": "tool",
		"cost": {
			"wood": 3,
			"stone": 1,
		},
	},
	"pickaxe": {
		"display_name": "Pickaxe",
		"type": "tool",
		"cost": {
			"wood": 2,
			"stone": 3,
		},
	},
}

const BUILD_KEYS := {
	WALL_ID: KEY_1,
	CAMPFIRE_ID: KEY_2,
	WORKBENCH_ID: KEY_3,
	BED_ID: KEY_4,
}


func has_recipe(recipe_id: String) -> bool:
	return not get_recipe(recipe_id).is_empty()


func get_recipe(recipe_id: String) -> Dictionary:
	var normalized_id := normalize_recipe_id(recipe_id)
	var recipe_data := _get_raw_recipe(normalized_id)
	if recipe_data.is_empty():
		return {}

	var recipe := recipe_data.duplicate(true)
	recipe["id"] = normalized_id
	recipe["cost"] = _normalize_cost(recipe.get("cost", {}))
	if BUILD_KEYS.has(normalized_id):
		recipe["build_key"] = BUILD_KEYS[normalized_id]

	return recipe


func get_display_name(recipe_id: String) -> String:
	var normalized_id := normalize_recipe_id(recipe_id)
	return str(get_recipe(normalized_id).get("display_name", normalized_id.capitalize()))


func get_type(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("type", ""))


func get_cost(recipe_id: String) -> Array:
	var cost = get_recipe(recipe_id).get("cost", [])
	if cost is Array:
		return cost

	return []


func get_scene_path(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("scene_path", ""))


func get_build_key(recipe_id: String) -> int:
	return int(get_recipe(recipe_id).get("build_key", 0))


func get_recipe_id_for_key(keycode: int) -> String:
	for recipe in get_recipes_by_type("building"):
		var recipe_id := str(recipe.get("id", ""))
		if get_build_key(recipe_id) == keycode:
			return recipe_id

	return ""


func get_all_recipes() -> Array:
	var recipes := []
	var recipe_ids := _get_all_recipe_ids()
	recipe_ids.sort()

	for recipe_id in recipe_ids:
		var recipe := get_recipe(str(recipe_id))
		if not recipe.is_empty():
			recipes.append(recipe)

	return recipes


func get_recipes_by_type(recipe_type: String) -> Array:
	var recipes := []

	for recipe in get_all_recipes():
		if str(recipe.get("type", "")) == recipe_type:
			recipes.append(recipe)

	return recipes


func normalize_recipe_id(recipe_id: String) -> String:
	match recipe_id:
		"Wall":
			return WALL_ID
		"Campfire":
			return CAMPFIRE_ID
		"Workbench":
			return WORKBENCH_ID
		"Bed":
			return BED_ID
		_:
			return recipe_id.to_lower()


func _get_raw_recipe(recipe_id: String) -> Dictionary:
	var content_db := _get_content_db()
	if content_db != null and content_db.has_method("has_recipe") and content_db.has_recipe(recipe_id):
		return content_db.get_recipe(recipe_id)

	return FALLBACK_RECIPES.get(recipe_id, {})


func _get_all_recipe_ids() -> Array:
	var content_db := _get_content_db()
	if content_db != null:
		var content_recipes = content_db.get("recipes")
		if content_recipes is Dictionary:
			return content_recipes.keys()

	return FALLBACK_RECIPES.keys()


func _normalize_cost(cost_data) -> Array:
	var costs := []

	if cost_data is Dictionary:
		for item_id in cost_data.keys():
			var amount := int(cost_data[item_id])
			if amount > 0:
				costs.append({
					"resource": str(item_id),
					"amount": amount,
				})
		return costs

	if cost_data is Array:
		for cost_entry in cost_data:
			if not cost_entry is Dictionary:
				continue

			var item_id := str(cost_entry.get("resource", cost_entry.get("item_id", ""))).to_lower()
			var amount := int(cost_entry.get("amount", 0))
			if item_id.is_empty() or amount <= 0:
				continue

			costs.append({
				"resource": item_id,
				"amount": amount,
			})

	return costs


func _get_content_db() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null

	return main_loop.root.get_node_or_null("ContentDB")
