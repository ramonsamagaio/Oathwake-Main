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


static func get_sprite_local_foot_point(sprite: Sprite2D) -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	var authored_anchor: Variant = _ground_anchor_from_object(sprite)
	if authored_anchor != null:
		return authored_anchor as Vector2
	# Sprite2D.get_rect() already includes centered and drawing-offset rules.
	# Keeping this point in the sprite's own local space lets callers transform
	# it through arbitrary scale, rotation, skew and parent hierarchies.
	var local_rect := sprite.get_rect()
	return Vector2(local_rect.get_center().x, local_rect.end.y)


static func get_sprite_foot_offset(sprite: Sprite2D) -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	return sprite.transform * get_sprite_local_foot_point(sprite)


static func get_animated_sprite_local_foot_point(sprite: AnimatedSprite2D) -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	var frame_size := get_animated_sprite_unscaled_size(sprite)
	var top_left := sprite.offset
	if sprite.centered:
		top_left -= frame_size * 0.5

	# Animation-set anchors are authored in frame pixel coordinates, measured from
	# the frame's top-left. They are more accurate than the transparent cell edge
	# and remain stable across every frame of a walk, attack or idle cycle.
	var anchor_in_frame := Vector2(frame_size.x * 0.5, frame_size.y)
	var sprite_anchor: Variant = _ground_anchor_from_object(sprite)
	if sprite_anchor != null:
		anchor_in_frame = sprite_anchor as Vector2
	elif sprite.sprite_frames != null:
		var frames_anchor: Variant = _ground_anchor_from_object(sprite.sprite_frames)
		if frames_anchor != null:
			anchor_in_frame = frames_anchor as Vector2

	anchor_in_frame.x = clampf(anchor_in_frame.x, 0.0, frame_size.x)
	anchor_in_frame.y = clampf(anchor_in_frame.y, 0.0, frame_size.y)
	if sprite.flip_h:
		anchor_in_frame.x = frame_size.x - anchor_in_frame.x
	if sprite.flip_v:
		anchor_in_frame.y = frame_size.y - anchor_in_frame.y
	return top_left + anchor_in_frame


static func get_animated_sprite_foot_offset(sprite: AnimatedSprite2D) -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	return sprite.transform * get_animated_sprite_local_foot_point(sprite)


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
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	var frame_index := clampi(sprite.frame, 0, maxi(frame_count - 1, 0))
	var texture := sprite.sprite_frames.get_frame_texture(animation_name, frame_index)
	if texture == null:
		return Vector2(32.0, 48.0)
	return texture.get_size()


static func get_animated_sprite_visual_size(sprite: AnimatedSprite2D) -> Vector2:
	return get_animated_sprite_unscaled_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))


static func _ground_anchor_from_object(value: Object) -> Variant:
	if value == null:
		return null
	for metadata_name in ["shadow_ground_anchor", "ground_anchor", "animation_anchor"]:
		if not value.has_meta(metadata_name):
			continue
		var raw: Variant = value.get_meta(metadata_name)
		if raw is Vector2:
			var vector_value := raw as Vector2
			if vector_value.is_finite():
				return vector_value
		elif raw is Dictionary:
			var dictionary_value := raw as Dictionary
			var dictionary_vector := Vector2(
				float(dictionary_value.get("x", 0.0)),
				float(dictionary_value.get("y", 0.0))
			)
			if dictionary_vector.is_finite():
				return dictionary_vector
	return null
