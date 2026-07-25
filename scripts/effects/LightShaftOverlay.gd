@tool
extends CanvasLayer

@onready var shaft_rect: ColorRect = $ShaftRect

var _config: Dictionary = {}
var _night_strength := 0.0
var _last_camera_offset := Vector2(INF, INF)


func _ready() -> void:
	add_to_group("light_shaft_overlay")
	_reload_config()
	_connect_content_reload()
	_apply_config()
	set_process(true)


func _process(_delta: float) -> void:
	_update_night_strength()
	_update_world_anchor(false)


func refresh_from_content() -> void:
	_reload_config()
	_apply_config()
	_update_world_anchor(true)


func _reload_config() -> void:
	_config.clear()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var world_value: Variant = profile.get("world_visuals", {})
	if world_value is Dictionary:
		var shafts_value: Variant = (world_value as Dictionary).get("light_shafts", {})
		if shafts_value is Dictionary:
			_config = (shafts_value as Dictionary).duplicate(true)


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "refresh_from_content")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func _apply_config() -> void:
	visible = bool(_config.get("enabled", true))
	if not is_node_ready() or shaft_rect == null or not (shaft_rect.material is ShaderMaterial):
		return
	var material := shaft_rect.material as ShaderMaterial
	material.set_shader_parameter("enabled", visible)
	material.set_shader_parameter("shaft_color", _color(_config.get("color", "#FFE8A81C"), Color(1.0, 0.91, 0.66, 0.11)))
	material.set_shader_parameter("direction", _vector(_config.get("direction", {}), Vector2(-0.38, 1.0)))
	material.set_shader_parameter("intensity", maxf(float(_config.get("intensity", 0.32)), 0.0))
	material.set_shader_parameter("beam_count", maxf(float(_config.get("beam_count", 4.0)), 1.0))
	material.set_shader_parameter("beam_width", clampf(float(_config.get("beam_width", 0.22)), 0.02, 0.8))
	material.set_shader_parameter("softness", clampf(float(_config.get("softness", 0.16)), 0.01, 0.5))
	material.set_shader_parameter("drift_speed", maxf(float(_config.get("drift_speed", 0.045)), 0.0))
	material.set_shader_parameter("noise_strength", clampf(float(_config.get("noise_strength", 0.28)), 0.0, 1.0))
	material.set_shader_parameter("world_anchor_strength", maxf(float(_config.get("world_anchor_strength", 0.65)), 0.0))
	material.set_shader_parameter("day_multiplier", maxf(float(_config.get("day_multiplier", 1.0)), 0.0))
	material.set_shader_parameter("night_multiplier", maxf(float(_config.get("night_multiplier", 0.08)), 0.0))
	material.set_shader_parameter("night_strength", _night_strength)


func _update_night_strength() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	var strength := 0.0
	if cycle != null and cycle.has_method("get_night_strength"):
		strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	if is_equal_approx(strength, _night_strength):
		return
	_night_strength = strength
	if shaft_rect != null and shaft_rect.material is ShaderMaterial:
		(shaft_rect.material as ShaderMaterial).set_shader_parameter("night_strength", _night_strength)


func _update_world_anchor(force_update: bool) -> void:
	if shaft_rect == null or not (shaft_rect.material is ShaderMaterial):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var inverse_canvas := viewport.get_canvas_transform().affine_inverse()
	var world_top_left := inverse_canvas * Vector2.ZERO
	var world_bottom_right := inverse_canvas * viewport_size
	var span := (world_bottom_right - world_top_left).abs()
	span.x = maxf(span.x, 1.0)
	span.y = maxf(span.y, 1.0)
	var camera_offset := Vector2(world_top_left.x / span.x, world_top_left.y / span.y)
	if not force_update and camera_offset.is_equal_approx(_last_camera_offset):
		return
	_last_camera_offset = camera_offset
	(shaft_rect.material as ShaderMaterial).set_shader_parameter("camera_offset", camera_offset)


func _vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func _color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)
