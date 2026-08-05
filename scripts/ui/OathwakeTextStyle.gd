extends RefCounted

const FALLBACK_FONT_PATHS := [
	"res://assets/fonts/PixeloidSans.ttf",
	"res://assets/fonts/PixeloidSans-Bold.ttf",
	"res://assets/fonts/PixeloidMono.ttf",
	"res://assets/fonts/alagard.ttf",
	"res://assets/fonts/m6x11.ttf",
	"res://assets/fonts/m5x7.ttf",
]


static func get_default_font_path() -> String:
	for font_path in FALLBACK_FONT_PATHS:
		if FileAccess.file_exists(font_path):
			return font_path
	return ""


static func load_font_from_path(font_path: String) -> Font:
	var resolved_path := font_path
	if resolved_path.is_empty() or not FileAccess.file_exists(resolved_path):
		resolved_path = get_default_font_path()
	if resolved_path.is_empty() or not FileAccess.file_exists(resolved_path):
		return null

	var loaded_font = load(resolved_path)
	return loaded_font if loaded_font is Font else null


static func get_profile(profile_id: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var content_db := tree.root.get_node_or_null("ContentDB")
	if content_db == null:
		content_db = tree.root.get_node_or_null("/root/ContentDB")
	if content_db == null:
		return {}
	if not content_db.has_method("has_font_profile") or not content_db.has_font_profile(profile_id):
		return {}
	return content_db.get_font_profile(profile_id)


static func make_label_settings_for_profile(
	profile_id: String,
	override_color: Variant = null,
	override_font_size: int = -1,
	override_outline_size: int = -1
) -> LabelSettings:
	var profile := get_profile(profile_id)
	var settings := LabelSettings.new()

	var font := load_font_from_path(str(profile.get("font_path", "")))
	if font != null:
		settings.font = font

	settings.font_size = override_font_size if override_font_size > 0 else int(profile.get("font_size", 14))
	settings.font_color = parse_color(override_color, parse_color(profile.get("font_color", ""), Color.WHITE))
	settings.outline_size = override_outline_size if override_outline_size >= 0 else int(profile.get("outline_size", 0))
	settings.outline_color = parse_color(profile.get("outline_color", ""), Color.BLACK)
	if profile.has("shadow_size"):
		settings.shadow_size = int(profile.get("shadow_size", 0))
		settings.shadow_color = parse_color(profile.get("shadow_color", ""), Color(0, 0, 0, 0))
		var shadow_offset_x := int(profile.get("shadow_offset_x", 0))
		var shadow_offset_y := int(profile.get("shadow_offset_y", 0))
		settings.shadow_offset = Vector2i(shadow_offset_x, shadow_offset_y)
	return settings


static func apply_profile_to_label(
	label: Label,
	profile_id: String,
	override_color: Variant = null,
	override_font_size: int = -1,
	override_outline_size: int = -1
) -> void:
	if label == null:
		return
	label.label_settings = make_label_settings_for_profile(profile_id, override_color, override_font_size, override_outline_size)


static func apply_profile_to_control(control: Control, profile_id: String, override_font_size: int = -1) -> void:
	if control == null:
		return
	var profile := get_profile(profile_id)
	var font := load_font_from_path(str(profile.get("font_path", "")))
	if font != null:
		control.add_theme_font_override("font", font)
	var font_size := override_font_size if override_font_size > 0 else int(profile.get("font_size", 14))
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", parse_color(profile.get("font_color", ""), Color.WHITE))


static func apply_profile_to_rich_text(label: RichTextLabel, profile_id: String, override_font_size: int = -1) -> void:
	if label == null:
		return
	var profile := get_profile(profile_id)
	var normal_font := load_font_from_path(str(profile.get("font_path", "")))
	var bold_font := load_font_from_path("res://assets/fonts/PixeloidSans-Bold.ttf")
	if normal_font != null:
		for font_name in ["normal_font", "italics_font", "mono_font"]:
			label.add_theme_font_override(font_name, normal_font)
	if bold_font == null:
		bold_font = normal_font
	if bold_font != null:
		for font_name in ["bold_font", "bold_italics_font"]:
			label.add_theme_font_override(font_name, bold_font)
	var font_size := override_font_size if override_font_size > 0 else int(profile.get("font_size", 14))
	for size_name in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		label.add_theme_font_size_override(size_name, font_size)
	label.add_theme_color_override("default_color", parse_color(profile.get("font_color", ""), Color.WHITE))
	label.add_theme_color_override("font_outline_color", parse_color(profile.get("outline_color", ""), Color.BLACK))
	label.add_theme_constant_override("outline_size", int(profile.get("outline_size", 0)))


static func parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		var text := str(value).strip_edges()
		if text.is_empty():
			return fallback
		if _is_valid_html_color(text):
			return Color.html(text)
	return fallback


static func _is_valid_html_color(text: String) -> bool:
	if not text.begins_with("#"):
		return false
	if text.length() != 7 and text.length() != 9:
		return false
	for index in range(1, text.length()):
		var code := text.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_upper := code >= 65 and code <= 70
		var is_lower := code >= 97 and code <= 102
		if not is_digit and not is_upper and not is_lower:
			return false
	return true
