class_name WyrdframeSmartPixelCanvas
extends "res://tools/sprite_pose_lab/scripts/WyrdframePixelCanvas.gd"

const CLEANUP_SOURCE_SAMPLES: Array[Vector2] = [
	Vector2(0.5, 0.5),
	Vector2(0.25, 0.25),
	Vector2(0.75, 0.25),
	Vector2(0.25, 0.75),
	Vector2(0.75, 0.75),
]

var cleanup_pixels: bool = false
var cleanup_rotation_cache: Dictionary = {}


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
	cleanup_pixels = bool(settings.get("cleanup_pixels", false))
	queue_redraw()


func clear_pixel_rotation_cache() -> void:
	super.clear_pixel_rotation_cache()
	cleanup_rotation_cache.clear()


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

		# Pixel-perfect must rasterize the rotation itself. Merely using nearest filtering
		# still rotates the texture quad and leaves its source pixels diagonal to the canvas grid.
		var bake_to_pixel_grid: bool = (
			pixel_snap
			or preserve_pixel_thickness
			or preserve_sprite_outline
			or cleanup_pixels
		)

		if bake_to_pixel_grid and not is_zero_approx(total_rotation):
			var cache_id: String = texture_path if not texture_path.is_empty() else "placeholder:%s" % bone_id
			var rotated: Dictionary = _grid_locked_rotated_texture(
				texture,
				cache_id,
				total_rotation,
				preserve_pixel_thickness,
				preserve_sprite_outline,
				cleanup_pixels
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


func _grid_locked_rotated_texture(
	texture: Texture2D,
	cache_id: String,
	angle: float,
	keep_thickness: bool,
	keep_outline: bool,
	apply_cleanup: bool
) -> Dictionary:
	var base_result: Dictionary = _smart_rotated_texture(
		texture,
		cache_id,
		angle,
		keep_thickness,
		keep_outline
	)
	if not apply_cleanup or base_result.is_empty():
		return base_result

	var quantized_angle: float = float(base_result.get("angle", angle))
	var cache_key: String = "%s|%.5f|%d|%d|cleanup" % [
		cache_id,
		quantized_angle,
		1 if keep_thickness else 0,
		1 if keep_outline else 0,
	]
	if cleanup_rotation_cache.has(cache_key):
		return cleanup_rotation_cache[cache_key] as Dictionary

	var rotated_texture: Texture2D = base_result.get("texture") as Texture2D
	if rotated_texture == null:
		return base_result
	var output: Image = rotated_texture.get_image()
	var source: Image = texture.get_image()
	if output == null or source == null or output.is_empty() or source.is_empty():
		return base_result
	if output.is_compressed():
		output.decompress()
	if source.is_compressed():
		source.decompress()
	if output.get_format() != Image.FORMAT_RGBA8:
		output.convert(Image.FORMAT_RGBA8)
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)

	var source_to_output: Transform2D = base_result.get("anchor_transform", Transform2D.IDENTITY) as Transform2D
	_cleanup_generated_artifacts(output, source, source_to_output)

	var result: Dictionary = base_result.duplicate()
	result["texture"] = ImageTexture.create_from_image(output)
	cleanup_rotation_cache[cache_key] = result
	return result


