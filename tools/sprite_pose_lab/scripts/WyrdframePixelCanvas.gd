class_name WyrdframePixelCanvas
extends "res://tools/sprite_pose_lab/scripts/WyrdframeAdvancedCanvas.gd"

const ROTATION_SAMPLES: Array[Vector2] = [
	Vector2(0.25, 0.25),
	Vector2(0.75, 0.25),
	Vector2(0.25, 0.75),
	Vector2(0.75, 0.75),
]

var preserve_pixel_thickness: bool = false
var preserve_sprite_outline: bool = false
var show_sprite_pins: bool = true

var smart_rotation_cache: Dictionary = {}
var source_analysis_cache: Dictionary = {}


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
	preserve_pixel_thickness = bool(settings.get("preserve_pixel_thickness", false))
	preserve_sprite_outline = bool(settings.get("preserve_sprite_outline", false))
	show_sprite_pins = bool(settings.get("show_sprite_pins", true))
	queue_redraw()


func clear_texture_cache() -> void:
	super.clear_texture_cache()
	clear_pixel_rotation_cache()


func clear_pixel_rotation_cache() -> void:
	smart_rotation_cache.clear()
	source_analysis_cache.clear()
	queue_redraw()


func _draw() -> void:
	super._draw()
	if show_sprite_pins and not export_mode:
		_draw_selected_sprite_pins()


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
		entries.append({
			"bone_id": bone_id,
			"z": int(transform_data.get("z_index", 0)),
			"transform": _global_transform(target_frame, bone_id, transform_cache),
			"transform_data": transform_data,
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
		var transform_data: Dictionary = entry.get("transform_data", {}) as Dictionary
		var binding: Dictionary = _sprite_binding(bone_id, transform_data, texture.get_size())
		var anchor: Vector2 = binding.get("anchor", texture.get_size() * 0.5) as Vector2
		var bind_rotation: float = float(binding.get("rotation", 0.0))
		var total_rotation: float = global_transform.get_rotation() + bind_rotation
		var use_smart_rotation: bool = preserve_pixel_thickness or preserve_sprite_outline

		if use_smart_rotation and not is_zero_approx(total_rotation):
			var cache_id: String = texture_path if not texture_path.is_empty() else "placeholder:%s" % bone_id
			var rotated: Dictionary = _smart_rotated_texture(
				texture,
				cache_id,
				total_rotation,
				preserve_pixel_thickness,
				preserve_sprite_outline
			)
			var rotated_texture: Texture2D = rotated.get("texture") as Texture2D
			if rotated_texture == null:
				continue
			var anchor_transform: Transform2D = rotated.get("anchor_transform", Transform2D.IDENTITY) as Transform2D
			var rotated_anchor: Vector2 = anchor_transform * anchor
			var draw_position: Vector2 = global_transform.origin - rotated_anchor
			if pixel_snap:
				draw_position = draw_position.round()
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_texture_rect(
				rotated_texture,
				Rect2(draw_position, rotated_texture.get_size()),
				false,
				tint
			)
		else:
			var draw_origin: Vector2 = global_transform.origin
			if pixel_snap:
				draw_origin = draw_origin.round()
			draw_set_transform(draw_origin, total_rotation, Vector2.ONE)
			draw_texture_rect(texture, Rect2(-anchor, texture.get_size()), false, tint)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _sprite_binding(bone_id: String, transform_data: Dictionary, texture_size: Vector2) -> Dictionary:
	var pivot: Vector2 = _vec(transform_data.get("pivot", [0.0, 0.0]))
	var legacy_anchor: Vector2 = texture_size * 0.5 + pivot
	var pins: Dictionary = _sprite_pins_for(bone_id)
	if not bool(pins.get("enabled", false)):
		return {"anchor": legacy_anchor, "rotation": 0.0, "pins_enabled": false}
	var start_pin: Vector2 = _vec(pins.get("start", [legacy_anchor.x, legacy_anchor.y]))
	var end_pin: Vector2 = _vec(pins.get("end", [legacy_anchor.x + 1.0, legacy_anchor.y]))
	var source_axis: Vector2 = end_pin - start_pin
	var target_axis: Vector2 = _bone_end_local(bone_id)
	if source_axis.length_squared() <= 0.0001 or target_axis.length_squared() <= 0.0001:
		return {"anchor": start_pin, "rotation": 0.0, "pins_enabled": true}
	return {
		"anchor": start_pin,
		"rotation": target_axis.angle() - source_axis.angle(),
		"pins_enabled": true,
		"start": start_pin,
		"end": end_pin,
	}


func _sprite_pins_for(bone_id: String) -> Dictionary:
	var actions: Dictionary = document.get("actions", {}) as Dictionary
	var action_data: Dictionary = actions.get(action_id, {}) as Dictionary
	var directions: Dictionary = action_data.get("directions", {}) as Dictionary
	var direction_data: Dictionary = directions.get(direction_id, {}) as Dictionary
	var pins_map: Dictionary = direction_data.get("sprite_pins", {}) as Dictionary
	var pin_value: Variant = pins_map.get(bone_id, {})
	if pin_value is Dictionary:
		return pin_value as Dictionary
	return {}


func canvas_to_sprite_pixel(bone_id: String, target_frame: int, canvas_position: Vector2) -> Vector2:
	var texture_path: String = _texture_path(bone_id)
	var texture: Texture2D = _load_texture(texture_path, bone_id, false)
	if texture == null:
		return Vector2(INF, INF)
	var transform_cache: Dictionary = {}
	var global_transform: Transform2D = _global_transform(target_frame, bone_id, transform_cache)
	var transform_data: Dictionary = _resolved_transform(target_frame, bone_id)
	var binding: Dictionary = _sprite_binding(bone_id, transform_data, texture.get_size())
	var anchor: Vector2 = binding.get("anchor", texture.get_size() * 0.5) as Vector2
	var total_rotation: float = global_transform.get_rotation() + float(binding.get("rotation", 0.0))
	var sprite_transform: Transform2D = Transform2D(total_rotation, global_transform.origin)
	var local_position: Vector2 = sprite_transform.affine_inverse() * canvas_position
	return local_position + anchor


func sprite_texture_size(bone_id: String) -> Vector2:
	var texture: Texture2D = _load_texture(_texture_path(bone_id), bone_id, false)
	return texture.get_size() if texture != null else Vector2.ZERO


func _draw_selected_sprite_pins() -> void:
	var bone_data: Dictionary = _bone_by_id(selected_bone_id)
	if bone_data.is_empty() or not bool(bone_data.get("has_sprite", true)):
		return
	var pins: Dictionary = _sprite_pins_for(selected_bone_id)
	if not bool(pins.get("enabled", false)):
		return
	var texture: Texture2D = _load_texture(_texture_path(selected_bone_id), selected_bone_id, false)
	if texture == null:
		return
	var transform_cache: Dictionary = {}
	var global_transform: Transform2D = _global_transform(frame_index, selected_bone_id, transform_cache)
	var transform_data: Dictionary = _resolved_transform(frame_index, selected_bone_id)
	var binding: Dictionary = _sprite_binding(selected_bone_id, transform_data, texture.get_size())
	var start_pin: Vector2 = _vec(pins.get("start", [0.0, 0.0]))
	var end_pin: Vector2 = _vec(pins.get("end", [1.0, 0.0]))
	var total_rotation: float = global_transform.get_rotation() + float(binding.get("rotation", 0.0))
	var start_world: Vector2 = global_transform.origin
	var end_world: Vector2 = start_world + (end_pin - start_pin).rotated(total_rotation)
	var radius: float = 4.5 / display_scale
	var line_width: float = maxf(1.0, 1.5 / display_scale)
	draw_line(start_world, end_world, Color(1.0, 0.86, 0.18, 0.92), line_width, false)
	draw_circle(start_world, radius + 1.4 / display_scale, Color(0.04, 0.07, 0.09, 0.95))
	draw_circle(start_world, radius, Color(0.16, 0.92, 1.0, 0.96))
	draw_circle(end_world, radius + 1.4 / display_scale, Color(0.04, 0.07, 0.09, 0.95))
	draw_circle(end_world, radius, Color(1.0, 0.47, 0.16, 0.96))
	var bone_tip: Vector2 = global_transform * _bone_end_local(selected_bone_id)
	if bone_tip.distance_to(end_world) > 0.2:
		draw_dashed_line(end_world, bone_tip, Color(1.0, 0.35, 0.18, 0.72), 1.0 / display_scale, 2.5 / display_scale, false)


func _smart_rotated_texture(
	texture: Texture2D,
	cache_id: String,
	angle: float,
	keep_thickness: bool,
	keep_outline: bool
) -> Dictionary:
	var normalized_angle: float = wrapf(angle, -PI, PI)
	var quantized_angle: float = snappedf(normalized_angle, deg_to_rad(0.5))
	var cache_key: String = "%s|%.5f|%d|%d" % [
		cache_id,
		quantized_angle,
		1 if keep_thickness else 0,
		1 if keep_outline else 0,
	]
	if smart_rotation_cache.has(cache_key):
		return smart_rotation_cache[cache_key] as Dictionary

	var source: Image = texture.get_image()
	if source == null or source.is_empty():
		return {}
	if source.is_compressed():
		source.decompress()
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)

	var source_size: Vector2i = source.get_size()
	var corners: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(float(source_size.x), 0.0),
		Vector2(0.0, float(source_size.y)),
		Vector2(float(source_size.x), float(source_size.y)),
	]
	var min_point: Vector2 = Vector2(INF, INF)
	var max_point: Vector2 = Vector2(-INF, -INF)
	for corner: Vector2 in corners:
		var rotated_corner: Vector2 = corner.rotated(quantized_angle)
		min_point.x = minf(min_point.x, rotated_corner.x)
		min_point.y = minf(min_point.y, rotated_corner.y)
		max_point.x = maxf(max_point.x, rotated_corner.x)
		max_point.y = maxf(max_point.y, rotated_corner.y)
	var bounds_origin: Vector2 = Vector2(floorf(min_point.x), floorf(min_point.y))
	var output_size: Vector2i = Vector2i(
		maxi(1, ceili(max_point.x) - int(bounds_origin.x)),
		maxi(1, ceili(max_point.y) - int(bounds_origin.y))
	)
	var output: Image = Image.create_empty(output_size.x, output_size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)

	var pixel_count: int = output_size.x * output_size.y
	var alpha_mask: PackedByteArray = PackedByteArray()
	var coverage_map: PackedByteArray = PackedByteArray()
	var outline_votes: PackedByteArray = PackedByteArray()
	var candidate_colors: PackedColorArray = PackedColorArray()
	var outline_colors: PackedColorArray = PackedColorArray()
	alpha_mask.resize(pixel_count)
	coverage_map.resize(pixel_count)
	outline_votes.resize(pixel_count)
	candidate_colors.resize(pixel_count)
	outline_colors.resize(pixel_count)

	var analysis: Dictionary = _source_analysis(cache_id, source)
	var source_outline: PackedByteArray = analysis.get("outline", PackedByteArray()) as PackedByteArray
	var inverse_angle: float = -quantized_angle
	for y_value: int in range(output_size.y):
		for x_value: int in range(output_size.x):
			var index: int = y_value * output_size.x + x_value
			var opaque_samples: int = 0
			var outline_sample_count: int = 0
			var chosen_color: Color = Color.TRANSPARENT
			var chosen_outline: Color = Color.TRANSPARENT
			var center_world: Vector2 = bounds_origin + Vector2(float(x_value) + 0.5, float(y_value) + 0.5)
			var center_source: Vector2 = center_world.rotated(inverse_angle)
			var center_color: Color = _sample_source_color(source, center_source)
			if center_color.a > 0.05:
				chosen_color = center_color
			for sample_offset: Vector2 in ROTATION_SAMPLES:
				var sample_world: Vector2 = bounds_origin + Vector2(float(x_value), float(y_value)) + sample_offset
				var sample_source: Vector2 = sample_world.rotated(inverse_angle)
				var source_x: int = floori(sample_source.x)
				var source_y: int = floori(sample_source.y)
				if source_x < 0 or source_y < 0 or source_x >= source_size.x or source_y >= source_size.y:
					continue
				var source_color: Color = source.get_pixel(source_x, source_y)
				if source_color.a <= 0.05:
					continue
				opaque_samples += 1
				if chosen_color.a <= 0.05:
					chosen_color = source_color
				var source_index: int = source_y * source_size.x + source_x
				if keep_outline and source_index < source_outline.size() and source_outline[source_index] > 0:
					outline_sample_count += 1
					if chosen_outline.a <= 0.05 or source_color.get_luminance() < chosen_outline.get_luminance():
						chosen_outline = source_color
			coverage_map[index] = opaque_samples
			outline_votes[index] = outline_sample_count
			candidate_colors[index] = chosen_color
			outline_colors[index] = chosen_outline
			if opaque_samples >= 2 and chosen_color.a > 0.05:
				alpha_mask[index] = 1
				output.set_pixel(x_value, y_value, chosen_color)

	if keep_thickness:
		_repair_rotated_thickness(output, alpha_mask, coverage_map, candidate_colors, output_size)
	if keep_outline:
		_repair_rotated_outline(output, alpha_mask, outline_votes, outline_colors, output_size)

	var output_texture: Texture2D = ImageTexture.create_from_image(output)
	var anchor_transform: Transform2D = Transform2D(quantized_angle, -bounds_origin)
	var result: Dictionary = {
		"texture": output_texture,
		"anchor_transform": anchor_transform,
		"angle": quantized_angle,
	}
	smart_rotation_cache[cache_key] = result
	return result


