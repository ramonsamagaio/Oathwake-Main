class_name SpritePoseCanvasV2
extends Node2D

const HANDLE_MOVE := "move"
const HANDLE_ROTATE := "rotate"
const HANDLE_PIVOT := "pivot"

var project
var canvas_size := Vector2i(64, 64)
var feet_y := 60
var selected_bone_id := "torso"
var frame_index := 0
var export_mode := false
var pixel_snap := true

var show_checkerboard := true
var show_grid := false
var show_axis := true
var show_feet_line := true
var show_gizmo := true
var previous_enabled := true
var next_enabled := true
var previous_opacity := 0.28
var next_opacity := 0.28

var _current_root: Node2D
var _previous_root: Node2D
var _next_root: Node2D
var _current_nodes: Dictionary = {}
var _current_sprites: Dictionary = {}
var _previous_nodes: Dictionary = {}
var _previous_sprites: Dictionary = {}
var _next_nodes: Dictionary = {}
var _next_sprites: Dictionary = {}
var _texture_cache: Dictionary = {}
var _placeholder_cache: Dictionary = {}
var _rig_signature := ""

var _gizmo_root: Node2D
var _gizmo_lines: Line2D
var _move_handle: Polygon2D
var _pivot_handle: Polygon2D
var _rotate_handle: Polygon2D


func _ready() -> void:
	_build_roots()
	queue_redraw()


func set_project(value) -> void:
	var project_changed := project != value
	project = value
	canvas_size = project.canvas_size
	feet_y = project.feet_y
	_rebuild_if_needed(project_changed)


func configure(new_size: Vector2i, new_feet_y: int) -> void:
	canvas_size = Vector2i(maxi(1, new_size.x), maxi(1, new_size.y))
	feet_y = clampi(new_feet_y, 0, canvas_size.y - 1)
	queue_redraw()


func set_editor_settings(settings: Dictionary) -> void:
	show_checkerboard = bool(settings.get("checkerboard", true))
	show_grid = bool(settings.get("grid", false))
	show_axis = bool(settings.get("axis", true))
	show_feet_line = bool(settings.get("feet_line", true))
	show_gizmo = bool(settings.get("gizmo", true))
	pixel_snap = bool(settings.get("pixel_snap", true))
	previous_enabled = bool(settings.get("previous_enabled", true))
	next_enabled = bool(settings.get("next_enabled", true))
	previous_opacity = clampf(float(settings.get("previous_opacity", 0.28)), 0.0, 1.0)
	next_opacity = clampf(float(settings.get("next_opacity", 0.28)), 0.0, 1.0)
	queue_redraw()


func set_export_mode(enabled: bool) -> void:
	export_mode = enabled
	if _gizmo_root != null:
		_gizmo_root.visible = not enabled and show_gizmo
	if _previous_root != null:
		_previous_root.visible = not enabled and previous_enabled and frame_index > 0
	if _next_root != null:
		_next_root.visible = not enabled and next_enabled and project != null and frame_index < project.frame_count() - 1
	queue_redraw()


func apply_frame(new_frame_index: int, new_selected_bone_id: String) -> void:
	if project == null:
		return
	frame_index = clampi(new_frame_index, 0, maxi(0, project.frame_count() - 1))
	selected_bone_id = new_selected_bone_id
	configure(project.canvas_size, project.feet_y)
	_rebuild_if_needed(false)
	_apply_instance(_current_nodes, _current_sprites, frame_index, Color.WHITE)
	var has_previous := frame_index > 0
	var has_next := frame_index < project.frame_count() - 1
	_previous_root.visible = not export_mode and previous_enabled and has_previous
	_next_root.visible = not export_mode and next_enabled and has_next
	if has_previous:
		_apply_instance(
			_previous_nodes,
			_previous_sprites,
			frame_index - 1,
			Color(1.0, 0.16, 0.16, previous_opacity)
		)
	if has_next:
		_apply_instance(
			_next_nodes,
			_next_sprites,
			frame_index + 1,
			Color(0.18, 1.0, 0.32, next_opacity)
		)
	_update_gizmo()
	queue_redraw()


func clear_texture_cache() -> void:
	_texture_cache.clear()
	_placeholder_cache.clear()
	if project != null:
		_apply_instance(_current_nodes, _current_sprites, frame_index, Color.WHITE)