func _cleanup_generated_artifacts(
	image: Image,
	source: Image,
	source_to_output: Transform2D
) -> void:
	var size_value: Vector2i = image.get_size()
	var pixel_count: int = size_value.x * size_value.y
	var alpha_mask: PackedByteArray = PackedByteArray()
	var source_support: PackedByteArray = PackedByteArray()
	alpha_mask.resize(pixel_count)
	source_support.resize(pixel_count)
	var output_to_source: Transform2D = source_to_output.affine_inverse()

	for y_value: int in range(size_value.y):
		for x_value: int in range(size_value.x):
			var index: int = y_value * size_value.x + x_value
			if image.get_pixel(x_value, y_value).a <= 0.05:
				continue
			alpha_mask[index] = 1
			source_support[index] = _source_support_count(
				source,
				output_to_source,
				x_value,
				y_value
			)

	_remove_unsupported_micro_components(image, alpha_mask, source_support, size_value)

	# Two conservative pruning passes remove one- and two-pixel spurs. Each pixel
	# must have weak source support and be removable without disconnecting the local silhouette.
	for _pass_index: int in range(2):
		var remove_mask: PackedByteArray = PackedByteArray()
		remove_mask.resize(pixel_count)
		var removal_count: int = 0
		for y_value: int in range(size_value.y):
			for x_value: int in range(size_value.x):
				var index: int = y_value * size_value.x + x_value
				if alpha_mask[index] == 0 or source_support[index] >= 2:
					continue
				if not _is_mask_boundary(alpha_mask, size_value, x_value, y_value):
					continue
				var neighbor_count: int = _count_mask_neighbors(alpha_mask, size_value, x_value, y_value)
				var cardinal_count: int = _count_cardinal_neighbors(alpha_mask, size_value, x_value, y_value)
				var exposed_sides: int = 8 - neighbor_count
				var short_spur: bool = neighbor_count <= 2
				var pointed_ear: bool = neighbor_count <= 3 and cardinal_count <= 1 and exposed_sides >= 5
				if not short_spur and not pointed_ear:
					continue
				if _is_local_bridge(alpha_mask, size_value, x_value, y_value):
					continue
				remove_mask[index] = 1
				removal_count += 1
		if removal_count == 0:
			break
		for index: int in range(pixel_count):
			if remove_mask[index] == 0:
				continue
			alpha_mask[index] = 0
			image.set_pixel(index % size_value.x, index / size_value.x, Color.TRANSPARENT)


func _source_support_count(
	source: Image,
	output_to_source: Transform2D,
	x_value: int,
	y_value: int
) -> int:
	var support: int = 0
	for sample_offset: Vector2 in CLEANUP_SOURCE_SAMPLES:
		var output_sample: Vector2 = Vector2(float(x_value), float(y_value)) + sample_offset
		var source_sample: Vector2 = output_to_source * output_sample
		var source_x: int = floori(source_sample.x)
		var source_y: int = floori(source_sample.y)
		if source_x < 0 or source_y < 0 or source_x >= source.get_width() or source_y >= source.get_height():
			continue
		if source.get_pixel(source_x, source_y).a > 0.05:
			support += 1
	return support


func _remove_unsupported_micro_components(
	image: Image,
	alpha_mask: PackedByteArray,
	source_support: PackedByteArray,
	size_value: Vector2i
) -> void:
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(alpha_mask.size())
	var components: Array[Dictionary] = []
	var largest_size: int = 0
	for start_index: int in range(alpha_mask.size()):
		if alpha_mask[start_index] == 0 or visited[start_index] > 0:
			continue
		var queue: Array[int] = [start_index]
		var pixels: Array[int] = []
		var strong_support: bool = false
		visited[start_index] = 1
		while not queue.is_empty():
			var index: int = queue.pop_back()
			pixels.append(index)
			if source_support[index] >= 2:
				strong_support = true
			var x_value: int = index % size_value.x
			var y_value: int = index / size_value.x
			for offset_y: int in range(-1, 2):
				for offset_x: int in range(-1, 2):
					if offset_x == 0 and offset_y == 0:
						continue
					var nx: int = x_value + offset_x
					var ny: int = y_value + offset_y
					if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
						continue
					var neighbor_index: int = ny * size_value.x + nx
					if alpha_mask[neighbor_index] == 0 or visited[neighbor_index] > 0:
						continue
					visited[neighbor_index] = 1
					queue.append(neighbor_index)
		largest_size = maxi(largest_size, pixels.size())
		components.append({"pixels": pixels, "supported": strong_support})

	var micro_limit: int = maxi(2, int(round(float(largest_size) * 0.0025)))
	for component_value: Variant in components:
		var component: Dictionary = component_value as Dictionary
		var pixels: Array = component.get("pixels", []) as Array
		if bool(component.get("supported", false)) or pixels.size() > micro_limit:
			continue
		for pixel_value: Variant in pixels:
			var index: int = int(pixel_value)
			alpha_mask[index] = 0
			image.set_pixel(index % size_value.x, index / size_value.x, Color.TRANSPARENT)


func _count_cardinal_neighbors(
	mask: PackedByteArray,
	size_value: Vector2i,
	x_value: int,
	y_value: int
) -> int:
	var count: int = 0
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var nx: int = x_value + offset.x
		var ny: int = y_value + offset.y
		if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
			continue
		if mask[ny * size_value.x + nx] > 0:
			count += 1
	return count


