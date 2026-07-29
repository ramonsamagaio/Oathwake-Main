extends "res://scripts/player/PlayerLifeAnimationSuite.gd"

const MIN_LIGHT_PERSPECTIVE_ANGLE := 15.0
const MAX_LIGHT_PERSPECTIVE_ANGLE := 90.0
const DEFAULT_LIGHT_PERSPECTIVE_ANGLE := 50.0


func _apply_player_light_tuning() -> void:
	super._apply_player_light_tuning()
	var light := get_node_or_null("NightLight") as Node2D
	if light == null:
		return
	var enabled := bool(_content_light_config.get("enabled", true))
	var real_light_enabled := enabled and bool(_content_light_config.get("light_enabled", true))
	var perspective_angle := clampf(
		float(_content_light_config.get("perspective_angle_degrees", DEFAULT_LIGHT_PERSPECTIVE_ANGLE)),
		MIN_LIGHT_PERSPECTIVE_ANGLE,
		MAX_LIGHT_PERSPECTIVE_ANGLE
	)
	# GlowOverlay is the single owner of the light footprint. The aura, real
	# PointLight2D and post-process night mask all read this same projection.
	light.scale = Vector2.ONE
	_set_player_light_property(light, "use_point_light", real_light_enabled)
	_set_player_light_property(light, "perspective_angle_degrees", perspective_angle)
	_set_player_light_property(light, "mode", _player_light_visual_mode(str(_content_light_config.get("visual_mode", "texture"))))
	_set_player_light_property(light, "blend_style", 1 if str(_content_light_config.get("blend_mode", "additive")) == "additive" else 0)
	_set_player_light_property(light, "stretch", _player_light_vector(_content_light_config.get("stretch", {}), Vector2.ONE))
	_set_player_light_property(light, "flicker_enabled", bool(_content_light_config.get("flicker_enabled", false)))
	_set_player_light_property(light, "flicker_amount", clampf(float(_content_light_config.get("flicker_amount", 0.08)), 0.0, 1.0))
	_set_player_light_property(light, "flicker_speed", maxf(float(_content_light_config.get("flicker_speed", 2.0)), 0.05))
	_set_player_light_property(light, "casts_night_shadows", bool(_content_light_config.get("casts_night_shadows", true)))
	_set_player_light_property(light, "z_index_value", int(_content_light_config.get("overlay_z", 18)))
	if light.has_method("refresh_from_config"):
		light.call("refresh_from_config")
	var projection := Vector2(1.0, clampf(sin(deg_to_rad(perspective_angle)), 0.20, 1.0))
	light.set_meta("player_light_perspective_angle", perspective_angle)
	light.set_meta("player_light_vertical_projection", projection.y)


func _player_light_visual_mode(mode_name: String) -> int:
	match mode_name.to_lower():
		"procedural":
			return 1
		"both":
			return 2
		_:
			return 0
