@tool
extends Node2D

@export_group("Profile")
@export var use_content_db_profile: bool = true
@export var vfx_profile_id: String = "default"
@export var auto_play: bool = true
@export var auto_free_on_finish: bool = true

@export_group("Timing")
@export_range(0.01, 4.0, 0.01) var lifetime: float = 0.35

@export_group("Scale")
@export_range(0.05, 8.0, 0.05) var puff_scale: float = 1.2
@export_range(0.05, 4.0, 0.05) var start_scale_min: float = 0.75
@export_range(0.05, 4.0, 0.05) var start_scale_max: float = 0.95
@export_range(0.05, 6.0, 0.05) var end_scale_min: float = 1.1
@export_range(0.05, 6.0, 0.05) var end_scale_max: float = 1.25

@export_group("Color")
@export var puff_color_a: Color = Color(0.62, 0.62, 0.58, 0.72)
@export var puff_color_b: Color = Color(0.74, 0.74, 0.68, 0.68)
@export var puff_color_c: Color = Color(0.54, 0.54, 0.5, 0.64)
@export var puff_color_d: Color = Color(0.68, 0.68, 0.62, 0.55)
@export_range(0.0, 1.0, 0.01) var global_alpha: float = 1.0

@export_group("Motion")
@export_range(0.0, 1.5, 0.01) var random_rotation_range: float = 0.18
@export var fade_out: bool = true
@export var randomize_rotation: bool = true


func _ready() -> void:
	_apply_profile()
	_apply_visuals()
	if Engine.is_editor_hint():
		return

	scale = Vector2.ONE * randf_range(start_scale_min, start_scale_max) * puff_scale
	if randomize_rotation:
		rotation = randf_range(-random_rotation_range, random_rotation_range)

	if auto_play:
		call_deferred("_start_fade")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_visuals()


func setup_profile(profile_id: String) -> void:
	vfx_profile_id = profile_id if not profile_id.is_empty() else "default"
	_apply_profile()


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile(vfx_profile_id):
		return content_db.get_vfx_profile(vfx_profile_id)
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}


func _apply_profile() -> void:
	if not use_content_db_profile:
		return
	var vfx_profile := _get_vfx_profile()
	var active_lifetime := float(vfx_profile.get("smoke_puff_lifetime", lifetime))
	var active_scale := float(vfx_profile.get("smoke_puff_scale", puff_scale))
	lifetime = active_lifetime if active_lifetime > 0.0 else lifetime
	puff_scale = active_scale if active_scale > 0.0 else puff_scale


func _apply_visuals() -> void:
	_set_polygon_color("PuffA", puff_color_a)
	_set_polygon_color("PuffB", puff_color_b)
	_set_polygon_color("PuffC", puff_color_c)
	_set_polygon_color("PuffD", puff_color_d)


func _set_polygon_color(path: NodePath, color_value: Color) -> void:
	var polygon := get_node_or_null(path) as Polygon2D
	if polygon == null:
		return
	polygon.color = Color(color_value.r, color_value.g, color_value.b, color_value.a * global_alpha)


func _start_fade() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	if fade_out:
		tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.tween_property(self, "scale", Vector2.ONE * randf_range(end_scale_min, end_scale_max) * puff_scale, lifetime)
	tween.set_parallel(false)
	if auto_free_on_finish:
		tween.tween_callback(queue_free)
