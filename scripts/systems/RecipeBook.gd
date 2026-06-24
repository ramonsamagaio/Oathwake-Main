extends RefCounted

const WALL_ID := "Wall"
const CAMPFIRE_ID := "Campfire"
const WORKBENCH_ID := "Workbench"

var recipes := {
	WALL_ID: {
		"id": WALL_ID,
		"display_name": "Wall",
		"cost": [
			{"resource": "Wood", "amount": 1},
		],
		"scene_path": "",
		"build_key": KEY_1,
	},
	CAMPFIRE_ID: {
		"id": CAMPFIRE_ID,
		"display_name": "Campfire",
		"cost": [
			{"resource": "Wood", "amount": 3},
			{"resource": "Stone", "amount": 1},
		],
		"scene_path": "",
		"build_key": KEY_2,
	},
	WORKBENCH_ID: {
		"id": WORKBENCH_ID,
		"display_name": "Workbench",
		"cost": [
			{"resource": "Wood", "amount": 5},
			{"resource": "Stone", "amount": 2},
		],
		"scene_path": "",
		"build_key": KEY_3,
	},
}


func has_recipe(recipe_id: String) -> bool:
	return recipes.has(recipe_id)


func get_recipe(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {})


func get_display_name(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("display_name", recipe_id))


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
	for recipe_id in recipes.keys():
		if get_build_key(str(recipe_id)) == keycode:
			return str(recipe_id)

	return ""


func get_all_recipes() -> Array:
	return recipes.values()
