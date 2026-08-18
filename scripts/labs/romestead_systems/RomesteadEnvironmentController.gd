class_name RomesteadEnvironmentController
extends Node

signal time_changed(display_time: String)

@export var time_of_day := 16.5
@export var day_length_seconds := 210.0
@export var time_paused := false
@export_node_path("CanvasModulate") var canvas_modulate_path := NodePath("../WorldModulate")
@export_node_path("DirectionalLight2D") var sun_path := NodePath("../Sun")
@export_node_path("DirectionalLight2D") var moon_path := NodePath("../Moon")
@export_node_path("Node2D") var world_path := NodePath("../World")

var weather_state := {
	"ambient": Color.WHITE,
	"sun_color": Color(1.0, 0.92, 0.78),
	"sun_strength": 1.0,
	"wetness": 0.0,
	"wind_strength": 0.15,
	"wind_speed": 1.0,
	"wind_direction": Vector2(1.0, 0.15),
	"lightning": 0.0,
}

@onready var _world_modulate := get_node_or_null(canvas_modulate_path) as CanvasModulate
@onready var _sun := get_node_or_null(sun_path) as DirectionalLight2D
@onready var _moon := get_node_or_null(moon_path) as DirectionalLight2D
@onready var _world := get_node_or_null(world_path)


func _ready() -> void:
	add_to_group("romestead_environment_controller")
	_update_environment()
	set_process(not time_paused)


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta * 24.0 / maxf(day_length_seconds, 1.0), 24.0)
	_update_environment()
	time_changed.emit(get_time_string())


func apply_weather_state(state: Dictionary) -> void:
	for key in weather_state.keys():
		if state.has(key):
			weather_state[key] = state[key]
	if time_paused:
		_update_environment()


func set_world(world: Node) -> void:
	_world = world
	_update_environment()


func set_time(new_hour: float) -> void:
	time_of_day = fposmod(new_hour, 24.0)
	_update_environment()


func toggle_time_pause() -> void:
	time_paused = not time_paused
	set_process(not time_paused)
	_update_environment()


func get_time_string() -> String:
	var hours := floori(time_of_day)
	var minutes := floori((time_of_day - float(hours)) * 60.0)
	return "%02d:%02d" % [hours, minutes]


func get_daylight_strength() -> float:
	return clampf(sin((time_of_day - 6.0) / 24.0 * TAU), 0.0, 1.0)


func _update_environment() -> void:
	var daylight := clampf(sin((time_of_day - 6.0) / 24.0 * TAU), 0.0, 1.0)
	var twilight := clampf(1.0 - absf(time_of_day - 18.0) / 2.2, 0.0, 1.0)
	var dawn := clampf(1.0 - absf(time_of_day - 6.0) / 2.0, 0.0, 1.0)
	var day_color := _sample_day_color(time_of_day)
	var weather_color: Color = weather_state["ambient"]
	var final_ambient := day_color * weather_color
	final_ambient.a = 1.0
	if _world_modulate != null:
		_world_modulate.color = final_ambient

	if _sun != null:
		_sun.energy = daylight * float(weather_state["sun_strength"]) * 0.04
		_sun.color = (weather_state["sun_color"] as Color).lerp(Color(1.0, 0.68, 0.48), maxf(twilight, dawn) * 0.58)
		_sun.rotation = (time_of_day / 24.0) * TAU - PI * 0.5
	if _moon != null:
		_moon.energy = (1.0 - daylight) * 0.28
		_moon.rotation = (time_of_day / 24.0) * TAU + PI * 0.5

	var darkness := clampf(1.0 - daylight * 0.92, 0.08, 1.0)
	var seconds := Time.get_ticks_msec() * 0.001
	for node in get_tree().get_nodes_in_group("romestead_lab_lights"):
		var light := node as PointLight2D
		if light == null:
			continue
		var base_energy: float = float(light.get_meta("base_energy", 1.0))
		var phase: float = float(light.get_meta("flicker_phase", 0.0))
		var flicker := 0.92 + sin(seconds * 9.0 + phase) * 0.055 + sin(seconds * 17.0 + phase * 0.7) * 0.025
		light.energy = base_energy * lerpf(0.28, 1.0, darkness) * flicker

	if _world != null and _world.has_method("set_environment"):
		_world.call(
			"set_environment",
			float(weather_state["wetness"]),
			float(weather_state["lightning"]),
			float(weather_state["wind_strength"]),
			float(weather_state["wind_speed"]),
			weather_state["wind_direction"],
			time_of_day,
			daylight
		)
	for receiver in get_tree().get_nodes_in_group("romestead_environment_receivers"):
		if receiver == _world or not receiver.has_method("set_romestead_environment"):
			continue
		receiver.call(
			"set_romestead_environment",
			float(weather_state["wetness"]),
			float(weather_state["lightning"]),
			float(weather_state["wind_strength"]),
			float(weather_state["wind_speed"]),
			weather_state["wind_direction"],
			time_of_day,
			daylight
		)


func _sample_day_color(hour: float) -> Color:
	var night := Color(0.20, 0.24, 0.34)
	var dawn := Color(0.72, 0.53, 0.43)
	var day := Color(1.05, 1.04, 0.90)
	var dusk := Color(0.63, 0.40, 0.38)
	if hour < 5.0:
		return night
	if hour < 7.5:
		return night.lerp(dawn, (hour - 5.0) / 2.5)
	if hour < 10.0:
		return dawn.lerp(day, (hour - 7.5) / 2.5)
	if hour < 17.0:
		return day
	if hour < 20.0:
		return day.lerp(dusk, (hour - 17.0) / 3.0)
	if hour < 22.0:
		return dusk.lerp(night, (hour - 20.0) / 2.0)
	return night
