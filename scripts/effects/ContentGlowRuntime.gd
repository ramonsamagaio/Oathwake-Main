extends RefCounted

const GlowOverlayScene: PackedScene = preload("res://scenes/effects/GlowOverlay.tscn")

const DEFAULT_SHADOW_POLYGON := PackedVector2Array([
	Vector2(-13, -3), Vector2(-10, -5), Vector2(-4, -6), Vector2(4, -6),
	Vector2(10, -5), Vector2(13, -3), Vector2(14, 0), Vector2(13, 3),
	Vector2(10, 5), Vector2(4, 6), Vector2(-4, 6), Vector2(-10, 5),
	Vector2(-13, 3), Vector2(-14, 0),
])


static func apply_content_effects(target: Node2D, record: Dictionary, default_glow_z := 24) -> void:
	if target == null:
		return
	var glow_value: Variant = record.get("glow", {})
	var shadow_value: Variant = record.get("shadow", {})
	apply_glow(target, glow_value if glow_value is Dictionary else {}, default_glow_z)
	apply_shadow(target, shadow_value if shadow_value is Dictionary else {})


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


static func apply_shadow(target: Node2D, config: Dictionary) -> Polygon2D:
	if target == null:
		return null
	var shadow := target.get_node_or_null("GroundShadow") as Polygon2D
	var enabled := bool(config.get("enabled", false))
	if shadow == null and enabled:
		shadow = Polygon2D.new()
		shadow.name = "GroundShadow"
		shadow.polygon = DEFAULT_SHADOW_POLYGON
		target.add_child(shadow)
		shadow.add_to_group("persistent_content_visual")
	if shadow == null:
		return null

	shadow.visible = enabled
	shadow.show_behind_parent = true
	shadow.position = _vector_from_value(config.get("offset", {}), Vector2(0.0, 12.0))
	shadow.scale = _vector_from_value(config.get("scale", {}), Vector2(0.9, 0.34))
	shadow.z_index = int(config.get("z_index", 0))
	shadow.color = Color(0.01, 0.008, 0.015, clampf(float(config.get("opacity", 0.42)), 0.0, 1.0))
	shadow.modulate = Color.WHITE
	if not shadow.is_in_group("persistent_content_visual"):
		shadow.add_to_group("persistent_content_visual")
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
