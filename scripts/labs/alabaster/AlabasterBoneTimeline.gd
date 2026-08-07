extends Control
class_name AlabasterBoneTimeline

signal frame_changed(frame: int)
signal bone_selected(bone_name: String)
signal key_selected(frame: int, bone_name: String)

const LABEL_WIDTH := 170.0
const RULER_HEIGHT := 28.0
const ROW_HEIGHT := 25.0
const SCROLLBAR_SIZE := 16.0
const PIXELS_PER_FRAME := 12.0
const KEY_RADIUS := 5.5
const COLOR_BG := Color("#151821")
const COLOR_ROW_A := Color("#1B1F29")
const COLOR_ROW_B := Color("#202530")
const COLOR_GRID := Color("#343B49")
const COLOR_TEXT := Color("#D7DCE7")
const COLOR_SELECTED := Color("#33475E")
const COLOR_PLAYHEAD := Color("#E45C55")
const COLOR_KEY_NORMAL := Color("#E99A3E")
const COLOR_KEY_TWEEN := Color("#9A6DDF")
const COLOR_KEY_OUTLINE := Color("#181A21")

var bone_names: Array[String] = []
var key_data: Dictionary = {}
var current_frame := 0
var frame_count := 120
var selected_bone := ""

var horizontal_scroll: HScrollBar
var vertical_scroll: VScrollBar


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(640, 230)
	_build_scrollbars()
	resized.connect(_update_scrollbars)
	_update_scrollbars()
	queue_redraw()


func _build_scrollbars() -> void:
	horizontal_scroll = HScrollBar.new()
	horizontal_scroll.name = "HorizontalTimelineScroll"
	horizontal_scroll.anchor_left = 0.0
	horizontal_scroll.anchor_right = 1.0
	horizontal_scroll.anchor_top = 1.0
	horizontal_scroll.anchor_bottom = 1.0
	horizontal_scroll.offset_left = LABEL_WIDTH
	horizontal_scroll.offset_right = -SCROLLBAR_SIZE
	horizontal_scroll.offset_top = -SCROLLBAR_SIZE
	horizontal_scroll.offset_bottom = 0.0
	horizontal_scroll.step = PIXELS_PER_FRAME
	horizontal_scroll.value_changed.connect(func(_value: float) -> void: queue_redraw())
	add_child(horizontal_scroll)

	vertical_scroll = VScrollBar.new()
	vertical_scroll.name = "VerticalBoneScroll"
	vertical_scroll.anchor_left = 1.0
	vertical_scroll.anchor_right = 1.0
	vertical_scroll.anchor_top = 0.0
	vertical_scroll.anchor_bottom = 1.0
	vertical_scroll.offset_left = -SCROLLBAR_SIZE
	vertical_scroll.offset_right = 0.0
	vertical_scroll.offset_top = RULER_HEIGHT
	vertical_scroll.offset_bottom = -SCROLLBAR_SIZE
	vertical_scroll.step = ROW_HEIGHT
	vertical_scroll.value_changed.connect(func(_value: float) -> void: queue_redraw())
	add_child(vertical_scroll)


func set_timeline_data(new_bones: Array, new_keys: Dictionary, new_current_frame: int, new_frame_count: int) -> void:
	bone_names.clear()
	for bone_value in new_bones:
		bone_names.append(str(bone_value))
	key_data = new_keys.duplicate(true)
	current_frame = maxi(new_current_frame, 0)
	frame_count = maxi(new_frame_count, current_frame + 1, 1)
	if selected_bone.is_empty() and not bone_names.is_empty():
		selected_bone = bone_names[0]
	_update_scrollbars()
	_ensure_playhead_visible()
	queue_redraw()


func set_current_frame(frame: int, ensure_visible := true) -> void:
	current_frame = clampi(frame, 0, maxi(frame_count, 1))
	if ensure_visible:
		_ensure_playhead_visible()
	queue_redraw()


func set_selected_bone(bone_name: String) -> void:
	selected_bone = bone_name
	_ensure_bone_visible(bone_name)
	queue_redraw()


