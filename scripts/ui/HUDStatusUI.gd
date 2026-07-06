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
const PURPLE_FIRE_FRAMES_DIR := "res://assets/ui/HUDUI/purple_fire_frames"

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
var _purple_fire: TextureRect
var _purple_fire_frames: Array[Texture2D] = []
var _purple_fire_frame_index := 0
var _purple_fire_timer: Timer


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
	_add_layout_texture_rect(PORTRAIT_PATH, "hud.portrait", Rect2(18, 15, 184, 191))

	var life_rect := _get_rect("hud.life_bar", Rect2(194, 21, 269, 53))
	var mana_rect := _get_rect("hud.mana_bar", Rect2(194, 41, 270, 30))
	var stamina_rect := _get_rect("hud.stamina_bar", Rect2(196, 26, 270, 63))
	_life_width = life_rect.size.x
	_life_clip = _add_fill_bar("hud.life_bar", LIFE_BAR_PATH, life_rect)
	_life_label = _add_bar_label(life_rect, 11, -1.0)

	_mana_width = mana_rect.size.x
	_mana_clip = _add_fill_bar("hud.mana_bar", MANA_BAR_PATH, mana_rect)
	_mana_label = _add_bar_label(mana_rect, 10, -1.0)

	_stamina_width = stamina_rect.size.x
	_stamina_clip = _add_fill_bar("hud.stamina_bar", STAMINA_BAR_PATH, stamina_rect)
	_stamina_label = _add_bar_label(stamina_rect, 10, -1.0)

	var xp_frame_rect := _get_rect("hud.xp_bar_frame", Rect2(549, 1, 476, 61))
	var xp_fill_rect := _get_rect("hud.xp_bar_fill", Rect2(595, 29, 417, 61))
	_xp_width = xp_fill_rect.size.x
	_xp_clip = _add_fill_bar("hud.xp_bar_fill", EXP_BAR_PATH, xp_fill_rect)
	_add_layout_texture_rect(EXP_BORDER_PATH, "hud.xp_bar_frame", xp_frame_rect)
	_xp_label = _add_bar_label(xp_frame_rect, 11, -1.0)

	_add_layout_texture_rect(FLAME_FRAME_PATH, "hud.alignment_flame_frame", Rect2(1415, 723, 167, 159))
	_add_alignment_flame()

	_tool_label = Label.new()
	_tool_label.name = "CurrentToolLabel"
	_tool_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_label.position = Vector2(20, 202)
	_tool_label.size = Vector2(280, 28)
	add_child(_tool_label)
	OathwakeTextStyle.apply_profile_to_label(_tool_label, "base_ui", null, 12, 0)


func _add_layout_texture_rect(path: String, element_id: String, fallback_rect: Rect2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = element_id
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = _load_texture(path)
	add_child(texture_rect)
	UILayoutApplier.apply_texture_rect_from_layout(texture_rect, _layout, element_id, fallback_rect)
	return texture_rect


func _add_fill_bar(element_id: String, path: String, rect: Rect2) -> Control:
	var clip := Control.new()
	clip.name = "FillClip"
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	_apply_rect(clip, rect)
	add_child(clip)

	var texture_rect := TextureRect.new()
	texture_rect.name = "Fill"
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = _load_texture(path)
	clip.add_child(texture_rect)
	UILayoutApplier.apply_texture_rect_from_layout(texture_rect, _layout, element_id, rect)
	texture_rect.position = Vector2.ZERO
	texture_rect.size = rect.size
	return clip


func _add_bar_label(rect: Rect2, font_size := 11, vertical_bias := -1.0) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_contents = false
	label.visible = true
	label.show_behind_parent = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position + Vector2(0, vertical_bias)
	label.size = rect.size
	add_child(label)
	OathwakeTextStyle.apply_profile_to_label(label, "base_ui", null, font_size, 1)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 999
	label.move_to_front()
	return label


func _add_alignment_flame() -> void:
	var rect := _get_rect("hud.alignment_flame", Rect2(1490, 795, 40, 40))
	_purple_fire = TextureRect.new()
	_purple_fire.name = "Purple_fire"
	_purple_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_purple_fire)
	UILayoutApplier.apply_texture_rect_from_layout(_purple_fire, _layout, "hud.alignment_flame", rect)
	_scale_purple_fire(3.0)

	_purple_fire_frames = _load_purple_fire_frames()
	if not _purple_fire_frames.is_empty():
		_purple_fire.texture = _purple_fire_frames[0]
		_start_purple_fire_animation()
		return


func _start_purple_fire_animation() -> void:
	if _purple_fire_timer != null:
		_purple_fire_timer.queue_free()
		_purple_fire_timer = null

	_purple_fire_timer = Timer.new()
	_purple_fire_timer.wait_time = 0.09
	_purple_fire_timer.one_shot = false
	_purple_fire_timer.autostart = true
	_purple_fire_timer.timeout.connect(_advance_purple_fire_frame)
	add_child(_purple_fire_timer)


func _advance_purple_fire_frame() -> void:
	if _purple_fire == null or _purple_fire_frames.is_empty():
		return
	_purple_fire_frame_index = (_purple_fire_frame_index + 1) % _purple_fire_frames.size()
	_purple_fire.texture = _purple_fire_frames[_purple_fire_frame_index]


func _scale_purple_fire(multiplier: float) -> void:
	if _purple_fire == null:
		return
	var base_size := _purple_fire.size
	if base_size.x <= 0.0 or base_size.y <= 0.0:
		return
	var scaled_size := base_size * multiplier
	_purple_fire.position = _purple_fire.position + (base_size - scaled_size) * 0.5
	_purple_fire.size = scaled_size


func _load_purple_fire_frames() -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var dir := DirAccess.open(PURPLE_FIRE_FRAMES_DIR)
	if dir == null:
		return frames

	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()

	for name in file_names:
		var texture := _load_texture("%s/%s" % [PURPLE_FIRE_FRAMES_DIR, name])
		if texture != null:
			frames.append(texture)
	return frames


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
