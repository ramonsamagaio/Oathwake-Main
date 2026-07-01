extends Node2D

@export var lifetime: float = 0.35
@export var puff_scale: float = 1.2


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}


func _ready() -> void:
	var vfx_profile := _get_vfx_profile()
	var active_lifetime := float(vfx_profile.get("smoke_puff_lifetime", lifetime))
	var active_scale := float(vfx_profile.get("smoke_puff_scale", puff_scale))
	lifetime = active_lifetime if active_lifetime > 0.0 else lifetime
	puff_scale = active_scale if active_scale > 0.0 else puff_scale
	scale = Vector2.ONE * randf_range(0.75, 0.95) * puff_scale
	rotation = randf_range(-0.18, 0.18)
	call_deferred("_start_fade")


func _start_fade() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.tween_property(self, "scale", Vector2.ONE * randf_range(1.1, 1.25), lifetime)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
