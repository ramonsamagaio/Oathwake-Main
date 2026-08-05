class_name WyrdframeAdvancedCanvas
extends "res://tools/sprite_pose_lab/scripts/WyrdframeCanvas.gd"

var show_grid: bool = false
var display_scale: float = 1.0
var layer_rank: Dictionary = {}


func configure(
	new_document: Dictionary,
	new_action_id: String,
	new_direction_id: String,
	new_frame_index: int,
	new_selected_bone_id: String,
	settings: Dictionary
) -> void:
	super.configure(
		new_document,
		new_action_id,
		new_direction_id,
		new_frame_index,
		new_selected_bone_id,
		settings
	)
	show_grid = bool(settings.get("grid", false))
	display_scale = maxf(1.0, float(settings.get("display_scale", 1.0)))
	_rebuild_layer_rank()
	queue_redraw()


func _draw() -> void:
	var native_size: Vector2i = canvas_size()
	if show_checkerboard and not export_mode:
		_draw_checkerboard(native_size)
	if show_sprites:
		var frame_total: int = _frames().size()
		if show_previous and not export_mode and frame_index > 0:
			_draw_pose(frame_index - 1, Color(0.95, 0.18, 0.2, previous_opacity), false)
		if show_next and not export_mode and frame_index < frame_total - 1:
			_draw_pose(frame_index + 1, Color(0.18, 0.95, 0.42, next_opacity), false)
		_draw_pose(frame_index, Color(1.0, 1.0, 1.0, sprite_opacity), true)
	if show_grid and not export_mode:
		_draw_grid(native_size)
	if show_bones and not export_mode:
		_draw_bone_overlay()


func _draw_grid(native_size: Vector2i) -> void:
	var thin_width: float = 1.0 / display_scale
	var draw_minor: bool = display_scale >= 4.0
	var minor_color: Color = Color(0.66, 0.75, 0.82, 0.13)
	var major_color: Color = Color(0.72, 0.88, 0.98, 0.28)
	for x_value: int in range(native_size.x + 1):
		if not draw_minor and x_value % 8 != 0:
			continue
		var color_value: Color = major_color if x_value % 8 == 0 else minor_color
		draw_line(
			Vector2(float(x_value), 0.0),
			Vector2(float(x_value), float(native_size.y)),
			color_value,
			thin_width,
			false
		)
	for y_value: int in range(native_size.y + 1):
		if not draw_minor and y_value % 8 != 0:
			continue
		var color_value: Color = major_color if y_value % 8 == 0 else minor_color
		draw_line(
			Vector2(0.0, float(y_value)),
			Vector2(float(native_size.x), float(y_value)),
			color_value,
			thin_width,
			false
		)


func _rebuild_layer_rank() -> void:
	layer_rank.clear()
	var rig_data: Dictionary = document.get("rig", {}) as Dictionary
	var order_value: Array = rig_data.get("layer_order", []) as Array
	for index: int in range(order_value.size()):
		layer_rank[str(order_value[index])] = index


func _sort_draw_entries(left: Dictionary, right: Dictionary) -> bool:
	var left_id: String = str(left.get("bone_id", ""))
	var right_id: String = str(right.get("bone_id", ""))
	var left_rank: int = int(layer_rank.get(left_id, int(left.get("z", 0))))
	var right_rank: int = int(layer_rank.get(right_id, int(right.get("z", 0))))
	if left_rank == right_rank:
		return int(left.get("z", 0)) < int(right.get("z", 0))
	return left_rank < right_rank


func _draw_bone_overlay() -> void:
	var transform_cache: Dictionary = {}
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if not bool(bone_data.get("editor_visible", true)):
			continue
		var bone_id: String = str(bone_data.get("id", ""))
		var bone_transform: Transform2D = _global_transform(frame_index, bone_id, transform_cache)
		var start_point: Vector2 = bone_transform.origin
		var end_point: Vector2 = bone_transform * _bone_end_local(bone_id)
		var selected: bool = bone_id == selected_bone_id
		_draw_attachment_link(bone_data, bone_transform, transform_cache, selected)
		_draw_bone_segment(start_point, end_point, selected, bone_data)
		_draw_endpoint(start_point, selected, false, bone_data)
		_draw_endpoint(end_point, selected, true, bone_data)


