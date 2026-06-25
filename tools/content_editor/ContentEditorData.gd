extends RefCounted

const SECTION_ITEMS := "items"
const SECTION_RESOURCES := "resources"
const SECTION_MONSTERS := "monsters"
const SECTION_RECIPES := "recipes"
const SECTION_TERRAIN_TYPES := "terrain_types"
const SECTION_NPCS := "npcs"
const SECTION_SPRITES := "sprites"
const SECTION_ANIMATION_SETS := "animation_sets"
const SECTION_CHARACTERS := "characters"
const SECTION_TIERS := "tiers"
const SECTION_COMBAT_PREVIEW := "combat_preview"

const SECTIONS := [
	SECTION_ITEMS,
	SECTION_RESOURCES,
	SECTION_MONSTERS,
	SECTION_RECIPES,
	SECTION_TERRAIN_TYPES,
	SECTION_NPCS,
	SECTION_SPRITES,
	SECTION_ANIMATION_SETS,
	SECTION_CHARACTERS,
	SECTION_TIERS,
	SECTION_COMBAT_PREVIEW,
]

const SECTION_LABELS := {
	SECTION_ITEMS: "Items",
	SECTION_RESOURCES: "Resources",
	SECTION_MONSTERS: "Monsters",
	SECTION_RECIPES: "Recipes",
	SECTION_TERRAIN_TYPES: "Terrain Types",
	SECTION_NPCS: "NPCs",
	SECTION_SPRITES: "Sprites",
	SECTION_ANIMATION_SETS: "Animation Sets",
	SECTION_CHARACTERS: "Characters",
	SECTION_TIERS: "Tiers",
	SECTION_COMBAT_PREVIEW: "Combat Preview",
}

const SECTION_PATHS := {
	SECTION_ITEMS: "res://data/items.json",
	SECTION_RESOURCES: "res://data/resources.json",
	SECTION_MONSTERS: "res://data/monsters.json",
	SECTION_RECIPES: "res://data/recipes.json",
	SECTION_TERRAIN_TYPES: "res://data/terrain_types.json",
	SECTION_NPCS: "res://data/npcs.json",
	SECTION_SPRITES: "res://data/sprites.json",
	SECTION_ANIMATION_SETS: "res://data/animation_sets.json",
	SECTION_CHARACTERS: "res://data/characters.json",
	SECTION_TIERS: "res://data/tiers.json",
}

var content := {}


func load_all() -> String:
	for section in SECTIONS:
		if not SECTION_PATHS.has(section):
			continue

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
	var backup_error := _backup_file(path)
	if not backup_error.is_empty():
		return backup_error

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save file: %s" % path

	file.store_string(JSON.stringify(get_section_data(section), "\t") + "\n")
	return ""


func get_section_label(section: String) -> String:
	return str(SECTION_LABELS.get(section, section.capitalize()))


