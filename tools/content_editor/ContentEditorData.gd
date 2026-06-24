extends RefCounted

const SECTION_ITEMS := "items"
const SECTION_RESOURCES := "resources"
const SECTION_MONSTERS := "monsters"
const SECTION_RECIPES := "recipes"

const SECTIONS := [
	SECTION_ITEMS,
	SECTION_RESOURCES,
	SECTION_MONSTERS,
	SECTION_RECIPES,
]

const SECTION_LABELS := {
	SECTION_ITEMS: "Items",
	SECTION_RESOURCES: "Resources",
	SECTION_MONSTERS: "Monsters",
	SECTION_RECIPES: "Recipes",
}

const SECTION_PATHS := {
	SECTION_ITEMS: "res://data/items.json",
	SECTION_RESOURCES: "res://data/resources.json",
	SECTION_MONSTERS: "res://data/monsters.json",
	SECTION_RECIPES: "res://data/recipes.json",
}

var content := {}


func load_all() -> String:
	for section in SECTIONS:
		var error := load_section(section)
		if not error.is_empty():
			return error

	return ""


func load_section(section: String) -> String:
	if not SECTION_PATHS.has(section):
		return "Unknown content section: %s" % section

	var path := str(SECTION_PATHS[section])
	if not FileAccess.file_exists(path):
		return "File not found: %s" % path

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Could not open file: %s" % path

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		return "Invalid JSON in %s at line %d: %s" % [
			path,
			json.get_error_line(),
			json.get_error_message(),
		]

	if not json.data is Dictionary:
		return "Expected a JSON object in: %s" % path

	content[section] = json.data
	return ""


func save_section(section: String) -> String:
	if not SECTION_PATHS.has(section):
		return "Unknown content section: %s" % section

	if not content.has(section):
		return "No loaded data for section: %s" % section

	# This editor writes to res:// while used inside the Godot editor.
	# A future exported content editor should prefer user://data for writable external content.
	var path := str(SECTION_PATHS[section])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save file: %s" % path

	file.store_string(JSON.stringify(get_section_data(section), "\t") + "\n")
	return ""


func get_section_label(section: String) -> String:
	return str(SECTION_LABELS.get(section, section.capitalize()))


func get_section_data(section: String) -> Dictionary:
	if not content.has(section) or not content[section] is Dictionary:
		return {}

	return content[section] as Dictionary


func get_records(section: String) -> Array:
	var section_data := get_section_data(section)
	var ids := section_data.keys()
	ids.sort()

	var records := []
	for id in ids:
		records.append(get_record(section, str(id)))

	return records


func get_record(section: String, record_id: String) -> Dictionary:
	var section_data := get_section_data(section)
	if not section_data.has(record_id) or not section_data[record_id] is Dictionary:
		return {}

	var record := (section_data[record_id] as Dictionary).duplicate(true)
	record["id"] = record_id
	return record


func has_record(section: String, record_id: String) -> bool:
	return get_section_data(section).has(record_id)


func set_record(section: String, original_id: String, new_id: String, record: Dictionary) -> void:
	var section_data := get_section_data(section)
	var stored_record := record.duplicate(true)
	stored_record.erase("id")

	if not original_id.is_empty() and original_id != new_id:
		section_data.erase(original_id)

	section_data[new_id] = stored_record
	content[section] = section_data


func delete_record(section: String, record_id: String) -> void:
	var section_data := get_section_data(section)
	section_data.erase(record_id)
	content[section] = section_data


func create_unique_id(section: String, base_id: String) -> String:
	var clean_base := sanitize_id(base_id)
	if clean_base.is_empty():
		clean_base = "new_entry"

	if not has_record(section, clean_base):
		return clean_base

	var index := 2
	while has_record(section, "%s_%d" % [clean_base, index]):
		index += 1

	return "%s_%d" % [clean_base, index]


func sanitize_id(raw_id: String) -> String:
	var lower := raw_id.strip_edges().to_lower()
	var result := ""
	var last_was_underscore := false

	for index in range(lower.length()):
		var code := lower.unicode_at(index)
		var is_letter := code >= 97 and code <= 122
		var is_number := code >= 48 and code <= 57
		var is_separator := code == 32 or code == 45 or code == 95

		if is_letter or is_number:
			result += lower.substr(index, 1)
			last_was_underscore = false
		elif is_separator and not result.is_empty() and not last_was_underscore:
			result += "_"
			last_was_underscore = true

	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)

	return result


func validate_item(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_ITEMS, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if int(record.get("stack_size", 0)) < 1:
		return "Stack Size must be an integer greater than or equal to 1."

	return ""


func validate_resource(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_RESOURCES, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if int(record.get("max_health", 0)) < 1:
		return "Max Health must be an integer greater than or equal to 1."

	var drop_item_id := str(record.get("drop_item_id", ""))
	if drop_item_id.is_empty() or not has_record(SECTION_ITEMS, drop_item_id):
		return "Drop Item must reference an existing item."

	if int(record.get("drop_amount", 0)) < 1:
		return "Drop Amount must be an integer greater than or equal to 1."

	if float(record.get("respawn_time_seconds", -1.0)) < 0.0:
		return "Respawn Time Seconds must be greater than or equal to 0."

	return ""


func find_item_usage(item_id: String) -> Array:
	var usages := []
	_append_resource_item_usage(usages, item_id)
	_append_monster_item_usage(usages, item_id)
	_append_recipe_item_usage(usages, item_id)
	return usages


func _validate_record_id(section: String, record_id: String, original_id: String) -> String:
	if record_id.is_empty():
		return "ID cannot be empty."

	if record_id != sanitize_id(record_id):
		return "ID must use lowercase letters, numbers, and underscores."

	if record_id != original_id and has_record(section, record_id):
		return "ID already exists: %s" % record_id

	return ""


func _append_resource_item_usage(usages: Array, item_id: String) -> void:
	var resources := get_section_data(SECTION_RESOURCES)
	for resource_id in resources.keys():
		var resource_data = resources[resource_id]
		if resource_data is Dictionary and str(resource_data.get("drop_item_id", "")) == item_id:
			usages.append("resource %s drop_item_id" % resource_id)


func _append_monster_item_usage(usages: Array, item_id: String) -> void:
	var monsters := get_section_data(SECTION_MONSTERS)
	for monster_id in monsters.keys():
		var monster_data = monsters[monster_id]
		if not monster_data is Dictionary:
			continue

		var loot_table = monster_data.get("loot_table", [])
		if not loot_table is Array:
			continue

		for loot_entry in loot_table:
			if loot_entry is Dictionary and str(loot_entry.get("item_id", "")) == item_id:
				usages.append("monster %s loot_table" % monster_id)


func _append_recipe_item_usage(usages: Array, item_id: String) -> void:
	var recipes := get_section_data(SECTION_RECIPES)
	for recipe_id in recipes.keys():
		var recipe_data = recipes[recipe_id]
		if not recipe_data is Dictionary:
			continue

		var cost = recipe_data.get("cost", {})
		if cost is Dictionary and cost.has(item_id):
			usages.append("recipe %s cost" % recipe_id)
			continue

		if cost is Array:
			for cost_entry in cost:
				if cost_entry is Dictionary and str(cost_entry.get("item_id", cost_entry.get("resource", ""))).to_lower() == item_id:
					usages.append("recipe %s cost" % recipe_id)