func _draw_attachment_link(
	bone_data: Dictionary,
	bone_transform: Transform2D,
	transform_cache: Dictionary,
	selected: bool
) -> void:
	var parent_id: String = str(bone_data.get("parent", ""))
	if parent_id.is_empty():
		return
	var attachment: Dictionary = _attachment_for(bone_data)
	var parent_endpoint: String = str(attachment.get("parent_endpoint", "start"))
	var self_endpoint: String = str(attachment.get("self_endpoint", "start"))
	var parent_transform: Transform2D = _global_transform(frame_index, parent_id, transform_cache)
	var parent_anchor: Vector2 = parent_transform * _endpoint_local(parent_id, parent_endpoint)
	var self_anchor: Vector2 = bone_transform * _endpoint_local(str(bone_data.get("id", "")), self_endpoint)
	if parent_anchor.distance_to(self_anchor) <= 0.05:
		return
	var link_color: Color = Color(1.0, 0.58, 0.2, 0.8 * bone_opacity) if selected else Color(0.42, 0.78, 0.94, 0.48 * bone_opacity)
	draw_line(parent_anchor, self_anchor, link_color, 1.25 / display_scale, true)


func _draw_bone_segment(
	start_point: Vector2,
	end_point: Vector2,
	selected: bool,
	bone_data: Dictionary = {}
) -> void:
	var segment: Vector2 = end_point - start_point
	var segment_length: float = segment.length()
	if segment_length < 0.05:
		return
	var direction: Vector2 = segment / segment_length
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var screen_thickness: float = clampf(float(bone_data.get("editor_thickness", 6.0)), 2.0, 32.0)
	var half_width: float = screen_thickness * (0.62 if selected else 0.5) / display_scale
	var tip_width: float = maxf(1.2 / display_scale, half_width * 0.52)
	var polygon: PackedVector2Array = PackedVector2Array([
		start_point + normal * half_width,
		end_point + normal * tip_width,
		end_point - normal * tip_width,
		start_point - normal * half_width,
	])
	var alpha: float = bone_opacity
	var base_color: Color = _bone_color(bone_data)
	base_color.a *= alpha
	var fill_color: Color = base_color.lerp(Color(1.0, 0.62, 0.18, alpha), 0.42) if selected else base_color
	var outline_color: Color = Color(1.0, 0.38, 0.08, alpha) if selected else Color(0.04, 0.09, 0.13, alpha * 0.95)
	draw_colored_polygon(polygon, fill_color)
	var outline: PackedVector2Array = PackedVector2Array([
		polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]
	])
	draw_polyline(outline, outline_color, maxf(1.0, screen_thickness * 0.18) / display_scale, true)
	var center_color: Color = Color(1.0, 1.0, 1.0, alpha * (0.82 if selected else 0.48))
	draw_line(start_point, end_point, center_color, 1.0 / display_scale, true)


func _draw_endpoint(
	position_value: Vector2,
	selected: bool,
	is_end: bool,
	bone_data: Dictionary
) -> void:
	var alpha: float = bone_opacity
	var screen_thickness: float = clampf(float(bone_data.get("editor_thickness", 6.0)), 2.0, 32.0)
	var radius: float = maxf(4.5, screen_thickness * 0.72) / display_scale
	if selected:
		radius *= 1.22
	var outer_color: Color = Color(0.03, 0.07, 0.1, alpha)
	var base_color: Color = _bone_color(bone_data)
	base_color.a *= alpha
	var inner_color: Color = Color(1.0, 0.52, 0.12, alpha) if selected else base_color
	draw_circle(position_value, radius + 1.8 / display_scale, outer_color)
	draw_circle(position_value, radius, inner_color)
	if is_end:
		var diamond_radius: float = radius * 0.68
		var diamond: PackedVector2Array = PackedVector2Array([
			position_value + Vector2(0.0, -diamond_radius),
			position_value + Vector2(diamond_radius, 0.0),
			position_value + Vector2(0.0, diamond_radius),
			position_value + Vector2(-diamond_radius, 0.0),
			position_value + Vector2(0.0, -diamond_radius),
		])
		draw_polyline(diamond, Color(1.0, 1.0, 1.0, alpha * 0.92), 1.15 / display_scale, true)
	else:
		draw_circle(position_value, maxf(1.2 / display_scale, radius * 0.24), Color(1.0, 1.0, 1.0, alpha * 0.9))


func hit_test_bone(canvas_position: Vector2) -> String:
	var candidates: Array[String] = hit_test_bones(canvas_position)
	return "" if candidates.is_empty() else candidates[0]


