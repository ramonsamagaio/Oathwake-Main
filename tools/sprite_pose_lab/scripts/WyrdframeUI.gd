extends "res://tools/sprite_pose_lab/scripts/WyrdframeState.gd"

func _build_theme() -> void:
	var studio_theme: Theme = Theme.new()
	studio_theme.default_font_size = 14
	studio_theme.set_color("font_color", "Label", Color(0.9, 0.92, 0.95))
	studio_theme.set_color("font_color", "Button", Color(0.9, 0.92, 0.95))
	studio_theme.set_color("font_color", "CheckBox", Color(0.88, 0.9, 0.93))
	studio_theme.set_color("font_color", "LineEdit", Color(0.92, 0.94, 0.97))
	studio_theme.set_color("font_color", "OptionButton", Color(0.92, 0.94, 0.97))
	studio_theme.set_color("font_color", "Tree", Color(0.88, 0.9, 0.94))
	studio_theme.set_color("font_selected_color", "Tree", Color(1.0, 1.0, 1.0))
	studio_theme.set_color("selection_color", "Tree", Color(0.16, 0.42, 0.58, 1.0))
	studio_theme.set_color("panel", "PanelContainer", Color(0.12, 0.14, 0.17))
	var button_normal: StyleBoxFlat = _style_box(Color(0.18, 0.21, 0.25), Color(0.27, 0.31, 0.36), 1)
	var button_hover: StyleBoxFlat = _style_box(Color(0.23, 0.28, 0.33), Color(0.33, 0.55, 0.67), 1)
	var button_pressed: StyleBoxFlat = _style_box(Color(0.12, 0.38, 0.53), Color(0.25, 0.7, 0.82), 1)
	studio_theme.set_stylebox("normal", "Button", button_normal)
	studio_theme.set_stylebox("hover", "Button", button_hover)
	studio_theme.set_stylebox("pressed", "Button", button_pressed)
	studio_theme.set_stylebox("focus", "Button", button_hover)
	var line_edit_style: StyleBoxFlat = _style_box(Color(0.095, 0.11, 0.135), Color(0.25, 0.29, 0.34), 1)
	studio_theme.set_stylebox("normal", "LineEdit", line_edit_style)
	studio_theme.set_stylebox("normal", "SpinBox", line_edit_style)
	studio_theme.set_stylebox("normal", "OptionButton", button_normal)
	studio_theme.set_stylebox("hover", "OptionButton", button_hover)
	studio_theme.set_stylebox("pressed", "OptionButton", button_pressed)
	studio_theme.set_stylebox("panel", "PanelContainer", _style_box(Color(0.105, 0.12, 0.145), Color(0.22, 0.26, 0.31), 1))
	studio_theme.set_stylebox("panel", "TabContainer", _style_box(Color(0.09, 0.105, 0.13), Color(0.2, 0.24, 0.29), 1))
	studio_theme.set_stylebox("normal", "Tree", _style_box(Color(0.075, 0.09, 0.11), Color(0.18, 0.22, 0.27), 1))
	theme = studio_theme

