class_name DirectionalShadowRuntime
extends RefCounted

const ProjectedSpriteShadowScript := preload("res://scripts/effects/PinnedActiveFrameProjectedShadow.gd")
const DEFAULT_DIRECTION_DEGREES := -45.0
const DEFAULT_COLOR := Color(0.02, 0.024, 0.035, 1.0)
const EXCLUDED_SOURCE_NAME_TOKENS := [
	"shadow",
	"glow",
	"aura",
	"light",
	"outline",
	"mask",
	"fog",
	"particle",
	"beam",
	"shaft",
	"occlusion",
	"preview",
	"highlight",
	"flash",
	"spark",
	"smoke",
	"trail",
]
const EXCLUDED_SOURCE_GROUPS := [
	"persistent_content_visual",
	"world_light_emitter",
	"projected_shadow_caster",
	"projected_shadow_group",
]
const PREFERRED_SOURCE_NAMES := [
	"animatedsprite2d",
	"monstersprite",
	"contentsprite",
	"bodyvisual",
	"playervisual",
	"charactersprite",
	"sprite2d",
]


static func apply_to_target(
	target: Node2D,
	config: Dictionary = {},
	visual_size_hint := Vector2(32.0, 48.0),
	local_foot_offset := Vector2.ZERO,
	source_override: CanvasItem = null
) -> Polygon2D:
	if target == null or not is_instance_valid(target):
		return null
	var defaults := _get_global_defaults(target)
	var enabled := bool(defaults.get("enabled", true)) and bool(config.get("enabled", true))
	var shadow := target.get_node_or_null("GroundShadow") as Polygon2D
	if shadow != null and shadow.get_script() != ProjectedSpriteShadowScript:
		shadow.name = "LegacyGroundShadow"
		target.remove_child(shadow)
		shadow.queue_free()
		shadow = null
	if shadow == null and enabled:
		shadow = ProjectedSpriteShadowScript.new() as Polygon2D
		shadow.name = "GroundShadow"
		target.add_child(shadow)
	if shadow == null:
		return null

	shadow.visible = enabled
	shadow.set_meta("shadow_visual_size_hint", visual_size_hint)
	if not enabled:
		return shadow

	var source := source_override
	if source == null or not is_instance_valid(source) or not _is_valid_source(source, target):
		source = find_active_visual_source(target)
	if source == null:
		shadow.visible = false
		shadow.set_meta("shadow_source_rejected", true)
		return shadow

	var pinned_contact := local_foot_offset
	if not pinned_contact.is_finite():
		pinned_contact = _visual_contact_in_target(target, source)

	var resolved := config.duplicate(true)
	for projection_key in ["opacity", "stretch", "direction_degrees", "direction", "color"]:
		if defaults.has(projection_key):
			resolved[projection_key] = defaults[projection_key]
	if not resolved.has("direction_degrees"):
		resolved["direction_degrees"] = _direction_degrees_from_legacy(resolved.get("direction", {}))
	if not resolved.has("stretch"):
		resolved["stretch"] = 1.15
	if not resolved.has("opacity"):
		resolved["opacity"] = 0.30
	if not resolved.has("color"):
		resolved["color"] = "#050609FF"
	if not resolved.has("z_index"):
		resolved["z_index"] = -1
	resolved["enabled"] = enabled
	resolved["contact_pinned"] = true

	if shadow.has_method("configure"):
		shadow.call("configure", target, source, resolved, pinned_contact)
	shadow.set_meta("directional_shadow", true)
	shadow.set_meta("shadow_bound_source_id", source.get_instance_id())
	shadow.set_meta("shadow_pinned_contact", pinned_contact)
	shadow.set_meta("shadow_selected_source_name", str(source.name))
	shadow.set_meta("shadow_selected_source_path", str(target.get_path_to(source)))
	shadow.set_meta("shadow_source_rejected", false)
	return shadow


static func apply_to_sprite(sprite: Sprite2D, config: Dictionary = {}) -> Polygon2D:
	if sprite == null:
		return null
	var foot_offset := _visual_contact_in_target(sprite, sprite)
	return apply_to_target(sprite, config, WorldDepthRuntime.get_sprite_visual_size(sprite), foot_offset, sprite)


static func find_active_visual_source(target: Node) -> CanvasItem:
	return _find_largest_visual(target)


static func estimate_target_visual_size(target: Node2D) -> Vector2:
	var visual := find_active_visual_source(target)
	if visual is Sprite2D:
		var sprite := visual as Sprite2D
		return WorldDepthRuntime.get_sprite_visual_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
	if visual is AnimatedSprite2D:
		return WorldDepthRuntime.get_animated_sprite_visual_size(visual as AnimatedSprite2D)
	if visual is Polygon2D:
		return _polygon_bounds(visual as Polygon2D).size
	return Vector2(32.0, 48.0)


static func estimate_target_foot_offset(target: Node2D) -> Vector2:
	var visual := find_active_visual_source(target)
	if visual == null:
		return Vector2.ZERO
	return _visual_contact_in_target(target, visual)


static func _visual_contact_in_target(target: Node2D, visual: CanvasItem) -> Vector2:
	if target == null or visual == null or not is_instance_valid(visual):
		return Vector2.ZERO
	var visual_node := visual as Node2D
	if visual_node == null:
		return Vector2.ZERO
	var local_contact := _visual_local_contact(visual)
	if not local_contact.is_finite():
		return Vector2.ZERO
	return target.to_local(visual_node.to_global(local_contact))


