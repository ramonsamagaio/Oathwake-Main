extends "res://tools/sprite_pose_lab/scripts/SpritePoseLabBase.gd"

enum GizmoDragMode {
	NONE,
	MOVE,
	PIVOT,
	ROTATE,
}

var gizmo_drag_mode := GizmoDragMode.NONE
var gizmo_drag_start_mouse := Vector2.ZERO
var gizmo_drag_start_position := Vector2.ZERO
var gizmo_drag_start_pivot := Vector2.ZERO
var gizmo_drag_start_rotation := 0.0
var gizmo_drag_origin := Vector2.ZERO
var gizmo_drag_texture_center := Vector2.ZERO


func refresh_all() -> void:
	if model.frames.is_empty():
		model.frames = [model.default_frame("south")]
	frame_index = clampi(frame_index, 0, model.frames.size() - 1)
	part_index = clampi(part_index, 0, model.PARTS.size() - 1)

	var frame_data: Dictionary = model.frames[frame_index]
	var part_data: Dictionary = frame_data["parts"][model.PARTS[part_index]]
	var part_position := model.vector_from_value(part_data.get("position", [0, 0]))
	var part_pivot := model.vector_from_value(part_data.get("pivot", [0, 0]))

	updating = true
	direction_option.select(maxi(0, model.DIRECTIONS.find(str(frame_data.get("direction", "south")))))
	part_option.select(part_index)
	position_x_spin.value = part_position.x
	position_y_spin.value = part_position.y
	rotation_spin.value = float(part_data.get("rotation_degrees", 0.0))
	pivot_x_spin.value = part_pivot.x
	pivot_y_spin.value = part_pivot.y
	z_order_spin.value = int(part_data.get("z_index", 0))
	part_visible_check.button_pressed = bool(part_data.get("visible", true))
	frame_duration_spin.value = float(frame_data.get("duration", 0.125))
	fps_spin.value = model.fps
	duration_mode_check.button_pressed = model.use_frame_durations
	frame_duration_spin.editable = model.use_frame_durations
	fps_spin.editable = not model.use_frame_durations
	width_spin.value = model.canvas_size.x
	height_spin.value = model.canvas_size.y
	feet_spin.max_value = model.canvas_size.y - 1
	feet_spin.value = model.feet_y
	character_edit.text = model.character_name
	animation_edit.text = model.animation_name
	frame_label.text = "Frame %d / %d" % [frame_index + 1, model.frames.size()]
	play_button.text = "Pausar" if playing else "Reproduzir"

	var direction_name := str(frame_data.get("direction", "south"))
	var texture_path := str(model.part_library[direction_name].get(model.PARTS[part_index], ""))
	path_label.text = "Usando placeholder" if texture_path.is_empty() else texture_path
	updating = false
	refresh_canvas()


func refresh_canvas() -> void:
	if pose_canvas == null:
		return
	var previous_frame_data: Dictionary = {}
	if frame_index > 0:
		previous_frame_data = model.frames[frame_index - 1]

	pose_canvas.configure(model.canvas_size, model.feet_y)
	pose_canvas.set_guides(
		checker_check.button_pressed,
		grid_check.button_pressed,
		axis_check.button_pressed,
		feet_line_check.button_pressed
	)
	pose_canvas.set_pixel_perfect(pixel_preview_check.button_pressed)
	pose_canvas.set_selection(model.PARTS[part_index], gizmo_check.button_pressed)
	pose_canvas.apply_pose(
		model.frames[frame_index],
		model.part_library,
		previous_frame_data,
		onion_check.button_pressed
	)


func current_part() -> Dictionary:
	var frame_data: Dictionary = model.frames[frame_index]
	return frame_data["parts"][model.PARTS[part_index]]


func on_character_name_changed(value: String) -> void:
	if not updating:
		model.character_name = value


func on_animation_name_changed(value: String) -> void:
	if not updating:
		model.animation_name = value


func on_direction_selected(index: int) -> void:
	if updating:
		return
	model.frames[frame_index]["direction"] = model.DIRECTIONS[index]
	refresh_all()


func on_part_selected(index: int) -> void:
	if updating:
		return
	part_index = index
	gizmo_drag_mode = GizmoDragMode.NONE
	refresh_all()


func on_transform_changed(_value: float) -> void:
	if updating:
		return
	var new_position := Vector2(position_x_spin.value, position_y_spin.value)
	var new_pivot := Vector2(pivot_x_spin.value, pivot_y_spin.value)
	if snap_integer_check.button_pressed:
		new_position = new_position.round()
		new_pivot = new_pivot.round()

	var part_data := current_part()
	part_data["position"] = [new_position.x, new_position.y]
	part_data["rotation_degrees"] = rotation_spin.value
	part_data["pivot"] = [new_pivot.x, new_pivot.y]
	part_data["z_index"] = int(z_order_spin.value)
	refresh_canvas()


