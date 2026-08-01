class_name WyrdframeCanvas
extends Node2D

var document: Dictionary = {}
var action_id: String = "idle"
var direction_id: String = "south"
var frame_index: int = 0
var selected_bone_id: String = "torso"

var show_checkerboard: bool = true
var show_bones: bool = true
var show_sprites: bool = true
var show_previous: bool = true
var show_next: bool = true
var bone_opacity: float = 0.9
var sprite_opacity: float = 1.0
var previous_opacity: float = 0.25
var next_opacity: float = 0.25
var pixel_snap: bool = true
var export_mode: bool = false

var texture_cache: Dictionary = {}
var placeholder_cache: Dictionary = {}


func configure(
	new_document: Dictionary,
	new_action_id: String,
	new_direction_id: String,
	new_frame_index: int,
	new_selected_bone_id: String,
	settings: Dictionary
) -> void:
	document = new_document
	action_id = new_action_id
	direction_id = new_direction_id
	frame_index = new_frame_index
	selected_bone_id = new_selected_bone_id
	show_checkerboard = bool(settings.get("checkerboard", true))
	show_bones = bool(settings.get("bones", true))
	show_sprites = bool(settings.get("sprites", true))
	show_previous = bool(settings.get("previous", true))
	show_next = bool(settings.get("next", true))
	bone_opacity = clampf(float(settings.get("bone_opacity", 0.9)), 0.0, 1.0)
	sprite_opacity = clampf(float(settings.get("sprite_opacity", 1.0)), 0.0, 1.0)
	previous_opacity = clampf(float(settings.get("previous_opacity", 0.25)), 0.0, 1.0)
	next_opacity = clampf(float(settings.get("next_opacity", 0.25)), 0.0, 1.0)
	pixel_snap = bool(settings.get("pixel_snap", true))
	queue_redraw()


func set_export_mode(enabled: bool) -> void:
	export_mode = enabled
	queue_redraw()


func clear_texture_cache() -> void:
	texture_cache.clear()
	placeholder_cache.clear()
	queue_redraw()


func canvas_size() -> Vector2i:
	var canvas_data: Dictionary = document.get("canvas", {}) as Dictionary
	return Vector2i(
		maxi(1, int(canvas_data.get("width", 64))),
		maxi(1, int(canvas_data.get("height", 64)))
	)


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
	if show_bones and not export_mode:
		_draw_bone_overlay()


func _draw_checkerboard(native_size: Vector2i) -> void:
	var cell_size: int = 4
	var light_color: Color = Color(0.43, 0.45, 0.48, 1.0)
	var dark_color: Color = Color(0.31, 0.33, 0.36, 1.0)
	for y_value: int in range(0, native_size.y, cell_size):
		for x_value: int in range(0, native_size.x, cell_size):
			var checker_index: int = int(x_value / cell_size) + int(y_value / cell_size)
			var fill_color: Color = light_color if checker_index % 2 == 0 else dark_color
			var draw_width: int = mini(cell_size, native_size.x - x_value)
			var draw_height: int = mini(cell_size, native_size.y - y_value)
			draw_rect(Rect2(float(x_value), float(y_value), float(draw_width), float(draw_height)), fill_color)


