class_name ProfiledProjectedShadow
extends "res://scripts/effects/DynamicProjectedSpriteShadow.gd"

const ShadowProfiles := preload("res://scripts/effects/ShadowProfileLibrary.gd")
const PROJECTION_MODE := "ground_contact_silhouette"
const DEFAULT_CONTACT_BAND_HEIGHT := 3
const DEFAULT_CONTACT_MIN_PIXELS := 2
const CONTACT_ALPHA_THRESHOLD := 0.01

static var _contact_span_cache: Dictionary = {}


func _apply_animated_sprite(source: AnimatedSprite2D) -> void:
	if _should_use_legacy_silhouette():
		super._apply_animated_sprite(source)
		return
	if source.sprite_frames == null or not source.sprite_frames.has_animation(source.animation):
		_clear_visual()
		return
	var frame_count := source.sprite_frames.get_frame_count(source.animation)
	if frame_count <= 0:
		_clear_visual()
		return
	var frame_index := clampi(source.frame, 0, frame_count - 1)
	var frame_texture := source.sprite_frames.get_frame_texture(source.animation, frame_index)
	if not _is_valid_texture_size(frame_texture):
		_clear_visual()
		return
	_apply_profile_texture_rect(
		frame_texture,
		frame_texture.get_size(),
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)
	set_meta("shadow_source_kind", "AnimatedSprite2D")
	set_meta("shadow_source_animation", source.animation)
	set_meta("shadow_source_frame", frame_index)
	set_meta("shadow_source_frame_isolated", true)
	set_meta("shadow_active_frame_region_constrained", true)


func _apply_sprite(source: Sprite2D) -> void:
	if _should_use_legacy_silhouette():
		super._apply_sprite(source)
		return
	var frame_texture := _resolve_sprite_texture(source)
	if not _is_valid_texture_size(frame_texture):
		_clear_visual()
		return
	_apply_profile_texture_rect(
		frame_texture,
		frame_texture.get_size(),
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)
	set_meta("shadow_source_kind", "Sprite2D")
	set_meta("shadow_source_frame", source.frame)
	set_meta("shadow_source_frame_isolated", true)
	set_meta("shadow_active_frame_region_constrained", true)


func _apply_texture_rect(
	frame_texture: Texture2D,
	frame_size: Vector2,
	centered: bool,
	sprite_offset: Vector2,
	flip_h: bool,
	flip_v: bool,
	relative_transform: Transform2D
) -> void:
	if _should_use_legacy_silhouette():
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
	_apply_profile_texture_rect(
		frame_texture,
		frame_size,
		centered,
		sprite_offset,
		flip_h,
		flip_v,
		relative_transform
	)


func _apply_polygon(source: Polygon2D) -> void:
	if _should_use_legacy_silhouette():
		super._apply_polygon(source)
		return
	if source.polygon.is_empty():
		_clear_visual()
		return

	var bounds := Rect2(source.polygon[0], Vector2.ZERO)
	for point in source.polygon:
		bounds = bounds.expand(point)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_clear_visual()
		return

	var global_shadow_config := _get_live_global_config()
	var visual_size := _resolve_visual_size(bounds.size, _source_to_target_transform(source))
	var profile := ShadowProfiles.resolve_profile(_target, _source, _config, global_shadow_config, visual_size)
	var profile_length_scale := maxf(float(_config.get("shadow_profile_length_scale", 1.0)), 0.05)
	var profile_length_ratio := maxf(float(profile.get("length_ratio", 1.0)), 0.05)
	var root_overlap := _projection_root_overlap * maxf(float(profile.get("root_overlap_multiplier", 1.0)), 0.0)
	var relative_transform := _source_to_target_transform(source)
	var basis_scale := _relative_basis_scale(relative_transform)
	var contact_y := bounds.end.y
	var contact_local := Vector2(bounds.get_center().x, contact_y)
	var contact_target := relative_transform * contact_local
	var projection_anchor := contact_target - (_projection_direction * root_overlap)
	var side_axis := _projection_direction.rotated(PI * 0.5).normalized()
	var projected := PackedVector2Array()

	for point in source.polygon:
		var base_point := relative_transform * Vector2(point.x, contact_y)
		var lateral_offset := (base_point - contact_target).project(side_axis) * _projection_width_scale
		var projected_height := maxf(contact_y - point.y, 0.0) * basis_scale.y
		projected_height *= _projection_stretch * profile_length_ratio * profile_length_scale
		projected.append(projection_anchor + lateral_offset + (_projection_direction * projected_height))

	if projected.size() < 3:
		_clear_visual()
		return

	polygon = projected
	texture = source.texture if source.texture != null else _get_solid_mask_texture()
	if source.texture != null and source.uv.size() == source.polygon.size():
		uv = source.uv
	else:
		var solid_uv := PackedVector2Array()
		for _point in projected:
			solid_uv.append(Vector2(0.5, 0.5))
		uv = solid_uv
	_visible_frame_size = visual_size
	_publish_projection_metadata(contact_target, projection_anchor, side_axis, visual_size)
	_publish_profile_metadata(profile, visual_size, root_overlap, false, bounds.size.x)
	set_meta("shadow_source_kind", "Polygon2D")


