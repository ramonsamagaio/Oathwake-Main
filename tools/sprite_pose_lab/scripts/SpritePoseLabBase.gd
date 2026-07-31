extends Control

const CanvasScript := preload("res://tools/sprite_pose_lab/scripts/SpritePoseCanvas.gd")
const ModelScript := preload("res://tools/sprite_pose_lab/scripts/SpritePoseModel.gd")
const DIR_LABELS := ["Sul", "Norte", "Leste", "Oeste"]
const PART_LABELS := ["Cabeça", "Tronco", "Braço esquerdo", "Braço direito", "Perna esquerda", "Perna direita"]
const DATA_DIR := "user://sprite_pose_lab"

enum FileAction {
	NONE,
	LOAD_PART,
	SAVE_POSE,
	LOAD_POSE,
	SAVE_CYCLE,
	LOAD_CYCLE,
	EXPORT_FRAME,
	EXPORT_ALL,
	EXPORT_SHEET,
}

var model
var frame_index := 0
var part_index := 0
var playing := false
var updating := false
var file_action := FileAction.NONE

var render_viewport: SubViewport
var pose_canvas
var preview: TextureRect
var playback_timer: Timer
var file_dialog: FileDialog

var direction_option: OptionButton
var part_option: OptionButton
var path_label: Label
var position_x_spin: SpinBox
var position_y_spin: SpinBox
var rotation_spin: SpinBox
var pivot_x_spin: SpinBox
var pivot_y_spin: SpinBox
var z_order_spin: SpinBox
var part_visible_check: CheckBox
var snap_integer_check: CheckBox
var frame_label: Label
var frame_duration_spin: SpinBox
var fps_spin: SpinBox
var duration_mode_check: CheckBox
var play_button: Button
var width_spin: SpinBox
var height_spin: SpinBox
var feet_spin: SpinBox
var zoom_option: OptionButton
var checker_check: CheckBox
var grid_check: CheckBox
var axis_check: CheckBox
var feet_line_check: CheckBox
var onion_check: CheckBox
var pixel_preview_check: CheckBox
var gizmo_check: CheckBox
var character_edit: LineEdit
var animation_edit: LineEdit
var status_label: Label


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	model = ModelScript.new()
	_build_interface()
	_build_preview()
	_build_file_dialog()
	playback_timer = Timer.new()
	playback_timer.one_shot = true
	playback_timer.timeout.connect(Callable(self, "on_playback_timeout"))
	add_child(playback_timer)
	call("refresh_all")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_LEFT:
		call("step_frame", -1)
	elif event.keycode == KEY_RIGHT:
		call("step_frame", 1)
	elif event.keycode == KEY_SPACE:
		call("toggle_playback")
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var background := ColorRect.new()
	background.color = Color(0.035, 0.04, 0.05, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side_name in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side_name, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(_build_header())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 300
	root.add_child(split)

	var left_panel := _panel(_build_transform_panel())
	left_panel.custom_minimum_size.x = 290
	split.add_child(left_panel)

	var inner := HSplitContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.split_offset = 760
	split.add_child(inner)
	inner.add_child(_panel(_build_preview_panel()))

	var right_panel := _panel(_build_file_panel())
	right_panel.custom_minimum_size.x = 270
	inner.add_child(right_panel)
	root.add_child(_build_timeline())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "SPRITE POSE LAB"
	title.add_theme_font_size_override("font_size", 20)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(_make_label("Personagem"))
	character_edit = LineEdit.new()
	character_edit.text = "player"
	character_edit.custom_minimum_size.x = 130
	character_edit.text_changed.connect(Callable(self, "on_character_name_changed"))
	row.add_child(character_edit)

	row.add_child(_make_label("Animação"))
	animation_edit = LineEdit.new()
	animation_edit.text = "run"
	animation_edit.custom_minimum_size.x = 130
	animation_edit.text_changed.connect(Callable(self, "on_animation_name_changed"))
	row.add_child(animation_edit)
	return row


func _build_transform_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.add_child(_section_label("CONJUNTO DE PARTES"))

	direction_option = OptionButton.new()
	for direction_label in DIR_LABELS:
		direction_option.add_item(direction_label)
	direction_option.item_selected.connect(Callable(self, "on_direction_selected"))
	column.add_child(_labeled("Direção", direction_option))

	part_option = OptionButton.new()
	for part_label in PART_LABELS:
		part_option.add_item(part_label)
	part_option.item_selected.connect(Callable(self, "on_part_selected"))
	column.add_child(_labeled("Membro", part_option))

	var texture_row := HBoxContainer.new()
	texture_row.add_child(_make_button("Carregar PNG", Callable(self, "request_load_part")))
	texture_row.add_child(_make_button("Limpar", Callable(self, "clear_part_texture")))
	column.add_child(texture_row)

	path_label = Label.new()
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_label.modulate = Color(0.72, 0.76, 0.82)
	column.add_child(path_label)
	column.add_child(HSeparator.new())
	column.add_child(_section_label("TRANSFORM DA POSE"))

	var transform_grid := GridContainer.new()
	transform_grid.columns = 2
	position_x_spin = _add_spin_row(transform_grid, "Posição X", -2048, 2048, 1)
	position_y_spin = _add_spin_row(transform_grid, "Posição Y", -2048, 2048, 1)
	rotation_spin = _add_spin_row(transform_grid, "Rotação", -360, 360, 1)
	rotation_spin.suffix = "°"
	pivot_x_spin = _add_spin_row(transform_grid, "Pivô X", -2048, 2048, 1)
	pivot_y_spin = _add_spin_row(transform_grid, "Pivô Y", -2048, 2048, 1)
	z_order_spin = _add_spin_row(transform_grid, "Ordem Z", -4096, 4096, 1)
	column.add_child(transform_grid)

	for transform_control in [position_x_spin, position_y_spin, rotation_spin, pivot_x_spin, pivot_y_spin, z_order_spin]:
		transform_control.value_changed.connect(Callable(self, "on_transform_changed"))

	part_visible_check = _make_check("Membro visível", true)
	part_visible_check.toggled.connect(Callable(self, "on_visibility_changed"))
	column.add_child(part_visible_check)

	snap_integer_check = _make_check("Snap para pixels inteiros", true)
	snap_integer_check.toggled.connect(Callable(self, "on_snap_changed"))
	column.add_child(snap_integer_check)

	column.add_child(_make_button("Resetar pose deste frame", Callable(self, "reset_current_pose")))

	var note := Label.new()
	note.text = "Gizmo: verde move, vermelho gira e amarelo edita o pivô. Quando o verde e o amarelo coincidirem, use Alt + arrastar para mover o pivô."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.62, 0.66, 0.72)
	column.add_child(note)
	return column


