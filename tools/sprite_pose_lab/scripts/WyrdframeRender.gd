extends "res://tools/sprite_pose_lab/scripts/WyrdframeUI.gd"

func _build_rendering() -> void:
	render_viewport = SubViewport.new()
	render_viewport.transparent_bg = true
	render_viewport.disable_3d = true
	render_viewport.msaa_2d = Viewport.MSAA_DISABLED
	render_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(render_viewport)
	canvas_renderer = CanvasScript.new()
	render_viewport.add_child(canvas_renderer)
	preview.texture = render_viewport.get_texture()
	_apply_render()

func _build_runtime_helpers() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(Callable(self, "_on_file_selected"))
	file_dialog.dir_selected.connect(Callable(self, "_on_directory_selected"))
	file_dialog.canceled.connect(Callable(self, "_on_file_dialog_canceled"))
	add_child(file_dialog)
	playback_timer = Timer.new()
	playback_timer.one_shot = true
	playback_timer.timeout.connect(Callable(self, "_on_playback_timeout"))
	add_child(playback_timer)
	autosave_timer = Timer.new()
	autosave_timer.one_shot = true
	autosave_timer.wait_time = 0.8
	autosave_timer.timeout.connect(Callable(self, "_write_autosave"))
	add_child(autosave_timer)

func _view_settings() -> Dictionary:
	return {
		"checkerboard": checkerboard_check.button_pressed,
		"bones": show_bones_check.button_pressed,
		"sprites": show_sprites_check.button_pressed,
		"previous": previous_check.button_pressed,
		"next": next_check.button_pressed,
		"bone_opacity": bone_opacity_slider.value,
		"sprite_opacity": sprite_opacity_slider.value,
		"previous_opacity": previous_opacity.value,
		"next_opacity": next_opacity.value,
		"pixel_snap": pixel_snap_check.button_pressed,
	}

func _apply_render() -> void:
	if canvas_renderer == null or render_viewport == null:
		return
	var canvas_data: Dictionary = _canvas_section()
	var native_size: Vector2i = Vector2i(
		maxi(1, int(canvas_data.get("width", 64))),
		maxi(1, int(canvas_data.get("height", 64)))
	)
	render_viewport.size = native_size
	canvas_renderer.configure(document, current_action, current_direction, current_frame, selected_bone, _view_settings())
	_update_preview_size()

func _update_preview_size() -> void:
	if preview == null or zoom_option == null:
		return
	var canvas_data: Dictionary = _canvas_section()
	var zoom_value: int = maxi(1, zoom_option.get_selected_id())
	var preview_size: Vector2 = Vector2(
		float(canvas_data.get("width", 64)) * float(zoom_value),
		float(canvas_data.get("height", 64)) * float(zoom_value)
	)
	preview.custom_minimum_size = preview_size
	preview.size = preview_size

func _rebuild_structure() -> void:
	if _frames().is_empty():
		_frames().append(_new_frame())
	current_frame = clampi(current_frame, 0, _frames().size() - 1)
	if _bone_by_id(selected_bone).is_empty():
		selected_bone = "root"
	_rebuild_project_tree()
	_rebuild_rig_tree()
	_rebuild_parent_option()
	_refresh_controls()
	_rebuild_timeline()
	_apply_render()

func _refresh_context() -> void:
	if _frames().is_empty():
		_frames().append(_new_frame())
	current_frame = clampi(current_frame, 0, _frames().size() - 1)
	_rebuild_parent_option()
	_refresh_controls()
	_rebuild_timeline()
	_apply_render()

func _refresh_controls() -> void:
	updating_ui = true
	var project_data: Dictionary = _project_section()
	project_name_edit.text = str(project_data.get("name", "Novo Projeto"))
	asset_name_edit.text = str(project_data.get("asset_name", "asset"))
	_select_option_by_metadata(entity_option, str(project_data.get("entity_type", "custom")))
	_select_option_by_metadata(direction_option, current_direction)
	var action_data: Dictionary = _action_data()
	action_name_edit.text = str(action_data.get("name", current_action))
	var playback_data: Dictionary = _playback_section()
	fps_spin.value = float(playback_data.get("fps", 8.0))
	_select_option_by_metadata(loop_option, str(playback_data.get("loop_mode", "loop")))
	use_duration_check.button_pressed = bool(playback_data.get("use_frame_durations", false))
	frame_duration_spin.value = float(_frame_data(current_frame).get("duration", 0.125))
	frame_duration_spin.editable = use_duration_check.button_pressed
	frame_label.text = "Frame %d / %d" % [current_frame + 1, _frames().size()]
	play_button.text = "Pausar" if playing else "Play"
	_refresh_inspector()
	updating_ui = false
	_update_window_title()

func _refresh_inspector() -> void:
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	if bone_data.is_empty():
		return
	var transform_data: Dictionary = _resolved_transform(current_frame, selected_bone)
	var position_value: Vector2 = _vec(transform_data.get("position", [0.0, 0.0]))
	var pivot_value: Vector2 = _vec(transform_data.get("pivot", [0.0, 0.0]))
	bone_name_edit.text = str(bone_data.get("name", selected_bone))
	_select_option_by_metadata(parent_option, str(bone_data.get("parent", "")))
	position_x_spin.value = position_value.x
	position_y_spin.value = position_value.y
	rotation_spin.value = float(transform_data.get("rotation_degrees", 0.0))
	pivot_x_spin.value = pivot_value.x
	pivot_y_spin.value = pivot_value.y
	z_spin.value = int(transform_data.get("z_index", 0))
	visible_check.button_pressed = bool(transform_data.get("visible", true))
	locked_check.button_pressed = bool(bone_data.get("locked", false))
	bone_editor_visible_check.button_pressed = bool(bone_data.get("editor_visible", true))
	var path_value: String = _texture_path(selected_bone)
	texture_path_label.text = "Sem PNG nesta ação/direção. Placeholder suave ativo." if path_value.is_empty() else path_value

