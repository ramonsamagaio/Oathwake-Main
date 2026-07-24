class_name WorldDepthRuntime
extends RefCounted

# Every world object receives an absolute z-index derived from a meaningful
# ground/depth line. This lets actors and map content sort across different
# scene branches instead of depending on one shared YSort parent.
const Z_BASE := 512
const DEPTH_SCALE := 2.0
const Z_MIN := -4000
const Z_MAX := 4000


static func apply_depth(target: CanvasItem, depth_y: float, layer_bias := 0) -> int:
	if target == null:
		return 0
	var resolved_z := clampi(Z_BASE + roundi(depth_y * DEPTH_SCALE) + int(layer_bias), Z_MIN, Z_MAX)
	target.z_as_relative = false
	target.z_index = resolved_z
	target.set_meta("world_depth_y", depth_y)
	target.set_meta("world_depth_z", resolved_z)
	return resolved_z


static func apply_node_depth(target: Node2D, depth_offset_y := 0.0, layer_bias := 0) -> int:
	if target == null:
		return 0
	return apply_depth(target, target.global_position.y + depth_offset_y, layer_bias)


static func apply_sprite_depth(sprite: Sprite2D, line_ratio := 0.58, depth_offset_y := 0.0, layer_bias := 0) -> int:
	if sprite == null:
		return 0
	return apply_depth(sprite, get_sprite_depth_y(sprite, line_ratio) + depth_offset_y, layer_bias)


static func get_sprite_depth_y(sprite: Sprite2D, line_ratio := 0.58) -> float:
	if sprite == null:
		return 0.0
	var visual_size := get_sprite_visual_size(sprite)
	var clamped_ratio := clampf(line_ratio, 0.0, 1.0)
	var top_y := sprite.offset.y
	if sprite.centered:
		top_y -= visual_size.y * 0.5
	var line_y := top_y + visual_size.y * clamped_ratio
	return sprite.to_global(Vector2(0.0, line_y)).y


static func get_sprite_foot_offset(sprite: Sprite2D) -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	var visual_size := get_sprite_visual_size(sprite)
	var bottom_y := sprite.offset.y + visual_size.y
	if sprite.centered:
		bottom_y = sprite.offset.y + visual_size.y * 0.5
	return sprite.position + Vector2(0.0, bottom_y)


static func get_animated_sprite_foot_offset(sprite: AnimatedSprite2D) -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	var visual_size := get_animated_sprite_unscaled_size(sprite)
	var scaled_half_height := visual_size.y * absf(sprite.scale.y) * 0.5
	return sprite.position + Vector2(0.0, scaled_half_height)


static func get_sprite_visual_size(sprite: Sprite2D) -> Vector2:
	if sprite == null:
		return Vector2(32.0, 32.0)
	if sprite.region_enabled and sprite.region_rect.size.x > 0.0 and sprite.region_rect.size.y > 0.0:
		return sprite.region_rect.size
	if sprite.texture == null:
		return Vector2(32.0, 32.0)
	var size := sprite.texture.get_size()
	if sprite.hframes > 1:
		size.x /= float(sprite.hframes)
	if sprite.vframes > 1:
		size.y /= float(sprite.vframes)
	return size


static func get_animated_sprite_unscaled_size(sprite: AnimatedSprite2D) -> Vector2:
	if sprite == null or sprite.sprite_frames == null:
		return Vector2(32.0, 48.0)
	var animation_name := sprite.animation
	if not sprite.sprite_frames.has_animation(animation_name) or sprite.sprite_frames.get_frame_count(animation_name) < 1:
		var names := sprite.sprite_frames.get_animation_names()
		if names.is_empty():
			return Vector2(32.0, 48.0)
		animation_name = names[0]
	var texture := sprite.sprite_frames.get_frame_texture(animation_name, 0)
	if texture == null:
		return Vector2(32.0, 48.0)
	return texture.get_size()


static func get_animated_sprite_visual_size(sprite: AnimatedSprite2D) -> Vector2:
	return get_animated_sprite_unscaled_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