func _sample_source_color(image: Image, source_position: Vector2) -> Color:
	var x_value: int = floori(source_position.x)
	var y_value: int = floori(source_position.y)
	if x_value < 0 or y_value < 0 or x_value >= image.get_width() or y_value >= image.get_height():
		return Color.TRANSPARENT
	return image.get_pixel(x_value, y_value)


func _repair_rotated_thickness(
	image: Image,
	alpha_mask: PackedByteArray,
	coverage_map: PackedByteArray,
	candidate_colors: PackedColorArray,
	size_value: Vector2i
) -> void:
	var repaired: PackedByteArray = alpha_mask.duplicate()
	for y_value: int in range(size_value.y):
		for x_value: int in range(size_value.x):
			var index: int = y_value * size_value.x + x_value
			if alpha_mask[index] > 0 or coverage_map[index] == 0:
				continue
			var neighbor_count: int = _count_mask_neighbors(alpha_mask, size_value, x_value, y_value)
			var bridges_gap: bool = _has_opposite_mask_neighbors(alpha_mask, size_value, x_value, y_value)
			if neighbor_count < 2 and not bridges_gap:
				continue
			var candidate: Color = candidate_colors[index]
			if candidate.a <= 0.05:
				candidate = _nearest_opaque_color(image, alpha_mask, size_value, x_value, y_value)
			if candidate.a <= 0.05:
				continue
			repaired[index] = 1
			image.set_pixel(x_value, y_value, candidate)
	for index: int in range(alpha_mask.size()):
		alpha_mask[index] = repaired[index]