func get_section_path(section: String) -> String:
	return str(SECTION_PATHS.get(section, ""))


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

	if record_id != sanitize_id(record_id):
		return "ID must use lowercase_with_underscore."

	var sprite_error := _validate_optional_sprite_id(record)
	if not sprite_error.is_empty():
		return sprite_error

	var item_type := str(record.get("item_type", "material"))
	if item_type == "material":
		var tier := int(record.get("tier", 0))
		if tier < 1 or tier > 7:
			return "Material Tier must be between 1 and 7."
		if str(record.get("material_family", "")).is_empty():
			return "Material Family is required for material items."

	if item_type == "weapon" or item_type == "tool":
		var tool_tier := int(record.get("tool_tier", 0))
		if tool_tier < 1 or tool_tier > 7:
			return "Tool Tier must be between 1 and 7."
		if int(record.get("tool_damage", -1)) < 0:
			return "Tool Damage must be greater than or equal to 0."
		if float(record.get("tool_speed", 0.0)) <= 0.0:
			return "Tool Speed must be greater than 0."
		if int(record.get("durability", -1)) < 0:
			return "Durability must be greater than or equal to 0."
		if float(record.get("crit_chance", -1.0)) < 0.0 or float(record.get("crit_chance", 0.0)) > 1.0:
			return "Crit Chance must be between 0 and 1."
		if float(record.get("crit_power", 0.0)) < 1.0:
			return "Crit Power must be greater than or equal to 1."

		var combat_value: Variant = record.get("combat", {})
		if not combat_value is Dictionary:
			return "Combat must be a dictionary."
		var combat: Dictionary = combat_value

		if int(combat.get("attack_power", -1)) < 0:
			return "Attack Power must be greater than or equal to 0."
		if float(combat.get("attack_variance", -1.0)) < 0.0 or float(combat.get("attack_variance", 0.0)) > 1.0:
			return "Attack Variance must be between 0 and 1."
		if float(combat.get("crit_chance_bonus", -1.0)) < 0.0 or float(combat.get("crit_chance_bonus", 0.0)) > 1.0:
			return "Crit Chance Bonus must be between 0 and 1."
		if float(combat.get("crit_damage_bonus", -1.0)) < 0.0:
			return "Crit Damage Bonus must be greater than or equal to 0."

		var stat_scaling_value: Variant = combat.get("stat_scaling", {})
		if stat_scaling_value is Dictionary:
			var stat_scaling: Dictionary = stat_scaling_value
			for stat_name in stat_scaling.keys():
				if float(stat_scaling[stat_name]) < 0.0:
					return "%s Scaling must be greater than or equal to 0." % str(stat_name).to_upper()

		var resource_damage_value: Variant = combat.get("resource_damage", {})
		if resource_damage_value is Dictionary:
			var resource_damage: Dictionary = resource_damage_value
			for resource_type_id in resource_damage.keys():
				var clean_resource_id := str(resource_type_id)
				if clean_resource_id.is_empty() or not has_record(SECTION_RESOURCES, clean_resource_id):
					return "Resource Damage references an unknown resource: %s" % clean_resource_id
				if int(resource_damage[resource_type_id]) < 0:
					return "Resource Damage must be greater than or equal to 0."

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

	var resource_tier := int(record.get("resource_tier", 0))
	if resource_tier < 1 or resource_tier > 7:
		return "Resource Tier must be between 1 and 7."
	if int(record.get("resource_hp", 0)) <= 0:
		return "Resource HP must be greater than 0."
	if str(record.get("required_tool_type", "")).is_empty():
		return "Required Tool Type is required."
	var base_drops_error := _validate_drop_rows(record.get("base_drops", []), true)
	if not base_drops_error.is_empty():
		return "Base Drops: %s" % base_drops_error
	var rare_drops_error := _validate_drop_rows(record.get("rare_drops", []), false)
	if not rare_drops_error.is_empty():
		return "Rare Drops: %s" % rare_drops_error

	var sprite_error := _validate_optional_sprite_id(record)
	if not sprite_error.is_empty():
		return sprite_error

	return ""


func _validate_drop_rows(drop_rows_value: Variant, require_one: bool) -> String:
	if not drop_rows_value is Array:
		return "must be a list."

	var drop_rows: Array = drop_rows_value
	if require_one and drop_rows.is_empty():
		return "must have at least one drop."

	for drop_entry in drop_rows:
		if not drop_entry is Dictionary:
			return "each drop must be a dictionary."

		var drop_data: Dictionary = drop_entry
		var item_id := str(drop_data.get("item_id", ""))
		if item_id.is_empty() or not has_record(SECTION_ITEMS, item_id):
			return "drop item_id must reference an existing item: %s" % item_id
		if int(drop_data.get("min_amount", 0)) < 1:
			return "min_amount must be greater than or equal to 1."
		if int(drop_data.get("max_amount", 0)) < int(drop_data.get("min_amount", 1)):
			return "max_amount must be greater than or equal to min_amount."
		if float(drop_data.get("chance", -1.0)) < 0.0 or float(drop_data.get("chance", 0.0)) > 1.0:
			return "chance must be between 0 and 1."

	return ""


func validate_tier(record_id: String, original_id: String, record: Dictionary) -> String:
	var tier_id := int(record.get("id", 0))
	if tier_id < 1 or tier_id > 99:
		return "Tier ID must be an integer between 1 and 99."

	var clean_record_id := str(tier_id)
	if has_record(SECTION_TIERS, clean_record_id) and clean_record_id != original_id:
		return "Tier ID already exists."

	if str(record.get("display_name", "")).strip_edges().is_empty():
		return "Display Name is required."

	return ""


