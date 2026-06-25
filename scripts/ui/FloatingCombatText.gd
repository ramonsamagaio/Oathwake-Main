extends Node2D

@export var duration: float = 1.0
@export var rise_distance: float = 32.0
@export var horizontal_jitter: float = 10.0

var text := ""
var text_color := Color(1.0, 0.95, 0.65, 1.0)
var is_critical := false

@onready var label: Label = $Label


func _ready() -> void:
	var jitter: float = randf_range(-horizontal_jitter, horizontal_jitter)
	position.x += jitter

	_apply_label_style()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise_distance, duration)
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func setup(new_text: String, color: Color, critical := false) -> void:
	text = new_text
	text_color = color
	is_critical = critical
	if is_node_ready():
		_apply_label_style()


func _apply_label_style() -> void:
	label.text = text
	label.label_settings = _make_label_settings()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _make_label_settings() -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_color = text_color
	settings.font_size = 18 if is_critical else 14
	settings.outline_color = Color.BLACK
	settings.outline_size = 2

	var font_path := "res://assets/fonts/pixel_font.ttf"
	if FileAccess.file_exists(font_path):
		settings.font = load(font_path)

	return settings
