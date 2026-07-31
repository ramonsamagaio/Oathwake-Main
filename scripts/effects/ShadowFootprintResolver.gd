class_name ShadowFootprintResolver
extends RefCounted

const DEFAULT_ELLIPSE_SEGMENTS := 16
const MIN_FOOTPRINT_POINTS := 3


static func resolve(
	target: Node2D,
	source: CanvasItem,
	contact: Vector2,
	visual_size: Vector2,
	profile: Dictionary,
	config: Dictionary
) -> Dictionary:
	var axes := _resolve_ground_axes(target, source)
	var root_axis: Vector2 = axes.get("root_axis", Vector2.RIGHT)
	var ground_axis: Vector2 = axes.get("ground_axis", Vector2.DOWN)

	var configured_points := _configured_points(target, source, config)
	if configured_points.size() >= MIN_FOOTPRINT_POINTS:
		var authored_hull := _convex_hull(configured_points)
		if authored_hull.size() >= MIN_FOOTPRINT_POINTS:
			var authored_support := _support_point(authored_hull, root_axis, ground_axis)
			return {
				"points": authored_hull,
				"support": authored_support,
				"root_axis": root_axis,
				"ground_axis": ground_axis,
				"source_kind": "configured_polygon",
				"source_name": "ContentFootprint",
				"authored": true,
			}

	var candidate := _find_footprint_candidate(target)
	if not candidate.is_empty():
		var candidate_node := candidate.get("node") as Node2D
		var candidate_points := _points_from_candidate(target, candidate_node)
		if candidate_points.size() >= MIN_FOOTPRINT_POINTS:
			candidate_points = _convex_hull(candidate_points)
			var explicit := bool(candidate.get("explicit", false))
			var align_to_contact := bool(config.get("shadow_footprint_align_to_contact", not explicit))
			if align_to_contact:
				candidate_points = _align_support_to_contact(candidate_points, contact, root_axis, ground_axis)
			var candidate_support := _support_point(candidate_points, root_axis, ground_axis)
			return {
				"points": candidate_points,
				"support": candidate_support,
				"root_axis": root_axis,
				"ground_axis": ground_axis,
				"source_kind": _candidate_kind(candidate_node),
				"source_name": str(candidate_node.name),
				"authored": explicit,
			}

	var fallback_points := _fallback_ellipse(contact, root_axis, ground_axis, visual_size, profile, config)
	return {
		"points": fallback_points,
		"support": _support_point(fallback_points, root_axis, ground_axis),
		"root_axis": root_axis,
		"ground_axis": ground_axis,
		"source_kind": "profile_fallback",
		"source_name": str(profile.get("id", "fallback")),
		"authored": false,
	}


static func _configured_points(target: Node2D, source: CanvasItem, config: Dictionary) -> PackedVector2Array:
	var values: Array = [
		config.get("shadow_footprint_points", null),
		config.get("footprint_points", null),
	]
	for value in [target, source]:
		if value == null:
			continue
		for metadata_name in ["shadow_footprint_points", "day_shadow_footprint_points"]:
			if value.has_meta(metadata_name):
				values.append(value.get_meta(metadata_name))
	for raw_value in values:
		var parsed := _parse_points(raw_value)
		if parsed.size() >= MIN_FOOTPRINT_POINTS:
			return parsed
	return PackedVector2Array()


static func _parse_points(raw_value: Variant) -> PackedVector2Array:
	if raw_value is PackedVector2Array:
		return (raw_value as PackedVector2Array).duplicate()
	var result := PackedVector2Array()
	if not raw_value is Array:
		return result
	for point_value in raw_value as Array:
		if point_value is Vector2:
			var vector_point := point_value as Vector2
			if vector_point.is_finite():
				result.append(vector_point)
		elif point_value is Dictionary:
			var point_data := point_value as Dictionary
			var dictionary_point := Vector2(
				float(point_data.get("x", 0.0)),
				float(point_data.get("y", 0.0))
			)
			if dictionary_point.is_finite():
				result.append(dictionary_point)
	return result


