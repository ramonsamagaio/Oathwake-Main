class_name ProfiledProjectedShadow
extends "res://scripts/effects/DynamicProjectedSpriteShadow.gd"

const ShadowProfiles := preload("res://scripts/effects/ShadowProfileLibrary.gd")
const PROJECTION_MODE := "universal_shadow_profile"


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
	if frame_texture == null or frame_texture.get_size().x <= 0.0 or frame_texture.get_size().y <= 0.0:
		_clear_visual()
		return
	_apply_profile_projection(
		frame_texture.get_size(),
		source.centered,
		source.offset,
		_source_to_target_transform(source)
	)
	set_meta("shadow_source_kind", "AnimatedSprite2D")
	set_meta("shadow_source_animation", source.animation)
	set_meta("shadow_source_frame", frame_index)
	set_meta("shadow_source_frame_isolated", false)


func _apply_sprite(source: Sprite2D) -> void:
	if _should_use_legacy_silhouette():
		super._apply_sprite(source)
		return
	var frame_texture := _resolve_sprite_texture(source)
	if frame_texture == null or frame_texture.get_size().x <= 0.0 or frame_texture.get_size().y <= 0.0:
		_clear_visual()
		return
	_apply_profile_projection(
		frame_texture.get_size(),
		source.centered,
		source.offset,
		_source_to_target_transform(source)
	)
	set_meta("shadow_source_kind", "Sprite2D")
	set_meta("shadow_source_frame", source.frame)
	set_meta("shadow_source_frame_isolated", false)


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
	_apply_profile_projection(frame_size, centered, sprite_offset, relative_transform)


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
	_apply_profile_projection(
		bounds.size,
		true,
		bounds.get_center(),
		_source_to_target_transform(source)
	)
	set_meta("shadow_source_kind", "Polygon2D")


func _apply_profile_projection(
	frame_size: Vector2,
	centered: bool,
	sprite_offset: Vector2,
	relative_transform: Transform2D
) -> void:
	var global_shadow_config := _get_live_global_config()
	var visual_size := _resolve_visual_size(frame_size, relative_transform)
	var profile := ShadowProfiles.resolve_profile(_target, _source, _config, global_shadow_config, visual_size)
	var mask_texture := ShadowProfiles.get_mask_texture(profile)
	if mask_texture == null:
		_clear_visual()
		return

	var contact := _foot_offset
	if not contact.is_finite():
		contact = Vector2.ZERO
	if contact.is_zero_approx() and _target != _source:
		var base_top_left := sprite_offset
		if centered:
			base_top_left -= frame_size * 0.5
		contact = relative_transform * Vector2(base_top_left.x + frame_size.x * 0.5, base_top_left.y + frame_size.y)

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
	var root_overlap := _projection_root_overlap * maxf(float(profile.get("root_overlap_multiplier", 1.0)), 0.0)

	var direction := _projection_direction.normalized()
	if direction.length_squared() <= 0.0001:
		direction = Vector2.UP
	var side_axis := direction.rotated(PI * 0.5).normalized()
	var root_center := contact - direction * root_overlap
	var tip_center := root_center + direction * length
	var half_width := width * 0.5

	polygon = PackedVector2Array([
		tip_center - side_axis * half_width,
		tip_center + side_axis * half_width,
		root_center + side_axis * half_width,
		root_center - side_axis * half_width,
	])
	uv = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	texture = mask_texture
	_visible_frame_size = visual_size
	_publish_projection_metadata(contact, root_center, side_axis, visual_size)
	set_meta("shadow_projection_mode", PROJECTION_MODE)
	set_meta("shadow_projection_profiled", true)
	set_meta("shadow_profile_id", str(profile.get("id", ShadowProfiles.DEFAULT_PROFILE_ID)))
	set_meta("shadow_profile_display_name", str(profile.get("display_name", "Shadow Profile")))
	set_meta("shadow_profile_width", width)
	set_meta("shadow_profile_length", length)
	set_meta("shadow_profile_root_overlap", root_overlap)
	set_meta("shadow_profile_ignores_frame_silhouette", true)
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
	_render_proxy.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if _should_use_legacy_silhouette()
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
