class_name ProfiledProjectedShadow
extends "res://scripts/effects/DynamicProjectedSpriteShadow.gd"

const ShadowProfiles := preload("res://scripts/effects/ShadowProfileLibrary.gd")
const ShadowFootprints := preload("res://scripts/effects/ShadowFootprintResolver.gd")
const PROJECTION_MODE := "footprint_extrusion"

var _profile_mask_texture: Texture2D


func _apply_animated_sprite(source: AnimatedSprite2D) -> void:
	if _should_use_legacy_silhouette():
		_profile_mask_texture = null
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
	var frame_size := frame_texture.get_size()
	_apply_profile_projection(
		frame_size,
		source.centered,
		source.offset,
		_source_to_target_transform(source)
	)
	# The canonical node is transparent and keeps the authored frame only for
	# diagnostics. The compositor proxy renders the footprint extrusion instead.
	texture = frame_texture
	set_meta("shadow_opaque_rect", _full_frame_rect(frame_size))
	set_meta("shadow_source_kind", "AnimatedSprite2D")
	set_meta("shadow_source_animation", source.animation)
	set_meta("shadow_source_frame", frame_index)
	set_meta("shadow_source_frame_isolated", frame_texture is not AtlasTexture)


func _apply_sprite(source: Sprite2D) -> void:
	if _should_use_legacy_silhouette():
		_profile_mask_texture = null
		super._apply_sprite(source)
		return
	var frame_texture := _resolve_sprite_texture(source)
	if not _is_valid_texture_size(frame_texture):
		_clear_visual()
		return
	var frame_size := frame_texture.get_size()
	_apply_profile_projection(
		frame_size,
		source.centered,
		source.offset,
		_source_to_target_transform(source)
	)
	texture = frame_texture
	set_meta("shadow_opaque_rect", _full_frame_rect(frame_size))
	set_meta("shadow_source_kind", "Sprite2D")
	set_meta("shadow_source_frame", source.frame)
	set_meta("shadow_source_frame_isolated", frame_texture is not AtlasTexture)


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
		_profile_mask_texture = null
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
	if not _is_valid_texture_size(frame_texture) or frame_size.x <= 0.0 or frame_size.y <= 0.0:
		_clear_visual()
		return
	_apply_profile_projection(frame_size, centered, sprite_offset, relative_transform)
	texture = frame_texture
	set_meta("shadow_opaque_rect", _full_frame_rect(frame_size))


func _apply_polygon(source: Polygon2D) -> void:
	if _should_use_legacy_silhouette():
		_profile_mask_texture = null
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
	_apply_profile_projection(
		bounds.size,
		true,
		bounds.get_center(),
		_source_to_target_transform(source)
	)
	texture = _profile_mask_texture
	set_meta("shadow_opaque_rect", _full_frame_rect(bounds.size))
	set_meta("shadow_source_kind", "Polygon2D")


