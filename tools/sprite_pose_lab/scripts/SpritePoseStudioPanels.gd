extends "res://tools/sprite_pose_lab/scripts/SpritePoseStudioLayout.gd"

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background := ColorRect.new()
	background.color = Color(0.025, 0.028, 0.034, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side_name in ["left", "top", "right", "bottom"]:
		outer_margin.add_theme_constant_override("margin_%s" % side_name, 10)
	add_child(outer_margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	outer_margin.add_child(root)
	root.add_child(_build_header())

	var main_split := HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 270
	root.add_child(main_split)

	var rig_panel := _panel(_build_rig_panel())
	rig_panel.custom_minimum_size.x = 260
	main_split.add_child(rig_panel)

	var center_and_inspector := HSplitContainer.new()
	center_and_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_and_inspector.split_offset = 800
	main_split.add_child(center_and_inspector)
	center_and_inspector.add_child(_panel(_build_preview_panel()))

	var inspector_panel := _panel(_build_inspector())
	inspector_panel.custom_minimum_size.x = 300
	center_and_inspector.add_child(inspector_panel)

	root.add_child(_build_timeline_area())


func _build_inspector() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	column.add_child(_section("BONE / CAMADA"))
	bone_name_edit = LineEdit.new()
	bone_name_edit.text_submitted.connect(Callable(self, "_on_bone_name_changed"))
	column.add_child(_labeled("Nome", bone_name_edit))
	parent_option = OptionButton.new()
	parent_option.item_selected.connect(Callable(self, "_on_parent_changed"))
	column.add_child(_labeled("Parent", parent_option))

	var texture_buttons := HBoxContainer.new()
	texture_buttons.add_child(_button("Carregar PNG", Callable(self, "_request_load_texture")))
	texture_buttons.add_child(_button("Limpar", Callable(self, "_clear_texture")))
	column.add_child(texture_buttons)
	texture_path_label = Label.new()
	texture_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texture_path_label.modulate = Color(0.68, 0.72, 0.78)
	column.add_child(texture_path_label)
	column.add_child(HSeparator.new())

	column.add_child(_section("TRANSFORM DO FRAME"))
	var grid := GridContainer.new()
	grid.columns = 2
	position_x_spin = _spin_row(grid, "Posição X", -2048, 2048, 1)
	position_y_spin = _spin_row(grid, "Posição Y", -2048, 2048, 1)
	rotation_spin = _spin_row(grid, "Rotação", -720, 720, 1)
	rotation_spin.suffix = "°"
	pivot_x_spin = _spin_row(grid, "Pivô X", -2048, 2048, 1)
	pivot_y_spin = _spin_row(grid, "Pivô Y", -2048, 2048, 1)
	z_order_spin = _spin_row(grid, "Ordem Z", -4096, 4095, 1)
	column.add_child(grid)
	for spin in [position_x_spin, position_y_spin, rotation_spin, pivot_x_spin, pivot_y_spin, z_order_spin]:
		spin.value_changed.connect(Callable(self, "_on_transform_changed"))
	visible_check = _check("Visível neste frame", true)
	visible_check.toggled.connect(Callable(self, "_on_transform_changed"))
	column.add_child(visible_check)
	keyed_label = Label.new()
	column.add_child(keyed_label)
	var key_row := HBoxContainer.new()
	key_row.add_child(_button("Criar key", Callable(self, "_create_key")))
	key_row.add_child(_button("Remover key", Callable(self, "_remove_current_key")))
	column.add_child(key_row)
	column.add_child(HSeparator.new())

	column.add_child(_section("RIG / CONSTRAINTS"))
	locked_check = _check("Bone bloqueado", false)
	locked_check.toggled.connect(Callable(self, "_on_bone_settings_changed"))
	column.add_child(locked_check)
	var constraints_grid := GridContainer.new()
	constraints_grid.columns = 2
	rotation_min_spin = _spin_row(constraints_grid, "Rotação mínima", -720, 720, 1)
	rotation_max_spin = _spin_row(constraints_grid, "Rotação máxima", -720, 720, 1)
	column.add_child(constraints_grid)
	rotation_min_spin.value_changed.connect(Callable(self, "_on_bone_settings_changed"))
	rotation_max_spin.value_changed.connect(Callable(self, "_on_bone_settings_changed"))
	foot_contact_check = _check("Ponto de contato com chão", false)
	foot_contact_check.toggled.connect(Callable(self, "_on_bone_settings_changed"))
	column.add_child(foot_contact_check)
	return scroll


func _build_timeline_area() -> Control:
	var panel_column := VBoxContainer.new()
	panel_column.add_theme_constant_override("separation", 5)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 5)
	toolbar.add_child(_button("|◀", func() -> void: call("_select_frame", 0)))
	toolbar.add_child(_button("◀", func() -> void: call("_select_frame", selected_frame - 1)))
	play_button = _button("Play", Callable(self, "_toggle_playback"))
	toolbar.add_child(play_button)
	toolbar.add_child(_button("▶", func() -> void: call("_select_frame", selected_frame + 1)))
	toolbar.add_child(_button("▶|", func() -> void: call("_select_frame", pose_project.frame_count() - 1)))
	frame_label = Label.new()
	frame_label.custom_minimum_size.x = 110
	frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(frame_label)
	toolbar.add_child(_button("+ Quadro", Callable(self, "_add_frame")))
	toolbar.add_child(_button("Duplicar", Callable(self, "_duplicate_frame")))
	toolbar.add_child(_button("Remover", Callable(self, "_remove_frame")))
	toolbar.add_child(_label("FPS"))
	fps_spin = _spin(1, 60, 0.5)
	fps_spin.value_changed.connect(Callable(self, "_on_fps_changed"))
	toolbar.add_child(fps_spin)
	loop_option = OptionButton.new()
	loop_option.add_item("Loop")
	loop_option.set_item_metadata(0, "loop")
	loop_option.add_item("Ping-pong")
	loop_option.set_item_metadata(1, "pingpong")
	loop_option.add_item("Uma vez")
	loop_option.set_item_metadata(2, "once")
	loop_option.item_selected.connect(Callable(self, "_on_loop_changed"))
	toolbar.add_child(loop_option)
	use_frame_duration_check = _check("Duração por quadro", false)
	use_frame_duration_check.toggled.connect(Callable(self, "_on_frame_duration_mode_changed"))
	toolbar.add_child(use_frame_duration_check)
	frame_duration_spin = _spin(0.01, 5.0, 0.01)
	frame_duration_spin.suffix = " s"
	frame_duration_spin.value_changed.connect(Callable(self, "_on_frame_duration_changed"))
	toolbar.add_child(frame_duration_spin)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	clip_option = OptionButton.new()
	clip_option.item_selected.connect(Callable(self, "_on_clip_selected"))
	toolbar.add_child(clip_option)
	clip_name_edit = LineEdit.new()
	clip_name_edit.custom_minimum_size.x = 100
	clip_name_edit.text_submitted.connect(Callable(self, "_on_clip_name_changed"))
	toolbar.add_child(clip_name_edit)
	toolbar.add_child(_button("+ Clip", Callable(self, "_add_clip")))
	var animation_preset := OptionButton.new()
	animation_preset.add_item("Idle 4", 0)
	animation_preset.set_item_metadata(0, "idle_4")
	animation_preset.add_item("Walk 4", 1)
	animation_preset.set_item_metadata(1, "walk_4")
	animation_preset.add_item("Run 6", 2)
	animation_preset.set_item_metadata(2, "run_6")
	toolbar.add_child(animation_preset)
	toolbar.add_child(_button("Aplicar movimento", func() -> void:
		call("_apply_animation_preset", str(animation_preset.get_selected_metadata()))
	))
	panel_column.add_child(toolbar)

	var timeline_scroll := ScrollContainer.new()
	timeline_scroll.custom_minimum_size.y = 205
	timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline = TimelineScript.new()
	timeline.frame_selected.connect(Callable(self, "_select_frame"))
	timeline.cell_selected.connect(Callable(self, "_on_timeline_cell_selected"))
	timeline.remove_key_requested.connect(Callable(self, "_on_timeline_remove_key"))
	timeline_scroll.add_child(timeline)
	panel_column.add_child(timeline_scroll)

	status_label = Label.new()
	status_label.modulate = Color(0.72, 0.78, 0.75)
	panel_column.add_child(status_label)
	return _panel(panel_column)


func _build_render_viewport() -> void:
	render_viewport = SubViewport.new()
	render_viewport.name = "PoseRenderViewport"
	render_viewport.size = pose_project.canvas_size
	render_viewport.transparent_bg = true
	render_viewport.disable_3d = true
	render_viewport.msaa_2d = Viewport.MSAA_DISABLED
	render_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(render_viewport)
	pose_canvas = CanvasScript.new()
	pose_canvas.name = "PoseCanvas"
	render_viewport.add_child(pose_canvas)
	pose_canvas.set_project(pose_project)
	preview.texture = render_viewport.get_texture()
	_update_preview_size()


func _build_dialogs_and_timers() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(Callable(self, "_on_file_selected"))
	file_dialog.dir_selected.connect(Callable(self, "_on_directory_selected"))
	file_dialog.canceled.connect(func() -> void: file_action = FileAction.NONE)
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