func hit_test_bones(canvas_position: Vector2) -> Array[String]:
	var transform_cache: Dictionary = {}
	var hit_by_bone: Dictionary = {}
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if not bool(bone_data.get("editor_visible", true)):
			continue
		var bone_id: String = str(bone_data.get("id", ""))
		var bone_transform: Transform2D = _global_transform(frame_index, bone_id, transform_cache)
		var start_point: Vector2 = bone_transform.origin
		var end_point: Vector2 = bone_transform * _bone_end_local(bone_id)
		var thickness: float = clampf(float(bone_data.get("editor_thickness", 6.0)), 2.0, 32.0)
		var endpoint_radius: float = maxf(8.0, thickness) / display_scale
		var segment_radius: float = maxf(6.0, thickness * 0.72) / display_scale
		var start_distance: float = start_point.distance_to(canvas_position)
		var end_distance: float = end_point.distance_to(canvas_position)
		var segment_distance: float = _distance_to_segment(canvas_position, start_point, end_point)
		var best_distance: float = INF
		var endpoint_hit: bool = false
		if start_distance <= endpoint_radius:
			best_distance = start_distance
			endpoint_hit = true
		if end_distance <= endpoint_radius and end_distance < best_distance:
			best_distance = end_distance
			endpoint_hit = true
		if segment_distance <= segment_radius and segment_distance < best_distance:
			best_distance = segment_distance
		if best_distance < INF:
			hit_by_bone[bone_id] = {
				"bone_id": bone_id,
				"distance": best_distance,
				"endpoint": endpoint_hit,
				"rank": int(layer_rank.get(bone_id, 0)),
			}
	var hits: Array = hit_by_bone.values()
	hits.sort_custom(_sort_hits)
	var result: Array[String] = []
	for hit_value: Variant in hits:
		var hit: Dictionary = hit_value as Dictionary
		result.append(str(hit.get("bone_id", "")))
	return result


func _sort_hits(left: Dictionary, right: Dictionary) -> bool:
	var left_endpoint: bool = bool(left.get("endpoint", false))
	var right_endpoint: bool = bool(right.get("endpoint", false))
	if left_endpoint != right_endpoint:
		return left_endpoint
	var left_distance: float = float(left.get("distance", INF))
	var right_distance: float = float(right.get("distance", INF))
	if not is_equal_approx(left_distance, right_distance):
		return left_distance < right_distance
	return int(left.get("rank", 0)) > int(right.get("rank", 0))


func _global_transform(target_frame: int, bone_id: String, cache: Dictionary) -> Transform2D:
	if cache.has(bone_id):
		return cache[bone_id] as Transform2D
	var bone_data: Dictionary = _bone_by_id(bone_id)
	if bone_data.is_empty():
		return Transform2D.IDENTITY
	var transform_data: Dictionary = _resolved_transform(target_frame, bone_id)
	var local_position: Vector2 = _vec(transform_data.get("position", [0.0, 0.0]))
	if pixel_snap:
		local_position = local_position.round()
	var local_rotation: float = deg_to_rad(float(transform_data.get("rotation_degrees", 0.0)))
	var local_transform: Transform2D = Transform2D(local_rotation, local_position)
	var parent_id: String = str(bone_data.get("parent", ""))
	var result: Transform2D
	if parent_id.is_empty():
		result = local_transform
		result.origin += Vector2(canvas_size()) * 0.5
	else:
		var parent_transform: Transform2D = _global_transform(target_frame, parent_id, cache)
		var attachment: Dictionary = _attachment_for(bone_data)
		var parent_endpoint: String = str(attachment.get("parent_endpoint", "start"))
		var parent_anchor_local: Vector2 = _endpoint_local(parent_id, parent_endpoint)
		var anchor_transform: Transform2D = parent_transform
		anchor_transform.origin = parent_transform * parent_anchor_local
		result = anchor_transform * local_transform
	var self_endpoint: String = str(_attachment_for(bone_data).get("self_endpoint", "start"))
	if self_endpoint == "end":
		result.origin -= _basis_xform(result, _bone_end_local(bone_id))
	cache[bone_id] = result
	return result


func _basis_xform(transform_value: Transform2D, vector_value: Vector2) -> Vector2:
	return transform_value.x * vector_value.x + transform_value.y * vector_value.y


func _endpoint_local(bone_id: String, endpoint: String) -> Vector2:
	return _bone_end_local(bone_id) if endpoint == "end" else Vector2.ZERO


func _bone_end_local(bone_id: String) -> Vector2:
	var bone_data: Dictionary = _bone_by_id(bone_id)
	var length_value: float = maxf(0.0, float(bone_data.get("length", 12.0)))
	var angle_value: float = deg_to_rad(float(bone_data.get("bone_angle_degrees", 0.0)))
	return Vector2(length_value, 0.0).rotated(angle_value)


func _attachment_for(bone_data: Dictionary) -> Dictionary:
	var attachment_value: Variant = bone_data.get("attachment", {})
	if attachment_value is Dictionary:
		return attachment_value as Dictionary
	return {}


func _bone_color(bone_data: Dictionary) -> Color:
	var fallback: Color = Color(0.36, 0.82, 0.98, 1.0)
	var color_value: Variant = bone_data.get("editor_color", "#5ccdf8")
	if color_value is Color:
		return color_value as Color
	return Color.from_string(str(color_value), fallback)
