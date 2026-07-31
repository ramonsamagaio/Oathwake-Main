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

var viewport: SubViewport
var pose_canvas: Node2D
var preview: TextureRect
var playback_timer: Timer
var file_dialog: FileDialog

var direction_option: OptionButton
var part_option: OptionButton
var path_label: Label
var position_x: SpinBox
var position_y: SpinBox
var rotation: SpinBox
var pivot_x: SpinBox
var pivot_y: SpinBox
var z_index: SpinBox
var part_visible: CheckBox
var snap_integer: CheckBox
var frame_label: Label
var frame_duration: SpinBox
var fps_spin: SpinBox
var duration_mode: CheckBox
var play_button: Button
var width_spin: SpinBox
var height_spin: SpinBox
var feet_spin: SpinBox
var zoom_option: OptionButton
var checker: CheckBox
var grid: CheckBox
var axis: CheckBox
var feet_line: CheckBox
var onion: CheckBox
var character_edit: LineEdit
var animation_edit: LineEdit
var status_label: Label


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	model = ModelScript.new()
	build_interface()
	build_preview()
	build_file_dialog()
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


func build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background := ColorRect.new()
	background.color = Color(0.035, 0.04, 0.05, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(build_header())
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 300
	root.add_child(split)
	var left := panel(build_transform_panel())
	left.custom_minimum_size.x = 290
	split.add_child(left)
	var inner := HSplitContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.split_offset = 760
	split.add_child(inner)
	inner.add_child(panel(build_preview_panel()))
	var right := panel(build_file_panel())
	right.custom_minimum_size.x = 270
	inner.add_child(right)
	root.add_child(build_timeline())


func build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "SPRITE POSE LAB"
	title.add_theme_font_size_override("font_size", 20)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(make_label("Personagem"))
	character_edit = LineEdit.new()
	character_edit.text = "player"
	character_edit.custom_minimum_size.x = 130
	character_edit.text_changed.connect(Callable(self, "on_character_name_changed"))
	row.add_child(character_edit)
	row.add_child(make_label("Animação"))
	animation_edit = LineEdit.new()
	animation_edit.text = "run"
	animation_edit.custom_minimum_size.x = 130
	animation_edit.text_changed.connect(Callable(self, "on_animation_name_changed"))
	row.add_child(animation_edit)
	return row


func build_transform_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.add_child(section_label("CONJUNTO DE PARTES"))
	direction_option = OptionButton.new()
	for text in DIR_LABELS:
		direction_option.add_item(text)
	direction_option.item_selected.connect(Callable(self, "on_direction_selected"))
	column.add_child(labeled("Direção", direction_option))
	part_option = OptionButton.new()
	for text in PART_LABELS:
		part_option.add_item(text)
	part_option.item_selected.connect(Callable(self, "on_part_selected"))
	column.add_child(labeled("Membro", part_option))
	var texture_row := HBoxContainer.new()
	texture_row.add_child(make_button("Carregar PNG", Callable(self, "request_load_part")))
	texture_row.add_child(make_button("Limpar", Callable(self, "clear_part_texture")))
	column.add_child(texture_row)
	path_label = Label.new()
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_label.modulate = Color(0.72, 0.76, 0.82)
	column.add_child(path_label)
	column.add_child(HSeparator.new())
	column.add_child(section_label("TRANSFORM DA POSE"))
	var transform_grid := GridContainer.new()
	transform_grid.columns = 2
	position_x = add_spin_row(transform_grid, "Posição X", -2048, 2048, 1)
	position_y = add_spin_row(transform_grid, "Posição Y", -2048, 2048, 1)
	rotation = add_spin_row(transform_grid, "Rotação", -360, 360, 1)
	rotation.suffix = "°"
	pivot_x = add_spin_row(transform_grid, "Pivô X", -2048, 2048, 1)
	pivot_y = add_spin_row(transform_grid, "Pivô Y", -2048, 2048, 1)
	z_index = add_spin_row(transform_grid, "Ordem Z", -4096, 4096, 1)
	column.add_child(transform_grid)
	for control in [position_x, position_y, rotation, pivot_x, pivot_y, z_index]:
		control.value_changed.connect(Callable(self, "on_transform_changed"))
	part_visible = make_check("Membro visível", true)
	part_visible.toggled.connect(Callable(self, "on_visibility_changed"))
	column.add_child(part_visible)
	snap_integer = make_check("Snap para pixels inteiros", true)
	snap_integer.toggled.connect(Callable(self, "on_snap_changed"))
	column.add_child(snap_integer)
	column.add_child(make_button("Resetar pose deste frame", Callable(self, "reset_current_pose")))
	var note := Label.new()
	note.text = "Esquerda e direita são anatômicas. A sobreposição é definida pelo Z."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.62, 0.66, 0.72)
	column.add_child(note)
	return column


