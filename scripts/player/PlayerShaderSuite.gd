extends "res://scripts/player/PlayerEnhanced.gd"


func _start_dash(direction: Vector2) -> void:
	super._start_dash(direction)
	for screen_effects in get_tree().get_nodes_in_group("screen_effects"):
		if screen_effects != null and screen_effects.has_method("play_dash_lines"):
			screen_effects.play_dash_lines(dash_duration)