func _style_box(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6.0
	style.content_margin_top = 5.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 5.0
	return style

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.055, 0.065, 0.08, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	outer.add_child(_build_header())
	root_split = VSplitContainer.new()
	root_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_split.split_offset = 560
	outer.add_child(root_split)
	main_split = HSplitContainer.new()
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 300
	root_split.add_child(main_split)
	main_split.add_child(_panel_card("PROJETO E RIG", _build_left_panel(), Vector2(250, 300)))
	center_split = HSplitContainer.new()
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_split.split_offset = 830
	main_split.add_child(center_split)
	center_split.add_child(_panel_card("CANVAS / PREVIEW", _build_preview_panel(), Vector2(430, 300)))
	center_split.add_child(_panel_card("INSPECTOR", _build_inspector(), Vector2(285, 300)))
	root_split.add_child(_panel_card("TIMELINE", _build_timeline_panel(), Vector2(600, 220)))

func _build_header() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.1, 0.12, 0.145), Color(0.27, 0.34, 0.4), 1))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var title_box: VBoxContainer = VBoxContainer.new()
	var title: Label = Label.new()
	title.text = "WYRD FRAME"
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color(0.63, 0.9, 1.0)
	title_box.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = "OATHWAKE ANIMATION STUDIO"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.modulate = Color(0.62, 0.69, 0.76)
	title_box.add_child(subtitle)
	row.add_child(title_box)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var new_menu: MenuButton = MenuButton.new()
	new_menu.text = "Novo"
	var popup: PopupMenu = new_menu.get_popup()
	var entity_ids: Array[String] = ["character", "monster", "boss", "custom"]
	for entity_index: int in range(entity_ids.size()):
		var entity_id: String = entity_ids[entity_index]
		popup.add_item(str(ENTITY_LABELS[entity_id]), entity_index)
		popup.set_item_metadata(entity_index, entity_id)
	popup.id_pressed.connect(Callable(self, "_on_new_project_type_selected"))
	row.add_child(new_menu)
	row.add_child(_button("Abrir", Callable(self, "_request_load_project")))
	row.add_child(_button("Salvar", Callable(self, "_request_save_project")))
	row.add_child(_button("Desfazer", Callable(self, "_undo")))
	row.add_child(_button("Refazer", Callable(self, "_redo")))
	row.add_child(_button("Exportar frame", Callable(self, "_request_export_frame")))
	row.add_child(_button("Sequência", Callable(self, "_request_export_all")))
	row.add_child(_button("Sheet", Callable(self, "_request_export_sheet")))
	return panel

func _build_left_panel() -> Control:
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var project_tab: VBoxContainer = VBoxContainer.new()
	project_tab.name = "Projeto"
	project_tab.add_theme_constant_override("separation", 7)
	project_tab.add_child(_section_label("IDENTIDADE"))
	project_name_edit = LineEdit.new()
	project_name_edit.placeholder_text = "Nome do projeto"
	project_name_edit.text_changed.connect(Callable(self, "_on_project_name_changed"))
	project_tab.add_child(project_name_edit)
	asset_name_edit = LineEdit.new()
	asset_name_edit.placeholder_text = "Nome interno do asset"
	asset_name_edit.text_changed.connect(Callable(self, "_on_asset_name_changed"))
	project_tab.add_child(asset_name_edit)
	entity_option = OptionButton.new()
	for entity_id: String in ENTITY_LABELS.keys():
		entity_option.add_item(str(ENTITY_LABELS[entity_id]))
		entity_option.set_item_metadata(entity_option.item_count - 1, entity_id)
	entity_option.item_selected.connect(Callable(self, "_on_entity_selected"))
	project_tab.add_child(entity_option)
	project_tab.add_child(_section_label("AÇÕES E DIREÇÕES"))
	project_tree = Tree.new()
	project_tree.hide_root = true
	project_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	project_tree.custom_minimum_size.y = 220
	project_tree.item_selected.connect(Callable(self, "_on_project_tree_selected"))
	project_tab.add_child(project_tree)
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_child(_button("+ Ação custom", Callable(self, "_add_custom_action")))
	action_row.add_child(_button("Remover", Callable(self, "_remove_current_action")))
	project_tab.add_child(action_row)
	action_name_edit = LineEdit.new()
	action_name_edit.placeholder_text = "Renomear ação e Enter"
	action_name_edit.text_submitted.connect(Callable(self, "_rename_current_action"))
	project_tab.add_child(action_name_edit)
	var preset_row: HBoxContainer = HBoxContainer.new()
	action_preset_option = OptionButton.new()
	action_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset_id: String in ACTION_PRESETS.keys():
		var preset_data: Dictionary = ACTION_PRESETS[preset_id] as Dictionary
		action_preset_option.add_item(str(preset_data.get("name", preset_id)))
		action_preset_option.set_item_metadata(action_preset_option.item_count - 1, preset_id)
	preset_row.add_child(action_preset_option)
	preset_row.add_child(_button("Adicionar", Callable(self, "_add_preset_action")))
	project_tab.add_child(preset_row)
	tabs.add_child(project_tab)
	var rig_tab: VBoxContainer = VBoxContainer.new()
	rig_tab.name = "Rig"
	rig_tab.add_theme_constant_override("separation", 7)
	rig_tab.add_child(_section_label("HIERARQUIA DE BONES"))
	rig_tree = Tree.new()
	rig_tree.hide_root = true
	rig_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rig_tree.custom_minimum_size.y = 260
	rig_tree.item_selected.connect(Callable(self, "_on_rig_tree_selected"))
	rig_tab.add_child(rig_tree)
	var bone_row: HBoxContainer = HBoxContainer.new()
	bone_row.add_child(_button("+ Bone", Callable(self, "_add_bone")))
	bone_row.add_child(_button("Remover", Callable(self, "_remove_bone")))
	rig_tab.add_child(bone_row)
	var custom_note: Label = Label.new()
	custom_note.text = "Presets são pontos de partida. Ações, bones, parents e sprites continuam livres."
	custom_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_note.modulate = Color(0.67, 0.74, 0.81)
	rig_tab.add_child(custom_note)
	tabs.add_child(rig_tab)
	return tabs

