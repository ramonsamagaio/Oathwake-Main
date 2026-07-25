@tool
extends Node2D

@export var surface_size := Vector2(320.0, 180.0):
	set(value):
		surface_size = Vector2(maxf(value.x, 8.0), maxf(value.y, 8.0))
		_refresh_polygon()
@export var use_content_profile := true

@onready var surface: Polygon2D = $Surface

var _night_strength := 0.0
var _water_config: Dictionary = {}


func _ready() -> void:
	add_to_group("water_surface")
	add_to_group("world_light_reactive")
	_reload_content_config()
	_connect_content_reload()
	_refresh_polygon()
	_apply_config()
	set_process(true)


func _process(_delta: float) -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	var strength := 0.0
	if cycle != null and cycle.has_method("get_night_strength"):
		strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	set_day_night_strength(strength)


func set_day_night_strength(strength: float) -> void:
	_night_strength = clampf(strength, 0.0, 1.0)
	var material := _get_surface_material()
	if material != null:
		material.set_shader_parameter("night_strength", _night_strength)


func configure(config: Dictionary) -> void:
	_water_config = config.duplicate(true)
	_apply_config()


func apply_to_canvas_item(item: CanvasItem, config: Dictionary = {}) -> void:
	if item == null:
		return
	var shader := load("res://shaders/water_surface_2d.gdshader") as Shader
	if shader == null:
		return
	var material := ShaderMaterial.new()
	material.resource_local_to_scene = true
	material.shader = shader
	item.material = material
	_apply_material_config(material, config if not config.is_empty() else _water_config)
	item.add_to_group("water_surface")
	item.set_meta("world_water_surface", true)


func _reload_content_config() -> void:
	_water_config.clear()
	if not use_content_profile:
		return
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var world_value: Variant = profile.get("world_visuals", {})
	if not (world_value is Dictionary):
		return
	var water_value: Variant = (world_value as Dictionary).get("water", {})
	if water_value is Dictionary:
		_water_config = (water_value as Dictionary).duplicate(true)


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "_on_content_reloaded")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func _on_content_reloaded() -> void:
	_reload_content_config()
	_apply_config()


func _apply_config() -> void:
	var material := _get_surface_material()
	if material == null:
		return
	_apply_material_config(material, _water_config)


func _apply_material_config(material: ShaderMaterial, config: Dictionary) -> void:
	material.set_shader_parameter("enabled", bool(config.get("enabled", true)))
	material.set_shader_parameter("shallow_color", _color(config.get("shallow_color", "#347184E0"), Color(0.20, 0.43, 0.53, 0.88)))
	material.set_shader_parameter("deep_color", _color(config.get("deep_color", "#14304FF0"), Color(0.08, 0.19, 0.30, 0.94)))
	material.set_shader_parameter("highlight_color", _color(config.get("highlight_color", "#94D1E0B8"), Color(0.58, 0.82, 0.88, 0.72)))
	material.set_shader_parameter("flow_direction", _vector(config.get("flow_direction", {}), Vector2(1.0, 0.18)))
	material.set_shader_parameter("flow_speed", maxf(float(config.get("flow_speed", 0.36)), 0.0))
	material.set_shader_parameter("ripple_scale", maxf(float(config.get("ripple_scale", 28.0)), 1.0))
	material.set_shader_parameter("ripple_strength", maxf(float(config.get("ripple_strength", 0.008)), 0.0))
	material.set_shader_parameter("reflection_strength", maxf(float(config.get("reflection_strength", 0.24)), 0.0))
	material.set_shader_parameter("caustic_strength", maxf(float(config.get("caustic_strength", 0.18)), 0.0))
	material.set_shader_parameter("edge_fade", clampf(float(config.get("edge_fade", 0.06)), 0.0, 0.5))
	material.set_shader_parameter("night_strength", _night_strength)


func _refresh_polygon() -> void:
	if not is_node_ready() or surface == null:
		return
	var half := surface_size * 0.5
	surface.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	surface.uv = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])


func _get_surface_material() -> ShaderMaterial:
	if not is_node_ready() or surface == null or not (surface.material is ShaderMaterial):
		return null
	return surface.material as ShaderMaterial


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
