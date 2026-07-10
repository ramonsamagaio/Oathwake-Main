## Centralizes paths and directory creation for the parallel save architecture.
class_name SavePaths
extends RefCounted

const SAVES_DIR := "user://saves"
const PLAYERS_DIR := SAVES_DIR + "/players"
const WORLDS_DIR := SAVES_DIR + "/worlds"
const SESSIONS_DIR := SAVES_DIR + "/sessions"


static func get_player_path(player_id: String) -> String:
	if not _is_safe_id(player_id):
		return ""
	return "%s/%s.json" % [PLAYERS_DIR, player_id]


static func get_world_dir(world_id: String) -> String:
	if not _is_safe_id(world_id):
		return ""
	return "%s/%s" % [WORLDS_DIR, world_id]


static func get_world_path(world_id: String) -> String:
	var world_dir := get_world_dir(world_id)
	if world_dir.is_empty():
		return ""
	return world_dir + "/world.json"


static func get_session_path(slot_id: String) -> String:
	if not _is_safe_id(slot_id):
		return ""
	return "%s/%s.json" % [SESSIONS_DIR, slot_id]


static func ensure_save_dirs() -> String:
	for directory in [SAVES_DIR, PLAYERS_DIR, WORLDS_DIR, SESSIONS_DIR]:
		if DirAccess.dir_exists_absolute(directory):
			continue
		var error := DirAccess.make_dir_recursive_absolute(directory)
		if error != OK:
			return "Could not create save directory: %s" % directory
	return ""


static func ensure_world_dir(world_id: String) -> String:
	var world_dir := get_world_dir(world_id)
	if world_dir.is_empty():
		return "Invalid world id: %s" % world_id
	var base_error := ensure_save_dirs()
	if not base_error.is_empty():
		return base_error
	if DirAccess.dir_exists_absolute(world_dir):
		return ""
	if DirAccess.make_dir_recursive_absolute(world_dir) != OK:
		return "Could not create world directory: %s" % world_dir
	return ""


static func _is_safe_id(value: String) -> bool:
	if value.strip_edges().is_empty():
		return false
	return not value.contains("/") and not value.contains("\\") and not value.contains("..")
