class_name AlabasterWeatherController
extends Node

signal weather_changed(weather_id: String)
signal weather_state_changed(state: Dictionary)

const TRANSITION_SECONDS := 7.0
const WEATHER_ORDER := ["clear", "windy", "rain", "storm", "snow", "embers"]
const PROFILES := {
	"clear": {
		"ambient": Color(1.0, 1.0, 0.97), "sun_color": Color(1.0, 0.93, 0.78), "sun_strength": 1.0,
		"wind_strength": 0.28, "wind_speed": 1.0, "wind_direction": Vector2(1.0, 0.12),
		"clouds": 0.08, "rain": 0.0, "snow": 0.0, "embers": 0.0, "wetness": 0.0, "lightning": 0.0,
	},
	"windy": {
		"ambient": Color(0.93, 0.96, 0.94), "sun_color": Color(0.94, 0.96, 1.0), "sun_strength": 0.82,
		"wind_strength": 0.82, "wind_speed": 2.2, "wind_direction": Vector2(1.0, 0.20),
		"clouds": 0.38, "rain": 0.0, "snow": 0.0, "embers": 0.0, "wetness": 0.0, "lightning": 0.0,
	},
	"rain": {
		"ambient": Color(0.72, 0.79, 0.84), "sun_color": Color(0.72, 0.80, 0.88), "sun_strength": 0.40,
		"wind_strength": 0.52, "wind_speed": 1.7, "wind_direction": Vector2(0.9, 0.32),
		"clouds": 0.76, "rain": 0.68, "snow": 0.0, "embers": 0.0, "wetness": 0.72, "lightning": 0.0,
	},
	"storm": {
		"ambient": Color(0.50, 0.58, 0.69), "sun_color": Color(0.62, 0.70, 0.82), "sun_strength": 0.16,
		"wind_strength": 1.0, "wind_speed": 3.1, "wind_direction": Vector2(1.0, 0.42),
		"clouds": 1.0, "rain": 1.0, "snow": 0.0, "embers": 0.0, "wetness": 1.0, "lightning": 0.0,
	},
	"snow": {
		"ambient": Color(0.82, 0.88, 0.94), "sun_color": Color(0.78, 0.87, 1.0), "sun_strength": 0.52,
		"wind_strength": 0.36, "wind_speed": 1.1, "wind_direction": Vector2(0.7, 0.15),
		"clouds": 0.66, "rain": 0.0, "snow": 0.82, "embers": 0.0, "wetness": 0.20, "lightning": 0.0,
	},
	"embers": {
		"ambient": Color(0.88, 0.69, 0.56), "sun_color": Color(1.0, 0.50, 0.28), "sun_strength": 0.48,
		"wind_strength": 0.58, "wind_speed": 1.5, "wind_direction": Vector2(-0.55, 0.12),
		"clouds": 0.46, "rain": 0.0, "snow": 0.0, "embers": 0.74, "wetness": 0.0, "lightning": 0.0,
	},
}

@export var initial_weather := "clear"
@export var auto_cycle := false
@export var auto_cycle_seconds := 24.0
@export_node_path("Node") var environment_path := NodePath("../Environment")
@export_node_path("Node2D") var visuals_path := NodePath("../WeatherLayer/Visuals")

var current_weather := "clear"
var target_weather := "clear"
var _from_state: Dictionary = {}
var _current_state: Dictionary = {}
var _target_state: Dictionary = {}
var _transition_elapsed := TRANSITION_SECONDS
var _cycle_elapsed := 0.0
var _storm_timer := 2.0
var _lightning := 0.0

@onready var _environment := get_node_or_null(environment_path)
@onready var _visuals := get_node_or_null(visuals_path)


func _ready() -> void:
	current_weather = initial_weather if PROFILES.has(initial_weather) else "clear"
	target_weather = current_weather
	_current_state = (PROFILES[current_weather] as Dictionary).duplicate(true)
	_from_state = _current_state.duplicate(true)
	_target_state = _current_state.duplicate(true)
	_publish_state()
	set_process(auto_cycle or current_weather == "storm")


func _process(delta: float) -> void:
	if auto_cycle:
		_cycle_elapsed += delta
		if _cycle_elapsed >= auto_cycle_seconds:
			_cycle_elapsed = 0.0
			var next_index := (WEATHER_ORDER.find(target_weather) + 1) % WEATHER_ORDER.size()
			set_weather(WEATHER_ORDER[next_index])

	if _transition_elapsed < TRANSITION_SECONDS:
		_transition_elapsed = minf(_transition_elapsed + delta, TRANSITION_SECONDS)
		var linear_t := _transition_elapsed / TRANSITION_SECONDS
		var smooth_t := linear_t * linear_t * (3.0 - 2.0 * linear_t)
		_current_state = _blend_profiles(_from_state, _target_state, smooth_t)
		if _transition_elapsed >= TRANSITION_SECONDS:
			current_weather = target_weather
			weather_changed.emit(current_weather)

	_update_lightning(delta)
	_current_state["lightning"] = _lightning
	_publish_state()
	if not auto_cycle and _transition_elapsed >= TRANSITION_SECONDS and target_weather != "storm":
		set_process(false)


func set_weather(weather_id: String) -> void:
	if not PROFILES.has(weather_id) or weather_id == target_weather:
		return
	_from_state = _current_state.duplicate(true)
	_target_state = (PROFILES[weather_id] as Dictionary).duplicate(true)
	target_weather = weather_id
	_transition_elapsed = 0.0
	_cycle_elapsed = 0.0
	set_process(true)
	weather_changed.emit(target_weather)


func toggle_auto_cycle() -> void:
	auto_cycle = not auto_cycle
	_cycle_elapsed = 0.0
	set_process(auto_cycle or _transition_elapsed < TRANSITION_SECONDS or target_weather == "storm")


func get_transition_progress() -> float:
	return clampf(_transition_elapsed / TRANSITION_SECONDS, 0.0, 1.0)


func _blend_profiles(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	var blended := {}
	for key in to.keys():
		var from_value: Variant = from.get(key, to[key])
		var to_value: Variant = to[key]
		if to_value is Color:
			blended[key] = (from_value as Color).lerp(to_value as Color, weight)
		elif to_value is Vector2:
			blended[key] = (from_value as Vector2).lerp(to_value as Vector2, weight)
		else:
			blended[key] = lerpf(float(from_value), float(to_value), weight)
	return blended


func _update_lightning(delta: float) -> void:
	_lightning = move_toward(_lightning, 0.0, delta * 2.8)
	if target_weather != "storm":
		_storm_timer = 2.0
		return
	_storm_timer -= delta
	if _storm_timer <= 0.0:
		_lightning = 1.0
		_storm_timer = randf_range(2.2, 6.0)


func _publish_state() -> void:
	if _environment != null and _environment.has_method("apply_weather_state"):
		_environment.call("apply_weather_state", _current_state)
	if _visuals != null and _visuals.has_method("apply_weather_state"):
		_visuals.call("apply_weather_state", _current_state)
	weather_state_changed.emit(_current_state)
