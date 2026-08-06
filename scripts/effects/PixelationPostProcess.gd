extends Node

signal pixelation_state_changed(enabled: bool)

const PIXELATION_SHADER := preload("res://shaders/pixelation_post_process.gdshader")
const POST_PROCESS_LAYER := 6
const BUTTON_REFRESH_INTERVAL := 0.20

const DEFAULT_PIXEL_SIZE := 4.0
const DEFAULT_STRENGTH := 1.0
const DEFAULT_PIXEL_ASPECT := 1.0
const DEFAULT_COLOR_STEPS := 0
const DEFAULT_DITHER_STRENGTH := 0.0

var _canvas_layer: CanvasLayer
var _back_buffer_copy: BackBufferCopy
var _pixel_rect: ColorRect
var _material: ShaderMaterial
var _post_config: Dictionary = {}
var _runtime_enabled_override: Variant = null
var _debug_button: Button
var _last_emitted_state := false
var _has_emitted_state := false
var _button_refresh_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_renderer()
	_connect_content_reload()
	_reload_config()
	_apply_material_settings()
	call_deferred("_ensure_debug_button")
	set_process(true)


func _process(delta: float) -> void:
	_button_refresh_left -= delta
	if _button_refresh_left > 0.0:
		return
	_button_refresh_left = BUTTON_REFRESH_INTERVAL
	_ensure_debug_button()


func is_pixelation_enabled() -> bool:
	if _runtime_enabled_override is bool:
		return bool(_runtime_enabled_override)
	return bool(_post_config.get("pixelation_enabled", false))


func toggle_pixelation_runtime() -> bool:
	_runtime_enabled_override = not is_pixelation_enabled()
	_apply_material_settings()
	return is_pixelation_enabled()


func set_pixelation_runtime_enabled(enabled: bool) -> void:
	_runtime_enabled_override = enabled
	_apply_material_settings()


func clear_pixelation_runtime_override() -> void:
	_runtime_enabled_override = null
	_apply_material_settings()


func get_pixelation_settings() -> Dictionary:
	return {
		"enabled": is_pixelation_enabled(),
		"pixel_size": _get_pixel_size(),
		"strength": _get_strength(),
		"pixel_aspect": _get_pixel_aspect(),
		"color_steps": _get_color_steps(),
		"dither_strength": _get_dither_strength(),
	}


func refresh_from_content() -> void:
	_reload_config()
	_apply_material_settings()


func _build_renderer() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "PixelationPostProcessLayer"
	_canvas_layer.layer = POST_PROCESS_LAYER
	add_child(_canvas_layer)

	_back_buffer_copy = BackBufferCopy.new()
	_back_buffer_copy.name = "PixelationBackBufferCopy"
	_back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	_canvas_layer.add_child(_back_buffer_copy)

	_material = ShaderMaterial.new()
	_material.shader = PIXELATION_SHADER

	_pixel_rect = ColorRect.new()
	_pixel_rect.name = "PixelationRect"
	_pixel_rect.material = _material
	_pixel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pixel_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_pixel_rect.anchor_left = 0.0
	_pixel_rect.anchor_top = 0.0
	_pixel_rect.anchor_right = 1.0
	_pixel_rect.anchor_bottom = 1.0
	_pixel_rect.offset_left = 0.0
	_pixel_rect.offset_top = 0.0
	_pixel_rect.offset_right = 0.0
	_pixel_rect.offset_bottom = 0.0
	_pixel_rect.visible = false
	_canvas_layer.add_child(_pixel_rect)


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


func _apply_material_settings() -> void:
	if _material == null or _pixel_rect == null or _back_buffer_copy == null:
		return
	var enabled := is_pixelation_enabled()
	_material.set_shader_parameter("enabled", enabled)
	_material.set_shader_parameter("pixel_size", _get_pixel_size())
	_material.set_shader_parameter("strength", _get_strength())
	_material.set_shader_parameter("pixel_aspect", _get_pixel_aspect())
	_material.set_shader_parameter("color_steps", _get_color_steps())
	_material.set_shader_parameter("dither_strength", _get_dither_strength())
	_pixel_rect.visible = enabled
	_back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if enabled else BackBufferCopy.COPY_MODE_DISABLED
	_update_debug_button()
	_emit_state_if_changed(enabled)


func _get_pixel_size() -> float:
	return clampf(round(float(_post_config.get("pixelation_pixel_size", DEFAULT_PIXEL_SIZE))), 1.0, 32.0)


func _get_strength() -> float:
	return clampf(float(_post_config.get("pixelation_strength", DEFAULT_STRENGTH)), 0.0, 1.0)


func _get_pixel_aspect() -> float:
	return clampf(float(_post_config.get("pixelation_aspect", DEFAULT_PIXEL_ASPECT)), 0.5, 2.0)


func _get_color_steps() -> int:
	return clampi(int(_post_config.get("pixelation_color_steps", DEFAULT_COLOR_STEPS)), 0, 32)


func _get_dither_strength() -> float:
	return clampf(float(_post_config.get("pixelation_dither_strength", DEFAULT_DITHER_STRENGTH)), 0.0, 1.0)


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
		existing.tooltip_text = "Liga/desliga o filtro de pixelizacao do mundo. O Content Editor define tamanho do pixel, intensidade, formato e reducao de cores."
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
