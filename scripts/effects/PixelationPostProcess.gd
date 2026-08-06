extends Node

signal pixelation_state_changed(enabled: bool)

const BUTTON_REFRESH_INTERVAL := 0.20
const DEFAULT_PIXEL_SIZE := 4.0
const DEFAULT_STRENGTH := 1.0
const DEFAULT_PIXEL_ASPECT := 1.0
const DEFAULT_COLOR_STEPS := 0
const DEFAULT_DITHER_STRENGTH := 0.0

var _post_config: Dictionary = {}
var _runtime_enabled_override: Variant = null
var _debug_button: Button
var _screen_effects_target: Node
var _last_emitted_state := false
var _has_emitted_state := false
var _button_refresh_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_content_reload()
	_reload_config()
	call_deferred("_ensure_debug_button")
	call_deferred("_sync_screen_effects_target")
	set_process(true)


func _process(delta: float) -> void:
	_button_refresh_left -= delta
	if _button_refresh_left > 0.0:
		return
	_button_refresh_left = BUTTON_REFRESH_INTERVAL
	_ensure_debug_button()
	_sync_screen_effects_target()


func is_pixelation_enabled() -> bool:
	if _runtime_enabled_override is bool:
		return bool(_runtime_enabled_override)
	return bool(_post_config.get("pixelation_enabled", false))


func toggle_pixelation_runtime() -> bool:
	_runtime_enabled_override = not is_pixelation_enabled()
	_apply_runtime_override_to_target()
	_update_debug_button()
	_emit_state_if_changed(is_pixelation_enabled())
	return is_pixelation_enabled()


func set_pixelation_runtime_enabled(enabled: bool) -> void:
	_runtime_enabled_override = enabled
	_apply_runtime_override_to_target()
	_update_debug_button()
	_emit_state_if_changed(is_pixelation_enabled())


func clear_pixelation_runtime_override() -> void:
	_runtime_enabled_override = null
	_apply_runtime_override_to_target()
	_update_debug_button()
	_emit_state_if_changed(is_pixelation_enabled())


func get_pixelation_settings() -> Dictionary:
	return {
		"enabled": is_pixelation_enabled(),
		"pixel_size": clampf(round(float(_post_config.get("pixelation_pixel_size", DEFAULT_PIXEL_SIZE))), 1.0, 32.0),
		"strength": clampf(float(_post_config.get("pixelation_strength", DEFAULT_STRENGTH)), 0.0, 1.0),
		"pixel_aspect": clampf(float(_post_config.get("pixelation_aspect", DEFAULT_PIXEL_ASPECT)), 0.5, 2.0),
		"color_steps": clampi(int(_post_config.get("pixelation_color_steps", DEFAULT_COLOR_STEPS)), 0, 32),
		"dither_strength": clampf(float(_post_config.get("pixelation_dither_strength", DEFAULT_DITHER_STRENGTH)), 0.0, 1.0),
	}


func refresh_from_content() -> void:
	_reload_config()
	_apply_runtime_override_to_target()
	_update_debug_button()
	_emit_state_if_changed(is_pixelation_enabled())


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_signal("content_reloaded"):
		return
	var callback := Callable(self, "_on_content_reloaded")
	if not content_db.content_reloaded.is_connected(callback):
		content_db.content_reloaded.connect(callback)


func _on_content_reloaded() -> void:
	refresh_from_content()


func _reload_config() -> void:
	_post_config.clear()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var world_value: Variant = profile.get("world_visuals", {})
	if not world_value is Dictionary:
		return
	var post_value: Variant = (world_value as Dictionary).get("post_processing", {})
	if post_value is Dictionary:
		_post_config = (post_value as Dictionary).duplicate(true)


func _sync_screen_effects_target() -> void:
	var candidate := get_tree().get_first_node_in_group("screen_effects")
	if candidate == _screen_effects_target and candidate != null and is_instance_valid(candidate):
		return
	_screen_effects_target = candidate
	_apply_runtime_override_to_target()


func _apply_runtime_override_to_target() -> void:
	if _screen_effects_target == null or not is_instance_valid(_screen_effects_target):
		return
	if _runtime_enabled_override is bool:
		if _screen_effects_target.has_method("set_pixelation_runtime_enabled"):
			_screen_effects_target.call("set_pixelation_runtime_enabled", bool(_runtime_enabled_override))
	elif _screen_effects_target.has_method("clear_pixelation_runtime_override"):
		_screen_effects_target.call("clear_pixelation_runtime_override")


func _emit_state_if_changed(enabled: bool) -> void:
	if _has_emitted_state and _last_emitted_state == enabled:
		return
	_last_emitted_state = enabled
	_has_emitted_state = true
	pixelation_state_changed.emit(enabled)


func _ensure_debug_button() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		_debug_button = null
		return
	var ui := scene.get_node_or_null("UI")
	if ui == null:
		_debug_button = null
		return
	var load_button := ui.get_node_or_null("LoadButton") as Button
	if load_button == null:
		_debug_button = null
		return

	var existing := ui.get_node_or_null("PixelFilterButton") as Button
	if existing == null:
		existing = Button.new()
		existing.name = "PixelFilterButton"
		existing.focus_mode = Control.FOCUS_NONE
		existing.tooltip_text = "Liga/desliga a pixelizacao dentro do compositor principal. Os parametros persistentes ficam em VFX Profiles > default > Final Pixelation Filter."
		ui.add_child(existing)
	var callback := Callable(self, "_on_debug_button_pressed")
	if not existing.pressed.is_connected(callback):
		existing.pressed.connect(callback)
	_debug_button = existing
	_place_debug_button(load_button)
	_update_debug_button()


func _place_debug_button(load_button: Button) -> void:
	if _debug_button == null or not is_instance_valid(_debug_button):
		return
	_debug_button.anchor_left = load_button.anchor_left
	_debug_button.anchor_top = load_button.anchor_top
	_debug_button.anchor_right = load_button.anchor_right
	_debug_button.anchor_bottom = load_button.anchor_bottom
	_debug_button.grow_horizontal = load_button.grow_horizontal
	_debug_button.grow_vertical = load_button.grow_vertical
	var source_height := maxf(load_button.offset_bottom - load_button.offset_top, 36.0)
	var gap := 6.0
	_debug_button.offset_left = load_button.offset_left
	_debug_button.offset_right = load_button.offset_right
	_debug_button.offset_top = load_button.offset_bottom + gap
	_debug_button.offset_bottom = _debug_button.offset_top + source_height
	_debug_button.visible = load_button.visible


func _update_debug_button() -> void:
	if _debug_button == null or not is_instance_valid(_debug_button):
		return
	var enabled := is_pixelation_enabled()
	_debug_button.text = "PIXEL FILTER: ON" if enabled else "PIXEL FILTER: OFF"
	_debug_button.modulate = Color(0.78, 1.0, 0.78, 1.0) if enabled else Color.WHITE


func _on_debug_button_pressed() -> void:
	toggle_pixelation_runtime()
