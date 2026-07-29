class_name DynamicProjectedSpriteShadow
extends "res://scripts/effects/ProjectedSpriteShadow.gd"

const CASTER_GROUP := "projected_shadow_caster"
const DEFAULT_MORNING_DIRECTION := -45.0
const DEFAULT_EVENING_DIRECTION := 45.0


func configure(target: Node2D, source: CanvasItem, config: Dictionary, foot_offset: Vector2) -> void:
	super.configure(target, source, config, foot_offset)
	var is_local := bool(_config.get("local_light_shadow", false))
	if not is_local and not is_in_group(CASTER_GROUP):
		add_to_group(CASTER_GROUP)
	elif is_local and is_in_group(CASTER_GROUP):
		remove_from_group(CASTER_GROUP)
	set_meta("shadow_kind", "local" if is_local else "solar")


func _apply_projection_settings() -> void:
	var live_global := _get_live_global_config()
	var is_local := bool(_config.get("local_light_shadow", false))
	var direction_degrees := float(_config.get("direction_degrees", DEFAULT_DIRECTION_DEGREES))
	var stretch_amount := maxf(float(_config.get("stretch", 1.15)), 0.05)
	var opacity := clampf(float(_config.get("opacity", 0.30)), 0.0, 1.0)
	var mask_weight := clampf(float(_config.get("mask_weight", 1.0)), 0.0, 1.0)

	if not is_local:
		stretch_amount = maxf(float(live_global.get("stretch", stretch_amount)), 0.05)
		opacity = clampf(float(live_global.get("opacity", opacity)), 0.0, 1.0)
		var solar := _dictionary_value(live_global.get("solar", {}))
		var rotate_with_day := bool(solar.get("rotate_with_day", true))
		var fade_with_night := bool(solar.get("fade_with_night", true))
		var cycle := get_tree().get_first_node_in_group("day_night_cycle")
		if rotate_with_day and cycle != null and cycle.has_method("get_sun_shadow_direction_degrees"):
			direction_degrees = float(cycle.call("get_sun_shadow_direction_degrees"))
		else:
			direction_degrees = float(live_global.get("direction_degrees", direction_degrees))
		if fade_with_night and cycle != null and cycle.has_method("get_daylight_strength"):
			mask_weight *= clampf(float(cycle.call("get_daylight_strength")), 0.0, 1.0)

	var offset := _vector_from_value(_config.get("offset", {}), Vector2.ZERO)
	_projection_direction = Vector2.RIGHT.rotated(deg_to_rad(direction_degrees)).normalized()
	_projection_stretch = stretch_amount
	rotation = 0.0
	scale = Vector2.ONE
	position = offset
	color = Color(1.0, 1.0, 1.0, 0.0)
	self_modulate = Color.WHITE
	z_index = int(_config.get("z_index", -1))
	visible = bool(_config.get("enabled", true)) and bool(live_global.get("enabled", true)) and opacity > 0.001 and mask_weight > 0.001
	set_meta("shadow_direction_degrees", direction_degrees)
	set_meta("shadow_stretch", stretch_amount)
	set_meta("shadow_opacity", opacity)
	set_meta("shadow_mask_weight", mask_weight)


func _sync_proxy_material() -> void:
	super._sync_proxy_material()
	if _proxy_material == null:
		return
	_proxy_material.set_shader_parameter("mask_weight", float(get_meta("shadow_mask_weight", 1.0)))


func get_shadow_target() -> Node2D:
	return _target


func get_shadow_source() -> CanvasItem:
	return _source


func get_shadow_foot_offset() -> Vector2:
	return _foot_offset


func get_shadow_config() -> Dictionary:
	return _config.duplicate(true)


func _dictionary_value(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
