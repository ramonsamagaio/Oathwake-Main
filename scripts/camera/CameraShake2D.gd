extends Camera2D

@export var default_normal_shake_strength: float = 0.65
@export var default_normal_shake_duration: float = 0.075
@export var default_critical_shake_strength: float = 4.2
@export var default_critical_shake_duration: float = 0.18
@export var shake_decay_curve: float = 1.0

@export var wheel_zoom_enabled := true
@export var default_zoom_level: float = 2.0
@export var minimum_zoom: float = 1.25
@export var maximum_zoom: float = 3.25
@export var zoom_step: float = 0.15
@export var zoom_smoothing_speed: float = 10.0

var base_offset := Vector2.ZERO
var shake_strength := 0.0
var shake_time_left := 0.0
var shake_duration := 0.0
var target_zoom_level := 2.0
var _camera_config_signature := ""
var _display_config_signature := ""


func _ready() -> void:
	add_to_group("game_camera")
	base_offset = offset
	_refresh_camera_tuning()
	var content_db := get_node_or_null("/root/ContentDB")
	var refresh_callable := Callable(self, "_refresh_camera_tuning")
	if content_db != null and content_db.has_signal("content_reloaded") and not content_db.is_connected("content_reloaded", refresh_callable):
		content_db.connect("content_reloaded", refresh_callable)
	set_process(true)
	set_process_unhandled_input(true)


func request_shake(strength: float = -1.0, duration: float = -1.0) -> void:
	var vfx_profile := _get_vfx_profile()
	var requested_strength := default_critical_shake_strength if strength < 0.0 else strength
	var requested_duration := default_critical_shake_duration if duration < 0.0 else duration
	if strength < 0.0:
		requested_strength = float(vfx_profile.get("critical_shake_strength", requested_strength))
	if duration < 0.0:
		requested_duration = float(vfx_profile.get("critical_shake_duration", requested_duration))
	_start_shake(requested_strength, requested_duration)


func request_hit_shake(is_critical: bool) -> void:
	var profile := _get_vfx_profile()
	var strength := default_critical_shake_strength if is_critical else default_normal_shake_strength
	var duration := default_critical_shake_duration if is_critical else default_normal_shake_duration
	if is_critical:
		strength = float(profile.get("critical_shake_strength", strength))
		duration = float(profile.get("critical_shake_duration", duration))
	else:
		strength = float(profile.get("normal_shake_strength", strength))
		duration = float(profile.get("normal_shake_duration", duration))
	_start_shake(strength, duration)


func debug_trigger_critical_shake() -> void:
	request_hit_shake(true)


func _start_shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	shake_strength = maxf(shake_strength, strength)
	shake_time_left = maxf(shake_time_left, duration)
	shake_duration = maxf(shake_duration, duration)


func _unhandled_input(event: InputEvent) -> void:
	if not wheel_zoom_enabled or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_target_zoom(target_zoom_level + zoom_step)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_target_zoom(target_zoom_level - zoom_step)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_zoom(delta)
	_update_shake(delta)


func _update_zoom(delta: float) -> void:
	var weight := clampf(delta * maxf(zoom_smoothing_speed, 0.01), 0.0, 1.0)
	var next_zoom := lerpf(zoom.x, target_zoom_level, weight)
	zoom = Vector2.ONE * next_zoom


func _update_shake(delta: float) -> void:
	if shake_time_left <= 0.0:
		offset = base_offset
		return
	shake_time_left = maxf(shake_time_left - delta, 0.0)
	var progress := 1.0
	if shake_duration > 0.0:
		progress = clampf(shake_time_left / shake_duration, 0.0, 1.0)
	var eased := pow(progress, maxf(shake_decay_curve, 0.01))
	var current_strength := shake_strength * eased
	offset = base_offset + Vector2(
		randf_range(-current_strength, current_strength),
		randf_range(-current_strength, current_strength)
	)
	if shake_time_left <= 0.0:
		offset = base_offset
		shake_strength = 0.0
		shake_duration = 0.0


func _refresh_camera_tuning() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_player_tuning"):
		if _camera_config_signature.is_empty():
			_set_target_zoom(default_zoom_level, true)
		return
	var tuning: Dictionary = content_db.get_player_tuning("default")
	var camera_value: Variant = tuning.get("camera", {})
	var camera := camera_value as Dictionary if camera_value is Dictionary else {}
	var camera_signature := JSON.stringify(camera)
	if camera_signature != _camera_config_signature:
		_camera_config_signature = camera_signature
		wheel_zoom_enabled = bool(camera.get("wheel_zoom_enabled", wheel_zoom_enabled))
		default_zoom_level = maxf(float(camera.get("default_zoom", default_zoom_level)), 0.05)
		minimum_zoom = maxf(float(camera.get("minimum_zoom", minimum_zoom)), 0.05)
		maximum_zoom = maxf(float(camera.get("maximum_zoom", maximum_zoom)), minimum_zoom)
		zoom_step = maxf(float(camera.get("zoom_step", zoom_step)), 0.01)
		zoom_smoothing_speed = maxf(float(camera.get("zoom_smoothing_speed", zoom_smoothing_speed)), 0.01)
		_set_target_zoom(default_zoom_level, true)

	var display_value: Variant = tuning.get("display", {})
	var display := display_value as Dictionary if display_value is Dictionary else {}
	var display_signature := JSON.stringify(display)
	if display_signature != _display_config_signature:
		_display_config_signature = display_signature
		var settings_manager := get_node_or_null("/root/SettingsManager")
		if settings_manager != null and settings_manager.has_method("set_borderless_fullscreen"):
			settings_manager.call_deferred(
				"set_borderless_fullscreen",
				bool(display.get("borderless_fullscreen_on_start", false)),
				false
			)


func _set_target_zoom(value: float, apply_immediately := false) -> void:
	target_zoom_level = clampf(value, minimum_zoom, maximum_zoom)
	if apply_immediately:
		zoom = Vector2.ONE * target_zoom_level


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}
