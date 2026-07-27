extends Node

const DEFAULT_SETTINGS_PATH := "res://data/settings.json"
const USER_SETTINGS_PATH := "user://settings.json"

var settings := {
	"resolution": "1600x900",
	"fullscreen": false,
	"vsync": true,
	"ui_scale": 1.0,
}


func _ready() -> void:
	load_settings()
	apply_settings()


func load_settings() -> Dictionary:
	settings = _load_settings_file(DEFAULT_SETTINGS_PATH, settings)
	if FileAccess.file_exists(USER_SETTINGS_PATH):
		settings = _load_settings_file(USER_SETTINGS_PATH, settings)
	return settings.duplicate(true)


func save_settings() -> String:
	var base_dir := USER_SETTINGS_PATH.get_base_dir()
	if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
		var make_error := DirAccess.make_dir_recursive_absolute(base_dir)
		if make_error != OK:
			return "Could not create settings directory: %s" % base_dir
	var file := FileAccess.open(USER_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return "Could not save settings to %s" % USER_SETTINGS_PATH
	file.store_string(JSON.stringify(settings, "\t") + "\n")
	return ""


func apply_settings() -> void:
	_apply_resolution(str(settings.get("resolution", "1600x900")))
	_apply_fullscreen(bool(settings.get("fullscreen", false)))
	_apply_vsync(bool(settings.get("vsync", true)))
	_apply_ui_scale(float(settings.get("ui_scale", 1.0)))


func set_resolution(resolution: String, apply_now := true, persist := true) -> void:
	settings["resolution"] = resolution
	if apply_now and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		_apply_resolution(resolution)
	if persist:
		save_settings()


func set_fullscreen(is_fullscreen: bool) -> void:
	set_borderless_fullscreen(is_fullscreen)


func set_borderless_fullscreen(is_fullscreen: bool, persist := true) -> void:
	settings["fullscreen"] = is_fullscreen
	_apply_fullscreen(is_fullscreen)
	if persist:
		save_settings()


func toggle_borderless_fullscreen() -> bool:
	var next_state := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
	set_borderless_fullscreen(next_state)
	return next_state


func is_borderless_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func set_vsync(enabled: bool) -> void:
	settings["vsync"] = enabled
	_apply_vsync(enabled)
	save_settings()


func set_ui_scale(scale: float) -> void:
	settings["ui_scale"] = maxf(scale, 0.5)
	_apply_ui_scale(float(settings["ui_scale"]))
	save_settings()


func _load_settings_file(path: String, fallback: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fallback.duplicate(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback.duplicate(true)
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK or not json.data is Dictionary:
		return fallback.duplicate(true)
	var loaded_settings: Dictionary = fallback.duplicate(true)
	var parsed: Dictionary = json.data
	for key in parsed.keys():
		loaded_settings[str(key)] = parsed[key]
	return loaded_settings


func _apply_resolution(resolution: String) -> void:
	var parts := resolution.split("x")
	if parts.size() != 2:
		return
	var width := int(parts[0])
	var height := int(parts[1])
	if width <= 0 or height <= 0:
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(Vector2i(width, height))


func _apply_fullscreen(is_fullscreen: bool) -> void:
	# WINDOW_MODE_FULLSCREEN is Godot's borderless desktop-filling mode. It keeps
	# normal application switching and multi-window behavior, unlike exclusive fullscreen.
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_resolution(str(settings.get("resolution", "1600x900")))


func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)


func _apply_ui_scale(scale: float) -> void:
	var root_loop := Engine.get_main_loop()
	if root_loop is SceneTree:
		var scene_tree := root_loop as SceneTree
		scene_tree.root.content_scale_factor = maxf(scale, 0.5)
