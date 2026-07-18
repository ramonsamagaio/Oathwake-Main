extends RefCounted

const UI_SKIN_PATH := "res://data/ui_skin.json"
const FALLBACK_UI_TEXTURE: Texture2D = preload("res://assets/generated/ui_fallback_checker.svg")

static var _skin_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _fallback_texture_cache: Dictionary = {}


static func apply_panel(control: Control, skin_key := "panel") -> void:
	if control == null:
		return
	control.add_theme_stylebox_override("panel", _make_stylebox(str(skin_key)))


static func apply_button(button: Button, size_key := "large") -> void:
	if button == null:
		return
	var resolved_size := _resolve_button_size_key(str(size_key))
	var normal := _make_stylebox("button_%s_normal" % resolved_size)
	var hover := _make_stylebox("button_%s_hover" % resolved_size)
	var pressed := _make_stylebox("button_%s_pressed" % resolved_size)
	var disabled := _make_stylebox("button_%s_disabled" % resolved_size)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover if hover != null else normal)
	button.add_theme_stylebox_override("focus", hover if hover != null else normal)
	button.add_theme_stylebox_override("pressed", pressed if pressed != null else normal)
	button.add_theme_stylebox_override("disabled", disabled if disabled != null else normal)


static func apply_slot_button(button: Button, variant := "empty") -> void:
	if button == null:
		return

	var slot_styles := _resolve_slot_style_keys(str(variant))
	var normal := _make_stylebox(str(slot_styles.get("normal", "item_slot_normal")))
	var hover := _make_stylebox(str(slot_styles.get("hover", "item_slot_hover")))
	var pressed := _make_stylebox(str(slot_styles.get("pressed", "item_slot_selected")))
	var disabled := _make_stylebox(str(slot_styles.get("disabled", "item_slot_blocked")))

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover if hover != null else normal)
	button.add_theme_stylebox_override("focus", hover if hover != null else normal)
	button.add_theme_stylebox_override("pressed", pressed if pressed != null else normal)
	button.add_theme_stylebox_override("disabled", disabled if disabled != null else normal)


static func apply_hotbar_slot_button(button: Button, variant := "empty") -> void:
	apply_slot_button(button, "hotbar_%s" % str(variant))


static func apply_tooltip(control: Control) -> void:
	apply_panel(control, "tooltip")


static func apply_dialog(control: Control) -> void:
	apply_panel(control, "dialog")


static func apply_inventory_panel(control: Control) -> void:
	# The inventory_window asset already contains a decorative grid.
	# Dynamic inventory UI should use a clean frame and draw slots separately.
	apply_panel(control, "panel")


static func apply_hotbar_panel(control: Control) -> void:
	apply_panel(control, "hotbar_frame")