func _build_roots() -> void:
	if _previous_root != null:
		return
	_previous_root = Node2D.new()
	_previous_root.name = "PreviousOnion"
	_previous_root.z_index = -2000
	add_child(_previous_root)
	_next_root = Node2D.new()
	_next_root.name = "NextOnion"
	_next_root.z_index = -1900
	add_child(_next_root)
	_current_root = Node2D.new()
	_current_root.name = "CurrentPose"
	add_child(_current_root)
	_build_gizmo()


func _build_gizmo() -> void:
	_gizmo_root = Node2D.new()
	_gizmo_root.name = "Gizmo"
	_gizmo_root.z_index = 4095
	add_child(_gizmo_root)
	_gizmo_lines = Line2D.new()
	_gizmo_lines.width = 1.0
	_gizmo_lines.antialiased = false
	_gizmo_lines.default_color = Color(0.25, 0.9, 1.0, 0.9)
	_gizmo_root.add_child(_gizmo_lines)
	_move_handle = _make_square_handle(Color(0.2, 1.0, 0.38, 0.95), 2.4)
	_gizmo_root.add_child(_move_handle)
	_pivot_handle = _make_diamond_handle(Color(1.0, 0.82, 0.15, 0.98), 2.8)
	_gizmo_root.add_child(_pivot_handle)
	_rotate_handle = _make_square_handle(Color(1.0, 0.25, 0.2, 0.98), 2.4)
	_gizmo_root.add_child(_rotate_handle)


func _make_square_handle(color: Color, radius: float) -> Polygon2D:
	var handle := Polygon2D.new()
	handle.polygon = PackedVector2Array([
		Vector2(-radius, -radius),
		Vector2(radius, -radius),
		Vector2(radius, radius),
		Vector2(-radius, radius),
	])
	handle.color = color
	return handle


func _make_diamond_handle(color: Color, radius: float) -> Polygon2D:
	var handle := Polygon2D.new()
	handle.polygon = PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius, 0),
		Vector2(0, radius),
		Vector2(-radius, 0),
	])
	handle.color = color
	return handle


func _rebuild_if_needed(force: bool) -> void:
	if project == null:
		return
	var signature := ",".join(project.bone_ids())
	for bone in project.bones:
		signature += "|%s>%s" % [str(bone.get("id", "")), str(bone.get("parent", ""))]
	if not force and signature == _rig_signature:
		return
	_rig_signature = signature
	_clear_children(_current_root)
	_clear_children(_previous_root)
	_clear_children(_next_root)
	_current_nodes.clear()
	_current_sprites.clear()
	_previous_nodes.clear()
	_previous_sprites.clear()
	_next_nodes.clear()
	_next_sprites.clear()
	_build_instance(_current_root, _current_nodes, _current_sprites)
	_build_instance(_previous_root, _previous_nodes, _previous_sprites)
	_build_instance(_next_root, _next_nodes, _next_sprites)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _build_instance(container: Node2D, node_map: Dictionary, sprite_map: Dictionary) -> void:
	var pending := project.bones.duplicate(true)
	var guard := 0
	while not pending.is_empty() and guard < project.bones.size() * 3:
		guard += 1
		for index in range(pending.size() - 1, -1, -1):
			var bone: Dictionary = pending[index]
			var bone_id := str(bone.get("id", ""))
			var parent_id := str(bone.get("parent", ""))
			if not parent_id.is_empty() and not node_map.has(parent_id):
				continue
			var bone_node := Node2D.new()
			bone_node.name = bone_id
			if parent_id.is_empty():
				container.add_child(bone_node)
			else:
				node_map[parent_id].add_child(bone_node)
			node_map[bone_id] = bone_node
			if bool(bone.get("has_sprite", true)):
				var sprite := Sprite2D.new()
				sprite.name = "Sprite"
				sprite.centered = true
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				bone_node.add_child(sprite)
				sprite_map[bone_id] = sprite
			pending.remove_at(index)
	if not pending.is_empty():
		for bone in pending:
			var fallback_id := str(bone.get("id", "bone"))
			var fallback_node := Node2D.new()
			fallback_node.name = fallback_id
			container.add_child(fallback_node)
			node_map[fallback_id] = fallback_node


