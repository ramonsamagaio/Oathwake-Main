extends Node

const DATA_PATH := "res://data/sfx_profiles.json"

var profiles: Dictionary = {}
var _last_stream_index: Dictionary = {}


func _ready() -> void:
	reload_profiles()


func reload_profiles() -> void:
	profiles = {}
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("SFXManager could not find %s" % DATA_PATH)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("SFXManager could not open %s" % DATA_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("SFXManager found invalid JSON in %s" % DATA_PATH)
		return
	profiles = json.data


func get_profiles() -> Dictionary:
	return profiles.duplicate(true)


func has_profile(profile_id: String) -> bool:
	return profiles.has(profile_id)


func play_profile(profile_id: String, world_position := Vector2.ZERO, parent: Node = null) -> bool:
	var profile := _get_profile(profile_id)
	if profile.is_empty():
		return false
	var stream_paths := _get_stream_paths(profile)
	if stream_paths.is_empty():
		return false
	var stream_index := _pick_stream_index(profile_id, stream_paths.size())
	var stream_path := str(stream_paths[stream_index])
	if not ResourceLoader.exists(stream_path):
		push_warning("SFXManager missing audio stream: %s" % stream_path)
		return false
	var stream := load(stream_path) as AudioStream
	if stream == null:
		return false
	var target_parent := parent
	if target_parent == null:
		var tree := get_tree()
		target_parent = tree.current_scene if tree != null else null
	if target_parent == null:
		return false
	var player := AudioStreamPlayer2D.new()
	player.name = "SFX_%s" % profile_id
	player.stream = stream
	player.bus = str(profile.get("bus", "Master"))
	player.volume_db = float(profile.get("volume_db", 0.0))
	var pitch_min := float(profile.get("pitch_min", 0.96))
	var pitch_max := float(profile.get("pitch_max", 1.04))
	if pitch_max < pitch_min:
		var swap := pitch_min
		pitch_min = pitch_max
		pitch_max = swap
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.max_distance = float(profile.get("max_distance", 640.0))
	target_parent.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	player.play()
	return true


func play_hit_for_target(target: Node, is_critical := false) -> void:
	if target == null:
		return
	var target_position := Vector2.ZERO
	if target is Node2D:
		target_position = (target as Node2D).global_position
	var target_profile := _resolve_hit_profile(target)
	if not target_profile.is_empty():
		play_profile(target_profile, target_position)
	if is_critical:
		play_profile("critical_hit", target_position)


func _resolve_hit_profile(target: Node) -> String:
	if target.is_in_group("player"):
		return "player_hit"
	if target.is_in_group("enemy"):
		var monster_id := _get_string_property(target, "monster_id")
		if not monster_id.is_empty() and has_profile("hit_%s" % monster_id):
			return "hit_%s" % monster_id
		return "hit_enemy"
	if target.is_in_group("resource_node"):
		var resource_type := ""
		if target.has_method("get_resource_type_id"):
			resource_type = str(target.call("get_resource_type_id")).to_lower()
		var drop_item := ""
		if target.has_method("get_drop_item_id"):
			drop_item = str(target.call("get_drop_item_id")).to_lower()
		var resource_name := ""
		if target.has_method("get_resource_name"):
			resource_name = str(target.call("get_resource_name")).to_lower()
		var identity := "%s %s %s" % [resource_type, drop_item, resource_name]
		if identity.contains("tree") or identity.contains("wood"):
			return "hit_wood"
		if identity.contains("rock") or identity.contains("stone") or identity.contains("ore") or identity.contains("coal"):
			return "hit_stone"
		return "hit_resource"
	return ""


func _get_profile(profile_id: String) -> Dictionary:
	var value: Variant = profiles.get(profile_id, {})
	return value if value is Dictionary else {}


func _get_stream_paths(profile: Dictionary) -> Array:
	var value: Variant = profile.get("stream_paths", [])
	if value is Array:
		var clean: Array = []
		for path_value in value:
			var path := str(path_value).strip_edges()
			if not path.is_empty():
				clean.append(path)
		return clean
	var single_path := str(profile.get("stream_path", "")).strip_edges()
	return [single_path] if not single_path.is_empty() else []


func _pick_stream_index(profile_id: String, count: int) -> int:
	if count <= 1:
		_last_stream_index[profile_id] = 0
		return 0
	var previous := int(_last_stream_index.get(profile_id, -1))
	var selected := randi() % count
	if selected == previous:
		selected = (selected + 1 + int(randi() % (count - 1))) % count
	_last_stream_index[profile_id] = selected
	return selected


func _get_string_property(target: Object, property_name: String) -> String:
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return str(target.get(property_name))
	return ""