func _repair_rotated_outline(
	image: Image,
	alpha_mask: PackedByteArray,
	outline_votes: PackedByteArray,
	outline_colors: PackedColorArray,
	size_value: Vector2i
) -> void:
	var projected_outline: PackedByteArray = PackedByteArray()
	projected_outline.resize(alpha_mask.size())
	for y_value: int in range(size_value.y):
		for x_value: int in range(size_value.x):
			var index: int = y_value * size_value.x + x_value
			if alpha_mask[index] == 0 or outline_votes[index] == 0:
				continue
			if not _is_mask_boundary(alpha_mask, size_value, x_value, y_value):
				continue
			var outline_color: Color = outline_colors[index]
			if outline_color.a <= 0.05:
				continue
			projected_outline[index] = 1
			image.set_pixel(x_value, y_value, outline_color)

	for y_value: int in range(size_value.y):
		for x_value: int in range(size_value.x):
			var index: int = y_value * size_value.x + x_value
			if alpha_mask[index] == 0 or projected_outline[index] > 0:
				continue
			if not _is_mask_boundary(alpha_mask, size_value, x_value, y_value):
				continue
			var outline_neighbors: int = _count_mask_neighbors(projected_outline, size_value, x_value, y_value)
			if outline_neighbors < 2:
				continue
			var support: bool = false
			for offset_y: int in range(-1, 2):
				for offset_x: int in range(-1, 2):
					var nx: int = x_value + offset_x
					var ny: int = y_value + offset_y
					if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
						continue
					if outline_votes[ny * size_value.x + nx] > 0:
						support = true
						break
				if support:
					break
			if not support:
				continue
			var repair_color: Color = _darkest_neighbor_color(image, projected_outline, size_value, x_value, y_value)
			if repair_color.a <= 0.05:
				continue
			projected_outline[index] = 1
			image.set_pixel(x_value, y_value, repair_color)


