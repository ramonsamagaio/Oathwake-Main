## Owns persistent player-profile data without depending on the legacy slot save.
class_name PlayerProfileSave
extends RefCounted

const SCHEMA_VERSION := 1
const SavePathsScript := preload("res://scripts/save/SavePaths.gd")


func create_default_data(player_id: String, display_name := "Player") -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"player_id": player_id,
		"display_name": display_name,
		"level": 1,
		"current_xp": 0,
		"xp_to_next_level": 30,
		"health": 100,
		"max_health": 100,
		"inventory_slots": [],
		"equipment_slots": {},
		"unlocked_tools": ["Hands"],
		"current_tool": "Hands",
		"hotbar_shortcuts": [],
		"selected_hotbar_slot": 0,
		"player_stats": {
			"base_stats": {},
		},
	}


func serialize_player(player: Node, runtime_data: Dictionary = {}) -> Dictionary:
	var player_id := str(runtime_data.get("player_id", "player_001"))
	var data := create_default_data(player_id, str(runtime_data.get("display_name", "Player")))
	for key in data.keys():
		if runtime_data.has(key):
			data[key] = runtime_data[key]

	if player != null:
		data["level"] = int(player.get("level"))
		data["current_xp"] = int(player.get("current_xp"))
		data["xp_to_next_level"] = int(player.get("xp_to_next_level"))
		data["health"] = int(player.get("health"))
		data["max_health"] = int(player.get("max_health"))
		if player.has_method("get_unlocked_tools"):
			data["unlocked_tools"] = player.get_unlocked_tools()
		if player.has_method("get_current_tool"):
			data["current_tool"] = player.get_current_tool()
		if player.has_method("get_debug_base_stats"):
			data["player_stats"] = {"base_stats": player.get_debug_base_stats()}

	data["schema_version"] = SCHEMA_VERSION
	return data


func validate(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "error": "Player profile must be a JSON object."}
	var profile: Dictionary = data
	for key in ["schema_version", "player_id", "display_name", "level", "current_xp", "xp_to_next_level", "health", "max_health", "inventory_slots", "equipment_slots", "unlocked_tools", "current_tool", "hotbar_shortcuts", "selected_hotbar_slot", "player_stats"]:
		if not profile.has(key):
			return {"ok": false, "error": "Player profile missing required field: %s" % key}
	if int(profile["schema_version"]) != SCHEMA_VERSION:
		return {"ok": false, "error": "Unsupported player profile schema version."}
	if str(profile["player_id"]).strip_edges().is_empty():
		return {"ok": false, "error": "Player profile has an empty player_id."}
	if not profile["inventory_slots"] is Array or not profile["equipment_slots"] is Dictionary:
		return {"ok": false, "error": "Player profile inventory or equipment has an invalid type."}
	if not profile["unlocked_tools"] is Array or not profile["hotbar_shortcuts"] is Array or not profile["player_stats"] is Dictionary:
		return {"ok": false, "error": "Player profile has invalid collection data."}
	return {"ok": true, "error": ""}


func save_profile(data: Dictionary) -> String:
	var validation := validate(data)
	if not bool(validation.get("ok", false)):
		return str(validation.get("error", "Invalid player profile."))
	var directory_error := SavePathsScript.ensure_save_dirs()
	if not directory_error.is_empty():
		return directory_error
	var path := SavePathsScript.get_player_path(str(data["player_id"]))
	if path.is_empty():
		return "Invalid player id."
	return _write_json(path, data)


func load_profile(player_id: String) -> Dictionary:
	var path := SavePathsScript.get_player_path(player_id)
	if path.is_empty():
		return {"ok": false, "error": "Invalid player id.", "data": {}}
	return _load_json(path)


func _write_json(path: String, data: Dictionary) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save player profile to %s" % path
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return ""


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "No player profile found at %s" % path, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not open player profile.", "data": {}}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": "Could not parse player profile JSON.", "data": {}}
	var validation := validate(json.data)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": str(validation.get("error", "Invalid player profile.")), "data": {}}
	return {"ok": true, "error": "", "data": json.data}
