class_name RomesteadEnvironmentController
extends Node

signal time_changed(display_time: String)

const RuntimeSchedulerScript := preload("res://scripts/world/RomesteadRuntimeSchedulerOptimized.gd")

@export var time_of_day := 16.5
@export var day_length_seconds := 210.0
@export var time_paused := false
@export_range(1.0, 30.0, 1.0) var visual_step_minutes := 4.0
@export_range(0.25, 5.0, 0.25) var receiver_cache_refresh_seconds := 1.5
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

var _runtime_scheduler: Node
var _cached_lab_lights: Array[PointLight2D] = []
var _cached_receivers: Array[Node] = []
var _receiver_cache_age := INF
var _last_applied_hour := INF
var _last_display_time := ""


func _ready() -> void:
	add_to_group("romestead_environment_controller")
	_refresh_receiver_cache()
	_configure_runtime_scheduler()
	_update_environment(true)
	set_process(not time_paused)


func _process(delta: float) -> void:
	_receiver_cache_age += delta
	if _receiver_cache_age >= receiver_cache_refresh_seconds:
		_refresh_receiver_cache()

	if not time_paused:
		time_of_day = fmod(time_of_day + delta * 24.0 / maxf(day_length_seconds, 1.0), 24.0)
		_maybe_update_environment(false)

	var display_time := get_time_string()
	if display_time != _last_display_time:
		_last_display_time = display_time
		time_changed.emit(display_time)


func apply_weather_state(state: Dictionary) -> void:
	var changed := false
	for key in weather_state.keys():
		if state.has(key) and weather_state[key] != state[key]:
			weather_state[key] = state[key]
			changed = true
	if changed:
		_update_environment(true)


func set_world(world: Node) -> void:
	_world = world
	_configure_runtime_scheduler()
	_refresh_receiver_cache()
	_update_environment(true)


func set_time(new_hour: float) -> void:
	time_of_day = fposmod(new_hour, 24.0)
	_maybe_update_environment(false)
	var display_time := get_time_string()
	if display_time != _last_display_time:
		_last_display_time = display_time
		time_changed.emit(display_time)


func toggle_time_pause() -> void:
	time_paused = not time_paused
	set_process(not time_paused)
	_update_environment(true)


func get_time_string() -> String:
	var hours := floori(time_of_day)
	var minutes := floori((time_of_day - float(hours)) * 60.0)
	return "%02d:%02d" % [hours, minutes]


func get_daylight_strength() -> float:
	return clampf(sin((time_of_day - 6.0) / 24.0 * TAU), 0.0, 1.0)


func get_runtime_performance_diagnostics() -> Dictionary:
	if _runtime_scheduler != null and is_instance_valid(_runtime_scheduler) and _runtime_scheduler.has_method("get_diagnostics"):
		return _runtime_scheduler.call("get_diagnostics") as Dictionary
	return {"scheduler_enabled": false}


func _configure_runtime_scheduler() -> void:
	if _runtime_scheduler != null and is_instance_valid(_runtime_scheduler):
		_runtime_scheduler.queue_free()
		_runtime_scheduler = null
	if _world == null or not is_instance_valid(_world):
		return
	_runtime_scheduler = RuntimeSchedulerScript.new()
	_runtime_scheduler.name = "RomesteadRuntimeScheduler"
	add_child(_runtime_scheduler)
	_runtime_scheduler.call("setup", _world)


func _maybe_update_environment(force: bool) -> void:
	if force or not is_finite(_last_applied_hour):
		_update_environment(true)
		return
	var delta_hours := absf(time_of_day - _last_applied_hour)
	delta_hours = minf(delta_hours, 24.0 - delta_hours)
	var step_hours := maxf(visual_step_minutes, 1.0) / 60.0
	if delta_hours >= step_hours:
		_update_environment(false)


func _update_environment(force_cache_refresh: bool = false) -> void:
	if force_cache_refresh or _receiver_cache_age >= receiver_cache_refresh_seconds:
		_refresh_receiver_cache()
	_last_applied_hour = time_of_day

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

	_update_cached_lab_lights(daylight)

	if _world != null and is_instance_valid(_world) and _world.has_method("set_environment"):
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
	for receiver in _cached_receivers:
		if receiver == null or not is_instance_valid(receiver) or receiver == _world:
			continue
		if not receiver.has_method("set_romestead_environment"):
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


func _refresh_receiver_cache() -> void:
	_cached_lab_lights.clear()
	_cached_receivers.clear()
	if not is_inside_tree():
		_receiver_cache_age = 0.0
		return
	for node in get_tree().get_nodes_in_group("romestead_lab_lights"):
		if node is PointLight2D:
			_cached_lab_lights.append(node as PointLight2D)
	for node in get_tree().get_nodes_in_group("romestead_environment_receivers"):
		if node is Node:
			_cached_receivers.append(node as Node)
	_receiver_cache_age = 0.0


func _update_cached_lab_lights(daylight: float) -> void:
	var darkness := clampf(1.0 - daylight * 0.92, 0.08, 1.0)
	var seconds := Time.get_ticks_msec() * 0.001
	for light in _cached_lab_lights:
		if light == null or not is_instance_valid(light):
			continue
		var base_energy := float(light.get_meta("base_energy", 1.0))
		var phase := float(light.get_meta("flicker_phase", 0.0))
		var flicker := 0.92 + sin(seconds * 9.0 + phase) * 0.055 + sin(seconds * 17.0 + phase * 0.7) * 0.025
		light.energy = base_energy * lerpf(0.28, 1.0, darkness) * flicker


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