static func _find_footprint_candidate(target: Node2D) -> Dictionary:
	if target == null:
		return {}
	var best: Dictionary = {}
	var best_score := -INF
	var queue: Array = []
	for child in target.get_children():
		if child is Node:
			queue.append({"node": child, "depth": 1})
	while not queue.is_empty():
		var entry := queue.pop_front() as Dictionary
		var node := entry.get("node") as Node
		var depth := int(entry.get("depth", 1))
		if node == null or _is_ignored_branch(node):
			continue
		var explicit := _is_explicit_footprint_node(node)
		var is_candidate := node is CollisionShape2D or node is CollisionPolygon2D or (explicit and node is Polygon2D)
		if is_candidate:
			var score := 1000.0 if explicit else 100.0
			if node.get_parent() == target:
				score += 80.0
			if node is CollisionPolygon2D:
				score += 20.0
			elif node is CollisionShape2D:
				score += 10.0
			score -= float(depth)
			if score > best_score:
				best_score = score
				best = {"node": node, "explicit": explicit}
		if node is Area2D:
			continue
		for child in node.get_children():
			if child is Node:
				queue.append({"node": child, "depth": depth + 1})
	return best


static func _is_ignored_branch(node: Node) -> bool:
	if node == null:
		return true
	if node.is_in_group("persistent_content_visual"):
		return true
	var lowered := str(node.name).to_lower()
	if lowered in ["groundshadow", "legacygroundshadow", "contentshadow", "contentglow"]:
		return true
	if lowered.contains("damagearea") or lowered.contains("hurtbox") or lowered.contains("hitbox"):
		return true
	return false


static func _is_explicit_footprint_node(node: Node) -> bool:
	if node == null:
		return false
	if node.is_in_group("shadow_footprint") or node.is_in_group("day_shadow_caster"):
		return true
	var lowered := str(node.name).to_lower().replace(" ", "").replace("_", "")
	return lowered.contains("shadowfootprint") or lowered.contains("dayshadowcaster") or lowered.contains("shadowcastershape")


static func _points_from_candidate(target: Node2D, candidate: Node2D) -> PackedVector2Array:
	if target == null or candidate == null:
		return PackedVector2Array()
	var local_points := PackedVector2Array()
	if candidate is CollisionPolygon2D:
		var collision_polygon := candidate as CollisionPolygon2D
		if collision_polygon.disabled:
			return local_points
		local_points = collision_polygon.polygon.duplicate()
	elif candidate is CollisionShape2D:
		var collision_shape := candidate as CollisionShape2D
		if collision_shape.disabled or collision_shape.shape == null:
			return local_points
		local_points = _shape_points(collision_shape.shape)
	elif candidate is Polygon2D:
		local_points = (candidate as Polygon2D).polygon.duplicate()
	if local_points.size() < MIN_FOOTPRINT_POINTS:
		return PackedVector2Array()
	var transformed := PackedVector2Array()
	for local_point in local_points:
		transformed.append(target.to_local(candidate.to_global(local_point)))
	return transformed


