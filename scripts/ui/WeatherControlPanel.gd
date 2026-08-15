class_name WeatherControlPanel
extends Panel

const WEATHER_LABELS := {
	"clear": "Limpo",
	"windy": "Ventania",
	"rain": "Chuva",
	"storm": "Tempestade",
	"snow": "Neve",
	"embers": "Cinzas",
}

var _day_night: Node
var _weather: Node
var _weather_label: Label
var _time_label: Label
var _hour_slider: HSlider
var _lock_day: CheckButton
var _auto_weather: CheckButton


func _ready() -> void:
	_build_controls()
	hide()


func setup(day_night: Node, weather: Node) -> void:
	_day_night = day_night
	_weather = weather
	# Deliberate gameplay defaults until the design of the cycles is approved.
	_lock_day.button_pressed = true
	_auto_weather.button_pressed = false
	_apply_day_lock(true)
	if _weather != null:
		_weather.set("auto_cycle", false)
		if _weather.has_method("set_weather"):
			_weather.call("set_weather", "clear")
	_update_labels()


func toggle_panel() -> void:
	visible = not visible
	if visible:
		_update_labels()


func _build_controls() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "CLIMA E ILUMINAÇÃO"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	header.add_child(close)

	_weather_label = Label.new()
	column.add_child(_weather_label)
	var weather_grid := GridContainer.new()
	weather_grid.columns = 2
	column.add_child(weather_grid)
	for weather_id in ["clear", "windy", "rain", "storm", "snow", "embers"]:
		var button := Button.new()
		button.text = str(WEATHER_LABELS[weather_id])
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_weather.bind(weather_id))
		weather_grid.add_child(button)

	var separator := HSeparator.new()
	column.add_child(separator)
	_time_label = Label.new()
	column.add_child(_time_label)

	_lock_day = CheckButton.new()
	_lock_day.text = "Travar de dia (16:00)"
	_lock_day.focus_mode = Control.FOCUS_NONE
	_lock_day.toggled.connect(_apply_day_lock)
	column.add_child(_lock_day)

	_hour_slider = HSlider.new()
	_hour_slider.min_value = 0.0
	_hour_slider.max_value = 24.0
	_hour_slider.step = 0.25
	_hour_slider.value = 16.0
	_hour_slider.value_changed.connect(_set_hour)
	column.add_child(_hour_slider)

	_auto_weather = CheckButton.new()
	_auto_weather.text = "Ciclo automático de clima"
	_auto_weather.focus_mode = Control.FOCUS_NONE
	_auto_weather.toggled.connect(_set_weather_auto)
	column.add_child(_auto_weather)

	var note := Label.new()
	note.text = "Padrão: dia fixo e tempo limpo"
	note.modulate = Color(0.76, 0.78, 0.72, 1.0)
	column.add_child(note)


func _select_weather(weather_id: String) -> void:
	if _weather != null and _weather.has_method("set_weather"):
		_weather.call("set_weather", weather_id)
	_update_labels(weather_id)


func _apply_day_lock(locked: bool) -> void:
	if _hour_slider != null:
		_hour_slider.editable = not locked
	if _day_night == null:
		return
	if locked:
		_hour_slider.set_value_no_signal(16.0)
		if _day_night.has_method("set_day"):
			_day_night.call("set_day")
	if _day_night.has_method("set_cycle_paused"):
		_day_night.call("set_cycle_paused", locked)
	else:
		_day_night.set("cycle_paused", locked)
	_update_labels()


func _set_hour(hour: float) -> void:
	if _day_night != null and _day_night.has_method("set_time_of_day"):
		# The Oathwake normalized clock starts at 06:00 in the Romestead bridge.
		_day_night.call("set_time_of_day", fposmod(hour - 6.0, 24.0) / 24.0)
	_update_labels()


func _set_weather_auto(enabled: bool) -> void:
	if _weather == null:
		return
	_weather.set("auto_cycle", enabled)
	_weather.set_process(enabled or str(_weather.get("target_weather")) == "storm")


func _update_labels(forced_weather := "") -> void:
	if _weather_label != null:
		var weather_id := forced_weather
		if weather_id.is_empty() and _weather != null:
			weather_id = str(_weather.get("target_weather"))
		_weather_label.text = "Clima: %s" % str(WEATHER_LABELS.get(weather_id, weather_id.capitalize()))
	if _time_label != null:
		var hour := _hour_slider.value if _hour_slider != null else 12.0
		_time_label.text = "Hora: %02d:%02d" % [floori(hour), floori(fposmod(hour, 1.0) * 60.0)]