func _apply_profile_texture_rect(
	frame_texture: Texture2D,
	frame_size: Vector2,
	centered: bool,
	sprite_offset: Vector2,
	flip_h: bool,
	flip_v: bool,
	relative_transform: Transform2D
) -> void:
	if not _is_valid_texture_size(frame_texture) or frame_size.x <= 0.0 or frame_size.y <= 0.0:
		_clear_visual()
		return

	var render_texture := frame_texture
	var sampling_origin := Vector2.ZERO
	if frame_texture is AtlasTexture:
		var atlas_texture := frame_texture as AtlasTexture
		if atlas_texture.atlas == null or not _is_valid_texture_size(atlas_texture.atlas):
			_clear_visual()
			return
		if atlas_texture.region.size.x <= 0.0 or atlas_texture.region.size.y <= 0.0:
			_clear_visual()
			return
		render_texture = atlas_texture.atlas
		sampling_origin = atlas_texture.region.position
		frame_size = atlas_texture.region.size

	var opaque_rect := _get_opaque_pixel_rect(frame_texture)
	if opaque_rect.size.x <= 0 or opaque_rect.size.y <= 0:
		opaque_rect = _full_frame_rect(frame_size)
	if opaque_rect.size.x <= 0 or opaque_rect.size.y <= 0:
		_clear_visual()
		return

	var global_shadow_config := _get_live_global_config()
	var visual_size := _resolve_visual_size(frame_size, relative_transform)
	var profile := ShadowProfiles.resolve_profile(_target, _source, _config, global_shadow_config, visual_size)
	var contact_band_height := clampi(
		int(_config.get("contact_band_height", _default_contact_band_height(profile))),
		1,
		maxi(opaque_rect.size.y, 1)
	)
	var contact_min_pixels := maxi(
		int(_config.get("contact_min_pixels", _default_contact_min_pixels(profile))),
		1
	)
	var alpha_threshold := clampf(
		float(_config.get("contact_alpha_threshold", CONTACT_ALPHA_THRESHOLD)),
		0.0,
		1.0
	)
	var contact_span := _get_texture_contact_span(
		frame_texture,
		opaque_rect,
		flip_h,
		flip_v,
		contact_band_height,
		contact_min_pixels,
		alpha_threshold
	)

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

	var contact_y := base_top_left.y + float(contact_span.get("draw_y", visible_bottom_right.y - base_top_left.y))
	var contact_left_x := base_top_left.x + float(contact_span.get("draw_left", drawn_position.x))
	var contact_right_x := base_top_left.x + float(contact_span.get("draw_right", drawn_position.x + opaque_size.x))
	if contact_right_x < contact_left_x:
		var swapped_x := contact_left_x
		contact_left_x = contact_right_x
		contact_right_x = swapped_x

	var contact_center_x := (contact_left_x + contact_right_x) * 0.5
	var alpha_extracted := bool(contact_span.get("alpha_extracted", false))
	if not alpha_extracted:
		var fallback_ratio := _fallback_contact_width_ratio(profile)
		var fallback_width := maxf(frame_size.x * fallback_ratio, 1.0)
		contact_left_x = contact_center_x - fallback_width * 0.5
		contact_right_x = contact_center_x + fallback_width * 0.5

	var max_contact_ratio := _max_contact_width_ratio(profile)
	var max_contact_width := maxf(frame_size.x * max_contact_ratio, 1.0)
	var resolved_contact_width := minf(contact_right_x - contact_left_x, max_contact_width)
	var contact_width_scale := maxf(float(_config.get("contact_width_scale", 1.0)), 0.05)
	resolved_contact_width = maxf(resolved_contact_width * contact_width_scale, 1.0)
	contact_left_x = contact_center_x - resolved_contact_width * 0.5
	contact_right_x = contact_center_x + resolved_contact_width * 0.5

	var contact_left_target := relative_transform * Vector2(contact_left_x, contact_y)
	var contact_right_target := relative_transform * Vector2(contact_right_x, contact_y)
	var contact_target := (contact_left_target + contact_right_target) * 0.5
	var side_axis := _projection_direction.rotated(PI * 0.5).normalized()

	var top_left_base := relative_transform * Vector2(visible_top_left.x, contact_y)
	var top_right_base := relative_transform * Vector2(visible_bottom_right.x, contact_y)
	var top_center_base := (top_left_base + top_right_base) * 0.5
	var width_scale := _projection_width_scale * maxf(float(_config.get("shadow_profile_width_scale", 1.0)), 0.05)
	top_left_base = top_center_base + (top_left_base - top_center_base) * width_scale
	top_right_base = top_center_base + (top_right_base - top_center_base) * width_scale

	var basis_scale := _relative_basis_scale(relative_transform)
	var raw_height := maxf(contact_y - visible_top_left.y, 0.0)
	var profile_length_scale := maxf(float(_config.get("shadow_profile_length_scale", 1.0)), 0.05)
	var profile_length_ratio := maxf(float(profile.get("length_ratio", 1.0)), 0.05)
	var projected_height := raw_height * basis_scale.y * _projection_stretch * profile_length_ratio * profile_length_scale
	var minimum_length := maxf(float(profile.get("minimum_length", 0.0)), 0.0)
	projected_height = maxf(projected_height, minimum_length * _projection_stretch * profile_length_scale)

	var root_overlap := _projection_root_overlap * maxf(float(profile.get("root_overlap_multiplier", 1.0)), 0.0)
	var overlap_offset := -_projection_direction * root_overlap
	var projected_offset := _projection_direction * projected_height
	var projected_top_left := top_left_base + projected_offset
	var projected_top_right := top_right_base + projected_offset
	var root_left := contact_left_target + overlap_offset
	var root_right := contact_right_target + overlap_offset

	polygon = PackedVector2Array([
		projected_top_left,
		projected_top_right,
		root_right,
		root_left,
	])

	var left_u := float(opaque_rect.end.x) if flip_h else float(opaque_rect.position.x)
	var right_u := float(opaque_rect.position.x) if flip_h else float(opaque_rect.end.x)
	var top_v := float(opaque_rect.end.y) if flip_v else float(opaque_rect.position.y)
	var bottom_left_u := (
		float(contact_span.get("source_right", opaque_rect.end.x))
		if flip_h
		else float(contact_span.get("source_left", opaque_rect.position.x))
	)
	var bottom_right_u := (
		float(contact_span.get("source_left", opaque_rect.position.x))
		if flip_h
		else float(contact_span.get("source_right", opaque_rect.end.x))
	)
	var bottom_v := float(
		contact_span.get(
			"source_contact_v",
			opaque_rect.position.y if flip_v else opaque_rect.end.y
		)
	)
	uv = PackedVector2Array([
		sampling_origin + Vector2(left_u, top_v),
		sampling_origin + Vector2(right_u, top_v),
		sampling_origin + Vector2(bottom_right_u, bottom_v),
		sampling_origin + Vector2(bottom_left_u, bottom_v),
	])
	texture = render_texture
	_visible_frame_size = visual_size

	_publish_projection_metadata(contact_target, (root_left + root_right) * 0.5, side_axis, visual_size)
	_publish_profile_metadata(profile, visual_size, root_overlap, alpha_extracted, resolved_contact_width)
	set_meta("shadow_opaque_rect", opaque_rect)
	set_meta("shadow_active_frame_uv_origin", sampling_origin)
	set_meta("shadow_active_frame_region_constrained", true)
	set_meta("shadow_contact_band_height", contact_band_height)
	set_meta("shadow_contact_min_pixels", contact_min_pixels)
	set_meta("shadow_contact_alpha_threshold", alpha_threshold)
	set_meta("shadow_contact_span_pixels", resolved_contact_width)
	set_meta("shadow_contact_extracted_from_alpha", alpha_extracted)
	set_meta("shadow_southern_limit_y", contact_target.y)
	set_meta("shadow_southern_limit_shift", Vector2.ZERO)


