extends Control

signal frame_clicked(frame_index: int, mouse_button: int)

var texture: Texture2D
var columns := 0
var rows := 0
var selected_frames: Array = []


func set_preview_data(new_texture: Texture2D, new_columns: int, new_rows: int) -> void:
	texture = new_texture
	columns = max(new_columns, 0)
	rows = max(new_rows, 0)
	queue_redraw()


func clear_preview() -> void:
	texture = null
	columns = 0
	rows = 0
	selected_frames.clear()
	queue_redraw()


func set_selected_frames(frames: Array) -> void:
	selected_frames = frames.duplicate()
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return

	var target_rect := _get_target_rect()
	draw_texture_rect(texture, target_rect, false)

	if columns <= 0 or rows <= 0:
		return

	var cell_width := target_rect.size.x / float(columns)
	var cell_height := target_rect.size.y / float(rows)
	var line_color := Color(1.0, 0.92, 0.35, 0.85)
	var highlight_color := Color(0.2, 0.75, 1.0, 0.32)

	for row in range(rows):
		for column in range(columns):
			var frame_index := (row * columns) + column
			if selected_frames.has(frame_index):
				var cell_position := Vector2(
					target_rect.position.x + (cell_width * column),
					target_rect.position.y + (cell_height * row)
				)
				draw_rect(Rect2(cell_position, Vector2(cell_width, cell_height)), highlight_color, true)

	for column in range(columns + 1):
		var x := target_rect.position.x + (cell_width * column)
		draw_line(Vector2(x, target_rect.position.y), Vector2(x, target_rect.position.y + target_rect.size.y), line_color, 1.0)

	for row in range(rows + 1):
		var y := target_rect.position.y + (cell_height * row)
		draw_line(Vector2(target_rect.position.x, y), Vector2(target_rect.position.x + target_rect.size.x, y), line_color, 1.0)

	var font := get_theme_default_font()
	var font_size := 12
	for row in range(rows):
		for column in range(columns):
			var frame_index := (row * columns) + column
			var text_position := Vector2(
				target_rect.position.x + (cell_width * column) + 3.0,
				target_rect.position.y + (cell_height * row) + float(font_size) + 2.0
			)
			draw_string(font, text_position + Vector2(1, 1), str(frame_index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
			draw_string(font, text_position, str(frame_index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))

			var order_text := _get_frame_order_text(frame_index)
			if not order_text.is_empty():
				var order_position := Vector2(
					target_rect.position.x + (cell_width * column) + 3.0,
					target_rect.position.y + (cell_height * row) + cell_height - 4.0
				)
				draw_string(font, order_position + Vector2(1, 1), order_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
				draw_string(font, order_position, order_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.2, 0.9, 1.0, 0.95))


func _gui_input(event: InputEvent) -> void:
	if texture == null or columns <= 0 or rows <= 0:
		return

	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var frame_index := _get_frame_index_at_position(mouse_event.position)
	if frame_index < 0:
		return

	frame_clicked.emit(frame_index, mouse_event.button_index)
	accept_event()


func _get_target_rect() -> Rect2:
	var texture_size: Vector2 = texture.get_size()
	var available_size: Vector2 = size
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		available_size = custom_minimum_size

	var scale_factor: float = min(available_size.x / texture_size.x, available_size.y / texture_size.y)
	var draw_size: Vector2 = texture_size * scale_factor
	var draw_position: Vector2 = (available_size - draw_size) * 0.5
	return Rect2(draw_position, draw_size)


func _get_frame_index_at_position(local_position: Vector2) -> int:
	var target_rect := _get_target_rect()
	if not target_rect.has_point(local_position):
		return -1

	var cell_width := target_rect.size.x / float(columns)
	var cell_height := target_rect.size.y / float(rows)
	var column := int((local_position.x - target_rect.position.x) / cell_width)
	var row := int((local_position.y - target_rect.position.y) / cell_height)
	if column < 0 or column >= columns or row < 0 or row >= rows:
		return -1

	return (row * columns) + column


func _get_frame_order_text(frame_index: int) -> String:
	var order_numbers := []
	for index in range(selected_frames.size()):
		if int(selected_frames[index]) == frame_index:
			order_numbers.append(str(index + 1))

	return ",".join(order_numbers)
