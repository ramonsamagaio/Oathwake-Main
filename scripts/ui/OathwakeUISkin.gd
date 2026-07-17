extends RefCounted

const FALLBACK_UI_TEXTURE: Texture2D = preload("res://assets/generated/ui_fallback_checker.svg")

static var _texture_cache: Dictionary = {}
static var _fallback_texture_cache: Dictionary = {}


static func make_panel_style(config: Dictionary = {}) -> StyleBox:
	var texture_path := str(config.get("texture_path", ""))
	var texture := _load_texture(texture_path)
	if texture == null:
		texture = _get_fallback_texture()
	var stylebox := StyleBoxTexture.new()
	stylebox.texture = texture
	stylebox.texture_margin_left = float(config.get("texture_margin_left", 16.0))
	stylebox.texture_margin_top = float(config.get("texture_margin_top", 16.0))
	stylebox.texture_margin_right = float(config.get("texture_margin_right", 16.0))
	stylebox.texture_margin_bottom = float(config.get("texture_margin_bottom", 16.0))
	stylebox.content_margin_left = float(config.get("content_margin_left", 18.0))
	stylebox.content_margin_top = float(config.get("content_margin_top", 18.0))
	stylebox.content_margin_right = float(config.get("content_margin_right", 18.0))
	stylebox.content_margin_bottom = float(config.get("content_margin_bottom", 18.0))
	stylebox.axis_stretch_horizontal = TextureRect.STRETCH_TILE
	stylebox.axis_stretch_vertical = TextureRect.STRETCH_TILE
	return stylebox


static func make_button_style(state: String = "normal", size_key: String = "large", config: Dictionary = {}) -> StyleBox:
	var resolved_size_key := _resolve_button_size_key(size_key)
	var normalized_state := state.to_lower().strip_edges()
	var texture_key := "%s_%s_texture_path" % [resolved_size_key, normalized_state]
	var fallback_key := "%s_normal_texture_path" % resolved_size_key
	var texture_path := str(config.get(texture_key, config.get(fallback_key, "")))
	var texture := _load_texture(texture_path)
	if texture == null:
		texture = _get_fallback_texture()
	var stylebox := StyleBoxTexture.new()
	stylebox.texture = texture
	var margins := config.get("%s_margins" % resolved_size_key, {})
	if margins is Dictionary:
		stylebox.texture_margin_left = _get_margin_value(margins, "left", 20)
		stylebox.texture_margin_top = _get_margin_value(margins, "top", 12)
		stylebox.texture_margin_right = _get_margin_value(margins, "right", 20)
		stylebox.texture_margin_bottom = _get_margin_value(margins, "bottom", 12)
	stylebox.content_margin_left = float(config.get("button_content_margin_left", 18.0))
	stylebox.content_margin_top = float(config.get("button_content_margin_top", 8.0))
	stylebox.content_margin_right = float(config.get("button_content_margin_right", 18.0))
	stylebox.content_margin_bottom = float(config.get("button_content_margin_bottom", 8.0))
	return stylebox


static func make_slot_style(variant: String = "normal", config: Dictionary = {}) -> StyleBox:
	var style_keys := _resolve_slot_style_keys(variant)
	var texture_path := str(config.get(style_keys.get("texture_key", ""), ""))
	var texture := _load_texture(texture_path)
	if texture == null:
		texture = _get_fallback_texture()
	var stylebox := StyleBoxTexture.new()
	stylebox.texture = texture
	var margin_value := int(config.get("slot_texture_margin", 8))
	stylebox.texture_margin_left = margin_value
	stylebox.texture_margin_top = margin_value
	stylebox.texture_margin_right = margin_value
	stylebox.texture_margin_bottom = margin_value
	stylebox.content_margin_left = float(config.get("slot_content_margin", 6.0))
	stylebox.content_margin_top = float(config.get("slot_content_margin", 6.0))
	stylebox.content_margin_right = float(config.get("slot_content_margin", 6.0))
	stylebox.content_margin_bottom = float(config.get("slot_content_margin", 6.0))
	return stylebox


static func apply_button_skin(button: Button, size_key: String = "large", config: Dictionary = {}) -> void:
	if button == null:
		return
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, make_button_style(state, size_key, config))


