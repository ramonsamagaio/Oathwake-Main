extends Node2D

@export var lifetime: float = 0.35


func _ready() -> void:
	scale = Vector2.ONE * randf_range(0.75, 0.95)
	rotation = randf_range(-0.18, 0.18)
	call_deferred("_start_fade")


func _start_fade() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.tween_property(self, "scale", Vector2.ONE * randf_range(1.1, 1.25), lifetime)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