func _apply_profile_projection(
	frame_size: Vector2,
	_centered: bool,
	_sprite_offset: Vector2,
	relative_transform: Transform2D
) -> void:
	var global_shadow_config := _get_live_global_config()
	var visual_size := _resolve_visual_size(frame_size, relative_transform)
	var profile := ShadowProfiles.resolve_profile(_target, _source, _config, global_shadow_config, visual_size)

	var contact := _foot_offset
	if not contact.is_finite():
		contact = Vector2.ZERO

	# Smart-lighting style daylight shadows begin from an authored ground collider
	# or physics footprint. The whole footprint is extruded away from the sun, and
	# the caster sprite is rendered above it to hide the seam at the feet/trunk.
	var footprint_data := ShadowFootprints.resolve(_target, _source, contact, visual_size, profile, _config)
	var footprint: PackedVector2Array = footprint_data.get("points", PackedVector2Array())
	if footprint.size() < 3:
		_clear_visual()
		return

	var mask_texture := _get_solid_mask_texture()
	if not _is_valid_texture_size(mask_texture):
		_clear_visual()
		return
	_profile_mask_texture = mask_texture

	var profile_length_scale := maxf(float(_config.get("shadow_profile_length_scale", 1.0)), 0.05)
	var length := maxf(
		visual_size.y * maxf(float(profile.get("length_ratio", 0.92)), 0.05),
		float(profile.get("minimum_length", 18.0))
	) * _projection_stretch * profile_length_scale

	var world_direction := _projection_direction.normalized()
	if world_direction.length_squared() <= 0.0001:
		world_direction = Vector2.UP
	var extrusion := _world_vector_to_target_local(world_direction * length)
	if extrusion.length_squared() <= 0.0001:
		extrusion = world_direction * length

	var root_width_ratio := maxf(float(profile.get("root_width_ratio", 0.8)), 0.05)
	var tip_width_ratio := maxf(float(profile.get("tip_width_ratio", root_width_ratio)), 0.02)
	var default_tip_scale := clampf(tip_width_ratio / root_width_ratio, 0.30, 1.25)
	var tip_scale := clampf(float(_config.get("shadow_footprint_tip_scale", default_tip_scale)), 0.15, 2.0)
	var footprint_center := _average_point(footprint)

	var combined := PackedVector2Array()
	for point in footprint:
		combined.append(point)
	for point in footprint:
		combined.append(footprint_center + (point - footprint_center) * tip_scale + extrusion)
	var projected_hull := _convex_hull(combined)
	if projected_hull.size() < 3:
		_clear_visual()
		return

	polygon = projected_hull
	var solid_uv := PackedVector2Array()
	for _point in projected_hull:
		solid_uv.append(Vector2(0.5, 0.5))
	uv = solid_uv
	texture = mask_texture
	_visible_frame_size = visual_size

	var support: Vector2 = footprint_data.get("support", contact)
	var root_axis: Vector2 = footprint_data.get("root_axis", Vector2.RIGHT)
	var ground_axis: Vector2 = footprint_data.get("ground_axis", Vector2.DOWN)
	_publish_projection_metadata(contact, contact, world_direction.rotated(PI * 0.5), visual_size)
	set_meta("shadow_projection_mode", PROJECTION_MODE)
	set_meta("shadow_projection_profiled", true)
	set_meta("shadow_profile_id", str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)))
	set_meta("shadow_profile_display_name", str(profile.get("display_name", "Shadow Profile")))
	set_meta("shadow_profile_length", length)
	set_meta("shadow_profile_root_overlap", 0.0)
	set_meta("shadow_profile_contact_pinned", support.distance_to(contact) <= 0.01)
	set_meta("shadow_profile_root_matches_contact", support.distance_to(contact) <= 0.01)
	set_meta("shadow_profile_ignores_frame_silhouette", true)
	set_meta("shadow_profile_mask_size", mask_texture.get_size())
	set_meta("shadow_footprint_points", footprint)
	set_meta("shadow_footprint_support", support)
	set_meta("shadow_footprint_root_axis", root_axis)
	set_meta("shadow_footprint_ground_axis", ground_axis)
	set_meta("shadow_footprint_source_kind", str(footprint_data.get("source_kind", "unknown")))
	set_meta("shadow_footprint_source_name", str(footprint_data.get("source_name", "")))
	set_meta("shadow_footprint_authored", bool(footprint_data.get("authored", false)))
	set_meta("shadow_footprint_extrusion", extrusion)
	set_meta("shadow_footprint_tip_scale", tip_scale)
	set_meta("shadow_footprint_masked_by_caster", true)
	set_meta("shadow_southern_limit_y", contact.y)
	set_meta("shadow_southern_limit_shift", Vector2.ZERO)


func _world_vector_to_target_local(world_vector: Vector2) -> Vector2:
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		return world_vector
	var global_origin := _target.global_position
	return _target.to_local(global_origin + world_vector) - _target.to_local(global_origin)


func _average_point(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in points:
		total += point
	return total / float(points.size())


func _convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0].distance_to(hull[hull.size() - 1]) <= 0.001:
		hull.resize(hull.size() - 1)
	return hull


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
	var uses_legacy := _should_use_legacy_silhouette()
	if not uses_legacy and _profile_mask_texture != null:
		_render_proxy.texture = _profile_mask_texture
		_render_proxy.set_meta("shadow_profile_mask", true)
		_render_proxy.set_meta("shadow_active_frame_texture_isolated", false)
		_render_proxy.set_meta("shadow_footprint_extrusion", true)
	_render_proxy.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if uses_legacy
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)


func _is_valid_texture_size(value: Texture2D) -> bool:
	if value == null:
		return false
	var size := value.get_size()
	return size.x > 0.0 and size.y > 0.0 and size.is_finite()


func _full_frame_rect(size: Vector2) -> Rect2i:
	var safe_size := Vector2i(maxi(int(round(size.x)), 1), maxi(int(round(size.y)), 1))
	return Rect2i(Vector2i.ZERO, safe_size)


func _clear_visual() -> void:
	_profile_mask_texture = null
	super._clear_visual()