func _get_texture_contact_span(
	frame_texture: Texture2D,
	opaque_rect: Rect2i,
	flip_h: bool,
	flip_v: bool,
	band_height: int,
	minimum_row_pixels: int,
	alpha_threshold: float
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
		"band_height": band_height,
		"alpha_extracted": false,
	}

	var cache_key := _contact_cache_key(
		frame_texture,
		flip_h,
		flip_v,
		band_height,
		minimum_row_pixels,
		alpha_threshold
	)
	if _contact_span_cache.has(cache_key):
		return (_contact_span_cache[cache_key] as Dictionary).duplicate(true)

	var image := frame_texture.get_image()
	if image == null or image.is_empty():
		_contact_span_cache[cache_key] = fallback
		return fallback.duplicate(true)

	frame_width = image.get_width()
	frame_height = image.get_height()
	if frame_width <= 0 or frame_height <= 0:
		_contact_span_cache[cache_key] = fallback
		return fallback.duplicate(true)

	var x_start := clampi(opaque_rect.position.x, 0, frame_width - 1)
	var x_end := clampi(opaque_rect.end.x, x_start + 1, frame_width)
	var rendered_bottom_y := -1
	var contact_source_y := -1
	var first_alpha_rendered_y := -1
	var first_alpha_source_y := -1

	for rendered_y in range(frame_height - 1, -1, -1):
		var source_y := frame_height - 1 - rendered_y if flip_v else rendered_y
		if source_y < opaque_rect.position.y or source_y >= opaque_rect.end.y:
			continue
		var row_alpha_count := 0
		for source_x in range(x_start, x_end):
			if image.get_pixel(source_x, source_y).a > alpha_threshold:
				row_alpha_count += 1
		if row_alpha_count > 0 and first_alpha_rendered_y < 0:
			first_alpha_rendered_y = rendered_y
			first_alpha_source_y = source_y
		if row_alpha_count >= minimum_row_pixels:
			rendered_bottom_y = rendered_y
			contact_source_y = source_y
			break

	if rendered_bottom_y < 0:
		rendered_bottom_y = first_alpha_rendered_y
		contact_source_y = first_alpha_source_y
	if rendered_bottom_y < 0 or contact_source_y < 0:
		_contact_span_cache[cache_key] = fallback
		return fallback.duplicate(true)

	var rendered_band_top := maxi(rendered_bottom_y - band_height + 1, 0)
	var minimum_draw_x := INF
	var maximum_draw_x := -INF
	var minimum_source_x := frame_width
	var maximum_source_x := -1

	for rendered_y in range(rendered_band_top, rendered_bottom_y + 1):
		var source_y := frame_height - 1 - rendered_y if flip_v else rendered_y
		if source_y < opaque_rect.position.y or source_y >= opaque_rect.end.y:
			continue
		for source_x in range(x_start, x_end):
			if image.get_pixel(source_x, source_y).a <= alpha_threshold:
				continue
			var draw_left := float(frame_width - source_x - 1) if flip_h else float(source_x)
			var draw_right := draw_left + 1.0
			minimum_draw_x = minf(minimum_draw_x, draw_left)
			maximum_draw_x = maxf(maximum_draw_x, draw_right)
			minimum_source_x = mini(minimum_source_x, source_x)
			maximum_source_x = maxi(maximum_source_x, source_x)

	if minimum_draw_x == INF or maximum_draw_x == -INF or maximum_source_x < minimum_source_x:
		_contact_span_cache[cache_key] = fallback
		return fallback.duplicate(true)

	var source_contact_v := float(contact_source_y) if flip_v else float(contact_source_y + 1)
	var result := {
		"draw_left": minimum_draw_x,
		"draw_right": maximum_draw_x,
		"draw_y": float(rendered_bottom_y + 1),
		"source_left": float(minimum_source_x),
		"source_right": float(maximum_source_x + 1),
		"source_contact_v": source_contact_v,
		"band_height": band_height,
		"alpha_extracted": true,
	}
	_contact_span_cache[cache_key] = result
	return result.duplicate(true)