static func _shape_points(shape: Shape2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	if shape is CircleShape2D:
		var radius := maxf((shape as CircleShape2D).radius, 1.0)
		return _ellipse_points(radius, radius, DEFAULT_ELLIPSE_SEGMENTS)
	if shape is RectangleShape2D:
		var half_size := (shape as RectangleShape2D).size * 0.5
		return PackedVector2Array([
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		])
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return _ellipse_points(maxf(capsule.radius, 1.0), maxf(capsule.height * 0.5, capsule.radius), DEFAULT_ELLIPSE_SEGMENTS)
	if shape is ConvexPolygonShape2D:
		return (shape as ConvexPolygonShape2D).points.duplicate()
	if shape is ConcavePolygonShape2D:
		return _convex_hull((shape as ConcavePolygonShape2D).segments)
	if shape is SegmentShape2D:
		var segment := shape as SegmentShape2D
		var direction := segment.b - segment.a
		if direction.length_squared() <= 0.0001:
			return result
		var normal := direction.normalized().rotated(PI * 0.5) * 1.5
		return PackedVector2Array([
			segment.a - normal,
			segment.b - normal,
			segment.b + normal,
			segment.a + normal,
		])
	return result


static func _ellipse_points(radius_x: float, radius_y: float, segment_count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var safe_segments := maxi(segment_count, 8)
	for index in range(safe_segments):
		var angle := TAU * float(index) / float(safe_segments)
		result.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return result


static func _fallback_ellipse(
	contact: Vector2,
	root_axis: Vector2,
	ground_axis: Vector2,
	visual_size: Vector2,
	profile: Dictionary,
	config: Dictionary
) -> PackedVector2Array:
	var root_width_ratio := clampf(float(profile.get("root_width_ratio", 0.8)), 0.10, 1.5)
	var minimum_width := maxf(float(profile.get("minimum_width", 12.0)), 4.0)
	var configured_width_scale := maxf(float(config.get("shadow_footprint_width_scale", 1.0)), 0.05)
	var footprint_width := maxf(visual_size.x * root_width_ratio * 0.42, minimum_width * 0.55) * configured_width_scale
	var footprint_depth_ratio := clampf(float(config.get("shadow_footprint_depth_ratio", 0.26)), 0.08, 0.75)
	var footprint_depth := maxf(footprint_width * footprint_depth_ratio, 3.0)
	var half_width := footprint_width * 0.5
	var half_depth := footprint_depth * 0.5
	var center := contact - ground_axis * half_depth
	var points := PackedVector2Array()
	for index in range(DEFAULT_ELLIPSE_SEGMENTS):
		var angle := TAU * float(index) / float(DEFAULT_ELLIPSE_SEGMENTS)
		points.append(
			center
			+ root_axis * (cos(angle) * half_width)
			+ ground_axis * (sin(angle) * half_depth)
		)
	return _convex_hull(points)


static func _resolve_ground_axes(target: Node2D, source: CanvasItem) -> Dictionary:
	var root_axis := Vector2.RIGHT
	var ground_axis := Vector2.DOWN
	var source_node := source as Node2D
	if target != null and source_node != null and target.is_inside_tree() and source_node.is_inside_tree():
		var relative_transform := target.global_transform.affine_inverse() * source_node.global_transform
		if relative_transform.x.length_squared() > 0.0001:
			root_axis = relative_transform.x.normalized()
		if relative_transform.y.length_squared() > 0.0001:
			ground_axis = relative_transform.y.normalized()
	if ground_axis.dot(Vector2.DOWN) < 0.0:
		ground_axis = -ground_axis
	if root_axis.length_squared() <= 0.0001:
		root_axis = ground_axis.rotated(-PI * 0.5)
	return {"root_axis": root_axis.normalized(), "ground_axis": ground_axis.normalized()}


static func _align_support_to_contact(
	points: PackedVector2Array,
	contact: Vector2,
	root_axis: Vector2,
	ground_axis: Vector2
) -> PackedVector2Array:
	if points.size() < MIN_FOOTPRINT_POINTS:
		return points
	var support := _support_point(points, root_axis, ground_axis)
	var delta := contact - support
	var aligned := PackedVector2Array()
	for point in points:
		aligned.append(point + delta)
	return aligned


static func _support_point(points: PackedVector2Array, root_axis: Vector2, ground_axis: Vector2) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var minimum_lateral := INF
	var maximum_lateral := -INF
	var maximum_ground := -INF
	for point in points:
		var lateral := point.dot(root_axis)
		var ground := point.dot(ground_axis)
		minimum_lateral = minf(minimum_lateral, lateral)
		maximum_lateral = maxf(maximum_lateral, lateral)
		maximum_ground = maxf(maximum_ground, ground)
	return root_axis * ((minimum_lateral + maximum_lateral) * 0.5) + ground_axis * maximum_ground


static func _convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < MIN_FOOTPRINT_POINTS:
		return points
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0].distance_to(hull[hull.size() - 1]) <= 0.001:
		hull.resize(hull.size() - 1)
	return hull


static func _candidate_kind(candidate: Node2D) -> String:
	if candidate is CollisionPolygon2D:
		return "collision_polygon"
	if candidate is CollisionShape2D:
		var shape := (candidate as CollisionShape2D).shape
		return "collision_shape:%s" % (shape.get_class() if shape != null else "null")
	if candidate is Polygon2D:
		return "authored_polygon"
	return "unknown"