func _build_preview_panel() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)
	var toolbar_scroll: ScrollContainer = ScrollContainer.new()
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(toolbar_scroll)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 7)
	toolbar_scroll.add_child(toolbar)
	direction_option = OptionButton.new()
	for direction_id: String in DIRECTIONS:
		direction_option.add_item(str(DIRECTION_LABELS[direction_id]))
		direction_option.set_item_metadata(direction_option.item_count - 1, direction_id)
	direction_option.item_selected.connect(Callable(self, "_on_direction_selected"))
	toolbar.add_child(_labeled_inline("Direção", direction_option))
	zoom_option = OptionButton.new()
	for zoom_value: int in range(1, 13):
		zoom_option.add_item("%dx" % zoom_value, zoom_value)
	zoom_option.select(5)
	zoom_option.item_selected.connect(Callable(self, "_on_zoom_selected"))
	toolbar.add_child(_labeled_inline("Zoom", zoom_option))
	pixel_snap_check = _check("Pixel-perfect", true, Callable(self, "_on_view_setting_changed"))
	toolbar.add_child(pixel_snap_check)
	checkerboard_check = _check("Transparência", true, Callable(self, "_on_view_setting_changed"))
	toolbar.add_child(checkerboard_check)
	var display_row: HBoxContainer = HBoxContainer.new()
	display_row.add_theme_constant_override("separation", 8)
	show_bones_check = _check("Bones", true, Callable(self, "_on_view_setting_changed"))
	display_row.add_child(show_bones_check)
	bone_opacity_slider = _slider(0.0, 1.0, 0.01, 0.9, 110, Callable(self, "_on_view_setting_changed"))
	display_row.add_child(_labeled_inline("Opacidade", bone_opacity_slider))
	show_sprites_check = _check("Sprites", true, Callable(self, "_on_view_setting_changed"))
	display_row.add_child(show_sprites_check)
	sprite_opacity_slider = _slider(0.0, 1.0, 0.01, 1.0, 110, Callable(self, "_on_view_setting_changed"))
	display_row.add_child(_labeled_inline("Opacidade", sprite_opacity_slider))
	column.add_child(display_row)
	var onion_row: HBoxContainer = HBoxContainer.new()
	onion_row.add_theme_constant_override("separation", 8)
	previous_check = _check("Anterior vermelho", true, Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(previous_check)
	previous_opacity = _slider(0.0, 1.0, 0.01, 0.24, 100, Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(previous_opacity)
	next_check = _check("Posterior verde", true, Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(next_check)
	next_opacity = _slider(0.0, 1.0, 0.01, 0.24, 100, Callable(self, "_on_view_setting_changed"))
	onion_row.add_child(next_opacity)
	column.add_child(onion_row)
	var canvas_frame: PanelContainer = PanelContainer.new()
	canvas_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_frame.add_theme_stylebox_override("panel", _style_box(Color(0.055, 0.065, 0.08), Color(0.28, 0.36, 0.43), 1))
	column.add_child(canvas_frame)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	canvas_frame.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
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
