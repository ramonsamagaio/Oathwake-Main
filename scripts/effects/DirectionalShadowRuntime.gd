class_name DirectionalShadowRuntime
extends RefCounted

const DEFAULT_DIRECTION := Vector2(-1.0, 0.55)
const DEFAULT_COLOR := Color(0.015, 0.01, 0.022, 1.0)


static func apply_to_target(
	target: Node2D,
	config: Dictionary = {},
	visual_size := Vector2(32.0, 48.0),
	local_foot_offset := Vector2.ZERO
) -> Polygon2D:
	if target == null:
		return null
	var shadow := target.get_node_or_null("GroundShadow") as Polygon2D
	var enabled := bool(config.get("enabled", true))
	if shadow == null and enabled:
		shadow = Polygon2D.new()
		shadow.name = "GroundShadow"
		target.add_child(shadow)
	if shadow == null:
		return null

	shadow.visible = enabled
	if not enabled:
		return shadow

	var defaults := _get_global_defaults(target)
	var direction := _vector_from_value(config.get("direction", defaults.get("direction", {})), DEFAULT_DIRECTION)
	if direction.length_squared() < 0.0001:
		direction = DEFAULT_DIRECTION
	direction = direction.normalized()

	var length_scale := maxf(float(defaults.get("length_scale", 1.0)), 0.01)
	var width_scale := maxf(float(defaults.get("width_scale", 1.0)), 0.01)
	var default_length := clampf(visual_size.y * 0.48 * length_scale, 14.0, 72.0)
	var default_width := clampf(visual_size.x * 0.42 * width_scale, 9.0, 54.0)
	var legacy_scale := _vector_from_value(config.get("scale", {}), Vector2.ONE)
	var length := maxf(float(config.get("length", default_length * maxf(legacy_scale.x, 0.25))), 1.0)
	var width := maxf(float(config.get("width", default_width * maxf(legacy_scale.x, 0.25))), 1.0)
	var tail_width_ratio := clampf(float(config.get("tail_width_ratio", defaults.get("tail_width_ratio", 0.18))), 0.0, 1.0)
	var opacity := clampf(float(config.get("opacity", defaults.get("opacity", 0.34))), 0.0, 1.0)
	var fade_power := maxf(float(config.get("fade_power", defaults.get("fade_power", 1.6))), 0.1)
	var mid_alpha := opacity * pow(0.48, fade_power)
	var color := _color_from_value(config.get("color", defaults.get("color", "#040306FF")), DEFAULT_COLOR)
	var offset := local_foot_offset + _vector_from_value(config.get("offset", {}), Vector2.ZERO)

	var perpendicular := Vector2(-direction.y, direction.x)
	var near_center := Vector2.ZERO
	var mid_center := direction * length * 0.48
	var far_center := direction * length
	var near_half := width * 0.5
	var mid_half := width * 0.34
	var far_half := width * tail_width_ratio * 0.5
	shadow.polygon = PackedVector2Array([
		near_center - perpendicular * near_half,
		near_center + perpendicular * near_half,
		mid_center + perpendicular * mid_half,
		far_center + perpendicular * far_half,
		far_center - perpendicular * far_half,
		mid_center - perpendicular * mid_half,
	])
	shadow.vertex_colors = PackedColorArray([
		Color(color.r, color.g, color.b, opacity),
		Color(color.r, color.g, color.b, opacity),
		Color(color.r, color.g, color.b, mid_alpha),
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, mid_alpha),
	])
	shadow.position = offset
	shadow.scale = Vector2.ONE
	shadow.rotation = 0.0
	shadow.color = Color.WHITE
	shadow.modulate = Color.WHITE
	shadow.show_behind_parent = true
	shadow.z_as_relative = true
	shadow.z_index = int(config.get("z_index", -1))
	shadow.set_meta("directional_shadow", true)
	shadow.set_meta("shadow_direction", direction)
	shadow.set_meta("shadow_length", length)
	shadow.set_meta("shadow_fade_power", fade_power)
	if not shadow.is_in_group("persistent_content_visual"):
		shadow.add_to_group("persistent_content_visual")
	return shadow


static func apply_to_sprite(sprite: Sprite2D, config: Dictionary = {}) -> Polygon2D:
	if sprite == null:
		return null
	var visual_size := WorldDepthRuntime.get_sprite_visual_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
	var foot_offset := WorldDepthRuntime.get_sprite_foot_offset(sprite)
	return apply_to_target(sprite, config, visual_size, foot_offset - sprite.position)


static func estimate_target_visual_size(target: Node2D) -> Vector2:
	var visual := _find_largest_visual(target)
	if visual is Sprite2D:
		var sprite := visual as Sprite2D
		return WorldDepthRuntime.get_sprite_visual_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
	if visual is AnimatedSprite2D:
		return WorldDepthRuntime.get_animated_sprite_visual_size(visual as AnimatedSprite2D)
	if visual is Polygon2D:
		return _polygon_bounds(visual as Polygon2D).size
	return Vector2(32.0, 48.0)


static func estimate_target_foot_offset(target: Node2D) -> Vector2:
	var visual := _find_largest_visual(target)
	if visual is Sprite2D:
		return (visual as Sprite2D).position + WorldDepthRuntime.get_sprite_foot_offset(visual as Sprite2D) - (visual as Sprite2D).position
	if visual is AnimatedSprite2D:
		return WorldDepthRuntime.get_animated_sprite_foot_offset(visual as AnimatedSprite2D)
	if visual is Polygon2D:
		var polygon := visual as Polygon2D
		var bounds := _polygon_bounds(polygon)
		return polygon.position + Vector2(bounds.get_center().x, bounds.end.y)
	return Vector2(0.0, 16.0)


static func _find_largest_visual(target: Node) -> CanvasItem:
	if target == null:
		return null
	var best: CanvasItem = null
	var best_area := 0.0
	var queue: Array[Node] = [target]
	while not queue.is_empty():
		var node: Node = queue.pop_front() as Node
		for child in node.get_children():
			if child is CanvasItem and (child as CanvasItem).is_in_group("persistent_content_visual"):
				continue
			if child is Node:
				queue.append(child)
			var size := Vector2.ZERO
			if child is Sprite2D:
				var sprite := child as Sprite2D
				if sprite.texture != null and sprite.visible:
					size = WorldDepthRuntime.get_sprite_visual_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
			elif child is AnimatedSprite2D:
				var animated := child as AnimatedSprite2D
				if animated.visible:
					size = WorldDepthRuntime.get_animated_sprite_visual_size(animated)
			elif child is Polygon2D:
				var polygon := child as Polygon2D
				if polygon.visible:
					size = _polygon_bounds(polygon).size
			var area := size.x * size.y
			if area > best_area:
				best_area = area
				best = child as CanvasItem
	return best


static func _polygon_bounds(polygon: Polygon2D) -> Rect2:
	if polygon == null or polygon.polygon.is_empty():
		return Rect2(Vector2(-16.0, -24.0), Vector2(32.0, 48.0))
	var min_point := polygon.polygon[0]
	var max_point := polygon.polygon[0]
	for point in polygon.polygon:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)


static func _get_global_defaults(target: Node) -> Dictionary:
	if target == null:
		return {}
	var content_db := target.get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return {}
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var value: Variant = profile.get("directional_shadow", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


static func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges()
	return Color.from_string(text, fallback) if not text.is_empty() else fallback
