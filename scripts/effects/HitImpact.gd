@tool
extends Node2D

@export_group("Profile")
@export var use_content_db_profile: bool = true
@export var auto_play: bool = true
@export var auto_free_on_finish: bool = true

@export_group("Timing")
@export_range(0.01, 2.0, 0.01) var lifetime: float = 0.12

@export_group("Scale")
@export var base_scale: Vector2 = Vector2.ONE
@export_range(0.1, 6.0, 0.05) var normal_scale_multiplier: float = 1.0
@export_range(0.1, 6.0, 0.05) var critical_scale_multiplier: float = 1.25
@export_range(0.1, 4.0, 0.05) var end_scale_multiplier: float = 1.25

@export_group("Color")
@export var normal_color: Color = Color(1.0, 0.95, 0.72, 0.95)
@export var critical_color: Color = Color(1.0, 0.84, 0.35, 1.0)
@export_range(0.0, 1.0, 0.01) var spark_alpha: float = 1.0
@export_range(0.0, 1.0, 0.01) var cross_alpha: float = 1.0
@export_range(0.0, 1.0, 0.01) var burst_alpha: float = 1.0

@export_group("Motion")
@export_range(0.0, 1.5, 0.01) var random_rotation_range: float = 0.35
@export var fade_out: bool = true
@export var randomize_rotation: bool = true

var is_critical := false

@onready var sparks: Node2D = get_node_or_null("Sparks")
@onready var cross: Line2D = get_node_or_null("Cross")
@onready var burst: Polygon2D = get_node_or_null("Burst")


func _ready() -> void:
	_apply_profile()
	_apply_variant()
	if Engine.is_editor_hint():
		return
	if auto_play:
		_play()


func setup(critical := false) -> void:
	is_critical = critical
	if is_node_ready():
		_apply_profile()
		_apply_variant()
		if not Engine.is_editor_hint() and auto_play:
			_play()


func preview_normal() -> void:
	is_critical = false
	_apply_variant()


func preview_critical() -> void:
	is_critical = true
	_apply_variant()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_variant()
		queue_redraw()


func _apply_profile() -> void:
	if not use_content_db_profile:
		return
	var vfx_profile := _get_vfx_profile()
	lifetime = float(vfx_profile.get("hit_flash_duration", lifetime))
	if is_critical:
		lifetime = float(vfx_profile.get("critical_hit_flash_duration", lifetime))


func _apply_variant() -> void:
	var variant_scale := critical_scale_multiplier if is_critical else normal_scale_multiplier
	if use_content_db_profile:
		var vfx_profile := _get_vfx_profile()
		if is_critical:
			variant_scale = float(vfx_profile.get("critical_bump_scale", critical_scale_multiplier))
		else:
			variant_scale = float(vfx_profile.get("hit_bump_scale", normal_scale_multiplier))

	scale = base_scale * variant_scale
	if randomize_rotation and not Engine.is_editor_hint():
		rotation = randf_range(-random_rotation_range, random_rotation_range)

	var base_color := critical_color if is_critical else normal_color
	_apply_color(base_color)

	if burst != null:
		burst.scale = Vector2.ONE * (1.12 if is_critical else 1.0)


func _apply_color(base_color: Color) -> void:
	if sparks != null:
		sparks.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * spark_alpha)
	if cross != null:
		cross.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * cross_alpha)
	if burst != null:
		burst.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * burst_alpha)


func _play() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", scale * end_scale_multiplier, lifetime)
	if fade_out:
		tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.set_parallel(false)
	if auto_free_on_finish:
		tween.tween_callback(queue_free)


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}
