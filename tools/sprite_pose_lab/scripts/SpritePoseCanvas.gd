extends Node2D

const PART_NAMES := [
	"head",
	"torso",
	"left_arm",
	"right_arm",
	"left_leg",
	"right_leg",
]

const PLACEHOLDER_COLORS := {
	"head": Color("d5c0a1"),
	"torso": Color("6f7f65"),
	"left_arm": Color("839276"),
	"right_arm": Color("576451"),
	"left_leg": Color("4b5363"),
	"right_leg": Color("363c49"),
}

var canvas_size := Vector2i(64, 64)
var feet_y := 60
var show_checkerboard := true
var show_grid := false
var show_axis := true
var show_feet_line := true
var export_mode := false

var _parts_root: Node2D
var _onion_root: Node2D
var _part_nodes: Dictionary = {}
var _onion_nodes: Dictionary = {}
var _texture_cache: Dictionary = {}
var _placeholder_cache: Dictionary = {}


func _ready() -> void:
	_build_part_nodes()
	queue_redraw()


func configure(new_canvas_size: Vector2i, new_feet_y: int) -> void:
	canvas_size = Vector2i(maxi(1, new_canvas_size.x), maxi(1, new_canvas_size.y))
	feet_y = clampi(new_feet_y, 0, canvas_size.y - 1)
	queue_redraw()


func set_guides(checkerboard: bool, grid: bool, axis: bool, foot_line: bool) -> void:
	show_checkerboard = checkerboard
	show_grid = grid
	show_axis = axis
	show_feet_line = foot_line
	queue_redraw()


func set_export_mode(enabled: bool) -> void:
	export_mode = enabled
	if _onion_root != null:
		_onion_root.visible = not enabled
	queue_redraw()


func apply_pose(frame_data: Dictionary, part_library: Dictionary, previous_frame: Dictionary = {}, onion_enabled: bool = false) -> void:
	if _parts_root == null:
		_build_part_nodes()

	var direction := str(frame_data.get("direction", "south"))
	var direction_library: Dictionary = part_library.get(direction, {})
	var parts: Dictionary = frame_data.get("parts", {})

	for part_name in PART_NAMES:
		var part_data: Dictionary = parts.get(part_name, {})
		_apply_part(_part_nodes[part_name], part_name, part_data, direction_library)

	_apply_onion(previous_frame, part_library, onion_enabled)


func clear_texture_cache() -> void:
	_texture_cache.clear()


func _build_part_nodes() -> void:
	if _parts_root != null:
		return

	_onion_root = Node2D.new()
	_onion_root.name = "OnionSkin"
	_onion_root.modulate = Color(0.55, 0.75, 1.0, 0.26)
	add_child(_onion_root)

	_parts_root = Node2D.new()
	_parts_root.name = "Parts"
	add_child(_parts_root)

	for part_name in PART_NAMES:
		var onion_sprite := Sprite2D.new()
		onion_sprite.name = "%sOnion" % _display_name(part_name)
		onion_sprite.centered = true
		onion_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		onion_sprite.visible = false
		_onion_root.add_child(onion_sprite)
		_onion_nodes[part_name] = onion_sprite

		var sprite := Sprite2D.new()
		sprite.name = _display_name(part_name)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_parts_root.add_child(sprite)
		_part_nodes[part_name] = sprite


func _apply_part(sprite: Sprite2D, part_name: String, part_data: Dictionary, direction_library: Dictionary) -> void:
	var position_values := _vector_from_json(part_data.get("position", [0.0, 0.0]))
	var pivot_values := _vector_from_json(part_data.get("pivot", [0.0, 0.0]))
	var texture_path := str(direction_library.get(part_name, ""))

	sprite.position = Vector2(canvas_size) * 0.5 + position_values
	sprite.rotation_degrees = float(part_data.get("rotation_degrees", 0.0))
	sprite.offset = -pivot_values
	sprite.z_index = int(part_data.get("z_index", 0))
	sprite.visible = bool(part_data.get("visible", true))
	sprite.texture = _load_texture(texture_path, part_name)


