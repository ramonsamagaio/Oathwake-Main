class_name ActiveFrameProjectedShadow
extends "res://scripts/effects/DynamicProjectedSpriteShadow.gd"

var _active_render_texture: Texture2D
var _active_frame_size := Vector2.ZERO
var _active_uv_origin := Vector2.ZERO
var _active_frame_uses_atlas := false


func _apply_animated_sprite(source: AnimatedSprite2D) -> void:
	if source.sprite_frames == null or not source.sprite_frames.has_animation(source.animation):
		_clear_visual()
		return
	var frame_count := source.sprite_frames.get_frame_count(source.animation)
	if frame_count <= 0:
		_clear_visual()
		return
	var frame_index := clampi(source.frame, 0, frame_count - 1)
	var authored_frame_texture := source.sprite_frames.get_frame_texture(source.animation, frame_index)
	if not _prepare_active_frame(authored_frame_texture):
		_clear_visual()
		return

	_apply_texture_rect(
		authored_frame_texture,
		_active_frame_size,
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)
	_shift_uv_to_active_atlas_region()
	# The canonical polygon remains tied to the authored SpriteFrames entry. The
	# compositor uses the atlas texture with UVs restricted to this exact region,
	# so no CPU image extraction or temporary ImageTexture is required.
	texture = authored_frame_texture
	set_meta("shadow_source_kind", "AnimatedSprite2D")
	set_meta("shadow_source_animation", source.animation)
	set_meta("shadow_source_frame", frame_index)
	set_meta("shadow_source_frame_isolated", true)
	set_meta("shadow_active_frame_region_constrained", true)


func _apply_sprite(source: Sprite2D) -> void:
	var authored_frame_texture := _resolve_sprite_texture(source)
	if not _prepare_active_frame(authored_frame_texture):
		_clear_visual()
		return

	_apply_texture_rect(
		authored_frame_texture,
		_active_frame_size,
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)
	_shift_uv_to_active_atlas_region()
	texture = authored_frame_texture
	set_meta("shadow_source_kind", "Sprite2D")
	set_meta("shadow_source_frame", source.frame)
	set_meta("shadow_source_frame_isolated", true)
	set_meta("shadow_active_frame_region_constrained", true)


func _prepare_active_frame(authored_frame_texture: Texture2D) -> bool:
	_active_render_texture = null
	_active_frame_size = Vector2.ZERO
	_active_uv_origin = Vector2.ZERO
	_active_frame_uses_atlas = false
	if authored_frame_texture == null:
		return false

	var local_size := authored_frame_texture.get_size()
	if local_size.x <= 0.0 or local_size.y <= 0.0 or not local_size.is_finite():
		return false
	_active_frame_size = local_size

	if authored_frame_texture is AtlasTexture:
		var atlas_texture := authored_frame_texture as AtlasTexture
		if atlas_texture.atlas == null:
			return false
		var atlas_size := atlas_texture.atlas.get_size()
		if atlas_size.x <= 0.0 or atlas_size.y <= 0.0:
			return false
		var region := atlas_texture.region
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			return false
		_active_render_texture = atlas_texture.atlas
		_active_frame_size = region.size
		_active_uv_origin = region.position
		_active_frame_uses_atlas = true
	else:
		_active_render_texture = authored_frame_texture
	return true


func _get_opaque_pixel_rect(_frame_texture: Texture2D) -> Rect2i:
	# The source texture's alpha still supplies the exact visible silhouette at
	# render time. Using the authored frame rectangle avoids Texture2D.get_image(),
	# which can return a transient zero-sized image for compressed atlas textures.
	if _active_frame_size.x <= 0.0 or _active_frame_size.y <= 0.0:
		return Rect2i()
	return Rect2i(
		Vector2i.ZERO,
		Vector2i(maxi(int(round(_active_frame_size.x)), 1), maxi(int(round(_active_frame_size.y)), 1))
	)


func _shift_uv_to_active_atlas_region() -> void:
	if not _active_frame_uses_atlas or _active_uv_origin.is_zero_approx():
		return
	for index in range(uv.size()):
		uv[index] += _active_uv_origin


func _sync_render_proxy() -> void:
	super._sync_render_proxy()
	if _render_proxy == null or not is_instance_valid(_render_proxy):
		return
	if _active_render_texture == null or not is_instance_valid(_active_render_texture):
		return
	_render_proxy.texture = _active_render_texture
	_render_proxy.set_meta("shadow_active_frame_texture_isolated", true)
	_render_proxy.set_meta("shadow_active_frame_region_constrained", true)
	_render_proxy.set_meta("shadow_active_frame_uv_origin", _active_uv_origin)
	set_meta("shadow_render_texture_id", _active_render_texture.get_instance_id())


func _clear_visual() -> void:
	_active_render_texture = null
	_active_frame_size = Vector2.ZERO
	_active_uv_origin = Vector2.ZERO
	_active_frame_uses_atlas = false
	super._clear_visual()