func _contact_cache_key(
	frame_texture: Texture2D,
	flip_h: bool,
	flip_v: bool,
	band_height: int,
	minimum_row_pixels: int,
	alpha_threshold: float
) -> String:
	var texture_key := "texture:%s" % str(frame_texture.get_instance_id())
	if frame_texture is AtlasTexture:
		var atlas_texture := frame_texture as AtlasTexture
		var atlas_id := "none"
		if atlas_texture.atlas != null:
			atlas_id = str(atlas_texture.atlas.get_instance_id())
		texture_key = "atlas:%s:%s" % [atlas_id, str(atlas_texture.region)]
	return "%s:h%s:v%s:b%d:m%d:a%d" % [
		texture_key,
		str(flip_h),
		str(flip_v),
		band_height,
		minimum_row_pixels,
		int(round(alpha_threshold * 10000.0)),
	]


func _publish_profile_metadata(
	profile: Dictionary,
	visual_size: Vector2,
	root_overlap: float,
	alpha_extracted: bool,
	contact_width: float
) -> void:
	set_meta("shadow_projection_mode", PROJECTION_MODE)
	set_meta("shadow_projection_profiled", true)
	set_meta("shadow_profile_id", str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)))
	set_meta("shadow_profile_display_name", str(profile.get("display_name", "Shadow Profile")))
	set_meta("shadow_profile_root_overlap", root_overlap)
	set_meta("shadow_profile_contact_pinned", true)
	set_meta("shadow_profile_root_matches_contact", true)
	set_meta("shadow_profile_ignores_frame_silhouette", false)
	set_meta("shadow_profile_uses_active_frame_alpha", true)
	set_meta("shadow_profile_uses_collision_footprint", false)
	set_meta("shadow_contact_extracted_from_alpha", alpha_extracted)
	set_meta("shadow_contact_width", contact_width)
	set_meta("shadow_projection_source_size", visual_size)


