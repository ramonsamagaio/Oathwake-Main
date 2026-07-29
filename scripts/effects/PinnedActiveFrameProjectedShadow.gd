class_name PinnedActiveFrameProjectedShadow
extends "res://scripts/effects/ActiveFrameProjectedShadow.gd"

const PROJECTION_MODE := "pinned_oblique_shear"


func _apply_texture_rect(
	frame_texture: Texture2D,
	frame_size: Vector2,
	centered: bool,
	sprite_offset: Vector2,
	flip_h: bool,
	flip_v: bool,
	relative_transform: Transform2D
) -> void:
	# Point-light shadows keep the existing rigid projection. The pinned oblique
	# projection is specifically the directional sunlight solution.
	if bool(_config.get("local_light_shadow", false)):
		super._apply_texture_rect(
			frame_texture,
			frame_size,
			centered,
			sprite_offset,
			flip_h,
			flip_v,
			relative_transform
		)
		return

	var opaque_rect := _get_opaque_pixel_rect(frame_texture)
	if opaque_rect.size.x <= 0 or opaque_rect.size.y <= 0:
		_clear_visual()
		return

	texture = frame_texture
	_visible_frame_size = frame_size
	var base_top_left := sprite_offset
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
	var contact_y := visible_bottom_right.y
	var contact_x := (visible_top_left.x + visible_bottom_right.x) * 0.5
	var contact_local := Vector2(contact_x, contact_y)
	var contact_target := relative_transform * contact_local
	var basis_scale := _relative_basis_scale(relative_transform)
	var base_axis := _relative_right_axis(relative_transform)

	var local_corners := PackedVector2Array([
		visible_top_left,
		Vector2(visible_bottom_right.x, visible_top_left.y),
		visible_bottom_right,
		Vector2(visible_top_left.x, visible_bottom_right.y),
	])
	var projected := PackedVector2Array()
	for point in local_corners:
		projected.append(_project_from_pinned_base(
			point,
			contact_x,
			contact_y,
			opaque_size.y,
			relative_transform,
			basis_scale,
			base_axis
		))
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

	var bottom_left_target := relative_transform * Vector2(visible_top_left.x, contact_y)
	var bottom_right_target := relative_transform * Vector2(visible_bottom_right.x, contact_y)
	_publish_pinned_metadata(
		contact_target,
		base_axis,
		opaque_size * basis_scale,
		bottom_left_target,
		bottom_right_target
	)
	set_meta("shadow_opaque_rect", opaque_rect)


func _apply_polygon(source: Polygon2D) -> void:
	if bool(_config.get("local_light_shadow", false)):
		super._apply_polygon(source)
		return

	texture = source.texture if source.texture != null else _get_solid_mask_texture()
	var relative_transform := _source_to_target_transform(source)
	if source.polygon.is_empty():
		_clear_visual()
		return

	var bounds := Rect2(source.polygon[0], Vector2.ZERO)
	for point in source.polygon:
		bounds = bounds.expand(point)
	var contact_y := bounds.end.y
	var contact_x := bounds.get_center().x
	var contact_target := relative_transform * Vector2(contact_x, contact_y)
	var basis_scale := _relative_basis_scale(relative_transform)
	var base_axis := _relative_right_axis(relative_transform)
	var projected := PackedVector2Array()
	for point in source.polygon:
		projected.append(_project_from_pinned_base(
			point,
			contact_x,
			contact_y,
			bounds.size.y,
			relative_transform,
			basis_scale,
			base_axis
		))
	polygon = projected

	if source.texture != null and source.uv.size() == source.polygon.size():
		uv = source.uv
	else:
		var solid_uv := PackedVector2Array()
		for _point in source.polygon:
			solid_uv.append(Vector2(0.5, 0.5))
		uv = solid_uv

	_visible_frame_size = bounds.size
	var bottom_left_target := relative_transform * Vector2(bounds.position.x, contact_y)
	var bottom_right_target := relative_transform * Vector2(bounds.end.x, contact_y)
	_publish_pinned_metadata(
		contact_target,
		base_axis,
		bounds.size * basis_scale,
		bottom_left_target,
		bottom_right_target
	)
	set_meta("shadow_source_kind", "Polygon2D")


func _project_from_pinned_base(
	point: Vector2,
	contact_x: float,
	contact_y: float,
	maximum_height: float,
	relative_transform: Transform2D,
	basis_scale: Vector2,
	base_axis: Vector2
) -> Vector2:
	# Every source column owns an immutable point on the south edge. Only the
	# portion above the pinned root band is displaced by sunlight. This is an
	# oblique projection, not a rotation of the sprite-shaped card.
	var base_point := relative_transform * Vector2(point.x, contact_y)
	var raw_height := maxf(contact_y - point.y, 0.0)
	var movable_height := maxf(raw_height - _projection_root_overlap, 0.0)
	var projected_height := movable_height * basis_scale.y * _projection_stretch
	var height_ratio := clampf(raw_height / maxf(maximum_height, 0.0001), 0.0, 1.0)

	# Width tuning is blended from zero at the pinned edge to its full amount at
	# the top. The two southern extremities therefore never slide sideways.
	var lateral_from_center := (point.x - contact_x) * basis_scale.x
	var width_delta := lateral_from_center * (_projection_width_scale - 1.0) * height_ratio
	return base_point + (base_axis * width_delta) + (_projection_direction * projected_height)


func _relative_right_axis(relative_transform: Transform2D) -> Vector2:
	var origin := relative_transform * Vector2.ZERO
	var right_vector := (relative_transform * Vector2.RIGHT) - origin
	if right_vector.length_squared() <= 0.000001:
		return Vector2.RIGHT
	return right_vector.normalized()


func _publish_pinned_metadata(
	contact_target: Vector2,
	base_axis: Vector2,
	source_size: Vector2,
	bottom_left_target: Vector2,
	bottom_right_target: Vector2
) -> void:
	_publish_projection_metadata(contact_target, contact_target, base_axis, source_size)
	set_meta("shadow_projection_rigid_basis", false)
	set_meta("shadow_projection_pinned_base", true)
	set_meta("shadow_projection_mode", PROJECTION_MODE)
	set_meta("shadow_projection_bottom_left", bottom_left_target)
	set_meta("shadow_projection_bottom_right", bottom_right_target)
	set_meta("shadow_projection_pinned_band", _projection_root_overlap)
	set_meta("shadow_southern_limit_y", maxf(bottom_left_target.y, bottom_right_target.y))
	set_meta("shadow_southern_limit_shift", Vector2.ZERO)
