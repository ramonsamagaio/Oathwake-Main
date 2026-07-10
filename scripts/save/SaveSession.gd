## Stores only the link between a menu slot, a player profile and a world save.
class_name SaveSession
extends RefCounted

const SCHEMA_VERSION := 1
const SavePathsScript := preload("res://scripts/save/SavePaths.gd")


func create_default_data(slot_id: String, player_id: String, world_id: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"slot_id": slot_id,
		"player_id": player_id,
		"world_id": world_id,
		"last_played_at": "",
	}


func save_session(data: Dictionary) -> String:
	var validation := validate(data)
	if not bool(validation.get("ok", false)):
		return str(validation.get("error", "Invalid save session."))
	var directory_error := SavePathsScript.ensure_save_dirs()
	if not directory_error.is_empty():
		return directory_error
	var path := SavePathsScript.get_session_path(str(data["slot_id"]))
	if path.is_empty():
		return "Invalid slot id."
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save session to %s" % path
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return ""


func load_session(slot_id: String) -> Dictionary:
	var path := SavePathsScript.get_session_path(slot_id)
	if path.is_empty():
		return {"ok": false, "error": "Invalid slot id.", "data": {}}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "No session found at %s" % path, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not open save session.", "data": {}}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"ok": false, "error": "Could not parse save session JSON.", "data": {}}
	var validation := validate(json.data)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": str(validation.get("error", "Invalid save session.")), "data": {}}
	return {"ok": true, "error": "", "data": json.data}


func validate(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "error": "Save session must be a JSON object."}
	var session: Dictionary = data
	for key in ["schema_version", "slot_id", "player_id", "world_id", "last_played_at"]:
		if not session.has(key):
			return {"ok": false, "error": "Save session missing required field: %s" % key}
	if int(session["schema_version"]) != SCHEMA_VERSION:
		return {"ok": false, "error": "Unsupported save session schema version."}
	for key in ["slot_id", "player_id", "world_id"]:
		if str(session[key]).strip_edges().is_empty():
			return {"ok": false, "error": "Save session has an empty %s." % key}
	return {"ok": true, "error": ""}