func _apply_instance(
	node_map: Dictionary,
	sprite_map: Dictionary,
	index: int,
	modulate_color: Color
) -> void:
	for bone in project.bones:
		var bone_id := str(bone.get("id", ""))
		if not node_map.has(bone_id):
			continue
		var transform_data := project.resolved_transform(index, bone_id)
		var local_position := _vector_from(transform_data.get("position", [0.0, 0.0]))
		var pivot := _vector_from(transform_data.get("pivot", [0.0, 0.0]))
		if pixel_snap:
			local_position = local_position.round()
			pivot = pivot.round()
		var bone_node: Node2D = node_map[bone_id]
		bone_node.position = local_position
		if str(bone.get("parent", "")).is_empty():
			bone_node.position += Vector2(canvas_size) * 0.5
		bone_node.rotation_degrees = float(transform_data.get("rotation_degrees", 0.0))
		bone_node.z_index = clampi(int(transform_data.get("z_index", 0)), -4096, 4095)
		bone_node.visible = bool(transform_data.get("visible", true))
		if sprite_map.has(bone_id):
			var sprite: Sprite2D = sprite_map[bone_id]
			sprite.offset = -pivot
			sprite.texture = _load_texture(project.texture_path(project.current_direction, bone_id), bone_id)
			sprite.modulate = modulate_color


func _load_texture(path: String, bone_id: String) -> Texture2D:
	if path.is_empty():
		return _placeholder_texture(bone_id)
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
	else:
		var image := Image.new()
		if image.load(path) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		texture = _placeholder_texture(bone_id)
	_texture_cache[path] = texture
	return texture


func _placeholder_texture(bone_id: String) -> Texture2D:
	if _placeholder_cache.has(bone_id):
		return _placeholder_cache[bone_id]
	var size := Vector2i(12, 12)
	if bone_id.contains("head"):
		size = Vector2i(18, 18)
	elif bone_id.contains("torso") or bone_id.contains("body"):
		size = Vector2i(16, 18)
	elif bone_id.contains("arm"):
		size = Vector2i(7, 18)
	elif bone_id.contains("leg"):
		size = Vector2i(7, 16)
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var seed := abs(bone_id.hash())
	var color := Color.from_hsv(float(seed % 360) / 360.0, 0.35, 0.75, 1.0)
	image.fill_rect(Rect2i(1, 1, size.x - 2, size.y - 2), color)
	var outline := color.darkened(0.48)
	for x in range(1, size.x - 1):
		image.set_pixel(x, 1, outline)
		image.set_pixel(x, size.y - 2, outline)
	for y in range(1, size.y - 1):
		image.set_pixel(1, y, outline)
		image.set_pixel(size.x - 2, y, outline)
	var texture := ImageTexture.create_from_image(image)
	_placeholder_cache[bone_id] = texture
	return texture


func _update_gizmo() -> void:
	if _gizmo_root == null:
		return
	var visible_now := not export_mode and show_gizmo and _current_nodes.has(selected_bone_id)
	_gizmo_root.visible = visible_now
	if not visible_now:
		return
	var pivot_position := bone_canvas_position(selected_bone_id)
	var visual_center := bone_visual_center(selected_bone_id)
	var rotate_position := rotation_handle_position(selected_bone_id)
	_move_handle.position = visual_center
	_pivot_handle.position = pivot_position
	_rotate_handle.position = rotate_position
	_gizmo_lines.points = PackedVector2Array([pivot_position, rotate_position])


func bone_canvas_position(bone_id: String) -> Vector2:
	if not _current_nodes.has(bone_id):
		return Vector2.ZERO
	return _current_nodes[bone_id].global_position


func bone_visual_center(bone_id: String) -> Vector2:
	if not _current_nodes.has(bone_id):
		return Vector2.ZERO
	var node: Node2D = _current_nodes[bone_id]
	var transform_data := project.resolved_transform(frame_index, bone_id)
	var pivot := _vector_from(transform_data.get("pivot", [0.0, 0.0]))
	return node.global_position + (-pivot).rotated(node.global_rotation)


