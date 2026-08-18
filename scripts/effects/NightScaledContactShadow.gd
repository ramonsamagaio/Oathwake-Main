class_name NightScaledContactShadow
extends Polygon2D

const DEFAULT_COLOR := Color(0.05, 0.04, 0.07, 1.0)

var _base_alpha := 0.18
var _night_minimum_strength := 0.28
var _cycle: Node


func _ready() -> void:
	add_to_group("night_scaled_contact_shadow")
	set_meta("contact_shadow", true)
	set_meta("base_shadow_alpha", _base_alpha)
	_connect_cycle()
	_sync_night_strength()


func configure(config: Dictionary) -> void:
	var offset_value: Variant = config.get("offset", {})
	position = _vector_from_value(offset_value, Vector2(0.0, 24.0))
	z_index = int(config.get("z_index", -2))
	z_as_relative = true
	var half_width := maxf(float(config.get("width", 7.0)), 2.0)
	var half_height := maxf(float(config.get("length", 12.0)) * 0.125, 1.25)
	polygon = PackedVector2Array([
		Vector2(-half_width, -half_height),
		Vector2(half_width, -half_height),
		Vector2(half_width + 2.0, 0.0),
		Vector2(half_width, half_height),
		Vector2(-half_width, half_height),
		Vector2(-half_width - 2.0, 0.0),
	])
	var configured_color := Color.from_string(str(config.get("color", "#0d0a12ff")), DEFAULT_COLOR)
	_base_alpha = clampf(float(config.get("opacity", 0.18)), 0.0, 1.0)
	_night_minimum_strength = clampf(float(config.get("night_minimum_strength", 0.28)), 0.0, 1.0)
	color = Color(configured_color.r, configured_color.g, configured_color.b, _base_alpha)
	set_meta("contact_shadow", true)
	set_meta("base_shadow_alpha", _base_alpha)
	_sync_night_strength()


func _connect_cycle() -> void:
	_cycle = get_tree().get_first_node_in_group("day_night_cycle")
	if _cycle == null or not _cycle.has_signal("lighting_state_changed"):
		return
	var callback := Callable(self, "_on_lighting_state_changed")
	if not _cycle.is_connected("lighting_state_changed", callback):
		_cycle.connect("lighting_state_changed", callback)


func _on_lighting_state_changed(_time: float, _night: float, daylight: float, _direction: float) -> void:
	_apply_daylight(daylight)


func _sync_night_strength() -> void:
	if not is_inside_tree():
		return
	if _cycle == null or not is_instance_valid(_cycle):
		_connect_cycle()
	var daylight := 1.0
	if _cycle != null and _cycle.has_method("get_daylight_strength"):
		daylight = float(_cycle.call("get_daylight_strength"))
	_apply_daylight(daylight)


func _apply_daylight(daylight: float) -> void:
	var strength := lerpf(_night_minimum_strength, 1.0, clampf(daylight, 0.0, 1.0))
	color.a = _base_alpha * strength
	set_meta("shadow_night_strength", strength)


func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback
