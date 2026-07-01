extends Node

const ITEMS_PATH := "res://data/items.json"
const RESOURCES_PATH := "res://data/resources.json"
const MONSTERS_PATH := "res://data/monsters.json"
const RECIPES_PATH := "res://data/recipes.json"
const TERRAIN_TYPES_PATH := "res://data/terrain_types.json"
const NPCS_PATH := "res://data/npcs.json"
const SPRITES_PATH := "res://data/sprites.json"
const ANIMATION_SETS_PATH := "res://data/animation_sets.json"
const CHARACTERS_PATH := "res://data/characters.json"
const TIERS_PATH := "res://data/tiers.json"
const PLAYER_TUNING_PATH := "res://data/player_tuning.json"

var items := {}
var resources := {}
var monsters := {}
var recipes := {}
var terrain_types := {}
var npcs := {}
var sprites := {}
var animation_sets := {}
var characters := {}
var tiers := {}
var player_tuning := {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	items = _load_json_dictionary(ITEMS_PATH)
	resources = _load_json_dictionary(RESOURCES_PATH)
	monsters = _load_json_dictionary(MONSTERS_PATH)
	recipes = _load_json_dictionary(RECIPES_PATH)
	terrain_types = _load_json_dictionary(TERRAIN_TYPES_PATH)
	npcs = _load_json_dictionary(NPCS_PATH)
	sprites = _load_json_dictionary(SPRITES_PATH)
	animation_sets = _load_json_dictionary(ANIMATION_SETS_PATH)
	characters = _load_json_dictionary(CHARACTERS_PATH)
	tiers = _load_json_dictionary(TIERS_PATH)
	player_tuning = _load_json_dictionary(PLAYER_TUNING_PATH)

	if not items.is_empty() and not resources.is_empty() and not monsters.is_empty() and not recipes.is_empty() and not terrain_types.is_empty() and not npcs.is_empty():
		print("ContentDB loaded successfully")


func get_item(id: String) -> Dictionary:
	return _get_entry(items, id, "item")


func get_resource(id: String) -> Dictionary:
	return _get_entry(resources, id, "resource")


func get_monster(id: String) -> Dictionary:
	return _get_entry(monsters, id, "monster")


func get_recipe(id: String) -> Dictionary:
	return _get_entry(recipes, id, "recipe")


func get_terrain_type(id: String) -> Dictionary:
	return _get_entry(terrain_types, id, "terrain type")


func get_npc(id: String) -> Dictionary:
	return _get_entry(npcs, id, "npc")


func get_sprite(id: String) -> Dictionary:
	return _get_entry(sprites, id, "sprite")


func get_animation_set(id: String) -> Dictionary:
	return _get_entry(animation_sets, id, "animation set")


func get_character(id: String) -> Dictionary:
	return _get_entry(characters, id, "character")


func get_tier(tier_id: int) -> Dictionary:
	return _get_entry(tiers, str(tier_id), "tier")


func get_player_tuning(id: String = "default") -> Dictionary:
	return _get_entry(player_tuning, id, "player tuning")


func get_all_terrain_types() -> Dictionary:
	return terrain_types.duplicate(true)


func get_all_npcs() -> Dictionary:
	return npcs.duplicate(true)


func get_all_monsters() -> Dictionary:
	return monsters.duplicate(true)


func get_all_resources() -> Dictionary:
	return resources.duplicate(true)


func get_all_sprites() -> Dictionary:
	return sprites.duplicate(true)


func get_all_animation_sets() -> Dictionary:
	return animation_sets.duplicate(true)


func get_all_items() -> Dictionary:
	return items.duplicate(true)


func get_all_characters() -> Dictionary:
	return characters.duplicate(true)


func get_all_tiers() -> Dictionary:
	return tiers.duplicate(true)


func get_all_player_tuning() -> Dictionary:
	return player_tuning.duplicate(true)


func has_item(id: String) -> bool:
	return items.has(id)


func has_resource(id: String) -> bool:
	return resources.has(id)


func has_monster(id: String) -> bool:
	return monsters.has(id)


func has_recipe(id: String) -> bool:
	return recipes.has(id)


func has_terrain_type(id: String) -> bool:
	return terrain_types.has(id)


func has_npc(id: String) -> bool:
	return npcs.has(id)


func has_sprite(id: String) -> bool:
	return sprites.has(id)


func has_animation_set(id: String) -> bool:
	return animation_sets.has(id)


func has_character(id: String) -> bool:
	return characters.has(id)


func has_tier(tier_id: int) -> bool:
	return tiers.has(str(tier_id))


func has_player_tuning(id: String = "default") -> bool:
	return player_tuning.has(id)


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ContentDB could not find JSON file: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ContentDB could not open JSON file: %s" % path)
		return {}

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("ContentDB found invalid JSON in %s: %s" % [path, json.get_error_message()])
		return {}

	if not json.data is Dictionary:
		push_error("ContentDB expected a JSON object in file: %s" % path)
		return {}

	return json.data


func _get_entry(collection: Dictionary, id: String, content_type: String) -> Dictionary:
	if collection.has(id):
		return collection[id]

	push_error("ContentDB could not find %s id: %s" % [content_type, id])
	return {}