func on_visibility_changed(value: bool) -> void:
	if updating:
		return
	current_part()["visible"] = value
	refresh_canvas()


func on_snap_changed(enabled: bool) -> void:
	if enabled:
		on_transform_changed(0.0)
	refresh_canvas()


func on_pixel_preview_changed(_enabled: bool) -> void:
	refresh_canvas()
	set_status("Raster pixel-perfect atualizado. O PNG original continua intacto.")


func on_gizmo_changed(_enabled: bool) -> void:
	gizmo_drag_mode = GizmoDragMode.NONE
	refresh_canvas()


func on_canvas_settings_changed(_value: float) -> void:
	if updating:
		return
	model.canvas_size = Vector2i(int(width_spin.value), int(height_spin.value))
	model.feet_y = clampi(int(feet_spin.value), 0, model.canvas_size.y - 1)
	render_viewport.size = model.canvas_size
	pose_canvas.configure(model.canvas_size, model.feet_y)
	update_preview_size()
	refresh_all()


func on_zoom_selected(_index: int) -> void:
	update_preview_size()


func on_guides_changed(_enabled: bool) -> void:
	if not updating:
		refresh_canvas()


func update_preview_size() -> void:
	if preview == null:
		return
	var zoom_value := get_preview_zoom()
	var preview_size := Vector2(model.canvas_size) * float(zoom_value)
	preview.custom_minimum_size = preview_size
	preview.size = preview_size


func get_preview_zoom() -> int:
	if zoom_option == null:
		return 6
	return maxi(1, int(zoom_option.get_selected_id()))


func reset_current_pose() -> void:
	var old_frame: Dictionary = model.frames[frame_index]
	var fresh_frame := model.default_frame(str(old_frame.get("direction", "south")))
	fresh_frame["duration"] = old_frame.get("duration", 0.125)
	model.frames[frame_index] = fresh_frame
	refresh_all()
	set_status("Pose resetada.")


func previous_frame() -> void:
	step_frame(-1)


func next_frame() -> void:
	step_frame(1)


func step_frame(delta: int) -> void:
	frame_index = posmod(frame_index + delta, model.frames.size())
	gizmo_drag_mode = GizmoDragMode.NONE
	refresh_all()
	schedule_next_frame()


func add_frame() -> void:
	var direction_name := str(model.frames[frame_index].get("direction", "south"))
	model.frames.insert(frame_index + 1, model.default_frame(direction_name))
	frame_index += 1
	refresh_all()


func duplicate_frame() -> void:
	model.frames.insert(frame_index + 1, model.frames[frame_index].duplicate(true))
	frame_index += 1
	refresh_all()


func remove_frame() -> void:
	if model.frames.size() == 1:
		set_status("O ciclo precisa manter um frame.", true)
		return
	model.frames.remove_at(frame_index)
	frame_index = mini(frame_index, model.frames.size() - 1)
	refresh_all()


func toggle_playback() -> void:
	playing = not playing
	if not playing:
		playback_timer.stop()
	refresh_all()
	schedule_next_frame()


func schedule_next_frame() -> void:
	if playback_timer == null:
		return
	playback_timer.stop()
	if not playing:
		return
	var wait_time := 1.0 / maxf(model.fps, 1.0)
	if model.use_frame_durations:
		wait_time = maxf(0.01, float(model.frames[frame_index].get("duration", 0.125)))
	playback_timer.start(wait_time)


func on_playback_timeout() -> void:
	if playing:
		step_frame(1)


func on_fps_changed(value: float) -> void:
	if updating:
		return
	model.fps = value
	schedule_next_frame()


func on_duration_mode_changed(value: bool) -> void:
	if updating:
		return
	model.use_frame_durations = value
	refresh_all()
	schedule_next_frame()


func on_frame_duration_changed(value: float) -> void:
	if updating:
		return
	model.frames[frame_index]["duration"] = maxf(0.01, value)
	schedule_next_frame()


func on_preview_gui_input(event: InputEvent) -> void:
	if not gizmo_check.button_pressed:
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		var canvas_point := _preview_to_canvas(mouse_button.position)
		if mouse_button.pressed:
			_begin_gizmo_drag(canvas_point, mouse_button.alt_pressed)
		else:
			_end_gizmo_drag()
		preview.accept_event()
		return

	if event is InputEventMouseMotion and gizmo_drag_mode != GizmoDragMode.NONE:
		var mouse_motion := event as InputEventMouseMotion
		_update_gizmo_drag(_preview_to_canvas(mouse_motion.position), mouse_motion.shift_pressed)
		preview.accept_event()


