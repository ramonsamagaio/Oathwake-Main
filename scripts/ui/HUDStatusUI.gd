extends Control

const UILayoutConfig = preload("res://scripts/ui/UILayoutConfig.gd")
const UILayoutApplier = preload("res://scripts/ui/UILayoutApplier.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")

const PORTRAIT_PATH := "res://assets/ui/HUDUI/PORTRAIT.png"
const LIFE_BAR_PATH := "res://assets/ui/HUDUI/BAR_LIFE.png"
const MANA_BAR_PATH := "res://assets/ui/HUDUI/BAR_MANA.png"
const STAMINA_BAR_PATH := "res://assets/ui/HUDUI/BAR_STAMINA.png"
const EXP_BORDER_PATH := "res://assets/ui/HUDUI/EXP_BORDER.png"
const EXP_BAR_PATH := "res://assets/ui/HUDUI/EXP_BAR.png"
const FLAME_FRAME_PATH := "res://assets/ui/HUDUI/FLAME_FRAME.png"
const PURPLE_FIRE_PATH := "res://assets/ui/HUDUI/PURPLE_FIRE.gif"

var _layout: Dictionary = {}
var _life_clip: Control
var _mana_clip: Control
var _stamina_clip: Control
var _xp_clip: Control
var _life_width := 1.0
var _mana_width := 1.0
var _stamina_width := 1.0
var _xp_width := 1.0
var _life_label: Label
var _mana_label: Label
var _stamina_label: Label
var _xp_label: Label
var _tool_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout = UILayoutConfig.load_layout()
	_build_ui()
	set_health(100, 100)
	set_mana(100, 100)
	set_stamina(100, 100)
	set_xp(0, 1, 1)


func set_health(current_health: int, max_health: int) -> void:
	var safe_max := maxi(max_health, 1)
	_set_clip_ratio(_life_clip, _life_width, float(current_health) / float(safe_max))
	if _life_label != null:
		_life_label.text = "%d/%d" % [current_health, safe_max]


func set_mana(current_mana: int, max_mana: int) -> void:
	var safe_max := maxi(max_mana, 1)
	_set_clip_ratio(_mana_clip, _mana_width, float(current_mana) / float(safe_max))
	if _mana_label != null:
		_mana_label.text = "%d/%d" % [current_mana, safe_max]


func set_stamina(current_stamina: int, max_stamina: int) -> void:
	var safe_max := maxi(max_stamina, 1)
	_set_clip_ratio(_stamina_clip, _stamina_width, float(current_stamina) / float(safe_max))
	if _stamina_label != null:
		_stamina_label.text = "%d/%d" % [current_stamina, safe_max]


func set_xp(current_xp: int, xp_to_next_level: int, level: int) -> void:
	var safe_next := maxi(xp_to_next_level, 1)
	_set_clip_ratio(_xp_clip, _xp_width, float(current_xp) / float(safe_next))
	if _xp_label != null:
		_xp_label.text = "LV %d  %d/%d" % [level, current_xp, safe_next]


func set_current_tool(tool_text: String) -> void:
	if _tool_label != null:
		_tool_label.text = "Tool: %s" % (tool_text if not tool_text.is_empty() else "Hands")


func _build_ui() -> void:
	_add_texture(PORTRAIT_PATH, "hud.portrait", Rect2(20, 20, 184, 184))

	var life_rect := _get_rect("hud.life_bar", Rect2(194, 44, 270, 52))
	_life_width = life_rect.size.x
	_life_clip = _add_fill_bar(LIFE_BAR_PATH, life_rect)
	_life_label = _add_bar_label(life_rect)

	var mana_rect := _get_rect("hud.mana_bar", Rect2(194, 102, 270, 30))
	_mana_width = mana_rect.size.x
	_mana_clip = _add_fill_bar(MANA_BAR_PATH, mana_rect)
	_mana_label = _add_bar_label(mana_rect)

	var stamina_rect := _get_rect("hud.stamina_bar", Rect2(194, 136, 270, 42))
	_stamina_width = stamina_rect.size.x
	_stamina_clip = _add_fill_bar(STAMINA_BAR_PATH, stamina_rect)
	_stamina_label = _add_bar_label(stamina_rect)

	var xp_rect := _get_rect("hud.xp_bar_fill", Rect2(550, 28, 420, 46))
	_xp_width = xp_rect.size.x
	_xp_clip = _add_fill_bar(EXP_BAR_PATH, xp_rect)
	_add_texture(EXP_BORDER_PATH, "hud.xp_bar_frame", Rect2(530, 0, 476, 62))
	_xp_label = _add_bar_label(_get_rect("hud.xp_bar_frame", Rect2(530, 0, 476, 62)))

	_add_texture(FLAME_FRAME_PATH, "hud.alignment_flame_frame", Rect2(1395, 703, 167, 159))
	_add_alignment_flame()

	_tool_label = Label.new()
	_tool_label.name = "CurrentToolLabel"
	_tool_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_label.position = Vector2(20, 202)
	_tool_label.size = Vector2(280, 28)
	add_child(_tool_label)
	OathwakeTextStyle.apply_profile_to_label(_tool_label, "base_ui")


func _add_texture(path: String, element_id: String, fallback_rect: Rect2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = element_id
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture = _load_texture(path)
	_apply_rect(texture_rect, _get_rect(element_id, fallback_rect))
	add_child(texture_rect)
	return texture_rect


func _add_fill_bar(path: String, rect: Rect2) -> Control:
	var clip := Control.new()
	clip.name = "FillClip"
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	_apply_rect(clip, rect)
	add_child(clip)

	var texture_rect := TextureRect.new()
	texture_rect.name = "Fill"
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture = _load_texture(path)
	texture_rect.position = Vector2.ZERO
	texture_rect.size = rect.size
	clip.add_child(texture_rect)
	return clip


func _add_bar_label(rect: Rect2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	add_child(label)
	OathwakeTextStyle.apply_profile_to_label(label, "base_ui")
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _add_alignment_flame() -> void:
	var rect := _get_rect("hud.alignment_flame", Rect2(1470, 775, 40, 40))
	var fire_resource: Resource = ResourceLoader.load(PURPLE_FIRE_PATH) if ResourceLoader.exists(PURPLE_FIRE_PATH) else null
	if fire_resource is Texture2D:
		var fire_texture := TextureRect.new()
		fire_texture.name = "PurpleFire"
		fire_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fire_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fire_texture.stretch_mode = TextureRect.STRETCH_SCALE
		fire_texture.texture = fire_resource as Texture2D
		_apply_rect(fire_texture, rect)
		add_child(fire_texture)
		return

	var fallback := ColorRect.new()
	fallback.name = "PurpleFireFallback"
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.color = Color(0.62, 0.18, 1.0, 0.8)
	_apply_rect(fallback, rect)
	add_child(fallback)


func _set_clip_ratio(clip: Control, full_width: float, ratio: float) -> void:
	if clip == null:
		return
	var clamped_ratio := clampf(ratio, 0.0, 1.0)
	clip.size.x = maxf(0.0, full_width * clamped_ratio)


func _get_rect(element_id: String, fallback: Rect2) -> Rect2:
	var rect := UILayoutApplier.get_element_rect(_layout, element_id)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return fallback
	return rect


func _apply_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D