static func _visual_local_contact(visual: CanvasItem) -> Vector2:
	if visual is Sprite2D:
		return WorldDepthRuntime.get_sprite_local_foot_point(visual as Sprite2D)
	if visual is AnimatedSprite2D:
		return WorldDepthRuntime.get_animated_sprite_local_foot_point(visual as AnimatedSprite2D)
	if visual is Polygon2D:
		var bounds := _polygon_bounds(visual as Polygon2D)
		return Vector2(bounds.get_center().x, bounds.end.y)
	return Vector2.ZERO


static func _find_largest_visual(target: Node) -> CanvasItem:
	if target == null:
		return null
	var best: CanvasItem = null
	var best_priority := -1
	var best_area := 0.0
	var queue: Array[Node] = [target]
	while not queue.is_empty():
		var node: Node = queue.pop_front() as Node
		if node != target:
			var candidate := node as CanvasItem
			if candidate != null and _is_valid_source(candidate, target):
				var priority := _source_priority(candidate)
				var size := _visual_size(candidate)
				var area := size.x * size.y
				if priority > best_priority or (priority == best_priority and area > best_area):
					best_priority = priority
					best_area = area
					best = candidate
		for child in node.get_children():
			if child is Node:
				queue.append(child)
	if best == null and target is CanvasItem and _is_valid_source(target as CanvasItem, target):
		best = target as CanvasItem
	return best


static func _source_priority(candidate: CanvasItem) -> int:
	if bool(candidate.get_meta("directional_shadow_source", false)):
		return 1000
	var priority := 0
	if candidate is AnimatedSprite2D:
		priority = 300
	elif candidate is Sprite2D:
		priority = 200
	elif candidate is Polygon2D:
		priority = 100
	var normalized_name := _normalized_node_name(str(candidate.name))
	if PREFERRED_SOURCE_NAMES.has(normalized_name):
		priority += 80
	elif normalized_name.contains("character") or normalized_name.contains("body") or normalized_name.contains("content"):
		priority += 40
	return priority


static func _is_valid_source(candidate: CanvasItem, target: Node = null) -> bool:
	if candidate == null or not is_instance_valid(candidate) or not candidate.visible:
		return false
	if _is_excluded_visual_branch(candidate, target):
		return false
	if candidate is Sprite2D:
		var sprite := candidate as Sprite2D
		if sprite.texture == null or not _has_positive_texture_size(sprite.texture):
			return false
		if sprite.region_enabled:
			return sprite.region_rect.size.x > 0.0 and sprite.region_rect.size.y > 0.0
		return sprite.hframes > 0 and sprite.vframes > 0
	if candidate is AnimatedSprite2D:
		var animated := candidate as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return false
		var frame_count := animated.sprite_frames.get_frame_count(animated.animation)
		if frame_count <= 0:
			return false
		var frame_index := clampi(animated.frame, 0, frame_count - 1)
		var frame_texture := animated.sprite_frames.get_frame_texture(animated.animation, frame_index)
		return frame_texture != null and _has_positive_texture_size(frame_texture)
	if candidate is Polygon2D:
		return not (candidate as Polygon2D).polygon.is_empty()
	return false


static func _is_excluded_visual_branch(candidate: CanvasItem, target: Node = null) -> bool:
	if candidate == null:
		return true
	if candidate.has_meta("directional_shadow_source"):
		return not bool(candidate.get_meta("directional_shadow_source", false))
	var node: Node = candidate
	while node != null:
		if node == target:
			break
		if bool(node.get_meta("exclude_from_directional_shadow", false)):
			return true
		for group_name in EXCLUDED_SOURCE_GROUPS:
			if node.is_in_group(group_name):
				return true
		var normalized_name := _normalized_node_name(str(node.name))
		for token in EXCLUDED_SOURCE_NAME_TOKENS:
			if normalized_name.contains(token):
				return true
		node = node.get_parent()
	return false


static func _normalized_node_name(value: String) -> String:
	return value.to_lower().replace(" ", "").replace("_", "").replace("-", "")


static func _visual_size(candidate: CanvasItem) -> Vector2:
	if candidate is Sprite2D:
		var sprite := candidate as Sprite2D
		return WorldDepthRuntime.get_sprite_visual_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
	if candidate is AnimatedSprite2D:
		return WorldDepthRuntime.get_animated_sprite_visual_size(candidate as AnimatedSprite2D)
	if candidate is Polygon2D:
		return _polygon_bounds(candidate as Polygon2D).size
	return Vector2.ZERO


static func _has_positive_texture_size(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var texture_size := texture.get_size()
	return texture_size.x > 0.0 and texture_size.y > 0.0


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


static func _direction_degrees_from_legacy(value: Variant) -> float:
	var direction := Vector2.RIGHT.rotated(deg_to_rad(DEFAULT_DIRECTION_DEGREES))
	if value is Vector2:
		direction = value
	elif value is Dictionary:
		direction = Vector2(float(value.get("x", direction.x)), float(value.get("y", direction.y)))
	if direction.length_squared() < 0.0001:
		return DEFAULT_DIRECTION_DEGREES
	return rad_to_deg(direction.angle())
