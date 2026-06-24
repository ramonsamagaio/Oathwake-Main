extends RefCounted

var npc_id := ""
var display_name := "NPC"
var max_health := 50
var move_speed := 35.0
var role := "worker"
var preferred_workstation := ""
var production := []
var needs_house := true


func load_from_content_db(id: String, content_db: Node) -> String:
	npc_id = id
	if content_db == null:
		return "NPCData could not find ContentDB."

	if not content_db.has_method("has_npc") or not content_db.has_npc(npc_id):
		return "NPC id does not exist: %s" % npc_id

	var npc_data: Dictionary = content_db.get_npc(npc_id)
	display_name = str(npc_data.get("display_name", display_name))
	max_health = int(npc_data.get("max_health", max_health))
	move_speed = float(npc_data.get("move_speed", move_speed))
	role = str(npc_data.get("role", role))
	preferred_workstation = str(npc_data.get("preferred_workstation", preferred_workstation))
	needs_house = bool(npc_data.get("needs_house", needs_house))

	var loaded_production = npc_data.get("production", [])
	production = loaded_production.duplicate(true) if loaded_production is Array else []

	return validate(content_db)


func validate(content_db: Node) -> String:
	if npc_id.is_empty():
		return "NPC id cannot be empty."

	if max_health < 1:
		return "NPC max_health must be greater than or equal to 1."

	if move_speed < 0.0:
		return "NPC move_speed must be greater than or equal to 0."

	if not preferred_workstation.is_empty():
		if content_db == null or not content_db.has_method("has_recipe") or not content_db.has_recipe(preferred_workstation):
			return "NPC preferred_workstation must reference an existing recipe: %s" % preferred_workstation

		var recipe_data: Dictionary = content_db.get_recipe(preferred_workstation)
		if str(recipe_data.get("type", "")) != "building":
			return "NPC preferred_workstation must reference a building recipe: %s" % preferred_workstation

	for production_entry in production:
		if not production_entry is Dictionary:
			return "NPC production entries must be dictionaries."

		var item_id := str(production_entry.get("item_id", ""))
		if item_id.is_empty():
			return "NPC production item_id cannot be empty."

		if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
			return "NPC production item_id must reference an existing item: %s" % item_id

		if int(production_entry.get("amount", 0)) < 1:
			return "NPC production amount must be greater than or equal to 1."

		if float(production_entry.get("interval_seconds", 0.0)) <= 0.0:
			return "NPC production interval_seconds must be greater than 0."

	return ""


func to_dictionary() -> Dictionary:
	return {
		"id": npc_id,
		"display_name": display_name,
		"max_health": max_health,
		"move_speed": move_speed,
		"role": role,
		"preferred_workstation": preferred_workstation,
		"production": production.duplicate(true),
		"needs_house": needs_house,
	}
