class_name RomesteadWorldSystemsLab
extends Node2D

const WEATHER_LABELS := {
	"clear": "Céu limpo",
	"windy": "Ventania",
	"rain": "Chuva",
	"storm": "Tempestade",
	"snow": "Neve",
	"embers": "Cinzas",
}

@onready var world: RomesteadBiomeWorld2D = $World
@onready var player: RomesteadLabPlayer = $Player
@onready var environment: RomesteadEnvironmentController = $Environment
@onready var weather: AlabasterWeatherController = $Weather
@onready var status_label: Label = $UI/StatusPanel/Status
@onready var transition_label: Label = $UI/StatusPanel/Transition
@onready var auto_label: Label = $UI/StatusPanel/Auto

var _last_biome := ""


func _ready() -> void:
	world.world_generated.connect(_on_world_generated)
	weather.weather_changed.connect(_on_weather_changed)
	player.movement_bounds = world.get_world_bounds()
	_update_ui()


func _process(_delta: float) -> void:
	var biome := world.get_biome_name_at_world(player.global_position)
	if biome != _last_biome:
		_last_biome = biome
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			weather.set_weather("clear")
		KEY_2:
			weather.set_weather("windy")
		KEY_3:
			weather.set_weather("rain")
		KEY_4:
			weather.set_weather("storm")
		KEY_5:
			weather.set_weather("snow")
		KEY_6:
			weather.set_weather("embers")
		KEY_R:
			var seed_value := int(Time.get_ticks_msec() % 2147483000)
			world.generate_world(seed_value)
		KEY_Q:
			environment.set_time(environment.time_of_day - 1.0)
		KEY_E:
			environment.set_time(environment.time_of_day + 1.0)
		KEY_T:
			environment.toggle_time_pause()
		KEY_B:
			weather.toggle_auto_cycle()
		_:
			return
	get_viewport().set_input_as_handled()
	_update_ui()


func _update_ui() -> void:
	if status_label == null:
		return
	var weather_name: String = WEATHER_LABELS.get(weather.target_weather, weather.target_weather)
	status_label.text = "SEED  %d    |    BIOMA  %s    |    HORA  %s    |    CLIMA  %s" % [
		world.world_seed,
		_last_biome,
		environment.get_time_string(),
		weather_name,
	]
	var progress := weather.get_transition_progress()
	transition_label.text = "Transição atmosférica: %3d%%   |   molhado, vento, nuvens e luz interpolados em 7 segundos" % roundi(progress * 100.0)
	auto_label.text = "Ciclo automático: %s   |   relógio: %s" % [
		"ATIVO" if weather.auto_cycle else "PAUSADO",
		"PAUSADO" if environment.time_paused else "ATIVO",
	]


func _on_world_generated(_seed: int, _counts: Dictionary) -> void:
	player.movement_bounds = world.get_world_bounds()
	_update_ui()


func _on_weather_changed(_weather_id: String) -> void:
	_update_ui()
