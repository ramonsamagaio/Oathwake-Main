extends "res://tools/sprite_pose_lab/scripts/SpritePoseLabBase.gd"


func refresh_all() -> void:
	if model.frames.is_empty():
		model.frames = [model.default_frame("south")]
	frame_index = clampi(frame_index, 0, model.frames.size() - 1)
	part_index = clampi(part_index, 0, model.PARTS.size() - 1)
	var frame: Dictionary = model.frames[frame_index]
	var part: Dictionary = frame["parts"][model.PARTS[part_index]]
	var position := model.vector_from_value(part.get("position", [0, 0]))
	var pivot := model.vector_from_value(part.get("pivot", [0, 0]))
	updating = true
	direction_option.select(maxi(0, model.DIRECTIONS.find(str(frame.get("direction", "south")))))
	part_option.select(part_index)
	position_x.value = position.x
	position_y.value = position.y
	rotation.value = float(part.get("rotation_degrees", 0))
	pivot_x.value = pivot.x
	pivot_y.value = pivot.y
	z_index.value = int(part.get("z_index", 0))
	part_visible.button_pressed = bool(part.get("visible", true))
	frame_duration.value = float(frame.get("duration", 0.125))
	fps_spin.value = model.fps
	duration_mode.button_pressed = model.use_frame_durations
	frame_duration.editable = model.use_frame_durations
	fps_spin.editable = not model.use_frame_durations
	width_spin.value = model.canvas_size.x
	height_spin.value = model.canvas_size.y
	feet_spin.max_value = model.canvas_size.y - 1
	feet_spin.value = model.feet_y
	character_edit.text = model.character_name
	animation_edit.text = model.animation_name
	frame_label.text = "Frame %d / %d" % [frame_index + 1, model.frames.size()]
	play_button.text = "Pausar" if playing else "Reproduzir"
	var direction := str(frame.get("direction", "south"))
	var path := str(model.part_library[direction].get(model.PARTS[part_index], ""))
	path_label.text = "Usando placeholder" if path.is_empty() else path
	updating = false
	refresh_canvas()


func refresh_canvas() -> void:
	if pose_canvas == null:
		return
	var previous: Dictionary = {}
	if frame_index > 0:
		previous = model.frames[frame_index - 1]
	pose_canvas.configure(model.canvas_size, model.feet_y)
	pose_canvas.set_guides(checker.button_pressed, grid.button_pressed, axis.button_pressed, feet_line.button_pressed)
	pose_canvas.apply_pose(model.frames[frame_index], model.part_library, previous, onion.button_pressed)


func current_part() -> Dictionary:
	var frame: Dictionary = model.frames[frame_index]
	return frame["parts"][model.PARTS[part_index]]


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
	refresh_all()


func on_transform_changed(_value: float) -> void:
	if updating:
		return
	var position := Vector2(position_x.value, position_y.value)
	var pivot := Vector2(pivot_x.value, pivot_y.value)
	if snap_integer.button_pressed:
		position = position.round()
		pivot = pivot.round()
	var part := current_part()
	part["position"] = [position.x, position.y]
	part["rotation_degrees"] = rotation.value
	part["pivot"] = [pivot.x, pivot.y]
	part["z_index"] = int(z_index.value)
	refresh_canvas()


func on_visibility_changed(value: bool) -> void:
	if updating:
		return
	current_part()["visible"] = value
	refresh_canvas()


func on_snap_changed(enabled: bool) -> void:
	if enabled:
		on_transform_changed(0)


func on_canvas_settings_changed(_value: float) -> void:
	if updating:
		return
	model.canvas_size = Vector2i(int(width_spin.value), int(height_spin.value))
	model.feet_y = clampi(int(feet_spin.value), 0, model.canvas_size.y - 1)
	viewport.size = model.canvas_size
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
	var zoom := 6
	if zoom_option != null:
		zoom = int(zoom_option.get_selected_id())
	preview.custom_minimum_size = Vector2(model.canvas_size * zoom)
	preview.size = Vector2(model.canvas_size * zoom)


func reset_current_pose() -> void:
	var old: Dictionary = model.frames[frame_index]
	var fresh := model.default_frame(str(old.get("direction", "south")))
	fresh["duration"] = old.get("duration", 0.125)
	model.frames[frame_index] = fresh
	refresh_all()
	set_status("Pose resetada.")


func previous_frame() -> void:
	step_frame(-1)


func next_frame() -> void:
	step_frame(1)


func step_frame(delta: int) -> void:
	frame_index = posmod(frame_index + delta, model.frames.size())
	refresh_all()
	schedule_next_frame()


func add_frame() -> void:
	var direction := str(model.frames[frame_index].get("direction", "south"))
	model.frames.insert(frame_index + 1, model.default_frame(direction))
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