func _default_contact_band_height(profile: Dictionary) -> int:
	match str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)):
		"trunk_wide":
			return 5
		"building_wide":
			return 6
		_:
			return DEFAULT_CONTACT_BAND_HEIGHT


func _default_contact_min_pixels(profile: Dictionary) -> int:
	match str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)):
		"trunk_wide", "building_wide":
			return 3
		_:
			return DEFAULT_CONTACT_MIN_PIXELS


func _fallback_contact_width_ratio(profile: Dictionary) -> float:
	match str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)):
		"humanoid":
			return 0.18
		"small_creature":
			return 0.55
		"trunk_wide":
			return 0.16
		"rock_compact":
			return 0.72
		"building_wide":
			return 0.84
		"thin_segment":
			return 0.28
		_:
			return 0.22


func _max_contact_width_ratio(profile: Dictionary) -> float:
	match str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)):
		"humanoid":
			return 0.36
		"small_creature":
			return 0.90
		"trunk_wide":
			return 0.30
		"rock_compact":
			return 0.96
		"building_wide":
			return 1.0
		"thin_segment":
			return 0.48
		_:
			return 0.72


func _resolve_visual_size(frame_size: Vector2, relative_transform: Transform2D) -> Vector2:
	var hint_value: Variant = get_meta("shadow_visual_size_hint", Vector2.ZERO)
	if hint_value is Vector2:
		var hint := hint_value as Vector2
		if hint.x > 0.0 and hint.y > 0.0:
			return hint
	var basis_scale := _relative_basis_scale(relative_transform)
	return Vector2(
		maxf(frame_size.x * basis_scale.x, 1.0),
		maxf(frame_size.y * basis_scale.y, 1.0)
	)


func _should_use_legacy_silhouette() -> bool:
	if bool(_config.get("local_light_shadow", false)):
		return true
	return not ShadowProfiles.is_profile_system_enabled(_get_live_global_config())


func _sync_render_proxy() -> void:
	super._sync_render_proxy()
	if _render_proxy == null or not is_instance_valid(_render_proxy):
		return
	var uses_ground_contact_projection := not _should_use_legacy_silhouette()
	_render_proxy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_render_proxy.set_meta("shadow_profile_mask", false)
	_render_proxy.set_meta("shadow_ground_contact_silhouette", uses_ground_contact_projection)
	_render_proxy.set_meta("shadow_active_frame_texture_isolated", true)
	_render_proxy.set_meta("shadow_footprint_extrusion", false)


func _is_valid_texture_size(value: Texture2D) -> bool:
	if value == null:
		return false
	var size := value.get_size()
	return size.x > 0.0 and size.y > 0.0 and size.is_finite()


func _full_frame_rect(size: Vector2) -> Rect2i:
	var safe_size := Vector2i(maxi(int(round(size.x)), 1), maxi(int(round(size.y)), 1))
	return Rect2i(Vector2i.ZERO, safe_size)


func _clear_visual() -> void:
	super._clear_visual()