func validate_monster(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_MONSTERS, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if int(record.get("max_health", 0)) < 1:
		return "Max Health must be an integer greater than or equal to 1."
	if float(record.get("move_speed", -1.0)) < 0.0:
		return "Move Speed must be greater than or equal to 0."
	if int(record.get("damage", -1)) < 0:
		return "Damage must be greater than or equal to 0."
	if float(record.get("attack_cooldown", -1.0)) < 0.0:
		return "Attack Cooldown must be greater than or equal to 0."
	if float(record.get("spawn_time_seconds", -1.0)) < 0.0:
		return "Spawn Time Seconds must be greater than or equal to 0."

	var spawn_tiles = record.get("spawn_tiles", [])
	if not spawn_tiles is Array:
		return "Spawn Tiles must be a list."

	var sprite_error := _validate_optional_sprite_id(record)
	if not sprite_error.is_empty():
		return sprite_error

	return ""


func validate_recipe(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_RECIPES, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if str(record.get("display_name", "")).strip_edges().is_empty():
		return "Display Name cannot be empty."

	if str(record.get("type", "")).strip_edges().is_empty():
		return "Type cannot be empty."

	var sprite_error := _validate_optional_sprite_id(record)
	if not sprite_error.is_empty():
		return sprite_error

	return ""


func validate_terrain_type(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_TERRAIN_TYPES, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if record_id != original_id and not find_terrain_type_usage(original_id).is_empty():
		return "Cannot rename terrain type because it is used by: %s" % _join_strings(find_terrain_type_usage(original_id), ", ")

	var sprite_error := _validate_optional_sprite_id(record)
	if not sprite_error.is_empty():
		return sprite_error

	return ""


func validate_npc(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_NPCS, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if int(record.get("max_health", 0)) < 1:
		return "Max Health must be an integer greater than or equal to 1."

	if float(record.get("move_speed", -1.0)) < 0.0:
		return "Move Speed must be greater than or equal to 0."

	var preferred_workstation := str(record.get("preferred_workstation", ""))
	if not preferred_workstation.is_empty():
		if not has_record(SECTION_RECIPES, preferred_workstation):
			return "Preferred Workstation must reference an existing recipe."

		var recipe := get_record(SECTION_RECIPES, preferred_workstation)
		if str(recipe.get("type", "")) != "building":
			return "Preferred Workstation must reference a building recipe."

	var production = record.get("production", [])
	if not production is Array:
		return "Production must be a list."

	for production_entry in production:
		if not production_entry is Dictionary:
			return "Production entries must be dictionaries."

		var item_id := str(production_entry.get("item_id", ""))
		if item_id.is_empty() or not has_record(SECTION_ITEMS, item_id):
			return "Production item_id must reference an existing item."

		if int(production_entry.get("amount", 0)) < 1:
			return "Production amount must be greater than or equal to 1."

		if float(production_entry.get("interval_seconds", 0.0)) <= 0.0:
			return "Production interval_seconds must be greater than 0."

	var sprite_error := _validate_optional_sprite_id(record)
	if not sprite_error.is_empty():
		return sprite_error

	return ""


func validate_sprite(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_SPRITES, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	var sprite_type := str(record.get("type", "single_sprite"))
	if not ["single_sprite", "sprite_sheet"].has(sprite_type):
		return "Type must be single_sprite or sprite_sheet."

	var texture_path := str(record.get("texture_path", ""))
	if not texture_path.is_empty() and not FileAccess.file_exists(texture_path):
		return "Texture Path must point to an existing file."

	var texture: Texture2D = null
	if not texture_path.is_empty():
		var loaded_texture := load(texture_path)
		if not loaded_texture is Texture2D:
			return "Texture Path must load a Texture2D."
		texture = loaded_texture as Texture2D

	var category := str(record.get("category", ""))
	if category.is_empty():
		return "Category cannot be empty."

	var tags = record.get("tags", [])
	if not tags is Array:
		return "Tags must be a list."

	var region = record.get("region", {})
	if not region is Dictionary:
		return "Region must be a dictionary."

	if int(region.get("w", 0)) < 1 or int(region.get("h", 0)) < 1:
		return "Region width and height must be greater than or equal to 1."

	var frame_size = record.get("frame_size", {})
	if not frame_size is Dictionary:
		return "Frame Size must be a dictionary."

	if int(frame_size.get("w", 0)) < 1 or int(frame_size.get("h", 0)) < 1:
		return "Frame Size width and height must be greater than or equal to 1."

	if sprite_type == "sprite_sheet":
		if texture_path.is_empty():
			return "Texture Path is required for sprite_sheet."

		var frame_width := int(record.get("frame_width", frame_size.get("w", 0)))
		var frame_height := int(record.get("frame_height", frame_size.get("h", 0)))
		var columns := int(record.get("columns", 0))
		var rows := int(record.get("rows", 0))
		var total_frames := int(record.get("total_frames", 0))

		if frame_width < 1 or frame_height < 1:
			return "Frame Width and Frame Height must be greater than or equal to 1."
		if columns < 1 or rows < 1 or total_frames < 1:
			return "Columns, Rows, and Total Frames must be greater than or equal to 1."

		var texture_size := texture.get_size()
		var texture_width := int(texture_size.x)
		var texture_height := int(texture_size.y)
		if texture_width % frame_width != 0:
			return "Texture width must be divisible by Frame Width."
		if texture_height % frame_height != 0:
			return "Texture height must be divisible by Frame Height."

		var expected_columns := int(texture_width / frame_width)
		var expected_rows := int(texture_height / frame_height)
		var expected_total_frames := expected_columns * expected_rows
		if columns != expected_columns:
			return "Columns must match the texture width divided by Frame Width."
		if rows != expected_rows:
			return "Rows must match the texture height divided by Frame Height."
		if total_frames != expected_total_frames:
			return "Total Frames must be Columns multiplied by Rows."

	return ""


func validate_animation_set(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_ANIMATION_SETS, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if str(record.get("display_name", "")).strip_edges().is_empty():
		return "Display Name cannot be empty."

	var sprite_sheet_id := str(record.get("sprite_sheet_id", ""))
	if sprite_sheet_id.is_empty() or not has_record(SECTION_SPRITES, sprite_sheet_id):
		return "Sprite Sheet must reference an existing sprite."

	var sprite_record := get_record(SECTION_SPRITES, sprite_sheet_id)
	if str(sprite_record.get("type", "single_sprite")) != "sprite_sheet":
		return "Sprite Sheet must reference a sprite with type sprite_sheet."

	var anchor = record.get("anchor", {})
	if not anchor is Dictionary:
		return "Anchor must be a dictionary."

	var animations = record.get("animations", {})
	if not animations is Dictionary:
		return "Animations must be a dictionary."

	var total_frames := int(sprite_record.get("total_frames", 0))
	for animation_name in animations.keys():
		var animation_data = animations[animation_name]
		if not animation_data is Dictionary:
			return "Animation '%s' must be a dictionary." % str(animation_name)

		if str(animation_name).strip_edges().is_empty():
			return "Animation name cannot be empty."

		if float(animation_data.get("fps", 0.0)) <= 0.0:
			return "Animation '%s' FPS must be greater than 0." % str(animation_name)

		if animation_data.has("frame_count") and int(animation_data.get("frame_count", 0)) < 1:
			return "Animation '%s' frame_count must be greater than or equal to 1." % str(animation_name)

		var frames = animation_data.get("frames", [])
		if not frames is Array:
			return "Animation '%s' frames must be a list." % str(animation_name)

		for frame in frames:
			var frame_index := int(frame)
			if frame_index < 0 or frame_index >= total_frames:
				return "Animation '%s' has frame %d outside 0-%d." % [str(animation_name), frame_index, total_frames - 1]

	return ""


func validate_character(record_id: String, original_id: String, record: Dictionary) -> String:
	var id_error := _validate_record_id(SECTION_CHARACTERS, record_id, original_id)
	if not id_error.is_empty():
		return id_error

	if str(record.get("display_name", "")).strip_edges().is_empty():
		return "Display Name cannot be empty."

	var sprite_sheet_id := str(record.get("sprite_sheet_id", ""))
	if sprite_sheet_id.is_empty() or not has_record(SECTION_SPRITES, sprite_sheet_id):
		return "Sprite Sheet must reference an existing sprite."

	var sprite_record := get_record(SECTION_SPRITES, sprite_sheet_id)
	if str(sprite_record.get("type", "single_sprite")) != "sprite_sheet":
		return "Sprite Sheet must reference a sprite with type sprite_sheet."

	var animation_set_id := str(record.get("animation_set_id", ""))
	if animation_set_id.is_empty():
		return "Animation Set cannot be empty."

	if has_record(SECTION_ANIMATION_SETS, animation_set_id):
		var animation_set_record := get_record(SECTION_ANIMATION_SETS, animation_set_id)
		if str(animation_set_record.get("sprite_sheet_id", "")) != sprite_sheet_id:
			return "Animation Set must use the selected Sprite Sheet."

	return ""


func find_item_usage(item_id: String) -> Array:
	return find_item_usages(item_id)


func find_item_usages(item_id: String) -> Array:
	var usages := []
	_append_resource_item_usage(usages, item_id)
	_append_monster_item_usage(usages, item_id)
	_append_recipe_item_usage(usages, item_id)
	return usages


func find_terrain_type_usage(terrain_type_id: String) -> Array:
	var usages := []
	var monsters := get_section_data(SECTION_MONSTERS)

	for monster_id in monsters.keys():
		var monster_data = monsters[monster_id]
		if not monster_data is Dictionary:
			continue

		var spawn_tiles = monster_data.get("spawn_tiles", [])
		if spawn_tiles is Array and spawn_tiles.has(terrain_type_id):
			usages.append("monster %s spawn_tiles" % monster_id)

	return usages


func find_sprite_usage(sprite_id: String) -> Array:
	return find_sprite_usages(sprite_id)


func find_sprite_usages(sprite_id: String) -> Array:
	var usages := []
	_append_sprite_usage_in_section(usages, SECTION_ITEMS, sprite_id)
	_append_sprite_usage_in_section(usages, SECTION_MONSTERS, sprite_id)
	_append_sprite_usage_in_section(usages, SECTION_RESOURCES, sprite_id)
	_append_sprite_usage_in_section(usages, SECTION_RECIPES, sprite_id)
	_append_sprite_usage_in_section(usages, SECTION_TERRAIN_TYPES, sprite_id)
	_append_animation_set_sprite_usage(usages, sprite_id)
	return usages


func find_recipe_usages(recipe_id: String) -> Array:
	var usages := []
	if [
		"wall",
		"campfire",
		"workbench",
		"axe",
		"pickaxe",
		"bed",
	].has(recipe_id):
		usages.append("essential gameplay recipe")

	var npcs := get_section_data(SECTION_NPCS)
	for npc_id in npcs.keys():
		var npc_data = npcs[npc_id]
		if npc_data is Dictionary and str(npc_data.get("preferred_workstation", "")) == recipe_id:
			usages.append("npc %s preferred_workstation" % npc_id)

	return usages


func find_monster_usages(_monster_id: String) -> Array:
	return []


func find_resource_usages(resource_id: String) -> Array:
	var usages := []
	usages.append("ResourceNode scene references may use resource_type_id '%s'; delete is blocked for now" % resource_id)
	return usages


func find_animation_set_usages(_animation_set_id: String) -> Array:
	var usages := []
	var characters := get_section_data(SECTION_CHARACTERS)
	for character_id in characters.keys():
		var character_data = characters[character_id]
		if character_data is Dictionary and str(character_data.get("animation_set_id", "")) == _animation_set_id:
			usages.append("character %s animation_set_id" % character_id)

	return usages


func _validate_record_id(section: String, record_id: String, original_id: String) -> String:
	if record_id.is_empty():
		return "ID cannot be empty."

	if record_id != sanitize_id(record_id):
		return "ID must use lowercase letters, numbers, and underscores."

	if record_id != original_id and has_record(section, record_id):
		return "ID already exists: %s" % record_id

	return ""


func _validate_optional_sprite_id(record: Dictionary) -> String:
	var sprite_id := str(record.get("sprite_id", ""))
	if sprite_id.is_empty():
		return ""

	if not has_record(SECTION_SPRITES, sprite_id):
		return "Sprite must reference an existing sprite."

	return ""


func _append_sprite_usage_in_section(usages: Array, section: String, sprite_id: String) -> void:
	var section_data := get_section_data(section)
	for record_id in section_data.keys():
		var record_data = section_data[record_id]
		if record_data is Dictionary and str(record_data.get("sprite_id", "")) == sprite_id:
			usages.append("%s %s sprite_id" % [section, record_id])


func _append_animation_set_sprite_usage(usages: Array, sprite_id: String) -> void:
	var animation_sets := get_section_data(SECTION_ANIMATION_SETS)
	for animation_set_id in animation_sets.keys():
		var record_data = animation_sets[animation_set_id]
		if record_data is Dictionary and str(record_data.get("sprite_sheet_id", "")) == sprite_id:
			usages.append("animation set %s sprite_sheet_id" % animation_set_id)


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

		if str(recipe_data.get("output_item_id", "")) == item_id:
			usages.append("recipe %s output_item_id" % recipe_id)
			continue

		if cost is Array:
			for cost_entry in cost:
				if cost_entry is Dictionary and str(cost_entry.get("item_id", cost_entry.get("resource", ""))).to_lower() == item_id:
					usages.append("recipe %s cost" % recipe_id)


func _backup_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""

	var backup_dir := "user://content_backups"
	var dir_error := DirAccess.make_dir_recursive_absolute(backup_dir)
	if dir_error != OK:
		return "Could not create content backup directory."

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file_name := path.get_file()
	var backup_path := "%s/%s_%s.bak" % [backup_dir, file_name, timestamp]
	var copy_error := DirAccess.copy_absolute(path, backup_path)
	if copy_error != OK:
		return "Could not create backup for %s" % path

	return ""


func _join_strings(values: Array, separator: String) -> String:
	var text := ""

	for value in values:
		if not text.is_empty():
			text += separator

		text += str(value)

	return text