func _build_preview_panel() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)

	var settings := HBoxContainer.new()
	width_spin = _make_spin(1, 2048, 1)
	width_spin.value = 64
	height_spin = _make_spin(1, 2048, 1)
	height_spin.value = 64
	feet_spin = _make_spin(0, 2047, 1)
	feet_spin.value = 60
	for canvas_control in [width_spin, height_spin, feet_spin]:
		canvas_control.custom_minimum_size.x = 75
		canvas_control.value_changed.connect(Callable(self, "on_canvas_settings_changed"))
	settings.add_child(_make_label("Canvas"))
	settings.add_child(width_spin)
	settings.add_child(_make_label("×"))
	settings.add_child(height_spin)
	settings.add_child(_make_label("Pés"))
	settings.add_child(feet_spin)

	zoom_option = OptionButton.new()
	for zoom_value in range(1, 13):
		zoom_option.add_item("%dx" % zoom_value, zoom_value)
	zoom_option.select(5)
	zoom_option.item_selected.connect(Callable(self, "on_zoom_selected"))
	settings.add_child(_make_label("Zoom"))
	settings.add_child(zoom_option)
	column.add_child(settings)

	var guide_row := HBoxContainer.new()
	checker_check = _make_check("Quadriculado", true)
	grid_check = _make_check("Grade", false)
	axis_check = _make_check("Eixo", true)
	feet_line_check = _make_check("Linha dos pés", true)
	onion_check = _make_check("Onion skin", false)
	for guide_control in [checker_check, grid_check, axis_check, feet_line_check, onion_check]:
		guide_control.toggled.connect(Callable(self, "on_guides_changed"))
		guide_row.add_child(guide_control)
	column.add_child(guide_row)

	var mode_row := HBoxContainer.new()
	pixel_preview_check = _make_check("Raster pixel-perfect", true)
	pixel_preview_check.tooltip_text = "Renderiza na resolução nativa e aproxima o resultado à grade de pixels sem alterar o PNG original."
	pixel_preview_check.toggled.connect(Callable(self, "on_pixel_preview_changed"))
	mode_row.add_child(pixel_preview_check)
	gizmo_check = _make_check("Gizmo", true)
	gizmo_check.toggled.connect(Callable(self, "on_gizmo_changed"))
	mode_row.add_child(gizmo_check)
	column.add_child(mode_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
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
	preview.gui_input.connect(Callable(self, "on_preview_gui_input"))
	center.add_child(preview)
	return column


func _build_file_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.add_child(_section_label("POSES E CICLOS"))
	column.add_child(_make_button("Salvar pose JSON", Callable(self, "request_save_pose")))
	column.add_child(_make_button("Carregar pose JSON", Callable(self, "request_load_pose")))
	column.add_child(_make_button("Salvar ciclo JSON", Callable(self, "request_save_cycle")))
	column.add_child(_make_button("Carregar ciclo JSON", Callable(self, "request_load_cycle")))
	column.add_child(HSeparator.new())
	column.add_child(_section_label("EXPORTAÇÃO"))
	column.add_child(_make_button("Exportar frame atual", Callable(self, "request_export_frame")))
	column.add_child(_make_button("Exportar frames separados", Callable(self, "request_export_all")))
	column.add_child(_make_button("Exportar sprite sheet", Callable(self, "request_export_sheet")))
	column.add_child(HSeparator.new())

	status_label = Label.new()
	status_label.text = "Pronto. Os blocos coloridos são placeholders."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(status_label)

	var note := Label.new()
	note.text = "O PNG original nunca é alterado. O preview e a exportação são snapshots rasterizados no canvas nativo."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.62, 0.66, 0.72)
	column.add_child(note)
	return column


