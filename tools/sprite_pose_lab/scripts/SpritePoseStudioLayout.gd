extends "res://tools/sprite_pose_lab/scripts/SpritePoseStudioState.gd"

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "OATHWAKE  •  SPRITE POSE LAB"
	title.add_theme_font_size_override("font_size", 19)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("Desfazer", Callable(self, "_undo")))
	row.add_child(_button("Refazer", Callable(self, "_redo")))
	row.add_child(_button("Salvar projeto", Callable(self, "_request_save_project")))
	row.add_child(_button("Abrir projeto", Callable(self, "_request_load_project")))
	row.add_child(_button("Exportar frame", Callable(self, "_request_export_frame")))
	row.add_child(_button("Sequência PNG", Callable(self, "_request_export_all")))
	row.add_child(_button("Sprite sheet", Callable(self, "_request_export_sheet")))
	return row


func _build_rig_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.add_child(_section("RIG E CAMADAS"))
	var preset_row := HBoxContainer.new()
	var rig_preset := OptionButton.new()
	rig_preset.add_item("Humanoid Basic", 0)
	rig_preset.add_item("Custom", 1)
	rig_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_child(rig_preset)
	preset_row.add_child(_button("Aplicar", func() -> void:
		if rig_preset.get_selected_id() == 0:
			call("_apply_humanoid_preset")
	))
	column.add_child(preset_row)

	rig_tree = Tree.new()
	rig_tree.hide_root = true
	rig_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rig_tree.custom_minimum_size.y = 260
	rig_tree.item_selected.connect(Callable(self, "_on_tree_selected"))
	column.add_child(rig_tree)

	var bone_buttons := HBoxContainer.new()
	bone_buttons.add_child(_button("+ Bone", Callable(self, "_add_bone")))
	bone_buttons.add_child(_button("Remover", Callable(self, "_remove_bone")))
	column.add_child(bone_buttons)
	var note := Label.new()
	note.text = "O modo custom está sempre ativo: adicione, renomeie e faça o parent dos bones livremente."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.62, 0.66, 0.72)
	column.add_child(note)
	return column


func _build_preview_panel() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)

	var first_row := HBoxContainer.new()
	first_row.add_child(_label("Direção"))
	direction_option = OptionButton.new()
	for direction in pose_project.DIRECTIONS:
		direction_option.add_item(DIRECTION_LABELS.get(direction, direction))
		direction_option.set_item_metadata(direction_option.item_count - 1, direction)
	direction_option.item_selected.connect(Callable(self, "_on_direction_selected"))
	first_row.add_child(direction_option)
	first_row.add_child(_label("Canvas"))
	canvas_width_spin = _spin(1, 2048, 1)
	canvas_width_spin.value = 64
	canvas_width_spin.custom_minimum_size.x = 64
	canvas_width_spin.value_changed.connect(Callable(self, "_on_canvas_changed"))
	first_row.add_child(canvas_width_spin)
	first_row.add_child(_label("×"))
	canvas_height_spin = _spin(1, 2048, 1)
	canvas_height_spin.value = 64
	canvas_height_spin.custom_minimum_size.x = 64
	canvas_height_spin.value_changed.connect(Callable(self, "_on_canvas_changed"))
	first_row.add_child(canvas_height_spin)
	first_row.add_child(_label("Pés"))
	feet_y_spin = _spin(0, 2047, 1)
	feet_y_spin.value = 60
	feet_y_spin.custom_minimum_size.x = 64
	feet_y_spin.value_changed.connect(Callable(self, "_on_canvas_changed"))
	first_row.add_child(feet_y_spin)
	first_row.add_child(_label("Zoom"))
	zoom_option = OptionButton.new()
	for zoom in range(1, 13):
		zoom_option.add_item("%dx" % zoom, zoom)
	zoom_option.select(5)
	zoom_option.item_selected.connect(Callable(self, "_on_zoom_changed"))
	first_row.add_child(zoom_option)
	pixel_snap_check = _check("Raster pixel-perfect", true)
	pixel_snap_check.toggled.connect(Callable(self, "_on_view_setting_changed"))
	first_row.add_child(pixel_snap_check)
	gizmo_check = _check("Gizmo", true)
	gizmo_check.toggled.connect(Callable(self, "_on_view_setting_changed"))
	first_row.add_child(gizmo_check)
	column.add_child(first_row)

	var onion_row := HBoxContainer.new()
	previous_check = _check("Anterior vermelho", true)
	previous_check.toggled.connect(Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(previous_check)
	previous_opacity = HSlider.new()
	previous_opacity.min_value = 0.0
	previous_opacity.max_value = 1.0
	previous_opacity.step = 0.01
	previous_opacity.value = 0.28
	previous_opacity.custom_minimum_size.x = 105
	previous_opacity.value_changed.connect(Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(previous_opacity)
	next_check = _check("Posterior verde", true)
	next_check.toggled.connect(Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(next_check)
	next_opacity = HSlider.new()
	next_opacity.min_value = 0.0
	next_opacity.max_value = 1.0
	next_opacity.step = 0.01
	next_opacity.value = 0.28
	next_opacity.custom_minimum_size.x = 105
	next_opacity.value_changed.connect(Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(next_opacity)
	column.add_child(onion_row)

	var guides_row := HBoxContainer.new()
	checker_check = _check("Quadriculado", true)
	grid_check = _check("Grade", false)
	axis_check = _check("Eixo", true)
	feet_line_check = _check("Linha dos pés", true)
	for item in [checker_check, grid_check, axis_check, feet_line_check]:
		item.toggled.connect(Callable(self, "_on_view_setting_changed"))
		guides_row.add_child(item)
	column.add_child(guides_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	preview.gui_input.connect(Callable(self, "_on_preview_input"))
	center.add_child(preview)
	return column
