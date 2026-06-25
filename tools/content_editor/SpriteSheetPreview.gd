extends Control

var texture: Texture2D
var columns := 0
var rows := 0


func set_preview_data(new_texture: Texture2D, new_columns: int, new_rows: int) -> void:
	texture = new_texture
	columns = max(new_columns, 0)
	rows = max(new_rows, 0)
	queue_redraw()


func clear_preview() -> void:
	texture = null
	columns = 0
	rows = 0
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


func _get_target_rect() -> Rect2:
	var texture_size := texture.get_size()
	var available_size := size
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		available_size = custom_minimum_size

	var scale_factor := min(available_size.x / texture_size.x, available_size.y / texture_size.y)
	var draw_size := texture_size * scale_factor
	var draw_position := (available_size - draw_size) * 0.5
	return Rect2(draw_position, draw_size)
