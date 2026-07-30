class_name ProfiledProjectedShadow
extends "res://scripts/effects/DynamicProjectedSpriteShadow.gd"

const ShadowProfiles := preload("res://scripts/effects/ShadowProfileLibrary.gd")
const PROJECTION_MODE := "universal_shadow_profile"

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
	# diagnostics. Solar profiles intentionally do not read or crop its pixels.
	# Avoiding an AtlasTexture image read also prevents transient zero-size image
	# errors while imported SpriteFrames are being rebuilt during content reload.
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
	# Polygon fallbacks have no authored frame texture, so the canonical node may
	# safely keep the profile mask as its non-null source identity.
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
	var mask_texture := ShadowProfiles.get_mask_texture(profile)
	if not _is_valid_texture_size(mask_texture):
		_clear_visual()
		return
	_profile_mask_texture = mask_texture

	# The runtime resolves this point from the visual node's local bottom-center,
	# then converts it through the complete transform chain into target-local space.
	# Vector2.ZERO is a valid contact when the sprite was authored around its feet.
	var contact := _foot_offset
	if not contact.is_finite():
		contact = Vector2.ZERO

	var profile_width_scale := maxf(float(_config.get("shadow_profile_width_scale", 1.0)), 0.05)
	var profile_length_scale := maxf(float(_config.get("shadow_profile_length_scale", 1.0)), 0.05)
	var width := maxf(
		visual_size.x * maxf(float(profile.get("width_ratio", 0.52)), 0.05),
		float(profile.get("minimum_width", 12.0))
	) * _projection_width_scale * profile_width_scale
	var length := maxf(
		visual_size.y * maxf(float(profile.get("length_ratio", 0.92)), 0.05),
		float(profile.get("minimum_length", 18.0))
	) * _projection_stretch * profile_length_scale
	var requested_root_overlap := _projection_root_overlap * maxf(float(profile.get("root_overlap_multiplier", 1.0)), 0.0)

	var direction := _projection_direction.normalized()
	if direction.length_squared() <= 0.0001:
		direction = Vector2.UP
	var tip_axis := direction.rotated(PI * 0.5).normalized()

	# The source X basis is the sprite's real ground/base axis expressed in the
	# caster's coordinate space. Unlike the far edge, this axis must never rotate
	# with the sun. This is what turns the card into an anchored skewed projection.
	var root_axis := relative_transform.x.normalized()
	if not root_axis.is_finite() or root_axis.length_squared() <= 0.0001:
		root_axis = Vector2.RIGHT

	# Keep the visible contact neck narrow enough to remain underneath the feet,
	# trunk or prop base. The profile can widen immediately after leaving the root.
	var authored_root_ratio := clampf(float(profile.get("root_width_ratio", 0.80)), 0.05, 1.0)
	var contact_span_ratio := clampf(
		float(profile.get("contact_span_ratio", minf(authored_root_ratio * 0.28, 0.32))),
		0.04,
		0.65
	)
	var contact_half_width := maxf(width * contact_span_ratio * 0.5, 1.0)

	# The center and orientation of the contact edge are immutable. Only the far
	# edge follows the solar direction, so the shadow stretches/shears from the
	# exact base instead of rotating as one rigid plate around the character.
	var root_center := contact
	var tip_center := root_center + direction * length
	var tip_half_width := width * 0.5

	polygon = PackedVector2Array([
		tip_center - tip_axis * tip_half_width,
		tip_center + tip_axis * tip_half_width,
		root_center + root_axis * contact_half_width,
		root_center - root_axis * contact_half_width,
	])
	# Polygon2D UVs are texture-pixel coordinates, not normalized 0..1 values.
	var mask_size := mask_texture.get_size()
	uv = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(mask_size.x, 0.0),
		Vector2(mask_size.x, mask_size.y),
		Vector2(0.0, mask_size.y),
	])
	texture = mask_texture
	_visible_frame_size = visual_size
	_publish_projection_metadata(contact, root_center, tip_axis, visual_size)
	set_meta("shadow_projection_mode", PROJECTION_MODE)
	set_meta("shadow_projection_profiled", true)
	set_meta("shadow_profile_id", str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)))
	set_meta("shadow_profile_display_name", str(profile.get("display_name", "Shadow Profile")))
	set_meta("shadow_profile_width", width)
	set_meta("shadow_profile_length", length)
	set_meta("shadow_profile_requested_root_overlap", requested_root_overlap)
	set_meta("shadow_profile_root_overlap", 0.0)
	set_meta("shadow_profile_contact_pinned", true)
	set_meta("shadow_profile_root_matches_contact", root_center.distance_to(contact) <= 0.001)
	set_meta("shadow_profile_root_axis", root_axis)
	set_meta("shadow_profile_tip_axis", tip_axis)
	set_meta("shadow_profile_contact_span_ratio", contact_span_ratio)
	set_meta("shadow_profile_contact_half_width", contact_half_width)
	set_meta("shadow_profile_skewed_from_fixed_base", true)
	set_meta("shadow_profile_ignores_frame_silhouette", true)
	set_meta("shadow_profile_uv_pixel_space", true)
	set_meta("shadow_profile_mask_size", mask_size)
	set_meta("shadow_southern_limit_y", contact.y)
	set_meta("shadow_southern_limit_shift", Vector2.ZERO)


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
		_render_proxy.set_meta("shadow_profile_uv_pixel_space", true)
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
