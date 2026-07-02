extends RefCounted

const UI_SKIN_PATH := "res://data/ui_skin.json"

static var _skin_cache: Dictionary = {}


static func apply_panel(control: Control) -> void:
	var stylebox := _make_stylebox("panel")
	if stylebox == null:
		return
	control.add_theme_stylebox_override("panel", stylebox)


static func apply_button(button: Button) -> void:
	var normal := _make_stylebox("button_normal")
	var hover := _make_stylebox("button_hover")
	var pressed := _make_stylebox("button_pressed")

	if normal != null:
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("disabled", normal)
	if hover != null:
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("focus", hover)
	if pressed != null:
		button.add_theme_stylebox_override("pressed", pressed)


static func apply_slot_button(button: Button) -> void:
	var stylebox := _make_stylebox("slot")
	if stylebox == null:
		return
	button.add_theme_stylebox_override("normal", stylebox)
	button.add_theme_stylebox_override("hover", stylebox)
	button.add_theme_stylebox_override("pressed", stylebox)
	button.add_theme_stylebox_override("disabled", stylebox)


static func get_skin_data() -> Dictionary:
	if not _skin_cache.is_empty():
		return _skin_cache

	if not FileAccess.file_exists(UI_SKIN_PATH):
		_skin_cache = {}
		return _skin_cache

	var file := FileAccess.open(UI_SKIN_PATH, FileAccess.READ)
	if file == null:
		_skin_cache = {}
		return _skin_cache

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_skin_cache = {}
		return _skin_cache

	_skin_cache = json.data
	return _skin_cache


static func _make_stylebox(key: String) -> StyleBoxTexture:
	var texture := _get_texture(key)
	if texture == null:
		return null

	var stylebox := StyleBoxTexture.new()
	stylebox.texture = texture
	return stylebox


static func _get_texture(key: String) -> Texture2D:
	var skin_data := get_skin_data()
	var path := str(skin_data.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null

	var resource := load(path)
	return resource as Texture2D
