extends Node

const SaveSystem := preload("res://scripts/systems/SaveSystem.gd")
const DEFAULT_SLOT := "slot_1"
const SLOT_PATHS := {
	"slot_1": "user://saves/slot_1.json",
	"slot_2": "user://saves/slot_2.json",
	"slot_3": "user://saves/slot_3.json",
}

var _active_slot := DEFAULT_SLOT
var _save_system := SaveSystem.new()


func set_active_slot(slot_id: String) -> void:
	_active_slot = slot_id if SLOT_PATHS.has(slot_id) else DEFAULT_SLOT


func get_active_slot() -> String:
	return _active_slot if SLOT_PATHS.has(_active_slot) else DEFAULT_SLOT


func get_active_save_path() -> String:
	return str(SLOT_PATHS.get(get_active_slot(), SLOT_PATHS[DEFAULT_SLOT]))


func slot_exists(slot_id: String) -> bool:
	return FileAccess.file_exists(_get_slot_path(slot_id))


func delete_slot(slot_id: String) -> bool:
	var path := _get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return false

	return DirAccess.remove_absolute(path) == OK


func get_slot_summary(slot_id: String) -> Dictionary:
	var path := _get_slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return {
			"slot_id": slot_id,
			"exists": false,
			"path": path,
		}

	var load_result := _save_system.load_json(path)
	if not bool(load_result.get("ok", false)):
		return {
			"slot_id": slot_id,
			"exists": true,
			"path": path,
			"valid": false,
			"error": str(load_result.get("error", "")),
		}

	var save_data: Dictionary = load_result.get("data", {})
	var progression: Dictionary = save_data.get("player_progression", {})
	return {
		"slot_id": slot_id,
		"exists": true,
		"valid": true,
		"path": path,
		"level": int(progression.get("level", 1)),
		"current_xp": int(progression.get("current_xp", 0)),
		"xp_to_next_level": int(progression.get("xp_to_next_level", 30)),
	}


func _get_slot_path(slot_id: String) -> String:
	return str(SLOT_PATHS.get(slot_id, SLOT_PATHS[DEFAULT_SLOT]))