static func apply_panel_skin(panel: PanelContainer, config: Dictionary = {}) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", make_panel_style(config))


static func apply_slot_skin(control: Control, variant: String = "normal", config: Dictionary = {}) -> void:
	if control == null:
		return
	control.add_theme_stylebox_override("panel", make_slot_style(variant, config))


static func apply_label_skin(label: Label, config: Dictionary = {}) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", config.get("font_color", Color(0.92, 0.90, 0.84, 1.0)))
	label.add_theme_color_override("font_shadow_color", config.get("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85)))
	label.add_theme_constant_override("shadow_offset_x", int(config.get("shadow_offset_x", 1)))
	label.add_theme_constant_override("shadow_offset_y", int(config.get("shadow_offset_y", 1)))


static func apply_line_edit_skin(line_edit: LineEdit, config: Dictionary = {}) -> void:
	if line_edit == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = config.get("line_edit_background", Color(0.06, 0.07, 0.09, 0.96))
	normal.border_color = config.get("line_edit_border", Color(0.34, 0.28, 0.22, 1.0))
	normal.set_border_width_all(int(config.get("line_edit_border_width", 2)))
	normal.set_corner_radius_all(int(config.get("line_edit_corner_radius", 4)))
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("focus", normal.duplicate())


static func make_inventory_panel_style(config: Dictionary = {}) -> StyleBox:
	var stylebox := make_panel_style(config)
	if stylebox is StyleBoxTexture:
		var texture_style := stylebox as StyleBoxTexture
		texture_style.content_margin_left = float(config.get("inventory_content_margin_left", 22.0))
		texture_style.content_margin_top = float(config.get("inventory_content_margin_top", 22.0))
		texture_style.content_margin_right = float(config.get("inventory_content_margin_right", 22.0))
		texture_style.content_margin_bottom = float(config.get("inventory_content_margin_bottom", 22.0))
	return stylebox


static func make_tooltip_style(config: Dictionary = {}) -> StyleBox:
	var stylebox := make_panel_style(config)
	if stylebox is StyleBoxTexture:
		var texture_style := stylebox as StyleBoxTexture
		texture_style.content_margin_left = 12
		texture_style.content_margin_top = 10
		texture_style.content_margin_right = 12
		texture_style.content_margin_bottom = 10
	return stylebox


static func make_header_style(config: Dictionary = {}) -> StyleBox:
	var texture_path := str(config.get("header_texture_path", ""))
	var texture := _load_texture(texture_path)
	if texture == null:
		texture = _get_fallback_texture()
	var stylebox := StyleBoxTexture.new()
	stylebox.texture = texture
	stylebox.texture_margin_left = 12
	stylebox.texture_margin_top = 8
	stylebox.texture_margin_right = 12
	stylebox.texture_margin_bottom = 8
	stylebox.content_margin_left = 18
	stylebox.content_margin_top = 10
	stylebox.content_margin_right = 18
	stylebox.content_margin_bottom = 10
	return stylebox


static func make_compact_panel_style(config: Dictionary = {}) -> StyleBox:
	var stylebox := make_panel_style(config)
	if stylebox is StyleBoxTexture:
		var texture_style := stylebox as StyleBoxTexture
		texture_style.content_margin_left = 10
		texture_style.content_margin_top = 8
		texture_style.content_margin_right = 10
		texture_style.content_margin_bottom = 8
	return stylebox


static func make_large_panel_style(config: Dictionary = {}) -> StyleBox:
	var stylebox := make_panel_style(config)
	if stylebox is StyleBoxTexture:
		var texture_style := stylebox as StyleBoxTexture
		texture_style.content_margin_left = 26
		texture_style.content_margin_top = 26
		texture_style.content_margin_right = 26
		texture_style.content_margin_bottom = 26
	return stylebox


static func make_dialog_panel_style(config: Dictionary = {}) -> StyleBox:
	var stylebox := make_panel_style(config)
	if stylebox is StyleBoxTexture:
		var texture_style := stylebox as StyleBoxTexture
		texture_style.content_margin_left = 18
		texture_style.content_margin_top = 18
		texture_style.content_margin_right = 18
		texture_style.content_margin_bottom = 18
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
		return {"texture_key": "save_%s_texture_path" % save_state}
	return {"texture_key": "slot_%s_texture_path" % lowered}
