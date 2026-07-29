extends Node

signal lighting_state_changed(time_of_day: float, night_strength: float, daylight_strength: float, sun_shadow_direction_degrees: float)

@export var cycle_duration_seconds: float = 120.0
@export var day_color: Color = Color(0.95, 0.965, 0.98, 1.0)
@export var night_color: Color = Color(0.28, 0.34, 0.55, 1.0)
@export var canvas_modulate_path: NodePath = "../WorldTint"
@export var state_label_path: NodePath = "../UI/DayNightLabel"

var time_of_day := 0.0

var canvas_modulate: CanvasModulate
var state_label: Label


func _ready() -> void:
	add_to_group("day_night_cycle")
	setup({})
	_update_day_night_visuals()


func setup(context: Dictionary) -> void:
	canvas_modulate = context.get("canvas_modulate", canvas_modulate) as CanvasModulate
	state_label = context.get("state_label", state_label) as Label
	if canvas_modulate == null:
		canvas_modulate = get_node_or_null(canvas_modulate_path) as CanvasModulate
	if state_label == null:
		state_label = get_node_or_null(state_label_path) as Label


func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + (delta / maxf(cycle_duration_seconds, 0.001)), 1.0)
	_update_day_night_visuals()


func set_time_of_day(normalized_time: float) -> void:
	time_of_day = fposmod(normalized_time, 1.0)
	_update_day_night_visuals()


func set_day() -> void:
	set_time_of_day(0.25)


func set_night() -> void:
	set_time_of_day(0.75)


func is_day() -> bool:
	return time_of_day < 0.5


func get_night_strength() -> float:
	return _get_night_strength()


func get_daylight_strength() -> float:
	return 1.0 - _get_night_strength()


func get_sun_shadow_direction_degrees() -> float:
	var solar := _get_solar_shadow_config()
	var morning := float(solar.get("morning_direction_degrees", -45.0))
	var evening := float(solar.get("evening_direction_degrees", 45.0))
	var day_progress := clampf(time_of_day / 0.5, 0.0, 1.0)
	return lerpf(morning, evening, smoothstep(0.0, 1.0, day_progress))


func _update_day_night_visuals() -> void:
	var night_strength := _get_night_strength()
	var daylight_strength := 1.0 - night_strength
	if canvas_modulate != null:
		canvas_modulate.color = day_color.lerp(night_color, night_strength)
	if state_label != null:
		state_label.text = "Day" if is_day() else "Night"
	for emitter in get_tree().get_nodes_in_group("world_light_emitter"):
		if emitter != null and emitter.has_method("set_day_night_strength"):
			emitter.call("set_day_night_strength", night_strength)
	lighting_state_changed.emit(time_of_day, night_strength, daylight_strength, get_sun_shadow_direction_degrees())


func _get_night_strength() -> float:
	if is_day():
		return 0.0
	var night_progress := (time_of_day - 0.5) / 0.5
	return sin(night_progress * PI)


func _get_solar_shadow_config() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return {}
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var shadow_value: Variant = profile.get("directional_shadow", {})
	if not (shadow_value is Dictionary):
		return {}
	var solar_value: Variant = (shadow_value as Dictionary).get("solar", {})
	return (solar_value as Dictionary).duplicate(true) if solar_value is Dictionary else {}