func _update_scrollbars() -> void:
	if horizontal_scroll == null or vertical_scroll == null:
		return
	var timeline_view_width := maxf(size.x - LABEL_WIDTH - SCROLLBAR_SIZE, 1.0)
	var timeline_content_width := maxf(float(frame_count + 1) * PIXELS_PER_FRAME, timeline_view_width)
	horizontal_scroll.max_value = timeline_content_width
	horizontal_scroll.page = timeline_view_width
	horizontal_scroll.value = minf(horizontal_scroll.value, maxf(horizontal_scroll.max_value - horizontal_scroll.page, 0.0))

	var rows_view_height := maxf(size.y - RULER_HEIGHT - SCROLLBAR_SIZE, 1.0)
	var rows_content_height := maxf(float(bone_names.size()) * ROW_HEIGHT, rows_view_height)
	vertical_scroll.max_value = rows_content_height
	vertical_scroll.page = rows_view_height
	vertical_scroll.value = minf(vertical_scroll.value, maxf(vertical_scroll.max_value - vertical_scroll.page, 0.0))


func _ensure_playhead_visible() -> void:
	if horizontal_scroll == null:
		return
	var frame_x := float(current_frame) * PIXELS_PER_FRAME
	var left := horizontal_scroll.value
	var right := left + horizontal_scroll.page
	if frame_x < left:
		horizontal_scroll.value = frame_x
	elif frame_x > right - PIXELS_PER_FRAME * 2.0:
		horizontal_scroll.value = minf(frame_x - horizontal_scroll.page + PIXELS_PER_FRAME * 2.0, maxf(horizontal_scroll.max_value - horizontal_scroll.page, 0.0))


func _ensure_bone_visible(bone_name: String) -> void:
	if vertical_scroll == null:
		return
	var index := bone_names.find(bone_name)
	if index < 0:
		return
	var row_top := float(index) * ROW_HEIGHT
	var row_bottom := row_top + ROW_HEIGHT
	var top := vertical_scroll.value
	var bottom := top + vertical_scroll.page
	if row_top < top:
		vertical_scroll.value = row_top
	elif row_bottom > bottom:
		vertical_scroll.value = minf(row_bottom - vertical_scroll.page, maxf(vertical_scroll.max_value - vertical_scroll.page, 0.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	_draw_ruler()
	_draw_rows()
	_draw_playhead()


func _draw_ruler() -> void:
	var visible_start := int(floor(horizontal_scroll.value / PIXELS_PER_FRAME)) if horizontal_scroll != null else 0
	var visible_end := int(ceil((horizontal_scroll.value + maxf(size.x - LABEL_WIDTH, 0.0)) / PIXELS_PER_FRAME)) + 1 if horizontal_scroll != null else frame_count
	var scroll_x := horizontal_scroll.value if horizontal_scroll != null else 0.0

	draw_rect(Rect2(0.0, 0.0, LABEL_WIDTH, RULER_HEIGHT), Color("#10131A"))
	draw_string(get_theme_default_font(), Vector2(10.0, 19.0), "BONES", HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 20.0, 12, COLOR_TEXT)
	draw_rect(Rect2(LABEL_WIDTH, 0.0, maxf(size.x - LABEL_WIDTH, 0.0), RULER_HEIGHT), Color("#121620"))

	for frame in range(maxi(visible_start, 0), mini(visible_end, frame_count + 1)):
		var x := LABEL_WIDTH + float(frame) * PIXELS_PER_FRAME - scroll_x
		var major := frame % 5 == 0
		var line_h := 11.0 if major else 5.0
		draw_line(Vector2(x, RULER_HEIGHT - line_h), Vector2(x, RULER_HEIGHT), COLOR_GRID, 1.0)
		if major:
			draw_string(get_theme_default_font(), Vector2(x + 3.0, 17.0), str(frame), HORIZONTAL_ALIGNMENT_LEFT, 52.0, 10, COLOR_TEXT)


func _draw_rows() -> void:
	var scroll_y := vertical_scroll.value if vertical_scroll != null else 0.0
	var scroll_x := horizontal_scroll.value if horizontal_scroll != null else 0.0
	var rows_bottom := size.y - SCROLLBAR_SIZE
	var first_row := maxi(int(floor(scroll_y / ROW_HEIGHT)), 0)
	var last_row := mini(int(ceil((scroll_y + maxf(rows_bottom - RULER_HEIGHT, 0.0)) / ROW_HEIGHT)) + 1, bone_names.size())

	for row_index in range(first_row, last_row):
		var bone_name := bone_names[row_index]
		var y := RULER_HEIGHT + float(row_index) * ROW_HEIGHT - scroll_y
		var row_color := COLOR_ROW_A if row_index % 2 == 0 else COLOR_ROW_B
		if bone_name == selected_bone:
			row_color = COLOR_SELECTED
		draw_rect(Rect2(0.0, y, size.x - SCROLLBAR_SIZE, ROW_HEIGHT), row_color)
		draw_line(Vector2(0.0, y + ROW_HEIGHT), Vector2(size.x - SCROLLBAR_SIZE, y + ROW_HEIGHT), COLOR_GRID, 1.0)
		draw_line(Vector2(LABEL_WIDTH, y), Vector2(LABEL_WIDTH, y + ROW_HEIGHT), COLOR_GRID, 1.0)
		draw_string(get_theme_default_font(), Vector2(9.0, y + 17.0), bone_name, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 18.0, 11, COLOR_TEXT)

		for frame_value in key_data.keys():
			var frame := int(frame_value)
			var frame_data_value: Variant = key_data[frame_value]
			if not frame_data_value is Dictionary:
				continue
			var frame_data: Dictionary = frame_data_value
			var node_xfm_value: Variant = frame_data.get("nodeXfm", {})
			if not node_xfm_value is Dictionary:
				continue
			var node_xfm: Dictionary = node_xfm_value
			if not node_xfm.has(bone_name):
				continue
			var x := LABEL_WIDTH + float(frame) * PIXELS_PER_FRAME - scroll_x
			if x < LABEL_WIDTH - KEY_RADIUS or x > size.x - SCROLLBAR_SIZE + KEY_RADIUS:
				continue
			var center := Vector2(x, y + ROW_HEIGHT * 0.5)
			var spline := str(frame_data.get("spline", "LINEAR"))
			var color := COLOR_KEY_NORMAL if spline == "LINEAR" else COLOR_KEY_TWEEN
			_draw_diamond(center, KEY_RADIUS + 1.5, COLOR_KEY_OUTLINE)
			_draw_diamond(center, KEY_RADIUS, color)


func _draw_playhead() -> void:
	if horizontal_scroll == null:
		return
	var x := LABEL_WIDTH + float(current_frame) * PIXELS_PER_FRAME - horizontal_scroll.value
	if x < LABEL_WIDTH or x > size.x - SCROLLBAR_SIZE:
		return
	draw_line(Vector2(x, 0.0), Vector2(x, size.y - SCROLLBAR_SIZE), COLOR_PLAYHEAD, 1.5)
	var marker := PackedVector2Array([
		Vector2(x - 5.0, 0.0),
		Vector2(x + 5.0, 0.0),
		Vector2(x, 7.0),
	])
	draw_colored_polygon(marker, COLOR_PLAYHEAD)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var direction := -1.0 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mouse_event.shift_pressed:
				horizontal_scroll.value = clampf(horizontal_scroll.value + direction * PIXELS_PER_FRAME * 6.0, 0.0, maxf(horizontal_scroll.max_value - horizontal_scroll.page, 0.0))
			else:
				vertical_scroll.value = clampf(vertical_scroll.value + direction * ROW_HEIGHT * 3.0, 0.0, maxf(vertical_scroll.max_value - vertical_scroll.page, 0.0))
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_left_click(mouse_event.position)
			accept_event()


func _handle_left_click(position: Vector2) -> void:
	if position.y < RULER_HEIGHT:
		if position.x >= LABEL_WIDTH:
			_set_frame_from_x(position.x)
		return
	if position.y >= size.y - SCROLLBAR_SIZE:
		return
	var scroll_y := vertical_scroll.value if vertical_scroll != null else 0.0
	var row_index := int(floor((position.y - RULER_HEIGHT + scroll_y) / ROW_HEIGHT))
	if row_index < 0 or row_index >= bone_names.size():
		return
	var bone_name := bone_names[row_index]
	selected_bone = bone_name
	bone_selected.emit(bone_name)
	if position.x < LABEL_WIDTH:
		queue_redraw()
		return
	var frame := _frame_from_x(position.x)
	current_frame = frame
	frame_changed.emit(frame)
	if _has_key(frame, bone_name):
		key_selected.emit(frame, bone_name)
	queue_redraw()


func _set_frame_from_x(x: float) -> void:
	var frame := _frame_from_x(x)
	current_frame = frame
	frame_changed.emit(frame)
	queue_redraw()


func _frame_from_x(x: float) -> int:
	var scroll_x := horizontal_scroll.value if horizontal_scroll != null else 0.0
	var frame := int(round((x - LABEL_WIDTH + scroll_x) / PIXELS_PER_FRAME))
	return clampi(frame, 0, maxi(frame_count, 1))


func _has_key(frame: int, bone_name: String) -> bool:
	if not key_data.has(frame):
		return false
	var frame_data_value: Variant = key_data[frame]
	if not frame_data_value is Dictionary:
		return false
	var node_xfm_value: Variant = (frame_data_value as Dictionary).get("nodeXfm", {})
	return node_xfm_value is Dictionary and (node_xfm_value as Dictionary).has(bone_name)