func _preview_to_canvas(preview_point: Vector2) -> Vector2:
	return preview_point / float(get_preview_zoom())


func _begin_gizmo_drag(canvas_point: Vector2, alt_pressed: bool) -> void:
	var part_name: String = model.PARTS[part_index]
	var points: Dictionary = pose_canvas.get_gizmo_points(part_name)
	if points.is_empty():
		return

	var hit_radius := maxf(1.5, 9.0 / float(get_preview_zoom()))
	var move_point: Vector2 = points["move"]
	var pivot_point: Vector2 = points["pivot"]
	var rotate_point: Vector2 = points["rotate"]

	gizmo_drag_mode = GizmoDragMode.NONE
	if alt_pressed and canvas_point.distance_to(pivot_point) <= hit_radius * 1.6:
		gizmo_drag_mode = GizmoDragMode.PIVOT
	elif canvas_point.distance_to(rotate_point) <= hit_radius * 1.5:
		gizmo_drag_mode = GizmoDragMode.ROTATE
	elif canvas_point.distance_to(move_point) <= hit_radius * 1.6:
		gizmo_drag_mode = GizmoDragMode.MOVE
	elif canvas_point.distance_to(pivot_point) <= hit_radius * 1.4:
		gizmo_drag_mode = GizmoDragMode.PIVOT
	elif pose_canvas.hit_test_part(part_name, canvas_point):
		gizmo_drag_mode = GizmoDragMode.MOVE

	if gizmo_drag_mode == GizmoDragMode.NONE:
		return

	var part_data := current_part()
	gizmo_drag_start_mouse = canvas_point
	gizmo_drag_start_position = model.vector_from_value(part_data.get("position", [0, 0]))
	gizmo_drag_start_pivot = model.vector_from_value(part_data.get("pivot", [0, 0]))
	gizmo_drag_start_rotation = float(part_data.get("rotation_degrees", 0.0))
	gizmo_drag_origin = pivot_point
	gizmo_drag_texture_center = move_point


func _update_gizmo_drag(canvas_point: Vector2, shift_pressed: bool) -> void:
	var part_data := current_part()
	var new_position := gizmo_drag_start_position
	var new_pivot := gizmo_drag_start_pivot
	var new_rotation := gizmo_drag_start_rotation

	match gizmo_drag_mode:
		GizmoDragMode.MOVE:
			new_position = gizmo_drag_start_position + (canvas_point - gizmo_drag_start_mouse)
		GizmoDragMode.PIVOT:
			var rotation_radians := deg_to_rad(gizmo_drag_start_rotation)
			new_pivot = (canvas_point - gizmo_drag_texture_center).rotated(-rotation_radians)
			if snap_integer_check.button_pressed:
				new_pivot = new_pivot.round()
			new_position = gizmo_drag_texture_center + new_pivot.rotated(rotation_radians) - Vector2(model.canvas_size) * 0.5
		GizmoDragMode.ROTATE:
			new_rotation = rad_to_deg((canvas_point - gizmo_drag_origin).angle()) + 90.0
			var rotation_step := 15.0 if shift_pressed else 1.0
			new_rotation = snappedf(new_rotation, rotation_step)
			new_rotation = wrapf(new_rotation, -180.0, 180.0)

	if snap_integer_check.button_pressed:
		new_position = new_position.round()
		new_pivot = new_pivot.round()

	part_data["position"] = [new_position.x, new_position.y]
	part_data["pivot"] = [new_pivot.x, new_pivot.y]
	part_data["rotation_degrees"] = new_rotation
	_sync_transform_controls(part_data)
	refresh_canvas()


func _end_gizmo_drag() -> void:
	if gizmo_drag_mode != GizmoDragMode.NONE:
		set_status("Transform atualizado pelo gizmo.")
	gizmo_drag_mode = GizmoDragMode.NONE


func _sync_transform_controls(part_data: Dictionary) -> void:
	var part_position := model.vector_from_value(part_data.get("position", [0, 0]))
	var part_pivot := model.vector_from_value(part_data.get("pivot", [0, 0]))
	updating = true
	position_x_spin.value = part_position.x
	position_y_spin.value = part_position.y
	rotation_spin.value = float(part_data.get("rotation_degrees", 0.0))
	pivot_x_spin.value = part_pivot.x
	pivot_y_spin.value = part_pivot.y
	updating = false