func build_preview_panel() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)
	var settings := HBoxContainer.new()
	width_spin = make_spin(1, 2048, 1)
	width_spin.value = 64
	height_spin = make_spin(1, 2048, 1)
	height_spin.value = 64
	feet_spin = make_spin(0, 2047, 1)
	feet_spin.value = 60
	for control in [width_spin, height_spin, feet_spin]:
		control.custom_minimum_size.x = 75
		control.value_changed.connect(Callable(self, "on_canvas_settings_changed"))
	settings.add_child(make_label("Canvas"))
	settings.add_child(width_spin)
	settings.add_child(make_label("×"))
	settings.add_child(height_spin)
	settings.add_child(make_label("Pés"))
	settings.add_child(feet_spin)
	zoom_option = OptionButton.new()
	for zoom in range(1, 13):
		zoom_option.add_item("%dx" % zoom, zoom)
	zoom_option.select(5)
	zoom_option.item_selected.connect(Callable(self, "on_zoom_selected"))
	settings.add_child(make_label("Zoom"))
	settings.add_child(zoom_option)
	column.add_child(settings)
	var guide_row := HBoxContainer.new()
	checker = make_check("Quadriculado", true)
	grid = make_check("Grade", false)
	axis = make_check("Eixo", true)
	feet_line = make_check("Linha dos pés", true)
	onion = make_check("Onion skin", false)
	for control in [checker, grid, axis, feet_line, onion]:
		control.toggled.connect(Callable(self, "on_guides_changed"))
		guide_row.add_child(control)
	column.add_child(guide_row)
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
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(preview)
	return column


func build_file_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.add_child(section_label("POSES E CICLOS"))
	column.add_child(make_button("Salvar pose JSON", Callable(self, "request_save_pose")))
	column.add_child(make_button("Carregar pose JSON", Callable(self, "request_load_pose")))
	column.add_child(make_button("Salvar ciclo JSON", Callable(self, "request_save_cycle")))
	column.add_child(make_button("Carregar ciclo JSON", Callable(self, "request_load_cycle")))
	column.add_child(HSeparator.new())
	column.add_child(section_label("EXPORTAÇÃO"))
	column.add_child(make_button("Exportar frame atual", Callable(self, "request_export_frame")))
	column.add_child(make_button("Exportar frames separados", Callable(self, "request_export_all")))
	column.add_child(make_button("Exportar sprite sheet", Callable(self, "request_export_sheet")))
	column.add_child(HSeparator.new())
	status_label = Label.new()
	status_label.text = "Pronto. Os blocos coloridos são placeholders."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(status_label)
	var note := Label.new()
	note.text = "PNG RGBA, canvas fixo, filtro Nearest e nenhuma interpolação automática."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.62, 0.66, 0.72)
	column.add_child(note)
	return column


func build_timeline() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(make_button("◀", Callable(self, "previous_frame")))
	frame_label = Label.new()
	frame_label.custom_minimum_size.x = 110
	frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(frame_label)
	row.add_child(make_button("▶", Callable(self, "next_frame")))
	row.add_child(make_button("+ Frame", Callable(self, "add_frame")))
	row.add_child(make_button("Duplicar", Callable(self, "duplicate_frame")))
	row.add_child(make_button("Remover", Callable(self, "remove_frame")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	duration_mode = make_check("Duração por frame", false)
	duration_mode.toggled.connect(Callable(self, "on_duration_mode_changed"))
	row.add_child(duration_mode)
	frame_duration = make_spin(0.01, 10, 0.01)
	frame_duration.suffix = " s"
	frame_duration.value_changed.connect(Callable(self, "on_frame_duration_changed"))
	row.add_child(frame_duration)
	row.add_child(make_label("FPS"))
	fps_spin = make_spin(1, 60, 0.5)
	fps_spin.value_changed.connect(Callable(self, "on_fps_changed"))
	row.add_child(fps_spin)
	play_button = make_button("Reproduzir", Callable(self, "toggle_playback"))
	row.add_child(play_button)
	return panel(row)


func build_preview() -> void:
	viewport = SubViewport.new()
	viewport.name = "PoseRenderViewport"
	viewport.size = model.canvas_size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	pose_canvas = CanvasScript.new()
	pose_canvas.name = "PoseCanvas"
	viewport.add_child(pose_canvas)
	pose_canvas.configure(model.canvas_size, model.feet_y)
	preview.texture = viewport.get_texture()
	call("update_preview_size")


func build_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(Callable(self, "on_file_selected"))
	file_dialog.dir_selected.connect(Callable(self, "on_directory_selected"))
	file_dialog.canceled.connect(Callable(self, "on_file_dialog_canceled"))
	add_child(file_dialog)


func panel(content: Control) -> PanelContainer:
	var result := PanelContainer.new()
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	result.add_child(margin)
	margin.add_child(content)
	return result


func make_label(text: String) -> Label:
	var result := Label.new()
	result.text = text
	return result


func section_label(text: String) -> Label:
	var result := make_label(text)
	result.add_theme_font_size_override("font_size", 14)
	result.modulate = Color(0.86, 0.9, 0.95)
	return result


func labeled(text: String, control: Control) -> Control:
	var result := VBoxContainer.new()
	result.add_child(make_label(text))
	result.add_child(control)
	return result


func make_spin(minimum: float, maximum: float, step: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step
	result.allow_greater = false
	result.allow_lesser = false
	return result


func add_spin_row(parent: GridContainer, text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var result := make_spin(minimum, maximum, step)
	parent.add_child(make_label(text))
	parent.add_child(result)
	return result


func make_check(text: String, pressed: bool) -> CheckBox:
	var result := CheckBox.new()
	result.text = text
	result.button_pressed = pressed
	return result


func make_button(text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(callback)
	return result


func set_status(text: String, error: bool = false) -> void:
	status_label.text = text
	status_label.modulate = Color(1.0, 0.48, 0.42) if error else Color(0.78, 0.86, 0.8)
