extends "res://scripts/player/PlayerLifeAnimationSuite.gd"

const MIN_LIGHT_PERSPECTIVE_ANGLE := 15.0
const MAX_LIGHT_PERSPECTIVE_ANGLE := 90.0
const DEFAULT_LIGHT_PERSPECTIVE_ANGLE := 50.0


func _apply_player_light_tuning() -> void:
	super._apply_player_light_tuning()
	var light := get_node_or_null("NightLight") as Node2D
	if light == null:
		return
	var perspective_angle := clampf(
		float(_content_light_config.get("perspective_angle_degrees", DEFAULT_LIGHT_PERSPECTIVE_ANGLE)),
		MIN_LIGHT_PERSPECTIVE_ANGLE,
		MAX_LIGHT_PERSPECTIVE_ANGLE
	)
	# Ninety degrees represents a zenith camera and keeps the light circular.
	# Lower top-down camera angles compress the light vertically into the same
	# ground-plane ellipse that the player would produce in perspective.
	var vertical_projection := clampf(sin(deg_to_rad(perspective_angle)), 0.20, 1.0)
	light.scale = Vector2(1.0, vertical_projection)
	light.set_meta("player_light_perspective_angle", perspective_angle)
	light.set_meta("player_light_vertical_projection", vertical_projection)
