extends "res://tools/sprite_pose_lab/scripts/WyrdframeUIBase.gd"

func _build_inspector() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size.x = 260
	column.add_theme_constant_override("separation", 7)
	scroll.add_child(column)
	column.add_child(_section_label("BONE / CAMADA"))
	bone_name_edit = LineEdit.new()
	bone_name_edit.text_submitted.connect(Callable(self, "_rename_bone"))
	column.add_child(_labeled("Nome", bone_name_edit))
	parent_option = OptionButton.new()
	parent_option.item_selected.connect(Callable(self, "_on_parent_selected"))
	column.add_child(_labeled("Parent", parent_option))
	bone_editor_visible_check = _check("Mostrar este bone no overlay", true, Callable(self, "_on_bone_editor_visibility_changed"))
	column.add_child(bone_editor_visible_check)
	locked_check = _check("Bone bloqueado", false, Callable(self, "_on_locked_changed"))
	column.add_child(locked_check)
	column.add_child(HSeparator.new())
	column.add_child(_section_label("SPRITE DA AÇÃO / DIREÇÃO"))
	var texture_row: HBoxContainer = HBoxContainer.new()
	texture_row.add_child(_button("Carregar PNG", Callable(self, "_request_load_texture")))
	texture_row.add_child(_button("Limpar", Callable(self, "_clear_texture")))
	column.add_child(texture_row)
	texture_path_label = Label.new()
	texture_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texture_path_label.modulate = Color(0.68, 0.75, 0.82)
	column.add_child(texture_path_label)
	column.add_child(HSeparator.new())
	column.add_child(_section_label("TRANSFORM DO FRAME"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	position_x_spin = _spin_row(grid, "Posição X", -2048, 2048, 1)
	position_y_spin = _spin_row(grid, "Posição Y", -2048, 2048, 1)
	rotation_spin = _spin_row(grid, "Rotação", -720, 720, 1)
	rotation_spin.suffix = "°"
	pivot_x_spin = _spin_row(grid, "Pivô X", -2048, 2048, 1)
	pivot_y_spin = _spin_row(grid, "Pivô Y", -2048, 2048, 1)
	z_spin = _spin_row(grid, "Ordem Z", -4096, 4095, 1)
	column.add_child(grid)
	for control_value: Variant in [position_x_spin, position_y_spin, rotation_spin, pivot_x_spin, pivot_y_spin, z_spin]:
		var transform_spin: SpinBox = control_value as SpinBox
		transform_spin.value_changed.connect(Callable(self, "_on_transform_changed"))
	visible_check = _check("Sprite visível neste frame", true, Callable(self, "_on_transform_changed"))
	column.add_child(visible_check)
	var key_row: HBoxContainer = HBoxContainer.new()
	key_row.add_child(_button("Criar key", Callable(self, "_create_key")))
	key_row.add_child(_button("Remover key", Callable(self, "_remove_key")))
	column.add_child(key_row)
	var hint: Label = Label.new()
	hint.text = "No canvas: clique num joint/segmento para selecionar e arraste para mover. Rotação e pivô ficam no Inspector."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.63, 0.7, 0.77)
	column.add_child(hint)
	return scroll

func _build_timeline_panel() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	var toolbar_scroll: ScrollContainer = ScrollContainer.new()
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(toolbar_scroll)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 5)
	toolbar_scroll.add_child(toolbar)
	toolbar.add_child(_button("|◀", Callable(self, "_first_frame")))
	toolbar.add_child(_button("◀", Callable(self, "_previous_frame")))
	play_button = _button("Play", Callable(self, "_toggle_playback"))
	toolbar.add_child(play_button)
	toolbar.add_child(_button("▶", Callable(self, "_next_frame")))
	toolbar.add_child(_button("▶|", Callable(self, "_last_frame")))
	frame_label = Label.new()
	frame_label.custom_minimum_size.x = 105
	frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(frame_label)
	toolbar.add_child(_button("+ Quadro", Callable(self, "_add_frame")))
	toolbar.add_child(_button("Duplicar", Callable(self, "_duplicate_frame")))
	toolbar.add_child(_button("Remover", Callable(self, "_remove_frame")))
	toolbar.add_child(_button("← Quadro", Callable(self, "_move_frame_left")))
	toolbar.add_child(_button("Quadro →", Callable(self, "_move_frame_right")))
	fps_spin = _spin(1, 60, 0.5)
	fps_spin.value_changed.connect(Callable(self, "_on_fps_changed"))
	toolbar.add_child(_labeled_inline("FPS", fps_spin))
	loop_option = OptionButton.new()
	for loop_id: String in ["loop", "pingpong", "once"]:
		var loop_label: String = str({"loop": "Loop", "pingpong": "Ping-pong", "once": "Uma vez"}[loop_id])
		loop_option.add_item(loop_label)
		loop_option.set_item_metadata(loop_option.item_count - 1, loop_id)
	loop_option.item_selected.connect(Callable(self, "_on_loop_selected"))
	toolbar.add_child(loop_option)
	use_duration_check = _check("Duração por quadro", false, Callable(self, "_on_duration_mode_changed"))
	toolbar.add_child(use_duration_check)
	frame_duration_spin = _spin(0.01, 5.0, 0.01)
	frame_duration_spin.suffix = " s"
	frame_duration_spin.value_changed.connect(Callable(self, "_on_frame_duration_changed"))
	toolbar.add_child(frame_duration_spin)
	timeline_cell_width_spin = _spin(24, 128, 2)
	timeline_cell_width_spin.value = 44
	timeline_cell_width_spin.value_changed.connect(Callable(self, "_on_timeline_cell_width_changed"))
	toolbar.add_child(_labeled_inline("Célula", timeline_cell_width_spin))
	timeline_scroll = ScrollContainer.new()
	timeline_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.gui_input.connect(Callable(self, "_on_timeline_scroll_input"))
	column.add_child(timeline_scroll)
	timeline_grid = GridContainer.new()
	timeline_grid.add_theme_constant_override("h_separation", 1)
	timeline_grid.add_theme_constant_override("v_separation", 1)
	timeline_scroll.add_child(timeline_grid)
	status_label = Label.new()
	status_label.modulate = Color(0.67, 0.86, 0.73)
	column.add_child(status_label)
	return column

