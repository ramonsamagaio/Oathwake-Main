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

@export_group("Sprite Color")
@export var sprite_tint: Color = Color(0.78, 0.78, 0.70, 0.82)
@export_range(0.0, 1.0, 0.01) var global_alpha: float = 1.0

@export_group("Motion")
@export_range(0.0, 1.5, 0.01) var random_rotation_range: float = 0.18
@export var fade_out: bool = true
@export var randomize_rotation: bool = true

@onready var puff_sprite: Sprite2D = $Sprite2D


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


func _apply_profile() -> void:
	if not use_content_db_profile:
		return
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile"):
		return
	var profile_id := vfx_profile_id if content_db.has_vfx_profile(vfx_profile_id) else "default"
	if not content_db.has_vfx_profile(profile_id):
		return
	var profile: Dictionary = content_db.get_vfx_profile(profile_id)
	lifetime = maxf(float(profile.get("smoke_puff_lifetime", lifetime)), 0.01)
	puff_scale = maxf(float(profile.get("smoke_puff_scale", puff_scale)), 0.05)


func _apply_visuals() -> void:
	if puff_sprite == null:
		return
	puff_sprite.modulate = Color(sprite_tint.r, sprite_tint.g, sprite_tint.b, sprite_tint.a * global_alpha)
	puff_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _start_fade() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	if fade_out:
		tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.tween_property(self, "scale", Vector2.ONE * randf_range(end_scale_min, end_scale_max) * puff_scale, lifetime)
	tween.set_parallel(false)
	if auto_free_on_finish:
		tween.tween_callback(queue_free)