func rotation_handle_position(bone_id: String) -> Vector2:
	if not _current_nodes.has(bone_id):
		return Vector2.ZERO
	var node: Node2D = _current_nodes[bone_id]
	var radius := 14.0
	if _current_sprites.has(bone_id):
		var sprite: Sprite2D = _current_sprites[bone_id]
		if sprite.texture != null:
			var texture_size := sprite.texture.get_size()
			radius = maxf(texture_size.x, texture_size.y) * 0.5 + 8.0
	return node.global_position + Vector2(0, -radius).rotated(node.global_rotation)


func hit_test_handle(canvas_position: Vector2, force_pivot: bool = false) -> String:
	if not show_gizmo or export_mode:
		return ""
	if force_pivot and canvas_position.distance_to(bone_canvas_position(selected_bone_id)) <= 6.0:
		return HANDLE_PIVOT
	if canvas_position.distance_to(rotation_handle_position(selected_bone_id)) <= 6.0:
		return HANDLE_ROTATE
	if canvas_position.distance_to(bone_canvas_position(selected_bone_id)) <= 6.0:
		return HANDLE_PIVOT
	if canvas_position.distance_to(bone_visual_center(selected_bone_id)) <= 8.0:
		return HANDLE_MOVE
	return ""


func hit_test_bone(canvas_position: Vector2) -> String:
	var ordered := project.bones.duplicate(true)
	ordered.sort_custom(func(a, b):
		var a_id := str(a.get("id", ""))
		var b_id := str(b.get("id", ""))
		var a_z := int(project.resolved_transform(frame_index, a_id).get("z_index", 0))
		var b_z := int(project.resolved_transform(frame_index, b_id).get("z_index", 0))
		return a_z > b_z
	)
	for bone in ordered:
		var bone_id := str(bone.get("id", ""))
		if not _current_sprites.has(bone_id):
			continue
		var sprite: Sprite2D = _current_sprites[bone_id]
		if sprite.texture == null or not sprite.visible:
			continue
		var local := sprite.to_local(canvas_position)
		var rect := sprite.get_rect()
		if rect.has_point(local):
			return bone_id
	return ""


func canvas_delta_to_parent_local(bone_id: String, delta: Vector2) -> Vector2:
	var bone := project.bone_by_id(bone_id)
	var parent_id := str(bone.get("parent", ""))
	if parent_id.is_empty() or not _current_nodes.has(parent_id):
		return delta
	var parent_node: Node2D = _current_nodes[parent_id]
	return delta.rotated(-parent_node.global_rotation)


func selected_global_rotation() -> float:
	if not _current_nodes.has(selected_bone_id):
		return 0.0
	return _current_nodes[selected_bone_id].global_rotation


func _draw() -> void:
	if export_mode:
		return
	if show_checkerboard:
		_draw_checkerboard()
	if show_grid:
		_draw_grid()
	if show_axis:
		_draw_axis()
	if show_feet_line:
		draw_line(Vector2(0, feet_y), Vector2(canvas_size.x, feet_y), Color(1.0, 0.45, 0.25, 0.9), 1.0)


func _draw_checkerboard() -> void:
	var cell_size := 8
	for y in range(0, canvas_size.y, cell_size):
		for x in range(0, canvas_size.x, cell_size):
			var even := (int(x / cell_size) + int(y / cell_size)) % 2 == 0
			var color := Color(0.11, 0.12, 0.14, 1.0) if even else Color(0.17, 0.18, 0.21, 1.0)
			draw_rect(
				Rect2(x, y, mini(cell_size, canvas_size.x - x), mini(cell_size, canvas_size.y - y)),
				color
			)


func _draw_grid() -> void:
	var color := Color(1.0, 1.0, 1.0, 0.07)
	for x in range(canvas_size.x + 1):
		draw_line(Vector2(x, 0), Vector2(x, canvas_size.y), color, 1.0)
	for y in range(canvas_size.y + 1):
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), color, 1.0)


func _draw_axis() -> void:
	var center := Vector2(canvas_size) * 0.5
	draw_line(Vector2(center.x, 0), Vector2(center.x, canvas_size.y), Color(0.25, 0.75, 1.0, 0.45), 1.0)
	draw_line(Vector2(0, center.y), Vector2(canvas_size.x, center.y), Color(0.25, 0.75, 1.0, 0.22), 1.0)


func _vector_from(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	return Vector2.ZERO