func _build_timeline() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_make_button("◀", Callable(self, "previous_frame")))
	frame_label = Label.new()
	frame_label.custom_minimum_size.x = 110
	frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(frame_label)
	row.add_child(_make_button("▶", Callable(self, "next_frame")))
	row.add_child(_make_button("+ Frame", Callable(self, "add_frame")))
	row.add_child(_make_button("Duplicar", Callable(self, "duplicate_frame")))
	row.add_child(_make_button("Remover", Callable(self, "remove_frame")))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	duration_mode_check = _make_check("Duração por frame", false)
	duration_mode_check.toggled.connect(Callable(self, "on_duration_mode_changed"))
	row.add_child(duration_mode_check)
	frame_duration_spin = _make_spin(0.01, 10, 0.01)
	frame_duration_spin.suffix = " s"
	frame_duration_spin.value_changed.connect(Callable(self, "on_frame_duration_changed"))
	row.add_child(frame_duration_spin)
	row.add_child(_make_label("FPS"))
	fps_spin = _make_spin(1, 60, 0.5)
	fps_spin.value_changed.connect(Callable(self, "on_fps_changed"))
	row.add_child(fps_spin)
	play_button = _make_button("Reproduzir", Callable(self, "toggle_playback"))
	row.add_child(play_button)
	return _panel(row)


func _build_preview() -> void:
	render_viewport = SubViewport.new()
	render_viewport.name = "PoseRenderViewport"
	render_viewport.size = model.canvas_size
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
	pose_canvas.configure(model.canvas_size, model.feet_y)
	preview.texture = render_viewport.get_texture()
	call("update_preview_size")


func _build_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(Callable(self, "on_file_selected"))
	file_dialog.dir_selected.connect(Callable(self, "on_directory_selected"))
	file_dialog.canceled.connect(Callable(self, "on_file_dialog_canceled"))
	add_child(file_dialog)


func _panel(content: Control) -> PanelContainer:
	var result := PanelContainer.new()
	var margin := MarginContainer.new()
	for side_name in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side_name, 10)
	result.add_child(margin)
	margin.add_child(content)
	return result


func _make_label(label_text: String) -> Label:
	var result := Label.new()
	result.text = label_text
	return result


func _section_label(label_text: String) -> Label:
	var result := _make_label(label_text)
	result.add_theme_font_size_override("font_size", 14)
	result.modulate = Color(0.86, 0.9, 0.95)
	return result


func _labeled(label_text: String, control: Control) -> Control:
	var result := VBoxContainer.new()
	result.add_child(_make_label(label_text))
	result.add_child(control)
	return result


func _make_spin(minimum: float, maximum: float, step_value: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step_value
	result.allow_greater = false
	result.allow_lesser = false
	return result


func _add_spin_row(parent: GridContainer, label_text: String, minimum: float, maximum: float, step_value: float) -> SpinBox:
	var result := _make_spin(minimum, maximum, step_value)
	parent.add_child(_make_label(label_text))
	parent.add_child(result)
	return result


func _make_check(label_text: String, pressed: bool) -> CheckBox:
	var result := CheckBox.new()
	result.text = label_text
	result.button_pressed = pressed
	return result


func _make_button(label_text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = label_text
	result.pressed.connect(callback)
	return result


func set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.modulate = Color(1.0, 0.48, 0.42) if is_error else Color(0.78, 0.86, 0.8)