func _panel_card(title_text: String, content: Control, minimum: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.095, 0.11, 0.135), Color(0.23, 0.29, 0.35), 1))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var header: PanelContainer = PanelContainer.new()
	header.add_theme_stylebox_override("panel", _style_box(Color(0.145, 0.18, 0.21), Color(0.28, 0.38, 0.45), 1))
	var label: Label = Label.new()
	label.text = title_text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(0.7, 0.9, 0.98)
	header.add_child(label)
	column.add_child(header)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(margin)
	margin.add_child(content)
	return panel

func _section_label(text_value: String) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 11)
	label.modulate = Color(0.55, 0.82, 0.94)
	return label

func _button(text_value: String, callback: Callable) -> Button:
	var result: Button = Button.new()
	result.text = text_value
	result.pressed.connect(callback)
	return result

func _check(text_value: String, pressed: bool, callback: Callable) -> CheckBox:
	var result: CheckBox = CheckBox.new()
	result.text = text_value
	result.button_pressed = pressed
	result.toggled.connect(callback)
	return result

func _slider(minimum: float, maximum: float, step_value: float, current_value: float, width: float, callback: Callable) -> HSlider:
	var result: HSlider = HSlider.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step_value
	result.value = current_value
	result.custom_minimum_size.x = width
	result.value_changed.connect(callback)
	return result

func _labeled(text_value: String, control_value: Control) -> Control:
	var result: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = text_value
	label.modulate = Color(0.72, 0.78, 0.84)
	result.add_child(label)
	result.add_child(control_value)
	return result

func _labeled_inline(text_value: String, control_value: Control) -> Control:
	var result: HBoxContainer = HBoxContainer.new()
	result.add_theme_constant_override("separation", 4)
	var label: Label = Label.new()
	label.text = text_value
	label.modulate = Color(0.7, 0.77, 0.83)
	result.add_child(label)
	result.add_child(control_value)
	return result

func _spin(minimum: float, maximum: float, step_value: float) -> SpinBox:
	var result: SpinBox = SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step_value
	result.allow_greater = false
	result.allow_lesser = false
	return result

func _spin_row(parent: GridContainer, label_text: String, minimum: float, maximum: float, step_value: float) -> SpinBox:
	var label: Label = Label.new()
	label.text = label_text
	label.modulate = Color(0.72, 0.78, 0.84)
	parent.add_child(label)
	var result: SpinBox = _spin(minimum, maximum, step_value)
	parent.add_child(result)
	return result