func _rebuild_project_tree() -> void:
	rebuilding_trees = true
	project_tree.clear()
	var hidden_root: TreeItem = project_tree.create_item()
	var project_item: TreeItem = project_tree.create_item(hidden_root)
	if project_item == null:
		rebuilding_trees = false
		return
	project_item.set_text(0, str(_project_section().get("name", "Projeto")))
	project_item.set_metadata(0, {"kind": "project"})
	for action_id_value: Variant in _actions().keys():
		var action_id: String = str(action_id_value)
		var action_data: Dictionary = _action_data(action_id)
		var action_item: TreeItem = project_tree.create_item(project_item)
		if action_item == null:
			continue
		action_item.set_text(0, str(action_data.get("name", action_id)))
		action_item.set_metadata(0, {"kind": "action", "action": action_id})
		action_item.set_collapsed(false)
		for direction_id: String in DIRECTIONS:
			var direction_item: TreeItem = project_tree.create_item(action_item)
			if direction_item == null:
				continue
			direction_item.set_text(0, str(DIRECTION_LABELS[direction_id]))
			direction_item.set_metadata(0, {
				"kind": "direction",
				"action": action_id,
				"direction": direction_id,
			})
			if action_id == current_action and direction_id == current_direction:
				direction_item.select(0)
	project_item.set_collapsed(false)
	rebuilding_trees = false

func _rebuild_rig_tree() -> void:
	rebuilding_trees = true
	rig_tree.clear()
	var hidden_root: TreeItem = rig_tree.create_item()
	var item_map: Dictionary = {"": hidden_root}
	var pending: Array = _bones().duplicate(true)
	var guard: int = 0
	while not pending.is_empty() and guard < _bones().size() * 3:
		guard += 1
		for index: int in range(pending.size() - 1, -1, -1):
			var bone_data: Dictionary = pending[index] as Dictionary
			var bone_id: String = str(bone_data.get("id", ""))
			var parent_id: String = str(bone_data.get("parent", ""))
			if not item_map.has(parent_id):
				continue
			var parent_item: TreeItem = item_map[parent_id] as TreeItem
			var item: TreeItem = rig_tree.create_item(parent_item)
			if item == null:
				continue
			var visibility_prefix: String = "◉ " if bool(bone_data.get("editor_visible", true)) else "○ "
			item.set_text(0, visibility_prefix + str(bone_data.get("name", bone_id)))
			item.set_metadata(0, bone_id)
			item_map[bone_id] = item
			pending.remove_at(index)
	if item_map.has(selected_bone):
		var selected_item: TreeItem = item_map[selected_bone] as TreeItem
		selected_item.select(0)
	rebuilding_trees = false

func _rebuild_parent_option() -> void:
	updating_ui = true
	parent_option.clear()
	parent_option.add_item("Sem parent")
	parent_option.set_item_metadata(0, "")
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		if bone_id == selected_bone:
			continue
		parent_option.add_item(str(bone_data.get("name", bone_id)))
		parent_option.set_item_metadata(parent_option.item_count - 1, bone_id)
	var selected_data: Dictionary = _bone_by_id(selected_bone)
	_select_option_by_metadata(parent_option, str(selected_data.get("parent", "")))
	updating_ui = false

func _rebuild_timeline() -> void:
	for child_value: Variant in timeline_grid.get_children():
		var child: Node = child_value as Node
		timeline_grid.remove_child(child)
		child.queue_free()
	var frame_count: int = _frames().size()
	timeline_grid.columns = frame_count + 1
	var corner: Label = Label.new()
	corner.text = "BONES / FRAMES"
	corner.custom_minimum_size = Vector2(190, 32)
	corner.modulate = Color(0.64, 0.82, 0.9)
	timeline_grid.add_child(corner)
	var cell_width: float = timeline_cell_width_spin.value
	for frame_index_value: int in range(frame_count):
		var header: Button = Button.new()
		header.text = str(frame_index_value + 1)
		header.toggle_mode = true
		header.button_pressed = frame_index_value == current_frame
		header.custom_minimum_size = Vector2(cell_width, 32)
		header.pressed.connect(Callable(self, "_select_frame").bind(frame_index_value))
		timeline_grid.add_child(header)
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		var row_label: Button = Button.new()
		row_label.text = str(bone_data.get("name", bone_id))
		row_label.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row_label.custom_minimum_size = Vector2(190, 30)
		row_label.pressed.connect(Callable(self, "_select_bone").bind(bone_id))
		timeline_grid.add_child(row_label)
		for frame_index_value: int in range(frame_count):
			var cell: Button = Button.new()
			cell.text = "●" if _is_keyed(frame_index_value, bone_id) else "·"
			cell.custom_minimum_size = Vector2(cell_width, 30)
			cell.tooltip_text = "Clique: selecionar. Botão direito: remover key."
			cell.gui_input.connect(Callable(self, "_on_timeline_cell_input").bind(frame_index_value, bone_id))
			timeline_grid.add_child(cell)

func _is_keyed(frame_index_value: int, bone_id: String) -> bool:
	var keys: Dictionary = _frame_data(frame_index_value).get("keys", {}) as Dictionary
	return keys.has(bone_id)

func _select_option_by_metadata(option: OptionButton, metadata_value: Variant) -> void:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == metadata_value:
			option.select(index)
			return