func _apply_onion(previous_frame: Dictionary, part_library: Dictionary, enabled: bool) -> void:
	if _onion_root == null:
		return

	_onion_root.visible = enabled and not export_mode and not previous_frame.is_empty()
	if not _onion_root.visible:
		for part_name in PART_NAMES:
			_onion_nodes[part_name].visible = false
		return

	var direction := str(previous_frame.get("direction", "south"))
	var direction_library: Dictionary = part_library.get(direction, {})
	var parts: Dictionary = previous_frame.get("parts", {})

	for part_name in PART_NAMES:
		var sprite: Sprite2D = _onion_nodes[part_name]
		var part_data: Dictionary = parts.get(part_name, {})
		var position_values := _vector_from_json(part_data.get("position", [0.0, 0.0]))
		var pivot_values := _vector_from_json(part_data.get("pivot", [0.0, 0.0]))
		var texture_path := str(direction_library.get(part_name, ""))

		sprite.position = Vector2(canvas_size) * 0.5 + position_values
		sprite.rotation_degrees = float(part_data.get("rotation_degrees", 0.0))
		sprite.offset = -pivot_values
		sprite.z_index = int(part_data.get("z_index", 0)) - 1000
		sprite.visible = bool(part_data.get("visible", true))
		sprite.texture = _load_texture(texture_path, part_name)


func _load_texture(path: String, part_name: String) -> Texture2D:
	if path.is_empty():
		return _placeholder_texture(part_name)

	if _texture_cache.has(path):
		return _texture_cache[path]

	var texture: Texture2D
	if path.begins_with("res://") or path.begins_with("user://"):
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
	else:
		var image := Image.new()
		if image.load(path) == OK:
			texture = ImageTexture.create_from_image(image)

	if texture == null:
		push_warning("SpritePoseLab could not load texture: %s" % path)
		texture = _placeholder_texture(part_name)

	_texture_cache[path] = texture
	return texture


func _placeholder_texture(part_name: String) -> Texture2D:
	if _placeholder_cache.has(part_name):
		return _placeholder_cache[part_name]

	var image_size := Vector2i(12, 12)
	match part_name:
		"head":
			image_size = Vector2i(18, 18)
		"torso":
			image_size = Vector2i(16, 18)
		"left_arm", "right_arm":
			image_size = Vector2i(7, 18)
		"left_leg", "right_leg":
			image_size = Vector2i(7, 16)

	var image := Image.create_empty(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var color: Color = PLACEHOLDER_COLORS.get(part_name, Color.WHITE)
	var rect := Rect2i(1, 1, image_size.x - 2, image_size.y - 2)
	image.fill_rect(rect, color)

	var outline := color.darkened(0.42)
	for x in range(1, image_size.x - 1):
		image.set_pixel(x, 1, outline)
		image.set_pixel(x, image_size.y - 2, outline)
	for y in range(1, image_size.y - 1):
		image.set_pixel(1, y, outline)
		image.set_pixel(image_size.x - 2, y, outline)

	var texture := ImageTexture.create_from_image(image)
	_placeholder_cache[part_name] = texture
	return texture


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
		_draw_feet_line()


func _draw_checkerboard() -> void:
	var cell_size := 8
	var color_a := Color(0.12, 0.13, 0.15, 1.0)
	var color_b := Color(0.18, 0.19, 0.22, 1.0)
	for y in range(0, canvas_size.y, cell_size):
		for x in range(0, canvas_size.x, cell_size):
			var checker := int(x / cell_size) + int(y / cell_size)
			var color := color_a if checker % 2 == 0 else color_b
			var width := mini(cell_size, canvas_size.x - x)
			var height := mini(cell_size, canvas_size.y - y)
			draw_rect(Rect2(x, y, width, height), color)


func _draw_grid() -> void:
	var color := Color(1.0, 1.0, 1.0, 0.08)
	for x in range(canvas_size.x + 1):
		draw_line(Vector2(x, 0), Vector2(x, canvas_size.y), color, 1.0)
	for y in range(canvas_size.y + 1):
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), color, 1.0)


func _draw_axis() -> void:
	var center := Vector2(canvas_size) * 0.5
	draw_line(Vector2(center.x, 0), Vector2(center.x, canvas_size.y), Color(0.3, 0.75, 1.0, 0.5), 1.0)
	draw_line(Vector2(0, center.y), Vector2(canvas_size.x, center.y), Color(0.3, 0.75, 1.0, 0.25), 1.0)


func _draw_feet_line() -> void:
	draw_line(Vector2(0, feet_y), Vector2(canvas_size.x, feet_y), Color(1.0, 0.48, 0.28, 0.9), 1.0)


func _vector_from_json(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	return Vector2.ZERO


func _display_name(part_name: String) -> String:
	return part_name.capitalize().replace("_", "")
