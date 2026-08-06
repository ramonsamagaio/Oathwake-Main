extends Node2D

@export_range(0.05, 1.0, 0.01) var lifetime := 0.22
@export_range(0.1, 4.0, 0.05) var start_scale := 0.55
@export_range(0.1, 6.0, 0.05) var end_scale := 1.35
@export_range(-6.0, 6.0, 0.05) var spin_radians := 0.35


func _ready() -> void:
	scale = Vector2.ONE * start_scale
	rotation = -spin_radians * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * end_scale, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", spin_radians * 0.5, lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