func _draw_pose(target_frame: int, tint: Color, draw_placeholders: bool) -> void:
	var entries: Array[Dictionary] = []
	var transform_cache: Dictionary = {}
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if not bool(bone_data.get("has_sprite", true)):
			continue
		var bone_id: String = str(bone_data.get("id", ""))
		var transform_data: Dictionary = _resolved_transform(target_frame, bone_id)
		if not bool(transform_data.get("visible", true)):
			continue
		var global_transform: Transform2D = _global_transform(target_frame, bone_id, transform_cache)
		entries.append({
			"bone_id": bone_id,
			"z": int(transform_data.get("z_index", 0)),
			"transform": global_transform,
			"pivot": _vec(transform_data.get("pivot", [0.0, 0.0])),
		})
	entries.sort_custom(_sort_draw_entries)
	for entry: Dictionary in entries:
		var bone_id: String = str(entry.get("bone_id", ""))
		var texture_path: String = _texture_path(bone_id)
		if export_mode and texture_path.is_empty():
			continue
		var texture: Texture2D = _load_texture(texture_path, bone_id, draw_placeholders)
		if texture == null:
			continue
		var global_transform: Transform2D = entry.get("transform", Transform2D.IDENTITY) as Transform2D
		var pivot: Vector2 = entry.get("pivot", Vector2.ZERO) as Vector2
		var texture_size: Vector2 = texture.get_size()
		var draw_position: Vector2 = -texture_size * 0.5 - pivot
		draw_set_transform(global_transform.origin, global_transform.get_rotation(), Vector2.ONE)
		draw_texture_rect(texture, Rect2(draw_position, texture_size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _sort_draw_entries(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("z", 0)) < int(right.get("z", 0))


func _draw_bone_overlay() -> void:
	var transform_cache: Dictionary = {}
	var positions: Dictionary = {}
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		positions[bone_id] = _global_transform(frame_index, bone_id, transform_cache).origin
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		if not bool(bone_data.get("editor_visible", true)):
			continue
		var child_position: Vector2 = positions.get(bone_id, Vector2.ZERO) as Vector2
		var parent_id: String = str(bone_data.get("parent", ""))
		if parent_id.is_empty():
			_draw_joint(child_position, bone_id == selected_bone_id, true)
			continue
		var parent_position: Vector2 = positions.get(parent_id, child_position) as Vector2
		_draw_bone_segment(parent_position, child_position, bone_id == selected_bone_id)
		_draw_joint(child_position, bone_id == selected_bone_id, false)


func _draw_bone_segment(start_point: Vector2, end_point: Vector2, selected: bool) -> void:
	var segment: Vector2 = end_point - start_point
	var segment_length: float = segment.length()
	if segment_length < 0.5:
		return
	var direction: Vector2 = segment / segment_length
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var base_width: float = clampf(segment_length * 0.16, 1.5, 3.8)
	var tip_width: float = maxf(0.9, base_width * 0.38)
	var polygon: PackedVector2Array = PackedVector2Array([
		start_point + normal * base_width,
		end_point + normal * tip_width,
		end_point - normal * tip_width,
		start_point - normal * base_width,
	])
	var alpha: float = bone_opacity
	var fill_color: Color = Color(0.98, 0.78, 0.28, alpha) if selected else Color(0.82, 0.92, 0.96, alpha)
	var outline_color: Color = Color(0.22, 0.55, 0.72, alpha) if not selected else Color(1.0, 0.48, 0.12, alpha)
	draw_colored_polygon(polygon, fill_color)
	var outline: PackedVector2Array = PackedVector2Array([
		polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]
	])
	draw_polyline(outline, outline_color, 0.85, true)
	var center_line_color: Color = Color(0.25, 0.72, 0.88, alpha * 0.85)
	draw_line(start_point, end_point, center_line_color, 0.65, true)


func _draw_joint(position_value: Vector2, selected: bool, root_joint: bool) -> void:
	var alpha: float = bone_opacity
	var radius: float = 2.8 if selected else 2.2
	if root_joint:
		radius = 3.2
	var outer_color: Color = Color(0.05, 0.12, 0.16, alpha)
	var inner_color: Color = Color(1.0, 0.55, 0.12, alpha) if selected else Color(0.15, 1.0, 0.56, alpha)
	draw_circle(position_value, radius + 1.2, outer_color)
	draw_circle(position_value, radius, inner_color)
	draw_arc(position_value, radius + 1.2, 0.0, TAU, 16, Color(0.85, 0.95, 1.0, alpha), 0.65, true)


func hit_test_bone(canvas_position: Vector2) -> String:
	var transform_cache: Dictionary = {}
	var best_bone: String = ""
	var best_distance: float = 999999.0
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if not bool(bone_data.get("editor_visible", true)):
			continue
		var bone_id: String = str(bone_data.get("id", ""))
		var joint_position: Vector2 = _global_transform(frame_index, bone_id, transform_cache).origin
		var joint_distance: float = joint_position.distance_to(canvas_position)
		if joint_distance < best_distance and joint_distance <= 6.0:
			best_distance = joint_distance
			best_bone = bone_id
		var parent_id: String = str(bone_data.get("parent", ""))
		if not parent_id.is_empty():
			var parent_position: Vector2 = _global_transform(frame_index, parent_id, transform_cache).origin
			var segment_distance: float = _distance_to_segment(canvas_position, parent_position, joint_position)
			if segment_distance < best_distance and segment_distance <= 4.0:
				best_distance = segment_distance
				best_bone = bone_id
	return best_bone


func parent_local_delta(bone_id: String, canvas_delta: Vector2) -> Vector2:
	var bone_data: Dictionary = _bone_by_id(bone_id)
	var parent_id: String = str(bone_data.get("parent", ""))
	if parent_id.is_empty():
		return canvas_delta
	var transform_cache: Dictionary = {}
	var parent_transform: Transform2D = _global_transform(frame_index, parent_id, transform_cache)
	return canvas_delta.rotated(-parent_transform.get_rotation())


func _distance_to_segment(point_value: Vector2, start_point: Vector2, end_point: Vector2) -> float:
	var segment: Vector2 = end_point - start_point
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= 0.0001:
		return point_value.distance_to(start_point)
	var ratio: float = clampf((point_value - start_point).dot(segment) / segment_length_squared, 0.0, 1.0)
	var projection: Vector2 = start_point + segment * ratio
	return point_value.distance_to(projection)


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
		result = _global_transform(target_frame, parent_id, cache) * local_transform
	cache[bone_id] = result
	return result


func _resolved_transform(target_frame: int, bone_id: String) -> Dictionary:
	var bone_data: Dictionary = _bone_by_id(bone_id)
	var rest_value: Dictionary = bone_data.get("rest", {}) as Dictionary
	var result: Dictionary = rest_value.duplicate(true)
	var frames_value: Array = _frames()
	var last_index: int = mini(target_frame, frames_value.size() - 1)
	for index: int in range(last_index + 1):
		var frame_data: Dictionary = frames_value[index] as Dictionary
		var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
		if keys.has(bone_id):
			result = (keys[bone_id] as Dictionary).duplicate(true)
	return result


func _bones() -> Array:
	var rig_data: Dictionary = document.get("rig", {}) as Dictionary
	return rig_data.get("bones", []) as Array


func _bone_by_id(bone_id: String) -> Dictionary:
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if str(bone_data.get("id", "")) == bone_id:
			return bone_data
	return {}


func _frames() -> Array:
	var actions: Dictionary = document.get("actions", {}) as Dictionary
	var action_data: Dictionary = actions.get(action_id, {}) as Dictionary
	var directions: Dictionary = action_data.get("directions", {}) as Dictionary
	var direction_data: Dictionary = directions.get(direction_id, {}) as Dictionary
	return direction_data.get("frames", []) as Array


func _texture_path(bone_id: String) -> String:
	var actions: Dictionary = document.get("actions", {}) as Dictionary
	var action_data: Dictionary = actions.get(action_id, {}) as Dictionary
	var directions: Dictionary = action_data.get("directions", {}) as Dictionary
	var direction_data: Dictionary = directions.get(direction_id, {}) as Dictionary
	var textures: Dictionary = direction_data.get("textures", {}) as Dictionary
	return str(textures.get(bone_id, ""))


func _load_texture(path: String, bone_id: String, allow_placeholder: bool) -> Texture2D:
	if path.is_empty():
		return _placeholder_texture(bone_id) if allow_placeholder else null
	if texture_cache.has(path):
		return texture_cache[path] as Texture2D
	var texture: Texture2D = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
	else:
		var image: Image = Image.new()
		if image.load(path) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture != null:
		texture_cache[path] = texture
		return texture
	return _placeholder_texture(bone_id) if allow_placeholder else null


func _placeholder_texture(bone_id: String) -> Texture2D:
	if placeholder_cache.has(bone_id):
		return placeholder_cache[bone_id] as Texture2D
	var placeholder_size: Vector2i = Vector2i(10, 14)
	if bone_id.contains("head"):
		placeholder_size = Vector2i(18, 18)
	elif bone_id.contains("torso") or bone_id.contains("body"):
		placeholder_size = Vector2i(16, 18)
	elif bone_id.contains("arm"):
		placeholder_size = Vector2i(7, 18)
	elif bone_id.contains("leg"):
		placeholder_size = Vector2i(7, 16)
	var image: Image = Image.create_empty(placeholder_size.x, placeholder_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.23, 0.3, 0.36, 0.26))
	var border_color: Color = Color(0.42, 0.55, 0.63, 0.38)
	for x_value: int in range(placeholder_size.x):
		image.set_pixel(x_value, 0, border_color)
		image.set_pixel(x_value, placeholder_size.y - 1, border_color)
	for y_value: int in range(placeholder_size.y):
		image.set_pixel(0, y_value, border_color)
		image.set_pixel(placeholder_size.x - 1, y_value, border_color)
	var result: Texture2D = ImageTexture.create_from_image(image)
	placeholder_cache[bone_id] = result
	return result


func _vec(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array:
		var values: Array = value as Array
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO
