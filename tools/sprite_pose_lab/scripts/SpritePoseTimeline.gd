class_name SpritePoseTimeline
extends Control

signal frame_selected(frame_index: int)
signal cell_selected(frame_index: int, bone_id: String)
signal remove_key_requested(frame_index: int, bone_id: String)

var project
var selected_frame := 0
var selected_bone_id := "torso"
var row_height := 28.0
var column_width := 42.0
var label_width := 190.0
var header_height := 30.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func set_project(value) -> void:
	project = value
	_update_minimum_size()
	queue_redraw()


func set_selection(frame_index: int, bone_id: String) -> void:
	selected_frame = frame_index
	selected_bone_id = bone_id
	queue_redraw()


func _update_minimum_size() -> void:
	if project == null:
		custom_minimum_size = Vector2(420, 160)
		return
	custom_minimum_size = Vector2(
		label_width + column_width * maxf(1.0, float(project.frame_count())),
		header_height + row_height * maxf(1.0, float(project.bones.size()))
	)


func refresh() -> void:
	_update_minimum_size()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.06, 0.07, 1.0))
	if project == null:
		return
	_draw_header()
	_draw_rows()


func _draw_header() -> void:
	draw_rect(Rect2(0, 0, label_width, header_height), Color(0.085, 0.09, 0.105, 1.0))
	draw_string(
		get_theme_default_font(),
		Vector2(10, 20),
		"CAMADAS / BONES",
		HORIZONTAL_ALIGNMENT_LEFT,
		label_width - 20,
		12,
		Color(0.78, 0.82, 0.88)
	)
	for frame_number in range(project.frame_count()):
		var x := label_width + frame_number * column_width
		var header_color := Color(0.16, 0.25, 0.34, 1.0) if frame_number == selected_frame else Color(0.09, 0.095, 0.11, 1.0)
		draw_rect(Rect2(x, 0, column_width, header_height), header_color)
		draw_rect(Rect2(x, 0, column_width, header_height), Color(0.22, 0.23, 0.26), false, 1.0)
		draw_string(
			get_theme_default_font(),
			Vector2(x, 20),
			str(frame_number + 1),
			HORIZONTAL_ALIGNMENT_CENTER,
			column_width,
			12,
			Color(0.9, 0.92, 0.95)
		)


func _draw_rows() -> void:
	for row in range(project.bones.size()):
		var bone: Dictionary = project.bones[row]
		var bone_id := str(bone.get("id", ""))
		var y := header_height + row * row_height
		var selected_row := bone_id == selected_bone_id
		var row_color := Color(0.105, 0.145, 0.18, 1.0) if selected_row else Color(0.07, 0.075, 0.085, 1.0)
		draw_rect(Rect2(0, y, label_width, row_height), row_color)
		draw_rect(Rect2(0, y, label_width, row_height), Color(0.17, 0.18, 0.2), false, 1.0)
		var depth := _bone_depth(bone_id)
		var prefix := "[L] " if bool(bone.get("locked", false)) else ""
		var display_name := prefix + str(bone.get("name", bone_id))
		draw_string(
			get_theme_default_font(),
			Vector2(10 + depth * 14, y + 19),
			display_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			label_width - 20 - depth * 14,
			12,
			Color(0.86, 0.88, 0.92)
		)
		for frame_number in range(project.frame_count()):
			_draw_cell(frame_number, row, bone_id)


func _draw_cell(frame_number: int, row: int, bone_id: String) -> void:
	var x := label_width + frame_number * column_width
	var y := header_height + row * row_height
	var selected_cell := frame_number == selected_frame and bone_id == selected_bone_id
	var selected_column := frame_number == selected_frame
	var cell_color := Color(0.14, 0.2, 0.26, 1.0) if selected_column else Color(0.075, 0.08, 0.09, 1.0)
	if selected_cell:
		cell_color = Color(0.18, 0.33, 0.42, 1.0)
	draw_rect(Rect2(x, y, column_width, row_height), cell_color)
	draw_rect(Rect2(x, y, column_width, row_height), Color(0.17, 0.18, 0.2), false, 1.0)
	var center := Vector2(x + column_width * 0.5, y + row_height * 0.5)
	if project.is_keyed(frame_number, bone_id):
		draw_circle(center, 5.0, Color(0.25, 0.9, 1.0, 1.0))
		draw_circle(center, 2.0, Color(0.03, 0.08, 0.1, 1.0))
	elif frame_number > 0:
		draw_circle(center, 2.2, Color(0.48, 0.51, 0.56, 0.65))


func _bone_depth(bone_id: String) -> int:
	var depth := 0
	var cursor := bone_id
	var guard := 0
	while guard < 32:
		guard += 1
		var bone := project.bone_by_id(cursor)
		if bone.is_empty():
			break
		var parent_id := str(bone.get("parent", ""))
		if parent_id.is_empty():
			break
		depth += 1
		cursor = parent_id
	return depth


func _gui_input(event: InputEvent) -> void:
	if project == null:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		var frame_number := int(floor((mouse_event.position.x - label_width) / column_width))
		if mouse_event.position.y < header_height:
			if frame_number >= 0 and frame_number < project.frame_count():
				frame_selected.emit(frame_number)
				accept_event()
			return
		var row := int(floor((mouse_event.position.y - header_height) / row_height))
		if row < 0 or row >= project.bones.size():
			return
		var bone_id := str(project.bones[row].get("id", ""))
		if mouse_event.position.x < label_width:
			cell_selected.emit(selected_frame, bone_id)
			accept_event()
			return
		if frame_number < 0 or frame_number >= project.frame_count():
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			remove_key_requested.emit(frame_number, bone_id)
		else:
			cell_selected.emit(frame_number, bone_id)
		accept_event()