static func make_texture_rect(path: String, stretch_mode := TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.stretch_mode = stretch_mode

	var texture := _load_texture(path)
	if texture == null:
		texture = _get_fallback_texture()
	texture_rect.texture = texture
	return texture_rect


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


static func _make_stylebox(key: String) -> StyleBox:
	var skin_data: Dictionary = get_skin_data()
	var config: Variant = skin_data.get(key, null)
	var stylebox := _build_stylebox_from_config(config)
	if stylebox != null:
		return stylebox

	return _make_fallback_stylebox(key)


static func _build_stylebox_from_config(config: Variant) -> StyleBox:
	if config is String:
		var texture := _load_texture(str(config))
		if texture == null:
			return null
		return _build_texture_stylebox(texture, {}, {})

	if not config is Dictionary:
		return null

	var data: Dictionary = config
	var path := str(data.get("path", ""))
	var texture_from_path := _load_texture(path)
	if texture_from_path == null:
		return null

	var margins: Dictionary = data.get("margins", {}) if data.get("margins", {}) is Dictionary else {}
	var content_margins: Dictionary = data.get("content_margins", {}) if data.get("content_margins", {}) is Dictionary else {}
	return _build_texture_stylebox(texture_from_path, margins, content_margins)


static func _build_texture_stylebox(texture: Texture2D, margins: Dictionary, content_margins: Dictionary) -> StyleBoxTexture:
	var stylebox := StyleBoxTexture.new()
	stylebox.texture = texture
	stylebox.texture_margin_left = _get_margin_value(margins, "left", 16)
	stylebox.texture_margin_top = _get_margin_value(margins, "top", 16)
	stylebox.texture_margin_right = _get_margin_value(margins, "right", 16)
	stylebox.texture_margin_bottom = _get_margin_value(margins, "bottom", 16)
	stylebox.content_margin_left = _get_margin_value(content_margins, "left", _get_margin_value(margins, "left", 16))
	stylebox.content_margin_top = _get_margin_value(content_margins, "top", _get_margin_value(margins, "top", 16))
	stylebox.content_margin_right = _get_margin_value(content_margins, "right", _get_margin_value(margins, "right", 16))
	stylebox.content_margin_bottom = _get_margin_value(content_margins, "bottom", _get_margin_value(margins, "bottom", 16))
	return stylebox


static func _make_fallback_stylebox(key: String) -> StyleBoxFlat:
	var stylebox := StyleBoxFlat.new()
	var lowered := key.to_lower()
	var is_button := lowered.begins_with("button_")
	var is_slot := lowered.begins_with("item_slot_") or lowered.begins_with("save_slot_") or lowered.begins_with("hotbar_slot_")
	var is_tooltip := lowered == "tooltip"
	var is_dialog := lowered == "dialog" or lowered == "confirmation_box"
	var is_hotbar := lowered == "hotbar_frame"
	var is_inventory := lowered == "inventory_window"

	stylebox.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	stylebox.border_color = Color(0.28, 0.31, 0.36, 1.0)
	stylebox.set_border_width_all(2)
	stylebox.corner_radius_top_left = 10
	stylebox.corner_radius_top_right = 10
	stylebox.corner_radius_bottom_left = 10
	stylebox.corner_radius_bottom_right = 10
	stylebox.shadow_size = 2
	stylebox.shadow_color = Color(0.0, 0.0, 0.0, 0.35)

	if is_button:
		stylebox.bg_color = Color(0.12, 0.13, 0.16, 0.96)
		stylebox.border_color = Color(0.35, 0.37, 0.42, 1.0)
		stylebox.corner_radius_top_left = 8
		stylebox.corner_radius_top_right = 8
		stylebox.corner_radius_bottom_left = 8
		stylebox.corner_radius_bottom_right = 8
		stylebox.content_margin_left = 14
		stylebox.content_margin_top = 10
		stylebox.content_margin_right = 14
		stylebox.content_margin_bottom = 10
	elif is_slot:
		stylebox.bg_color = Color(0.11, 0.12, 0.14, 0.96)
		stylebox.border_color = Color(0.33, 0.34, 0.38, 1.0)
		stylebox.corner_radius_top_left = 6
		stylebox.corner_radius_top_right = 6
		stylebox.corner_radius_bottom_left = 6
		stylebox.corner_radius_bottom_right = 6
		stylebox.content_margin_left = 10
		stylebox.content_margin_top = 10
		stylebox.content_margin_right = 10
		stylebox.content_margin_bottom = 10
	elif is_tooltip:
		stylebox.bg_color = Color(0.06, 0.07, 0.08, 0.96)
		stylebox.border_color = Color(0.42, 0.38, 0.22, 1.0)
		stylebox.content_margin_left = 12
		stylebox.content_margin_top = 12
		stylebox.content_margin_right = 12
		stylebox.content_margin_bottom = 12
	elif is_dialog:
		stylebox.bg_color = Color(0.09, 0.07, 0.07, 0.96)
		stylebox.border_color = Color(0.45, 0.28, 0.24, 1.0)
		stylebox.content_margin_left = 18
		stylebox.content_margin_top = 18
		stylebox.content_margin_right = 18
		stylebox.content_margin_bottom = 18
	elif is_hotbar:
		stylebox.bg_color = Color(0.09, 0.10, 0.12, 0.92)
		stylebox.border_color = Color(0.30, 0.32, 0.36, 1.0)
		stylebox.content_margin_left = 8
		stylebox.content_margin_top = 8
		stylebox.content_margin_right = 8
		stylebox.content_margin_bottom = 8
	elif is_inventory:
		stylebox.bg_color = Color(0.08, 0.09, 0.11, 0.96)
		stylebox.border_color = Color(0.30, 0.33, 0.37, 1.0)
		stylebox.content_margin_left = 18
		stylebox.content_margin_top = 18
		stylebox.content_margin_right = 18
		stylebox.content_margin_bottom = 18
	else:
		stylebox.content_margin_left = 18
		stylebox.content_margin_top = 18
		stylebox.content_margin_right = 18
		stylebox.content_margin_bottom = 18

	return stylebox


static func _load_texture(path: String) -> Texture2D:
	var resolved_path := str(path).strip_edges()
	if resolved_path.is_empty() or resolved_path.ends_with(".import"):
		return null

	if _texture_cache.has(resolved_path):
		return _texture_cache[resolved_path]

	if not ResourceLoader.exists(resolved_path):
		_texture_cache[resolved_path] = null
		return null

	var resource := load(resolved_path)
	var texture := resource as Texture2D
	_texture_cache[resolved_path] = texture
	return texture


static func _get_fallback_texture() -> Texture2D:
	var cache_key := "fallback"
	if _fallback_texture_cache.has(cache_key):
		return _fallback_texture_cache[cache_key]
	_fallback_texture_cache[cache_key] = FALLBACK_UI_TEXTURE
	return FALLBACK_UI_TEXTURE


static func _get_margin_value(source: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = source.get(key, fallback)
	return int(value) if value is int or value is float else fallback


static func _resolve_button_size_key(size_key: String) -> String:
	var lowered := size_key.to_lower().strip_edges()
	if lowered == "medium":
		return "medium"
	return "large"


static func _resolve_slot_style_keys(variant: String) -> Dictionary:
	var lowered := variant.to_lower().strip_edges()
	if lowered.begins_with("save_"):
		var save_state := lowered.substr(5, lowered.length() - 5)
		var save_normal := "save_slot_empty"
		var save_hover := "save_slot_filled"
		var save_pressed := "save_slot_selected"
		var save_disabled := "save_slot_empty"
		match save_state:
			"filled":
				save_normal = "save_slot_filled"
				save_hover = "save_slot_selected"
				save_pressed = "save_slot_selected"
			"selected":
				save_normal = "save_slot_selected"
				save_hover = "save_slot_selected"
				save_pressed = "save_slot_selected"
			_:
				save_normal = "save_slot_empty"
		return {
			"normal": save_normal,
			"hover": save_hover,
			"pressed": save_pressed,
			"disabled": save_disabled,
		}

	if lowered.begins_with("hotbar_"):
		var hotbar_state := lowered.substr(7, lowered.length() - 7)
		var hotbar_normal := "hotbar_slot_selected" if hotbar_state == "selected" else "hotbar_slot_empty"
		var hotbar_hover := "hotbar_slot_selected"
		var hotbar_pressed := "hotbar_slot_selected"
		return {
			"normal": hotbar_normal,
			"hover": hotbar_hover,
			"pressed": hotbar_pressed,
			"disabled": hotbar_normal,
		}

	match lowered:
		"hover":
			return {
				"normal": "item_slot_hover",
				"hover": "item_slot_hover",
				"pressed": "item_slot_selected",
				"disabled": "item_slot_blocked",
			}
		"selected":
			return {
				"normal": "item_slot_selected",
				"hover": "item_slot_selected",
				"pressed": "item_slot_selected",
				"disabled": "item_slot_blocked",
			}
		"blocked":
			return {
				"normal": "item_slot_blocked",
				"hover": "item_slot_blocked",
				"pressed": "item_slot_blocked",
				"disabled": "item_slot_blocked",
			}
		_:
			return {
				"normal": "item_slot_normal",
				"hover": "item_slot_hover",
				"pressed": "item_slot_selected",
				"disabled": "item_slot_blocked",
			}
