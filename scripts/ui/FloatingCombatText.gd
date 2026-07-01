extends Node2D

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")

@export var duration: float = 1.45
@export var critical_duration: float = 1.60
@export var rise_distance: float = 26.0
@export var critical_rise_distance: float = 30.0
@export var horizontal_jitter: float = 8.0

var text := ""
var text_color := Color(1.0, 0.95, 0.65, 1.0)
var is_critical := false
var font_profile_id := "damage_number"

@onready var label: Label = $Label


func _ready() -> void:
	var jitter: float = randf_range(-horizontal_jitter, horizontal_jitter)
	position.x += jitter

	_apply_label_style()

	var active_duration := critical_duration if is_critical else duration
	var active_rise_distance := critical_rise_distance if is_critical else rise_distance
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - active_rise_distance, active_duration)
	tween.tween_property(self, "modulate:a", 0.0, active_duration)
	if is_critical:
		scale = Vector2(1.12, 1.12)
		tween.tween_property(self, "scale", Vector2.ONE, 0.12)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func setup(new_text: String, color: Color, critical := false, new_profile_id := "") -> void:
	text = new_text
	text_color = color
	is_critical = critical
	if not new_profile_id.is_empty():
		font_profile_id = new_profile_id
	else:
		font_profile_id = "critical_damage_number" if is_critical else "damage_number"
	if is_node_ready():
		_apply_label_style()


func _apply_label_style() -> void:
	label.text = text
	label.label_settings = _make_label_settings()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _make_label_settings() -> LabelSettings:
	return OathwakeTextStyle.make_label_settings_for_profile(
		font_profile_id,
		text_color,
		-1,
		-1
	)
