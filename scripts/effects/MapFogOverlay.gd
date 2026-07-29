@tool
extends CanvasLayer

@export_category("Fog Overlay")
@export var effect_enabled := true
@export_range(0.0, 1.0, 0.01) var density := 0.42
@export var speed := Vector2(0.018, 0.007)
@export var fog_color := Color(0.62, 0.68, 0.72, 0.16)
@export_range(0.25, 12.0, 0.05) var fog_scale := 3.25
@export_range(0.0, 1.0, 0.01) var coverage := 0.52
@export_range(0.01, 0.75, 0.01) var softness := 0.26
@export_range(0.0, 1.0, 0.01) var detail_mix := 0.42

@export_category("World Anchoring")
@export var anchor_to_world := true
@export_range(0.0, 2.0, 0.01) var world_anchor_strength := 1.0

@onready var fog_rect: ColorRect = $FogRect

var _config: Dictionary = {}
var _night_strength := 0.0
var _last_camera_offset := Vector2(INF, INF)
var _motion_time := 0.0


func _ready() -> void:
	add_to_group("map_fog_overlay")
	_reload_content_config()
	_connect_content_reload()
	_sync_material()
	_update_world_anchor(true)
	set_process(true)


func _process(delta: float) -> void:
	_update_night_strength()
	if visible:
		_motion_time = fmod(_motion_time + maxf(delta, 0.0), 100000.0)
		_update_motion_time()
		_update_world_anchor(false)


func refresh_from_settings() -> void:
	_config.clear()
	_sync_material()
	_update_world_anchor(true)


func refresh_from_content() -> void:
	_reload_content_config()
	_sync_material()
	_update_world_anchor(true)


func _reload_content_config() -> void:
	_config.clear()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var world_value: Variant = profile.get("world_visuals", {})
	if world_value is Dictionary:
		var fog_value: Variant = (world_value as Dictionary).get("layered_fog", {})
		if fog_value is Dictionary:
			_config = (fog_value as Dictionary).duplicate(true)


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "refresh_from_content")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func _sync_material() -> void:
	var enabled_value := bool(_config.get("enabled", effect_enabled))
	visible = enabled_value
	if not is_node_ready() or fog_rect == null:
		return
	fog_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	var material := fog_rect.material as ShaderMaterial
	if material == null or material.shader == null:
		fog_rect.visible = false
		return
	fog_rect.visible = enabled_value
	material.set_shader_parameter("enabled", enabled_value)
	material.set_shader_parameter("density", float(_config.get("density", density)))
	material.set_shader_parameter("speed", _vector(_config.get("speed", speed), speed))
	material.set_shader_parameter("fog_color", _color(_config.get("color", fog_color), fog_color))
	material.set_shader_parameter("fog_scale", float(_config.get("scale", fog_scale)))
	material.set_shader_parameter("coverage", float(_config.get("coverage", coverage)))
	material.set_shader_parameter("softness", float(_config.get("softness", softness)))
	material.set_shader_parameter("detail_mix", float(_config.get("detail_mix", detail_mix)))
	var anchor_strength := float(_config.get("world_anchor_strength", world_anchor_strength)) if anchor_to_world else 0.0
	material.set_shader_parameter("world_anchor_strength", anchor_strength)
	material.set_shader_parameter("motion_time", _motion_time)
	material.set_shader_parameter("ground_density", float(_config.get("ground_density", 0.28)))
	material.set_shader_parameter("ground_height", float(_config.get("ground_height", 0.42)))
	material.set_shader_parameter("ground_scale", float(_config.get("ground_scale", 5.2)))
	material.set_shader_parameter("ground_speed", _vector(_config.get("ground_speed", {}), Vector2(-0.010, 0.004)))
	material.set_shader_parameter("middle_density", float(_config.get("middle_density", 0.16)))
	material.set_shader_parameter("middle_band_center", float(_config.get("middle_band_center", 0.56)))
	material.set_shader_parameter("middle_band_width", float(_config.get("middle_band_width", 0.40)))
	material.set_shader_parameter("depth_density", float(_config.get("depth_density", 0.08)))
	material.set_shader_parameter("depth_falloff", float(_config.get("depth_falloff", 1.35)))
	material.set_shader_parameter("day_multiplier", float(_config.get("day_multiplier", 0.72)))
	material.set_shader_parameter("night_multiplier", float(_config.get("night_multiplier", 1.18)))
	material.set_shader_parameter("night_strength", _night_strength)


func _update_motion_time() -> void:
	if fog_rect == null or not (fog_rect.material is ShaderMaterial):
		return
	(fog_rect.material as ShaderMaterial).set_shader_parameter("motion_time", _motion_time)
	set_meta("fog_motion_time", _motion_time)


func _update_night_strength() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	var strength := 0.0
	if cycle != null and cycle.has_method("get_night_strength"):
		strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	if is_equal_approx(strength, _night_strength):
		return
	_night_strength = strength
	if fog_rect != null and fog_rect.material is ShaderMaterial:
		(fog_rect.material as ShaderMaterial).set_shader_parameter("night_strength", _night_strength)


func _update_world_anchor(force_update: bool) -> void:
	if not is_node_ready() or fog_rect == null or not anchor_to_world:
		return
	var material := fog_rect.material as ShaderMaterial
	if material == null or material.shader == null:
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
	var world_span := (world_bottom_right - world_top_left).abs()
	world_span.x = maxf(world_span.x, 1.0)
	world_span.y = maxf(world_span.y, 1.0)
	var camera_offset := Vector2(world_top_left.x / world_span.x, world_top_left.y / world_span.y)
	if not force_update and camera_offset.is_equal_approx(_last_camera_offset):
		return
	_last_camera_offset = camera_offset
	material.set_shader_parameter("camera_offset", camera_offset)


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
