extends Control

const MAIN_MENU_SCENE := preload("res://scenes/ui/MainMenu.tscn")
const VIDEO_PATH := "res://assets/intro/BG LOOP OATHWAKE.ogv"
const STUDIO_LOGO_PATH := "res://assets/intro/Shinebright Logo.png"
const GAME_LOGO_PATH := "res://assets/intro/OathhWake LOGO.png"
const PRESS_ANY_KEY_PATH := "res://assets/intro/PressAnyKey.png"
const START_SFX_PATH := "res://assets/intro/Start.mp3"
const MENU_THEME_PATH := "res://assets/audio/themes/OATHWAKE MAIN THEME.mp3"

var _video_player: VideoStreamPlayer
var _fallback_background: ColorRect
var _studio_logo: TextureRect
var _game_logo: TextureRect
var _press_any_key: TextureRect
var _black_overlay: ColorRect
var _menu_instance: Control
var _menu_music_player: AudioStreamPlayer
var _start_sfx_player: AudioStreamPlayer
var _can_accept_input := false
var _transition_started := false
var _press_any_key_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_load_audio()
	call_deferred("_run_intro_sequence")


func _unhandled_input(event: InputEvent) -> void:
	if not _can_accept_input or _transition_started:
		return

	var accepted := false
	if event is InputEventKey and event.pressed and not event.echo:
		accepted = true
	elif event is InputEventMouseButton and event.pressed:
		accepted = true
	elif event is InputEventJoypadButton and event.pressed:
		accepted = true

	if not accepted:
		return

	_transition_started = true
	_can_accept_input = false
	if _start_sfx_player.stream != null:
		_start_sfx_player.play()
	_stop_press_any_key_pulse()
	await _play_press_any_key_confirm()
	await _fade_canvas_item(_press_any_key, 0.0, 0.35)
	_press_any_key.visible = false
	await _fade_canvas_item(_game_logo, 0.0, 2.0)
	_game_logo.visible = false
	_black_overlay.visible = false
	_menu_instance.visible = true
	_menu_instance.modulate.a = 0.0
	_menu_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_child(_menu_instance, get_child_count() - 1)
	await _fade_canvas_item(_menu_instance, 1.0, 0.75)
	_menu_instance.mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().set_input_as_handled()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_fallback_background = ColorRect.new()
	_fallback_background.color = Color(0.01, 0.012, 0.018, 1.0)
	_fallback_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fallback_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback_background.modulate.a = 1.0
	add_child(_fallback_background)

	_video_player = VideoStreamPlayer.new()
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_player.modulate.a = 0.0
	_video_player.visible = false
	_video_player.finished.connect(_on_video_finished)
	add_child(_video_player)

	_studio_logo = _make_centered_texture_rect(STUDIO_LOGO_PATH, Vector2(540, 260))
	add_child(_studio_logo)

	_game_logo = _make_centered_texture_rect(GAME_LOGO_PATH, Vector2(660, 260))
	_game_logo.offset_top -= 30.0
	_game_logo.offset_bottom -= 30.0
	add_child(_game_logo)

	_press_any_key = _make_centered_texture_rect(PRESS_ANY_KEY_PATH, Vector2(520, 110))
	_press_any_key.anchor_top = 0.64
	_press_any_key.anchor_bottom = 0.64
	_press_any_key.offset_top = -55.0
	_press_any_key.offset_bottom = 55.0
	add_child(_press_any_key)

	_menu_instance = MAIN_MENU_SCENE.instantiate()
	_set_optional_property(_menu_instance, "show_background", false)
	_menu_instance.visible = false
	_menu_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_instance.modulate.a = 0.0
	add_child(_menu_instance)

	_black_overlay = ColorRect.new()
	_black_overlay.color = Color.BLACK
	_black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black_overlay)


func _load_audio() -> void:
	_menu_music_player = AudioStreamPlayer.new()
	_menu_music_player.bus = "Master"
	_menu_music_player.stream = _load_audio_stream(MENU_THEME_PATH, true)
	add_child(_menu_music_player)

	_start_sfx_player = AudioStreamPlayer.new()
	_start_sfx_player.bus = "Master"
	_start_sfx_player.stream = _load_audio_stream(START_SFX_PATH, false)
	add_child(_start_sfx_player)


