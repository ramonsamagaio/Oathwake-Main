## Owns persistent world data; map state remains grouped by stable map id.
class_name WorldSave
extends RefCounted

const SCHEMA_VERSION := 1
const SavePathsScript := preload("res://scripts/save/SavePaths.gd")


func create_default_data(world_id: String, world_name := "New World", seed := 0) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"world_id": world_id,
		"world_name": world_name,
		"seed": seed,
		"current_map_id": "start_area",
		"time": {"time_of_day": 0.0},
		"maps": {},
		"player_states": {},
		"settlement": {},
	}


func serialize_world(world_id: String, runtime_data: Dictionary = {}) -> Dictionary:
	var data := create_default_data(world_id, str(runtime_data.get("world_name", "New World")), int(runtime_data.get("seed", 0)))
	for key in data.keys():
		if runtime_data.has(key):
			data[key] = runtime_data[key]
	data["schema_version"] = SCHEMA_VERSION
	data["world_id"] = world_id
	return data


func validate(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "error": "World save must be a JSON object."}
	var world_data: Dictionary = data
	for key in ["schema_version", "world_id", "world_name", "seed", "current_map_id", "time", "maps", "player_states", "settlement"]:
		if not world_data.has(key):
			return {"ok": false, "error": "World save missing required field: %s" % key}
	if int(world_data["schema_version"]) != SCHEMA_VERSION:
		return {"ok": false, "error": "Unsupported world save schema version."}
	if str(world_data["world_id"]).strip_edges().is_empty():
		return {"ok": false, "error": "World save has an empty world_id."}
	if not world_data["time"] is Dictionary or not world_data["maps"] is Dictionary or not world_data["player_states"] is Dictionary or not world_data["settlement"] is Dictionary:
		return {"ok": false, "error": "World save has invalid structured data."}
	return {"ok": true, "error": ""}


func save_world(data: Dictionary) -> String:
	var validation := validate(data)
	if not bool(validation.get("ok", false)):
		return str(validation.get("error", "Invalid world save."))
	var world_id := str(data["world_id"])
	var directory_error := SavePathsScript.ensure_world_dir(world_id)
	if not directory_error.is_empty():
		return directory_error
	var path := SavePathsScript.get_world_path(world_id)
	return _write_json(path, data)


func load_world(world_id: String) -> Dictionary:
	var path := SavePathsScript.get_world_path(world_id)
	if path.is_empty():
		return {"ok": false, "error": "Invalid world id.", "data": {}}
	return _load_json(path)


func _write_json(path: String, data: Dictionary) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save world to %s" % path
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return ""


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "No world save found at %s" % path, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not open world save.", "data": {}}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": "Could not parse world save JSON.", "data": {}}
	var normalized_data := normalize_data(json.data)
	var validation := validate(normalized_data)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": str(validation.get("error", "Invalid world save.")), "data": {}}
	return {"ok": true, "error": "", "data": normalized_data}


func normalize_data(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var world_data: Dictionary = data.duplicate(true)
	var defaults := create_default_data(str(world_data.get("world_id", "world_001")), str(world_data.get("world_name", "New World")), int(world_data.get("seed", 0)))
	for key in defaults.keys():
		if not world_data.has(key):
			world_data[key] = defaults[key]
	return world_data
