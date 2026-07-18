## Owns overworld music and terrain-driven ambience for a gameplay scene.
class_name GameplayAudioController
extends Node

const OVERWORLD_THEME_PATH := "res://assets/audio/themes/OVERWORLD THEME 01.mp3"
const FOREST_AMBIENCE_PATH := "res://assets/audio/ambience/Forest Day.wav"
const AUDIO_MIX_PATH := "res://data/audio_mix.json"
const CHECK_INTERVAL := 0.35
const DEFAULT_OVERWORLD_VOLUME_DB := -8.0
const DEFAULT_AMBIENCE_VOLUME_DB := -22.0
const DEFAULT_INACTIVE_VOLUME_DB := -80.0

var world: Node
var player: Node2D
var overworld_music: AudioStreamPlayer
var forest_ambience: AudioStreamPlayer
var overworld_volume_db := DEFAULT_OVERWORLD_VOLUME_DB
var ambience_volume_db := DEFAULT_AMBIENCE_VOLUME_DB
var ambience_inactive_volume_db := DEFAULT_INACTIVE_VOLUME_DB
var _volume_tween: Tween
var _check_timer := 0.0
var _ambience_active := false


func setup(new_world: Node, new_player: Node2D) -> void:
	world = new_world
	player = new_player
	reload_mix()
	_setup_overworld_music()
	_setup_forest_ambience()


func reload_mix() -> void:
	overworld_volume_db = DEFAULT_OVERWORLD_VOLUME_DB
	ambience_volume_db = DEFAULT_AMBIENCE_VOLUME_DB
	ambience_inactive_volume_db = DEFAULT_INACTIVE_VOLUME_DB
	if FileAccess.file_exists(AUDIO_MIX_PATH):
		var file := FileAccess.open(AUDIO_MIX_PATH, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				overworld_volume_db = float(json.data.get("overworld_volume_db", DEFAULT_OVERWORLD_VOLUME_DB))
				ambience_volume_db = float(json.data.get("ambience_volume_db", DEFAULT_AMBIENCE_VOLUME_DB))
				ambience_inactive_volume_db = float(json.data.get("ambience_inactive_volume_db", DEFAULT_INACTIVE_VOLUME_DB))
	_apply_loaded_mix()


func update_ambience(delta: float) -> void:
	if player == null or world == null or forest_ambience == null or not world.has_method("get_tile_type_at_position"):
		return
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0
	var tile_type := str(world.get_tile_type_at_position(player.global_position)).to_lower()
	_set_forest_ambience_active(tile_type == "grass" or tile_type == "forest")


func _setup_overworld_music() -> void:
	if overworld_music != null:
		return
	overworld_music = AudioStreamPlayer.new()
	overworld_music.name = "OverworldMusicPlayer"
	overworld_music.bus = "Master"
	overworld_music.volume_db = overworld_volume_db
	var stream := _load_audio_stream(OVERWORLD_THEME_PATH)
	if stream == null:
		return
	_set_stream_loop(stream, true)
	overworld_music.stream = stream
	add_child(overworld_music)
	overworld_music.play()


func _setup_forest_ambience() -> void:
	if forest_ambience != null:
		return
	forest_ambience = AudioStreamPlayer.new()
	forest_ambience.name = "ForestAmbiencePlayer"
	forest_ambience.bus = "Master"
	forest_ambience.volume_db = ambience_inactive_volume_db
	var stream := _load_audio_stream(FOREST_AMBIENCE_PATH)
	if stream == null:
		return
	_set_stream_loop(stream, true)
	forest_ambience.stream = stream
	add_child(forest_ambience)


func _set_forest_ambience_active(is_active: bool) -> void:
	if forest_ambience == null or is_active == _ambience_active:
		return
	_ambience_active = is_active
	if _volume_tween != null:
		_volume_tween.kill()
	if is_active and not forest_ambience.playing:
		forest_ambience.play()
	_volume_tween = create_tween()
	_volume_tween.tween_property(forest_ambience, "volume_db", ambience_volume_db if is_active else ambience_inactive_volume_db, 1.0)


func _apply_loaded_mix() -> void:
	if overworld_music != null:
		overworld_music.volume_db = overworld_volume_db
	if forest_ambience != null:
		forest_ambience.volume_db = ambience_volume_db if _ambience_active else ambience_inactive_volume_db


func _load_audio_stream(path: String) -> AudioStream:
	return load(path) as AudioStream if ResourceLoader.exists(path) else null


func _set_stream_loop(stream: Resource, enabled: bool) -> void:
	for property_info in stream.get_property_list():
		if str(property_info.get("name", "")) == "loop":
			stream.set("loop", enabled)
			return
