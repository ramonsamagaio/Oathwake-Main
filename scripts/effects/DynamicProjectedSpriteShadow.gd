class_name DynamicProjectedSpriteShadow
extends "res://scripts/effects/ProjectedSpriteShadow.gd"

const CASTER_GROUP := "projected_shadow_caster"
const DEFAULT_MORNING_ANGLE_FROM_UP := -45.0
const DEFAULT_EVENING_ANGLE_FROM_UP := 45.0

var _projection_width_scale := 1.0
var _projection_root_overlap := 6.0


func configure(target: Node2D, source: CanvasItem, config: Dictionary, foot_offset: Vector2) -> void:
	super.configure(target, source, config, foot_offset)
	var is_local := bool(_config.get("local_light_shadow", false))
	if not is_local and not is_in_group(CASTER_GROUP):
		add_to_group(CASTER_GROUP)
	elif is_local and is_in_group(CASTER_GROUP):
		remove_from_group(CASTER_GROUP)
	set_meta("shadow_kind", "local" if is_local else "solar")

	# Local-light shadows are refreshed by their director at a bounded interval,
	# so they do not need a second per-frame silhouette pass. Solar shadows also
	# suspend processing during the fully hidden part of the night.
	if is_local:
		set_process(false)
	else:
		_sync_solar_processing_to_cycle()


func set_solar_shadow_processing(active: bool) -> void:
	if bool(_config.get("local_light_shadow", false)):
		return
	if active:
		set_process(true)
		_refresh_silhouette()
		return
	_apply_projection_settings()
	visible = false
	_hide_render_proxy()
	set_process(false)


func _sync_solar_processing_to_cycle() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if cycle != null and cycle.has_method("get_solar_shadow_strength"):
		set_solar_shadow_processing(float(cycle.call("get_solar_shadow_strength")) > 0.001)
	else:
		set_process(true)


func _apply_projection_settings() -> void:
	var live_global := _get_live_global_config()
	var is_local := bool(_config.get("local_light_shadow", false))
	var direction_degrees := float(_config.get("direction_degrees", DEFAULT_DIRECTION_DEGREES))
	var resolved_direction := Vector2.RIGHT.rotated(deg_to_rad(direction_degrees)).normalized()
	var stretch_amount := maxf(float(_config.get("stretch", 1.15)), 0.05)
	var opacity := clampf(float(_config.get("opacity", 0.30)), 0.0, 1.0)
	var mask_weight := clampf(float(_config.get("mask_weight", 1.0)), 0.0, 1.0)
	_projection_width_scale = maxf(float(_config.get("width_scale", 1.0)), 0.05)
	_projection_root_overlap = maxf(float(_config.get("root_overlap", 4.0 if is_local else 6.0)), 0.0)

	if not is_local:
		stretch_amount = maxf(float(live_global.get("stretch", stretch_amount)), 0.05)
		opacity = clampf(float(live_global.get("opacity", opacity)), 0.0, 1.0)
		var solar := _dictionary_value(live_global.get("solar", {}))
		var rotate_with_day := bool(solar.get("rotate_with_day", true))
		var fade_with_night := bool(solar.get("fade_with_night", true))
		_projection_width_scale = maxf(float(solar.get("width_scale", live_global.get("width_scale", _projection_width_scale))), 0.05)
		_projection_root_overlap = maxf(float(solar.get("root_overlap", live_global.get("root_overlap", _projection_root_overlap))), 0.0)
		var cycle := get_tree().get_first_node_in_group("day_night_cycle")
		if rotate_with_day and cycle != null and cycle.has_method("get_sun_shadow_direction"):
			var cycle_direction: Variant = cycle.call("get_sun_shadow_direction")
			if cycle_direction is Vector2 and (cycle_direction as Vector2).length_squared() > 0.0001:
				resolved_direction = (cycle_direction as Vector2).normalized()
				direction_degrees = rad_to_deg(resolved_direction.angle())
		elif rotate_with_day and cycle != null and cycle.has_method("get_sun_shadow_direction_degrees"):
			direction_degrees = float(cycle.call("get_sun_shadow_direction_degrees"))
			resolved_direction = Vector2.RIGHT.rotated(deg_to_rad(direction_degrees)).normalized()
		else:
			direction_degrees = float(live_global.get("direction_degrees", direction_degrees))
			resolved_direction = Vector2.RIGHT.rotated(deg_to_rad(direction_degrees)).normalized()
		if fade_with_night and cycle != null and cycle.has_method("get_solar_shadow_strength"):
			mask_weight *= clampf(float(cycle.call("get_solar_shadow_strength")), 0.0, 1.0)
		elif fade_with_night and cycle != null and cycle.has_method("get_daylight_strength"):
			mask_weight *= clampf(float(cycle.call("get_daylight_strength")), 0.0, 1.0)

	var offset := _vector_from_value(_config.get("offset", {}), Vector2.ZERO)
	_projection_direction = resolved_direction if resolved_direction.length_squared() > 0.0001 else Vector2.UP
	_projection_stretch = stretch_amount
	rotation = 0.0
	scale = Vector2.ONE
	position = offset
	color = Color(1.0, 1.0, 1.0, 0.0)
	self_modulate = Color.WHITE
	z_index = int(_config.get("z_index", -1))
	visible = bool(_config.get("enabled", true)) and bool(live_global.get("enabled", true)) and opacity > 0.001 and mask_weight > 0.001
	set_meta("shadow_direction_degrees", direction_degrees)
	set_meta("shadow_direction_vector", _projection_direction)
	set_meta("shadow_stretch", stretch_amount)
	set_meta("shadow_width_scale", _projection_width_scale)
	set_meta("shadow_root_overlap", _projection_root_overlap)
	set_meta("shadow_opacity", opacity)
	set_meta("shadow_mask_weight", mask_weight)


func _apply_texture_rect(
	frame_texture: Texture2D,
	frame_size: Vector2,
	centered: bool,
	offset: Vector2,
	flip_h: bool,
	flip_v: bool,
	relative_transform: Transform2D
) -> void:
	var opaque_rect := _get_opaque_pixel_rect(frame_texture)
	if opaque_rect.size.x <= 0 or opaque_rect.size.y <= 0:
		_clear_visual()
		return

	texture = frame_texture
	_visible_frame_size = frame_size
	var base_top_left := offset
	if centered:
		base_top_left -= frame_size * 0.5

	var drawn_position := Vector2(opaque_rect.position)
	var opaque_size := Vector2(opaque_rect.size)
	if flip_h:
		drawn_position.x = frame_size.x - float(opaque_rect.end.x)
	if flip_v:
		drawn_position.y = frame_size.y - float(opaque_rect.end.y)
	var visible_top_left := base_top_left + drawn_position
	var visible_bottom_right := visible_top_left + opaque_size
	var contact_local := Vector2((visible_top_left.x + visible_bottom_right.x) * 0.5, visible_bottom_right.y)
	var contact_target := relative_transform * contact_local
	var basis_scale := _relative_basis_scale(relative_transform)
	var side_axis := _projection_direction.rotated(PI * 0.5).normalized()
	var projection_anchor := contact_target - (_projection_direction * _projection_root_overlap)

	var local_corners := PackedVector2Array([
		visible_top_left,
		Vector2(visible_bottom_right.x, visible_top_left.y),
		visible_bottom_right,
		Vector2(visible_top_left.x, visible_bottom_right.y),
	])
	var projected := PackedVector2Array()
	for point in local_corners:
		var lateral := (point.x - contact_local.x) * basis_scale.x * _projection_width_scale
		var height := maxf(contact_local.y - point.y, 0.0) * basis_scale.y * _projection_stretch
		projected.append(projection_anchor + (side_axis * lateral) + (_projection_direction * height))
	polygon = projected

	var left_u := float(opaque_rect.end.x) if flip_h else float(opaque_rect.position.x)
	var right_u := float(opaque_rect.position.x) if flip_h else float(opaque_rect.end.x)
	var top_v := float(opaque_rect.end.y) if flip_v else float(opaque_rect.position.y)
	var bottom_v := float(opaque_rect.position.y) if flip_v else float(opaque_rect.end.y)
	uv = PackedVector2Array([
		Vector2(left_u, top_v),
		Vector2(right_u, top_v),
		Vector2(right_u, bottom_v),
		Vector2(left_u, bottom_v),
	])
	_publish_projection_metadata(contact_target, projection_anchor, side_axis, opaque_size * basis_scale)
	set_meta("shadow_opaque_rect", opaque_rect)


func _apply_polygon(source: Polygon2D) -> void:
	texture = source.texture
	var relative_transform := _source_to_target_transform(source)
	if source.polygon.is_empty():
		_clear_visual()
		return
	var bounds := Rect2(source.polygon[0], Vector2.ZERO)
	for point in source.polygon:
		bounds = bounds.expand(point)
	var contact_local := Vector2(bounds.get_center().x, bounds.end.y)
	var contact_target := relative_transform * contact_local
	var basis_scale := _relative_basis_scale(relative_transform)
	var side_axis := _projection_direction.rotated(PI * 0.5).normalized()
	var projection_anchor := contact_target - (_projection_direction * _projection_root_overlap)
	var projected := PackedVector2Array()
	for point in source.polygon:
		var lateral := (point.x - contact_local.x) * basis_scale.x * _projection_width_scale
		var height := maxf(contact_local.y - point.y, 0.0) * basis_scale.y * _projection_stretch
		projected.append(projection_anchor + (side_axis * lateral) + (_projection_direction * height))
	polygon = projected
	uv = source.uv
	_visible_frame_size = bounds.size
	_publish_projection_metadata(contact_target, projection_anchor, side_axis, bounds.size * basis_scale)
	set_meta("shadow_source_kind", "Polygon2D")


func _relative_basis_scale(relative_transform: Transform2D) -> Vector2:
	var origin := relative_transform * Vector2.ZERO
	var right_scale := ((relative_transform * Vector2.RIGHT) - origin).length()
	var up_scale := ((relative_transform * Vector2.UP) - origin).length()
	return Vector2(maxf(right_scale, 0.0001), maxf(up_scale, 0.0001))


func _publish_projection_metadata(contact: Vector2, anchor: Vector2, side_axis: Vector2, source_size: Vector2) -> void:
	set_meta("shadow_projection_contact", contact)
	set_meta("shadow_projection_anchor", anchor)
	set_meta("shadow_projection_side_axis", side_axis)
	set_meta("shadow_projection_direction", _projection_direction)
	set_meta("shadow_projection_source_size", source_size)
	set_meta("shadow_projection_rigid_basis", true)


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