func _source_analysis(cache_id: String, source: Image) -> Dictionary:
	if source_analysis_cache.has(cache_id):
		return source_analysis_cache[cache_id] as Dictionary
	var size_value: Vector2i = source.get_size()
	var pixel_count: int = size_value.x * size_value.y
	var boundary_mask: PackedByteArray = PackedByteArray()
	var outline_mask: PackedByteArray = PackedByteArray()
	boundary_mask.resize(pixel_count)
	outline_mask.resize(pixel_count)
	var boundary_luminances: Array[float] = []
	var all_luminance_sum: float = 0.0
	var all_opaque_count: int = 0
	var boundary_luminance_sum: float = 0.0
	var boundary_count: int = 0

	for y_value: int in range(size_value.y):
		for x_value: int in range(size_value.x):
			var color_value: Color = source.get_pixel(x_value, y_value)
			if color_value.a <= 0.05:
				continue
			var luminance: float = color_value.get_luminance()
			all_luminance_sum += luminance
			all_opaque_count += 1
			if _source_pixel_is_boundary(source, x_value, y_value):
				var index: int = y_value * size_value.x + x_value
				boundary_mask[index] = 1
				boundary_luminances.append(luminance)
				boundary_luminance_sum += luminance
				boundary_count += 1

	boundary_luminances.sort()
	var global_average: float = all_luminance_sum / float(maxi(1, all_opaque_count))
	var boundary_average: float = boundary_luminance_sum / float(maxi(1, boundary_count))
	var percentile_index: int = clampi(int(float(boundary_luminances.size() - 1) * 0.55), 0, maxi(0, boundary_luminances.size() - 1))
	var dark_cutoff: float = boundary_luminances[percentile_index] if not boundary_luminances.is_empty() else 0.0
	var has_consistent_dark_rim: bool = boundary_average + 0.045 < global_average

	for y_value: int in range(size_value.y):
		for x_value: int in range(size_value.x):
			var index: int = y_value * size_value.x + x_value
			if boundary_mask[index] == 0:
				continue
			var color_value: Color = source.get_pixel(x_value, y_value)
			var luminance: float = color_value.get_luminance()
			var local_inside_average: float = _local_opaque_luminance(source, x_value, y_value)
			var very_dark: bool = luminance <= 0.20
			var locally_darker: bool = luminance + 0.045 < local_inside_average
			var palette_dark: bool = has_consistent_dark_rim and luminance <= dark_cutoff
			if very_dark or (locally_darker and palette_dark):
				outline_mask[index] = 1

	var result: Dictionary = {"outline": outline_mask}
	source_analysis_cache[cache_id] = result
	return result


