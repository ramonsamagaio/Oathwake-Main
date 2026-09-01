## Keeps the active player/world pair in memory for the new parallel save flow.
## The legacy SaveSlotManager is synchronized at the session boundary because
## some gameplay systems still persist auxiliary per-slot state through it.
extends Node

const SavePathsScript := preload("res://scripts/save/SavePaths.gd")
const SaveSessionScript := preload("res://scripts/save/SaveSession.gd")
const PlayerProfileSaveScript := preload("res://scripts/save/PlayerProfileSave.gd")
const WorldSaveScript := preload("res://scripts/save/WorldSave.gd")

var active_slot_id := ""
var active_player_id := ""
var active_world_id := ""
var current_map_id := ""
var player_data: Dictionary = {}
var world_data: Dictionary = {}

var _session_save := SaveSessionScript.new()
var _player_save := PlayerProfileSaveScript.new()
var _world_save := WorldSaveScript.new()


func start_new_session(slot_id: String, player_name := "Player", world_name := "World", appearance: Dictionary = {}) -> bool:
	if SavePathsScript.get_session_path(slot_id).is_empty():
		push_error("GameSession received an invalid slot id: %s" % slot_id)
		return false

	active_slot_id = slot_id
	_sync_legacy_active_slot()
	active_player_id = _create_unique_player_id(player_name)
	active_world_id = _create_id("world", slot_id)
	player_data = _player_save.create_default_data(active_player_id, player_name)
	if not appearance.is_empty():
		player_data["appearance"] = appearance.duplicate(true)
	world_data = _world_save.create_default_data(active_world_id, world_name, _create_seed())
	current_map_id = str(world_data.get("current_map_id", "start_area"))
	world_data["player_states"] = {
		active_player_id: _create_initial_player_state(current_map_id),
	}
	_ensure_current_map_data()
	return save_all()


func load_session(slot_id: String) -> bool:
	var session_path := SavePathsScript.get_session_path(slot_id)
	if session_path.is_empty():
		push_error("GameSession received an invalid slot id: %s" % slot_id)
		return false
	if not FileAccess.file_exists(session_path):
		return start_new_session(slot_id)

	var session_result := _session_save.load_session(slot_id)
	if not bool(session_result.get("ok", false)):
		push_error(str(session_result.get("error", "Could not load save session.")))
		return false

	var session_data: Dictionary = session_result.get("data", {})
	active_slot_id = str(session_data.get("slot_id", slot_id))
	_sync_legacy_active_slot()
	active_player_id = str(session_data.get("player_id", ""))
	active_world_id = str(session_data.get("world_id", ""))
	if active_player_id.is_empty() or active_world_id.is_empty():
		push_error("GameSession found a session without player_id or world_id.")
		return false

	var created_missing_data := false
	var player_path := SavePathsScript.get_player_path(active_player_id)
	if player_path.is_empty():
		push_error("GameSession found an invalid player id in the session.")
		return false
	if FileAccess.file_exists(player_path):
		var player_result := _player_save.load_profile(active_player_id)
		if not bool(player_result.get("ok", false)):
			push_error(str(player_result.get("error", "Could not load player profile.")))
			return false
		player_data = player_result.get("data", {})
	else:
		player_data = _player_save.create_default_data(active_player_id)
		created_missing_data = true

	var world_path := SavePathsScript.get_world_path(active_world_id)
	if world_path.is_empty():
		push_error("GameSession found an invalid world id in the session.")
		return false
	if FileAccess.file_exists(world_path):
		var world_result := _world_save.load_world(active_world_id)
		if not bool(world_result.get("ok", false)):
			push_error(str(world_result.get("error", "Could not load world save.")))
			return false
		world_data = world_result.get("data", {})
	else:
		world_data = _world_save.create_default_data(active_world_id)
		created_missing_data = true

	current_map_id = str(world_data.get("current_map_id", "start_area"))
	_ensure_current_map_data()
	if created_missing_data:
		return save_all()

	return true


func save_all() -> bool:
	if not save_player():
		return false
	if not save_world():
		return false
	return _save_session()


func save_player() -> bool:
	if active_player_id.is_empty() or player_data.is_empty():
		push_error("GameSession has no active player data to save.")
		return false
	player_data["player_id"] = active_player_id
	player_data["schema_version"] = PlayerProfileSaveScript.SCHEMA_VERSION
	var save_error := _player_save.save_profile(player_data)
	if not save_error.is_empty():
		push_error(save_error)
		return false
	return true


func save_world() -> bool:
	if active_world_id.is_empty() or world_data.is_empty():
		push_error("GameSession has no active world data to save.")
		return false
	world_data["world_id"] = active_world_id
	world_data["schema_version"] = WorldSaveScript.SCHEMA_VERSION
	world_data["current_map_id"] = current_map_id
	_ensure_current_map_data()
	var save_error := _world_save.save_world(world_data)
	if not save_error.is_empty():
		push_error(save_error)
		return false
	return true


func get_current_map_data() -> Dictionary:
	if world_data.is_empty() or current_map_id.is_empty():
		return {}
	_ensure_current_map_data()
	var maps: Dictionary = world_data.get("maps", {})
	var map_data: Variant = maps.get(current_map_id, {})
	return map_data.duplicate(true) if map_data is Dictionary else {}


func set_current_map_id(map_id: String) -> void:
	if map_id.strip_edges().is_empty():
		push_warning("GameSession ignored an empty map id.")
		return
	current_map_id = map_id
	if not world_data.is_empty():
		world_data["current_map_id"] = current_map_id
		_ensure_current_map_data()


func _save_session() -> bool:
	if active_slot_id.is_empty() or active_player_id.is_empty() or active_world_id.is_empty():
		push_error("GameSession has no complete active session to save.")
		return false
	_sync_legacy_active_slot()
	var session_data := _session_save.create_default_data(active_slot_id, active_player_id, active_world_id)
	session_data["last_played_at"] = Time.get_datetime_string_from_system()
	var save_error := _session_save.save_session(session_data)
	if not save_error.is_empty():
		push_error(save_error)
		return false
	return true


func _sync_legacy_active_slot() -> void:
	# MultiFloor/legacy auxiliary systems still ask SaveSlotManager for their
	# path. Without this bridge a brand-new slot silently falls back to slot_1,
	# which made a new character inherit the first character's structures/world
	# state even though GameSession had correctly created a new procedural world.
	var legacy_slot_manager := get_node_or_null("/root/SaveSlotManager")
	if legacy_slot_manager != null and legacy_slot_manager.has_method("set_active_slot"):
		legacy_slot_manager.call("set_active_slot", active_slot_id)


func _ensure_current_map_data() -> void:
	if world_data.is_empty() or current_map_id.is_empty():
		return
	var maps_value: Variant = world_data.get("maps", {})
	var maps: Dictionary = maps_value if maps_value is Dictionary else {}
	if not maps.has(current_map_id) or not maps[current_map_id] is Dictionary:
		maps[current_map_id] = {}
	world_data["maps"] = maps


func _create_id(prefix: String, slot_id: String) -> String:
	var timestamp := Time.get_unix_time_from_system()
	return "%s_%s_%d_%d" % [prefix, slot_id, timestamp, randi_range(1000, 9999)]


func _create_unique_player_id(player_name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^a-z0-9]+")
	var base_id := regex.sub(player_name.to_lower().strip_edges(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	if base_id.is_empty():
		base_id = "player"
	var candidate := base_id
	var suffix := 2
	while FileAccess.file_exists(SavePathsScript.get_player_path(candidate)):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1
	return candidate


func _create_initial_player_state(map_id: String) -> Dictionary:
	return {
		"current_map_id": map_id,
		"position": {"x": 0.0, "y": 0.0},
		"has_respawn_point": false,
		"respawn_map_id": map_id,
		"respawn_position": {"x": 0.0, "y": 0.0},
		"initialized": false,
	}


func _create_seed() -> int:
	return randi_range(1, 2147483646)
