extends "res://scripts/enemies/EnemyBaseEnhanced.gd"


func _ready() -> void:
	super._ready()
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		sprite.play("idle")