func _is_local_bridge(
	mask: PackedByteArray,
	size_value: Vector2i,
	x_value: int,
	y_value: int
) -> bool:
	var occupied: Array[Vector2i] = []
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			var nx: int = x_value + offset_x
			var ny: int = y_value + offset_y
			if nx < 0 or ny < 0 or nx >= size_value.x or ny >= size_value.y:
				continue
			if mask[ny * size_value.x + nx] > 0:
				occupied.append(Vector2i(offset_x, offset_y))
	if occupied.size() <= 1:
		return false

	var visited: Dictionary = {}
	var components: int = 0
	for start: Vector2i in occupied:
		if visited.has(start):
			continue
		components += 1
		if components > 1:
			return true
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			for candidate: Vector2i in occupied:
				if visited.has(candidate):
					continue
				var delta: Vector2i = candidate - current
				if absi(delta.x) <= 1 and absi(delta.y) <= 1:
					visited[candidate] = true
					queue.append(candidate)
	return false


func _resolved_transform(target_frame: int, bone_id: String) -> Dictionary:
	if not _tween_enabled():
		return super._resolved_transform(target_frame, bone_id)
	return _tweened_transform(target_frame, bone_id)


func _tween_enabled() -> bool:
	var playback_data: Dictionary = document.get("playback", {}) as Dictionary
	return bool(playback_data.get("tween_enabled", false))


func _tweened_transform(target_frame: int, bone_id: String) -> Dictionary:
	var bone_data: Dictionary = _bone_by_id(bone_id)
	var rest_data: Dictionary = bone_data.get("rest", {}) as Dictionary
	var frames_value: Array = _frames()
	if frames_value.is_empty():
		return rest_data.duplicate(true)
	var safe_frame: int = clampi(target_frame, 0, frames_value.size() - 1)
	var exact_keys: Dictionary = (frames_value[safe_frame] as Dictionary).get("keys", {}) as Dictionary
	if exact_keys.has(bone_id):
		return (exact_keys[bone_id] as Dictionary).duplicate(true)

	var previous_index: int = -1
	var next_index: int = -1
	for index: int in range(safe_frame - 1, -1, -1):
		var keys: Dictionary = (frames_value[index] as Dictionary).get("keys", {}) as Dictionary
		if keys.has(bone_id):
			previous_index = index
			break
	for index: int in range(safe_frame + 1, frames_value.size()):
		var keys: Dictionary = (frames_value[index] as Dictionary).get("keys", {}) as Dictionary
		if keys.has(bone_id):
			next_index = index
			break

	if previous_index < 0:
		return rest_data.duplicate(true)
	var previous_keys: Dictionary = (frames_value[previous_index] as Dictionary).get("keys", {}) as Dictionary
	var previous_data: Dictionary = (previous_keys[bone_id] as Dictionary).duplicate(true)
	if next_index < 0:
		return previous_data
	var next_keys: Dictionary = (frames_value[next_index] as Dictionary).get("keys", {}) as Dictionary
	var next_data: Dictionary = next_keys[bone_id] as Dictionary
	var ratio: float = float(safe_frame - previous_index) / float(next_index - previous_index)
	return _interpolate_transform(previous_data, next_data, ratio)


func _interpolate_transform(from_data: Dictionary, to_data: Dictionary, ratio: float) -> Dictionary:
	var t: float = clampf(ratio, 0.0, 1.0)
	var from_position: Vector2 = _vec(from_data.get("position", [0.0, 0.0]))
	var to_position: Vector2 = _vec(to_data.get("position", [0.0, 0.0]))
	var from_pivot: Vector2 = _vec(from_data.get("pivot", [0.0, 0.0]))
	var to_pivot: Vector2 = _vec(to_data.get("pivot", [0.0, 0.0]))
	var from_angle: float = deg_to_rad(float(from_data.get("rotation_degrees", 0.0)))
	var to_angle: float = deg_to_rad(float(to_data.get("rotation_degrees", 0.0)))
	var angle_delta: float = wrapf(to_angle - from_angle, -PI, PI)
	var position_value: Vector2 = from_position.lerp(to_position, t)
	var pivot_value: Vector2 = from_pivot.lerp(to_pivot, t)
	if pixel_snap:
		position_value = position_value.round()
		pivot_value = pivot_value.round()
	return {
		"position": [position_value.x, position_value.y],
		"rotation_degrees": rad_to_deg(from_angle + angle_delta * t),
		"pivot": [pivot_value.x, pivot_value.y],
		"z_index": int(from_data.get("z_index", 0)),
		"visible": bool(from_data.get("visible", true)),
	}
