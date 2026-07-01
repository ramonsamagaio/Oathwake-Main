extends Node2D

@export var lifetime: float = 0.12
@export var base_scale: Vector2 = Vector2.ONE
@export var critical_scale_multiplier: float = 1.25

var is_critical := false

@onready var sparks: Node2D = $Sparks
@onready var cross: Line2D = $Cross
@onready var burst: Polygon2D = $Burst


func _ready() -> void:
	_apply_profile()
	_apply_variant()
	_play()


func setup(critical := false) -> void:
	is_critical = critical
	if is_node_ready():
		_apply_profile()
		_apply_variant()
		_play()


func _apply_profile() -> void:
	var vfx_profile := _get_vfx_profile()
	lifetime = float(vfx_profile.get("hit_flash_duration", lifetime))
	if is_critical:
		lifetime = float(vfx_profile.get("critical_hit_flash_duration", lifetime))


func _apply_variant() -> void:
	var variant_scale := critical_scale_multiplier if is_critical else 1.0
	var vfx_profile := _get_vfx_profile()
	if is_critical:
		variant_scale = float(vfx_profile.get("critical_bump_scale", critical_scale_multiplier))
	else:
		variant_scale = float(vfx_profile.get("hit_bump_scale", 1.0))
	scale = base_scale * variant_scale
	rotation = randf_range(-0.35, 0.35)

	var base_color := Color(1.0, 0.95, 0.72, 0.95)
	if is_critical:
		base_color = Color(1.0, 0.84, 0.35, 1.0)

	if sparks != null:
		sparks.modulate = base_color
	if cross != null:
		cross.modulate = base_color
	if burst != null:
		burst.modulate = base_color

	if is_critical and burst != null:
		burst.scale = Vector2(1.12, 1.12)


func _play() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", scale * 1.25, lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}
