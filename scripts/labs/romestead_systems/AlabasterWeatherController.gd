class_name AlabasterWeatherController
extends Node

signal weather_changed(weather_id: String)
signal weather_state_changed(state: Dictionary)

const TRANSITION_SECONDS := 7.0
const STATE_PUBLISH_HZ := 12.0
const STATE_PUBLISH_INTERVAL := 1.0 / STATE_PUBLISH_HZ
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
var _publish_elapsed := STATE_PUBLISH_INTERVAL
# --- Ciclo dirigido por data/weather.json (seção Weather do Content Editor) ---
# Antes: ordem fixa em WEATHER_ORDER, todo clima com a mesma duração
# (auto_cycle_seconds) e a mesma transição (TRANSITION_SECONDS). Agora cada
# clima tem peso no sorteio, duração min/max própria e transição própria.
const WEATHER_CONFIG_PATH := "res://data/weather.json"
var _weather_config: Dictionary = {}
var _cycle_target_seconds := 0.0
var _transition_seconds := TRANSITION_SECONDS
var _weather_rng := RandomNumberGenerator.new()

@onready var _environment := get_node_or_null(environment_path)
@onready var _visuals := get_node_or_null(visuals_path)


func _ready() -> void:
	_weather_rng.randomize()
	_load_weather_config()
	_cycle_target_seconds = _roll_duration(initial_weather)
	current_weather = initial_weather if PROFILES.has(initial_weather) else "clear"
	target_weather = current_weather
	_current_state = (PROFILES[current_weather] as Dictionary).duplicate(true)
	_from_state = _current_state.duplicate(true)
	_target_state = _current_state.duplicate(true)
	_publish_state()
	_publish_elapsed = 0.0
	set_process(auto_cycle or current_weather == "storm")


func _process(delta: float) -> void:
	_publish_elapsed += delta
	if auto_cycle:
		_cycle_elapsed += delta
		if _cycle_elapsed >= _cycle_target_seconds:
			_cycle_elapsed = 0.0
			set_weather(_pick_next_weather())

	var transition_finished := false
	if _transition_elapsed < _transition_seconds:
		_transition_elapsed = minf(_transition_elapsed + delta, _transition_seconds)
		var linear_t := _transition_elapsed / maxf(_transition_seconds, 0.001)
		var smooth_t := linear_t * linear_t * (3.0 - 2.0 * linear_t)
		_current_state = _blend_profiles(_from_state, _target_state, smooth_t)
		if _transition_elapsed >= _transition_seconds:
			current_weather = target_weather
			transition_finished = true
			weather_changed.emit(current_weather)

	_update_lightning(delta)
	_current_state["lightning"] = _lightning
	var dynamic_state := _transition_elapsed < _transition_seconds or target_weather == "storm"
	if transition_finished or (dynamic_state and _publish_elapsed >= STATE_PUBLISH_INTERVAL):
		_publish_state()
		_publish_elapsed = 0.0

	if not auto_cycle and _transition_elapsed >= _transition_seconds and target_weather != "storm":
		# Guarantee that the exact target profile is published before the process
		# callback sleeps. Intermediate transition states may be sampled at 12 Hz.
		if not transition_finished and _publish_elapsed > 0.0:
			_publish_state()
			_publish_elapsed = 0.0
		set_process(false)


func _load_weather_config() -> void:
	_weather_config = {}
	if not FileAccess.file_exists(WEATHER_CONFIG_PATH):
		return
	var file := FileAccess.open(WEATHER_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("weather.json inválido; ciclo volta para a ordem fixa.")
		return
	for weather_id in (json.data as Dictionary).keys():
		# Registro que não casa com um PROFILES é ignorado: sem isso um id
		# digitado errado no editor sortearia um clima que não existe.
		if PROFILES.has(str(weather_id)) and (json.data as Dictionary)[weather_id] is Dictionary:
			_weather_config[str(weather_id)] = (json.data as Dictionary)[weather_id]


func _roll_duration(weather_id: String) -> float:
	var entry_value: Variant = _weather_config.get(weather_id, null)
	if not entry_value is Dictionary:
		return auto_cycle_seconds
	var entry: Dictionary = entry_value
	var minimum := float(entry.get("min_seconds", auto_cycle_seconds))
	var maximum := float(entry.get("max_seconds", minimum))
	if maximum < minimum:
		maximum = minimum
	return _weather_rng.randf_range(minimum, maximum)


func _transition_for(weather_id: String) -> float:
	var entry_value: Variant = _weather_config.get(weather_id, null)
	if not entry_value is Dictionary:
		return TRANSITION_SECONDS
	return maxf(float((entry_value as Dictionary).get("transition_seconds", TRANSITION_SECONDS)), 0.05)


func _pick_next_weather() -> String:
	## Sorteio ponderado. Peso 0 tira o clima do ciclo sem apagar o registro.
	## Sem config utilizável, cai na ordem fixa antiga.
	var candidates: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for weather_id in _weather_config.keys():
		if str(weather_id) == target_weather:
			continue
		var weight := maxf(float((_weather_config[weather_id] as Dictionary).get("weight", 0.0)), 0.0)
		if weight <= 0.0:
			continue
		candidates.append(str(weather_id))
		weights.append(weight)
		total += weight
	if candidates.is_empty() or total <= 0.0:
		return WEATHER_ORDER[(WEATHER_ORDER.find(target_weather) + 1) % WEATHER_ORDER.size()]
	var roll := _weather_rng.randf() * total
	for index in range(candidates.size()):
		roll -= weights[index]
		if roll <= 0.0:
			return candidates[index]
	return candidates[candidates.size() - 1]


func set_weather(weather_id: String) -> void:
	if not PROFILES.has(weather_id) or weather_id == target_weather:
		return
	_from_state = _current_state.duplicate(true)
	_target_state = (PROFILES[weather_id] as Dictionary).duplicate(true)
	target_weather = weather_id
	_transition_seconds = _transition_for(weather_id)
	_cycle_target_seconds = _roll_duration(weather_id)
	_transition_elapsed = 0.0
	_cycle_elapsed = 0.0
	_publish_elapsed = STATE_PUBLISH_INTERVAL
	set_process(true)
	weather_changed.emit(target_weather)


func toggle_auto_cycle() -> void:
	auto_cycle = not auto_cycle
	_cycle_elapsed = 0.0
	set_process(auto_cycle or _transition_elapsed < _transition_seconds or target_weather == "storm")


func get_transition_progress() -> float:
	return clampf(_transition_elapsed / maxf(_transition_seconds, 0.001), 0.0, 1.0)


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