func _run_intro_sequence() -> void:
	await _wait(0.15)
	await _fade_canvas_item(_black_overlay, 0.0, 0.24)
	await _fade_canvas_item(_studio_logo, 1.0, 0.55)
	await _wait(0.75)
	await _fade_canvas_item(_studio_logo, 0.0, 0.45)
	_start_background_media()
	await _wait(2.0)
	await _fade_canvas_item(_game_logo, 1.0, 0.55)
	await _wait(2.0)
	await _fade_canvas_item(_press_any_key, 1.0, 0.45)
	_start_press_any_key_pulse()
	_can_accept_input = true


func _start_background_media() -> void:
	var video_stream := _load_video_stream(VIDEO_PATH)
	if video_stream != null:
		_video_player.stream = video_stream
		_video_player.play()
		await get_tree().process_frame
		_video_player.visible = true
		await _fade_canvas_item(_video_player, 1.0, 0.6)
	else:
		push_warning("IntroScreen could not load intro video: %s" % VIDEO_PATH)

	if _menu_music_player.stream != null and not _menu_music_player.playing:
		_menu_music_player.play()


func _on_video_finished() -> void:
	if _video_player.stream != null:
		_video_player.play()


func _make_centered_texture_rect(path: String, rect_size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.anchor_left = 0.5
	rect.anchor_top = 0.5
	rect.anchor_right = 0.5
	rect.anchor_bottom = 0.5
	rect.offset_left = -rect_size.x * 0.5
	rect.offset_top = -rect_size.y * 0.5
	rect.offset_right = rect_size.x * 0.5
	rect.offset_bottom = rect_size.y * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = _load_texture(path)
	rect.modulate.a = 0.0
	return rect


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("IntroScreen missing texture: %s" % path)
		return null
	return load(path) as Texture2D


func _load_video_stream(path: String) -> VideoStream:
	if not ResourceLoader.exists(path):
		return null

	var resource := load(path)
	var video_stream := resource as VideoStream
	return video_stream


func _load_audio_stream(path: String, loop_enabled: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("IntroScreen missing audio: %s" % path)
		return null

	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("IntroScreen could not load audio: %s" % path)
		return null

	_set_stream_loop(stream, loop_enabled)
	return stream


func _set_stream_loop(stream: Resource, loop_enabled: bool) -> void:
	for property_info in stream.get_property_list():
		if str(property_info.get("name", "")) == "loop":
			stream.set("loop", loop_enabled)
			return


func _fade_canvas_item(item: CanvasItem, target_alpha: float, duration: float) -> void:
	if item == null:
		return
	var tween := create_tween()
	tween.tween_property(item, "modulate:a", target_alpha, duration)
	await tween.finished


func _play_press_any_key_confirm() -> void:
	if _press_any_key == null:
		return

	var original_modulate := _press_any_key.modulate
	original_modulate.a = 1.0
	_press_any_key.modulate = original_modulate

	var shine_color := Color(1.8, 1.7, 1.3, 1.0)
	var tween := create_tween()
	tween.tween_property(_press_any_key, "modulate", shine_color, 0.10)
	tween.tween_property(_press_any_key, "modulate", original_modulate, 0.12)
	await tween.finished


func _start_press_any_key_pulse() -> void:
	_stop_press_any_key_pulse()
	if _press_any_key == null:
		return
	_press_any_key.modulate.a = 0.55
	_press_any_key_tween = create_tween()
	_press_any_key_tween.set_loops()
	_press_any_key_tween.tween_property(_press_any_key, "modulate:a", 1.0, 0.6)
	_press_any_key_tween.tween_property(_press_any_key, "modulate:a", 0.55, 0.6)


func _stop_press_any_key_pulse() -> void:
	if _press_any_key_tween != null:
		_press_any_key_tween.kill()
		_press_any_key_tween = null


func _set_optional_property(target: Object, property_name: StringName, value: Variant) -> void:
	if target == null:
		return

	for property_info in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			target.set(property_name, value)
			return


func _wait(duration: float) -> void:
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout
