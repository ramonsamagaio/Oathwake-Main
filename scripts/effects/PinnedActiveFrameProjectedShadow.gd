class_name PinnedActiveFrameProjectedShadow
extends "res://scripts/effects/ActiveFrameProjectedShadow.gd"

const PROJECTION_MODE := "pinned_oblique_shear"
const DEFAULT_CONTACT_BAND_HEIGHT := 3
const CONTACT_ALPHA_THRESHOLD := 0.01


func _apply_texture_rect(
	frame_texture: Texture2D,
	frame_size: Vector2,
	centered: bool,
	sprite_offset: Vector2,
	flip_h: bool,
	flip_v: bool,
	relative_transform: Transform2D
) -> void:
	# Point-light shadows keep the existing rigid projection. The ground-contact
	# extraction below is specifically the directional sunlight solution.
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
	var contact_span := _get_texture_contact_span(frame_texture, opaque_rect, flip_h, flip_v)
	var contact_y := base_top_left.y + float(contact_span.get("draw_y", visible_bottom_right.y - base_top_left.y))
	var contact_left_x := base_top_left.x + float(contact_span.get("draw_left", drawn_position.x))
	var contact_right_x := base_top_left.x + float(contact_span.get("draw_right", drawn_position.x + opaque_size.x))
	if contact_right_x < contact_left_x:
		var swap_x := contact_left_x
		contact_left_x = contact_right_x
		contact_right_x = swap_x

	var contact_center_x := (contact_left_x + contact_right_x) * 0.5
	var contact_width_scale := maxf(float(_config.get("contact_width_scale", 1.0)), 0.05)
	contact_left_x = contact_center_x + (contact_left_x - contact_center_x) * contact_width_scale
	contact_right_x = contact_center_x + (contact_right_x - contact_center_x) * contact_width_scale

	var contact_left_target := relative_transform * Vector2(contact_left_x, contact_y)
	var contact_right_target := relative_transform * Vector2(contact_right_x, contact_y)
	var contact_target := (contact_left_target + contact_right_target) * 0.5
	var basis_scale := _relative_basis_scale(relative_transform)
	var base_axis := _relative_right_axis(relative_transform)

	# The top keeps the full visible silhouette width, while the lower edge uses
	# only the pixels that actually touch the ground. This is what turns a tree
	# into a canopy-shaped projection rooted at its trunk instead of a dark card.
	var top_left_base := relative_transform * Vector2(visible_top_left.x, contact_y)
	var top_right_base := relative_transform * Vector2(visible_bottom_right.x, contact_y)
	var top_center_base := (top_left_base + top_right_base) * 0.5
	var top_left_lateral := (top_left_base - top_center_base) * _projection_width_scale
	var top_right_lateral := (top_right_base - top_center_base) * _projection_width_scale
	var raw_height := maxf(contact_y - visible_top_left.y, 0.0)
	var movable_height := maxf(raw_height - _projection_root_overlap, 0.0)
	var projected_height := movable_height * basis_scale.y * _projection_stretch
	var projected_offset := _projection_direction * projected_height
	var projected_top_left := top_center_base + top_left_lateral + projected_offset
	var projected_top_right := top_center_base + top_right_lateral + projected_offset
	polygon = PackedVector2Array([
		projected_top_left,
		projected_top_right,
		contact_right_target,
		contact_left_target,
	])

	var left_u := float(opaque_rect.end.x) if flip_h else float(opaque_rect.position.x)
	var right_u := float(opaque_rect.position.x) if flip_h else float(opaque_rect.end.x)
	var top_v := float(opaque_rect.end.y) if flip_v else float(opaque_rect.position.y)
	var bottom_left_u := float(contact_span.get("source_right", opaque_rect.end.x)) if flip_h else float(contact_span.get("source_left", opaque_rect.position.x))
	var bottom_right_u := float(contact_span.get("source_left", opaque_rect.position.x)) if flip_h else float(contact_span.get("source_right", opaque_rect.end.x))
	var bottom_v := float(contact_span.get("source_contact_v", opaque_rect.position.y if flip_v else opaque_rect.end.y))
	uv = PackedVector2Array([
		Vector2(left_u, top_v),
		Vector2(right_u, top_v),
		Vector2(bottom_right_u, bottom_v),
		Vector2(bottom_left_u, bottom_v),
	])

	_publish_pinned_metadata(
		contact_target,
		base_axis,
		opaque_size * basis_scale,
		contact_left_target,
		contact_right_target
	)
	set_meta("shadow_opaque_rect", opaque_rect)
	set_meta("shadow_contact_span_pixels", contact_right_x - contact_left_x)
	set_meta("shadow_contact_band_height", int(contact_span.get("band_height", DEFAULT_CONTACT_BAND_HEIGHT)))
	set_meta("shadow_contact_extracted_from_alpha", bool(contact_span.get("alpha_extracted", false)))


