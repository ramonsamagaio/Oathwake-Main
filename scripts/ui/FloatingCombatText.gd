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
var _spawn_world_position := Vector2.ZERO
var _has_spawn_world_position := false
var _motion_world_start := Vector2.ZERO
var _motion_world_target := Vector2.ZERO

@onready var label: Label = $Label


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 4090
	if _has_spawn_world_position:
		global_position = _spawn_world_position
	_apply_vfx_profile()
	_apply_label_style()

	var active_duration := critical_duration if is_critical else duration
	var active_rise_distance := critical_rise_distance if is_critical else rise_distance
	var canvas_transform := get_viewport().get_canvas_transform()
	var screen_start := canvas_transform * global_position
	screen_start.x += randf_range(-horizontal_jitter, horizontal_jitter)
	global_position = canvas_transform.affine_inverse() * screen_start
	var target_world := calculate_world_target_for_screen_rise(global_position, canvas_transform, active_rise_distance)
	_motion_world_start = global_position
	_motion_world_target = target_world

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target_world, active_duration)
	tween.tween_property(self, "modulate:a", 0.0, active_duration)
	if is_critical:
		scale = Vector2(1.12, 1.12)
		tween.tween_property(self, "scale", Vector2.ONE, 0.12)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


static func calculate_world_target_for_screen_rise(world_start: Vector2, canvas_transform: Transform2D, screen_distance: float) -> Vector2:
	var screen_start := canvas_transform * world_start
	var screen_target := screen_start + Vector2.UP * maxf(screen_distance, 0.0)
	return canvas_transform.affine_inverse() * screen_target


func configure_spawn(new_text: String, color: Color, critical: bool, new_profile_id: String, world_position: Vector2) -> void:
	_spawn_world_position = world_position
	_has_spawn_world_position = true
	setup(new_text, color, critical, new_profile_id)


func get_motion_world_start() -> Vector2:
	return _motion_world_start


func get_motion_world_target() -> Vector2:
	return _motion_world_target


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


func _apply_vfx_profile() -> void:
	var vfx_profile := _get_vfx_profile()
	if is_critical:
		duration = float(vfx_profile.get("critical_text_duration", critical_duration))
	else:
		duration = float(vfx_profile.get("floating_text_duration", duration))


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}
