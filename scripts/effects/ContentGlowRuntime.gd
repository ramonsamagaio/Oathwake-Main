extends RefCounted

const GlowOverlayScene: PackedScene = preload("res://scenes/effects/GlowOverlay.tscn")
const DirectionalShadowRuntimeScript := preload("res://scripts/effects/DirectionalShadowRuntime.gd")
const NightScaledContactShadowScript := preload("res://scripts/effects/NightScaledContactShadow.gd")


static func apply_content_effects(target: Node2D, record: Dictionary, default_glow_z := 24) -> void:
	if target == null:
		return
	var glow_value: Variant = record.get("glow", {})
	var shadow_value: Variant = record.get("shadow", {})
	apply_glow(target, glow_value if glow_value is Dictionary else {}, default_glow_z)
	apply_shadow(target, shadow_value if shadow_value is Dictionary else {}, bool(record.get("flying", false)))


static func apply_glow(target: Node2D, config: Dictionary, default_glow_z := 24) -> Node2D:
	if target == null:
		return null
	var glow := target.get_node_or_null("ContentGlow") as Node2D
	var enabled := bool(config.get("enabled", false))
	if glow == null and enabled:
		glow = GlowOverlayScene.instantiate() as Node2D
		if glow == null:
			return null
		glow.name = "ContentGlow"
		target.add_child(glow)
		glow.add_to_group("persistent_content_visual")
	if glow == null:
		return null

	glow.visible = enabled
	_set_optional_property(glow, "visual_enabled", enabled and bool(config.get("visual_enabled", true)))
	_set_optional_property(glow, "mode", _visual_mode_to_int(str(config.get("visual_mode", "texture"))))
	_set_optional_property(glow, "blend_style", _blend_style_to_int(str(config.get("blend_mode", "additive"))))
	_set_optional_property(glow, "glow_color", _color_from_value(config.get("color", "#FFFFFF"), Color.WHITE))
	_set_optional_property(glow, "intensity", maxf(float(config.get("intensity", 1.0)), 0.0))
	_set_optional_property(glow, "alpha", clampf(float(config.get("alpha", 0.75)), 0.0, 1.0))
	_set_optional_property(glow, "scale_multiplier", maxf(float(config.get("scale", 1.0)), 0.01))
	_set_optional_property(glow, "blur_amount", maxf(float(config.get("blur", 0.0)), 0.0))
	_set_optional_property(glow, "stretch", _vector_from_value(config.get("stretch", {}), Vector2.ONE))
	_set_optional_property(glow, "flicker_enabled", bool(config.get("flicker_enabled", false)))
	_set_optional_property(glow, "flicker_amount", clampf(float(config.get("flicker_amount", 0.08)), 0.0, 1.0))
	_set_optional_property(glow, "flicker_speed", maxf(float(config.get("flicker_speed", 2.0)), 0.05))
	_set_optional_property(glow, "use_point_light", enabled and bool(config.get("light_enabled", true)))
	_set_optional_property(glow, "point_light_energy", maxf(float(config.get("light_energy", 0.8)), 0.0))
	_set_optional_property(glow, "point_light_scale", maxf(float(config.get("light_scale", 1.5)), 0.05))
	_set_optional_property(glow, "day_light_multiplier", clampf(float(config.get("day_multiplier", 0.18)), 0.0, 4.0))
	_set_optional_property(glow, "night_light_multiplier", clampf(float(config.get("night_multiplier", 1.0)), 0.0, 4.0))
	_set_optional_property(glow, "z_index_value", int(config.get("overlay_z", default_glow_z)))
	glow.position = _vector_from_value(config.get("offset", {}), Vector2.ZERO)
	if glow.has_method("refresh_from_config"):
		glow.call("refresh_from_config")
	return glow


static func apply_shadow(target: Node2D, config: Dictionary, use_contact_shadow := false) -> Polygon2D:
	if target == null:
		return null
	if use_contact_shadow or str(config.get("mode", "")).to_lower() == "contact":
		return _apply_contact_shadow(target, config)
	var resolved_config := config.duplicate(true)
	if not resolved_config.has("enabled"):
		resolved_config["enabled"] = false
	var active_source := DirectionalShadowRuntimeScript.find_active_visual_source(target)
	var visual_size := DirectionalShadowRuntimeScript.estimate_target_visual_size(target)
	var foot_offset := DirectionalShadowRuntimeScript.estimate_target_foot_offset(target)
	return DirectionalShadowRuntimeScript.apply_to_target(target, resolved_config, visual_size, foot_offset, active_source)


static func _apply_contact_shadow(target: Node2D, config: Dictionary) -> Polygon2D:
	var shadow := target.get_node_or_null("GroundShadow") as Polygon2D
	if shadow == null or shadow.get_script() != NightScaledContactShadowScript:
		if shadow != null:
			target.remove_child(shadow)
			shadow.queue_free()
		shadow = NightScaledContactShadowScript.new() as Polygon2D
		shadow.name = "GroundShadow"
		target.add_child(shadow)
	shadow.visible = bool(config.get("enabled", true))
	if shadow.has_method("configure"):
		shadow.call("configure", config)
	return shadow


static func _visual_mode_to_int(mode_name: String) -> int:
	match mode_name.to_lower():
		"procedural":
			return 1
		"both":
			return 2
		_:
			return 0


static func _blend_style_to_int(style_name: String) -> int:
	return 1 if style_name.to_lower() == "additive" else 0


static func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges()
	if text.is_empty():
		return fallback
	return Color.from_string(text, fallback)


static func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(
			float(value.get("x", fallback.x)),
			float(value.get("y", fallback.y))
		)
	return fallback


static func _set_optional_property(target: Object, property_name: StringName, value: Variant) -> void:
	if target == null:
		return
	for property_info in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			target.set(property_name, value)
			return