func _get_texture_contact_span(
	frame_texture: Texture2D,
	opaque_rect: Rect2i,
	flip_h: bool,
	flip_v: bool
) -> Dictionary:
	var frame_width := maxi(int(round(frame_texture.get_width())), 1)
	var frame_height := maxi(int(round(frame_texture.get_height())), 1)
	var fallback_draw_left := float(frame_width - opaque_rect.end.x) if flip_h else float(opaque_rect.position.x)
	var fallback_draw_right := fallback_draw_left + float(opaque_rect.size.x)
	var fallback_draw_y := float(frame_height - opaque_rect.position.y) if flip_v else float(opaque_rect.end.y)
	var fallback := {
		"draw_left": fallback_draw_left,
		"draw_right": fallback_draw_right,
		"draw_y": fallback_draw_y,
		"source_left": float(opaque_rect.position.x),
		"source_right": float(opaque_rect.end.x),
		"source_contact_v": float(opaque_rect.position.y if flip_v else opaque_rect.end.y),
		"band_height": DEFAULT_CONTACT_BAND_HEIGHT,
		"alpha_extracted": false,
	}
	var image := frame_texture.get_image()
	if image == null or image.is_empty():
		return fallback

	var image_width := image.get_width()
	var image_height := image.get_height()
	if image_width <= 0 or image_height <= 0:
		return fallback
	frame_width = image_width
	frame_height = image_height

	var x_start := clampi(opaque_rect.position.x, 0, frame_width - 1)
	var x_end := clampi(opaque_rect.end.x, x_start + 1, frame_width)
	var rendered_bottom_y := -1
	var contact_source_y := -1
	for rendered_y in range(frame_height - 1, -1, -1):
		var source_y := frame_height - 1 - rendered_y if flip_v else rendered_y
		if source_y < opaque_rect.position.y or source_y >= opaque_rect.end.y:
			continue
		var row_has_alpha := false
		for source_x in range(x_start, x_end):
			if image.get_pixel(source_x, source_y).a > CONTACT_ALPHA_THRESHOLD:
				row_has_alpha = true
				break
		if row_has_alpha:
			rendered_bottom_y = rendered_y
			contact_source_y = source_y
			break
	if rendered_bottom_y < 0:
		return fallback

	var band_height := clampi(
		int(_config.get("contact_band_height", DEFAULT_CONTACT_BAND_HEIGHT)),
		1,
		maxi(opaque_rect.size.y, 1)
	)
	var rendered_band_top := maxi(rendered_bottom_y - band_height + 1, 0)
	var minimum_draw_x := INF
	var maximum_draw_x := -INF
	var minimum_source_x := frame_width
	var maximum_source_x := -1
	for rendered_y in range(rendered_bottom_y, rendered_band_top - 1, -1):
		var source_y := frame_height - 1 - rendered_y if flip_v else rendered_y
		if source_y < opaque_rect.position.y or source_y >= opaque_rect.end.y:
			continue
		for source_x in range(x_start, x_end):
			if image.get_pixel(source_x, source_y).a <= CONTACT_ALPHA_THRESHOLD:
				continue
			var draw_x := frame_width - 1 - source_x if flip_h else source_x
			minimum_draw_x = minf(minimum_draw_x, float(draw_x))
			maximum_draw_x = maxf(maximum_draw_x, float(draw_x + 1))
			minimum_source_x = mini(minimum_source_x, source_x)
			maximum_source_x = maxi(maximum_source_x, source_x + 1)

	if not is_finite(minimum_draw_x) or not is_finite(maximum_draw_x) or maximum_draw_x <= minimum_draw_x:
		return fallback
	return {
		"draw_left": minimum_draw_x,
		"draw_right": maximum_draw_x,
		"draw_y": float(rendered_bottom_y + 1),
		"source_left": float(minimum_source_x),
		"source_right": float(maximum_source_x),
		"source_contact_v": float(contact_source_y if flip_v else contact_source_y + 1),
		"band_height": band_height,
		"alpha_extracted": true,
	}


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
	var base_point := relative_transform * Vector2(point.x, contact_y)
	var raw_height := maxf(contact_y - point.y, 0.0)
	var movable_height := maxf(raw_height - _projection_root_overlap, 0.0)
	var projected_height := movable_height * basis_scale.y * _projection_stretch
	var height_ratio := clampf(raw_height / maxf(maximum_height, 0.0001), 0.0, 1.0)
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
