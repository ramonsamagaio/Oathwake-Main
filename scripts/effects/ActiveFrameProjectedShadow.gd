class_name ActiveFrameProjectedShadow
extends "res://scripts/effects/DynamicProjectedSpriteShadow.gd"

var _active_render_texture: Texture2D


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
	if authored_frame_texture == null:
		_clear_visual()
		return
	var isolated_texture := _isolate_active_frame_texture(authored_frame_texture)
	if isolated_texture == null:
		_clear_visual()
		return

	_active_render_texture = isolated_texture
	_apply_texture_rect(
		isolated_texture,
		isolated_texture.get_size(),
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)
	# Keep the canonical node associated with the exact authored SpriteFrames entry.
	# The invisible canonical polygon owns metadata; the compositor proxy below uses
	# the physically isolated frame so its shader can never sample the entire atlas.
	texture = authored_frame_texture
	set_meta("shadow_source_kind", "AnimatedSprite2D")
	set_meta("shadow_source_animation", source.animation)
	set_meta("shadow_source_frame", frame_index)
	set_meta("shadow_source_frame_isolated", isolated_texture != authored_frame_texture)


func _apply_sprite(source: Sprite2D) -> void:
	var authored_frame_texture := _resolve_sprite_texture(source)
	if authored_frame_texture == null:
		_clear_visual()
		return
	var isolated_texture := _isolate_active_frame_texture(authored_frame_texture)
	if isolated_texture == null:
		_clear_visual()
		return

	_active_render_texture = isolated_texture
	_apply_texture_rect(
		isolated_texture,
		isolated_texture.get_size(),
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)
	texture = authored_frame_texture
	set_meta("shadow_source_kind", "Sprite2D")
	set_meta("shadow_source_frame", source.frame)
	set_meta("shadow_source_frame_isolated", isolated_texture != authored_frame_texture)


func _sync_render_proxy() -> void:
	super._sync_render_proxy()
	if _render_proxy == null or not is_instance_valid(_render_proxy):
		return
	if _active_render_texture == null or not is_instance_valid(_active_render_texture):
		return
	_render_proxy.texture = _active_render_texture
	_render_proxy.set_meta("shadow_active_frame_texture_isolated", true)
	set_meta("shadow_render_texture_id", _active_render_texture.get_instance_id())


func _clear_visual() -> void:
	_active_render_texture = null
	super._clear_visual()