func _source_pixel_is_boundary(source: Image, x_value: int, y_value: int) -> bool:
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			var nx: int = x_value + offset_x
			var ny: int = y_value + offset_y
			if nx < 0 or ny < 0 or nx >= source.get_width() or ny >= source.get_height():
				return true
			if source.get_pixel(nx, ny).a <= 0.05:
				return true
	return false


func _local_opaque_luminance(source: Image, x_value: int, y_value: int) -> float:
	var luminance_sum: float = 0.0
	var count: int = 0
	for offset_y: int in range(-2, 3):
		for offset_x: int in range(-2, 3):
			if offset_x == 0 and offset_y == 0:
				continue
			var nx: int = x_value + offset_x
			var ny: int = y_value + offset_y
			if nx < 0 or ny < 0 or nx >= source.get_width() or ny >= source.get_height():
				continue
			var color_value: Color = source.get_pixel(nx, ny)
			if color_value.a <= 0.05:
				continue
			luminance_sum += color_value.get_luminance()
			count += 1
	return luminance_sum / float(maxi(1, count))


func _count_mask_neighbors(mask: PackedByteArray, size_value: Vector2i, x_value: int, y_value: int) -> int:
	var count: int = 0
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			var nx: int = x_value + offset_x
			var ny: int = y_value + offset_y
			if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
				continue
			if mask[ny * size_value.x + nx] > 0:
				count += 1
	return count


func _has_opposite_mask_neighbors(mask: PackedByteArray, size_value: Vector2i, x_value: int, y_value: int) -> bool:
	var pairs: Array = [
		[Vector2i(-1, 0), Vector2i(1, 0)],
		[Vector2i(0, -1), Vector2i(0, 1)],
		[Vector2i(-1, -1), Vector2i(1, 1)],
		[Vector2i(1, -1), Vector2i(-1, 1)],
	]
	for pair_value: Variant in pairs:
		var pair: Array = pair_value as Array
		var first: Vector2i = pair[0]
		var second: Vector2i = pair[1]
		var ax: int = x_value + first.x
		var ay: int = y_value + first.y
		var bx: int = x_value + second.x
		var by: int = y_value + second.y
		if ax < 0 or ay < 0 or bx < 0 or by < 0:
			continue
		if ax >= size_value.x or bx >= size_value.x or ay >= size_value.y or by >= size_value.y:
			continue
		if mask[ay * size_value.x + ax] > 0 and mask[by * size_value.x + bx] > 0:
			return true
	return false


func _is_mask_boundary(mask: PackedByteArray, size_value: Vector2i, x_value: int, y_value: int) -> bool:
	if mask[y_value * size_value.x + x_value] == 0:
		return false
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			var nx: int = x_value + offset_x
			var ny: int = y_value + offset_y
			if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
				return true
			if mask[ny * size_value.x + nx] == 0:
				return true
	return false


func _nearest_opaque_color(
	image: Image,
	mask: PackedByteArray,
	size_value: Vector2i,
	x_value: int,
	y_value: int
) -> Color:
	for radius: int in range(1, 3):
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				var nx: int = x_value + offset_x
				var ny: int = y_value + offset_y
				if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
					continue
				if mask[ny * size_value.x + nx] > 0:
					return image.get_pixel(nx, ny)
	return Color.TRANSPARENT


func _darkest_neighbor_color(
	image: Image,
	mask: PackedByteArray,
	size_value: Vector2i,
	x_value: int,
	y_value: int
) -> Color:
	var result: Color = Color.TRANSPARENT
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var nx: int = x_value + offset_x
			var ny: int = y_value + offset_y
			if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
				continue
			if mask[ny * size_value.x + nx] == 0:
				continue
			var color_value: Color = image.get_pixel(nx, ny)
			if result.a <= 0.05 or color_value.get_luminance() < result.get_luminance():
				result = color_value
	return result
