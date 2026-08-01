extends Control

const PROGRAM_NAME: String = "Wyrdframe Studio"
const FORMAT_NAME: String = "wyrdframe_project"
const FORMAT_VERSION: int = 4
const FILE_EXTENSION: String = "wyrd"
const DATA_DIR: String = "user://wyrdframe"
const AUTOSAVE_PATH: String = "user://wyrdframe/autosave.wyrd"
const LAYOUT_PATH: String = "user://wyrdframe/layout.cfg"
const DIRECTIONS: Array[String] = ["south", "north", "east", "west"]
const DIRECTION_LABELS: Dictionary = {
	"south": "Sul",
	"north": "Norte",
	"east": "Leste",
	"west": "Oeste",
}
const ENTITY_LABELS: Dictionary = {
	"character": "Personagem",
	"monster": "Monstro",
	"boss": "Boss",
	"custom": "Custom",
}
const ACTION_PRESETS: Dictionary = {
	"idle": {"name": "Idle", "frames": 4},
	"walk": {"name": "Walk", "frames": 4},
	"run": {"name": "Run", "frames": 6},
	"attack_1h": {"name": "Attack 1H", "frames": 6},
	"attack_2h": {"name": "Attack 2H", "frames": 7},
	"attack_bow": {"name": "Attack Bow", "frames": 7},
	"attack": {"name": "Attack", "frames": 6},
	"cast": {"name": "Cast", "frames": 6},
	"hit": {"name": "Hit", "frames": 4},
	"death": {"name": "Death", "frames": 8},
	"phase": {"name": "Phase", "frames": 8},
	"custom": {"name": "Custom", "frames": 1},
}
const ENTITY_STARTERS: Dictionary = {
	"character": ["idle", "walk", "run", "attack_1h", "attack_2h", "attack_bow", "custom"],
	"monster": ["idle", "walk", "attack", "hit", "death", "custom"],
	"boss": ["idle", "walk", "attack", "cast", "phase", "hit", "death", "custom"],
	"custom": ["custom"],
}

enum FileAction {
	NONE,
	LOAD_TEXTURE,
	SAVE_PROJECT,
	LOAD_PROJECT,
	EXPORT_FRAME,
	EXPORT_ALL,
	EXPORT_SHEET,
}

var document: Dictionary = {}
var current_action: String = "idle"
var current_direction: String = "south"
var current_frame: int = 0
var selected_bone: String = "torso"
var current_project_path: String = ""
var dirty: bool = false
var updating_ui: bool = false
var playing: bool = false
var playback_direction: int = 1
var file_action: int = FileAction.NONE
var drag_active: bool = false
var drag_start_canvas: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO

var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

var root_split: VSplitContainer
var main_split: HSplitContainer
var center_split: HSplitContainer
var project_tree: Tree
var rig_tree: Tree
var action_option: OptionButton
var direction_option: OptionButton
var entity_option: OptionButton
var project_name_edit: LineEdit
var asset_name_edit: LineEdit
var action_name_edit: LineEdit
var status_label: Label
var preview: TextureRect
var timeline_grid: GridContainer
var timeline_scroll: ScrollContainer
var timeline_cell_width_spin: SpinBox
var frame_label: Label
var play_button: Button
var fps_spin: SpinBox
var loop_option: OptionButton
var frame_duration_spin: SpinBox
var use_duration_check: CheckBox
var previous_check: CheckBox
var next_check: CheckBox
var previous_opacity: HSlider
var next_opacity: HSlider
var zoom_option: OptionButton
var pixel_snap_check: CheckBox
var bone_name_edit: LineEdit
var parent_option: OptionButton
var texture_path_label: Label
var position_x_spin: SpinBox
var position_y_spin: SpinBox
var rotation_spin: SpinBox
var pivot_x_spin: SpinBox
var pivot_y_spin: SpinBox
var z_spin: SpinBox
var visible_check: CheckBox
var locked_check: CheckBox
var file_dialog: FileDialog
var playback_timer: Timer
var autosave_timer: Timer
var render_viewport: SubViewport
var previous_root: Node2D
var current_root: Node2D
var next_root: Node2D
var node_maps: Dictionary = {}
var sprite_maps: Dictionary = {}
var texture_cache: Dictionary = {}
var placeholder_cache: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	_create_new_document("character")
	_build_ui()
	_build_rendering()
	_build_runtime_helpers()
	_restore_layout()
	_rebuild_all()
	_configure_window()
	_set_status("Wyrdframe pronto. Projeto novo criado.")


func _exit_tree() -> void:
	_save_layout()


func _configure_window() -> void:
	var app_window: Window = get_window()
	app_window.title = PROGRAM_NAME
	app_window.unresizable = false
	app_window.min_size = Vector2i(1050, 680)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed and key_event.keycode == KEY_S:
		_request_save_project()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_O:
		_request_load_project()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_Z:
		_undo()
	elif key_event.ctrl_pressed and key_event.keycode == KEY_Y:
		_redo()
	elif key_event.alt_pressed and key_event.keycode == KEY_D:
		_duplicate_frame()
	elif key_event.keycode == KEY_INSERT:
		_add_frame()
	elif key_event.keycode == KEY_DELETE:
		_remove_frame()
	elif key_event.keycode == KEY_LEFT:
		_select_frame(current_frame - 1)
	elif key_event.keycode == KEY_RIGHT:
		_select_frame(current_frame + 1)
	elif key_event.keycode == KEY_SPACE:
		_toggle_playback()
		get_viewport().set_input_as_handled()


func _create_new_document(entity_type: String) -> void:
	var safe_type: String = entity_type if ENTITY_LABELS.has(entity_type) else "custom"
	document = {
		"format": FORMAT_NAME,
		"version": FORMAT_VERSION,
		"project": {
			"name": "Novo Projeto",
			"asset_name": "player" if safe_type == "character" else safe_type,
			"entity_type": safe_type,
		},
		"canvas": {"width": 64, "height": 64, "feet_y": 60},
		"playback": {"fps": 8.0, "loop_mode": "loop", "use_frame_durations": false},
		"rig": {"bones": _default_bones()},
		"actions": {},
		"metadata": {"created_with": PROGRAM_NAME, "notes": ""},
	}
	var starter_value: Variant = ENTITY_STARTERS.get(safe_type, ["custom"])
	var starter_actions: Array = starter_value as Array
	for preset_value: Variant in starter_actions:
		_add_action_data(str(preset_value), str(preset_value), false)
	var action_keys: Array = _actions().keys()
	current_action = str(action_keys[0]) if not action_keys.is_empty() else "custom"
	current_direction = "south"
	current_frame = 0
	selected_bone = "torso"
	current_project_path = ""
	dirty = false
	undo_stack.clear()
	redo_stack.clear()


func _default_bones() -> Array:
	return [
		_bone("root", "Root", "", false, Vector2.ZERO, 0),
		_bone("torso", "Tronco", "root", true, Vector2.ZERO, 3),
		_bone("head", "Cabeça", "torso", true, Vector2(0, -18), 5),
		_bone("left_arm", "Braço esquerdo", "torso", true, Vector2(-11, 0), 4),
		_bone("right_arm", "Braço direito", "torso", true, Vector2(11, 0), 2),
		_bone("left_leg", "Perna esquerda", "root", true, Vector2(-4, 17), 1),
		_bone("right_leg", "Perna direita", "root", true, Vector2(4, 17), 0),
	]


func _bone(id_value: String, label: String, parent_id: String, has_sprite: bool, position_value: Vector2, order: int) -> Dictionary:
	return {
		"id": id_value,
		"name": label,
		"parent": parent_id,
		"has_sprite": has_sprite,
		"locked": false,
		"rest": _transform_dict(position_value, 0.0, Vector2.ZERO, order, true),
		"constraints": {"rotation_min": -180.0, "rotation_max": 180.0, "foot_contact": id_value.ends_with("leg")},
	}


func _transform_dict(position_value: Vector2, rotation_value: float, pivot_value: Vector2, order: int, is_visible: bool) -> Dictionary:
	return {
		"position": [position_value.x, position_value.y],
		"rotation_degrees": rotation_value,
		"pivot": [pivot_value.x, pivot_value.y],
		"z_index": order,
		"visible": is_visible,
	}


func _project_section() -> Dictionary:
	return document.get("project", {}) as Dictionary


func _canvas_section() -> Dictionary:
	return document.get("canvas", {}) as Dictionary


func _playback_section() -> Dictionary:
	return document.get("playback", {}) as Dictionary


func _rig_section() -> Dictionary:
	return document.get("rig", {}) as Dictionary


func _bones() -> Array:
	return _rig_section().get("bones", []) as Array


func _actions() -> Dictionary:
	return document.get("actions", {}) as Dictionary


func _action_data(action_id: String = "") -> Dictionary:
	var target: String = current_action if action_id.is_empty() else action_id
	return _actions().get(target, {}) as Dictionary


func _direction_data(action_id: String = "", direction_id: String = "") -> Dictionary:
	var target_direction: String = current_direction if direction_id.is_empty() else direction_id
	var directions: Dictionary = _action_data(action_id).get("directions", {}) as Dictionary
	return directions.get(target_direction, {}) as Dictionary


func _frames() -> Array:
	return _direction_data().get("frames", []) as Array


func _frame_data(index: int) -> Dictionary:
	var frames_value: Array = _frames()
	if frames_value.is_empty():
		frames_value.append(_new_frame())
	var safe_index: int = clampi(index, 0, frames_value.size() - 1)
	return frames_value[safe_index] as Dictionary


func _new_frame() -> Dictionary:
	return {"duration": 0.125, "keys": {}}


func _bone_by_id(bone_id: String) -> Dictionary:
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if str(bone_data.get("id", "")) == bone_id:
			return bone_data
	return {}


func _unique_id(label: String, existing: Array, fallback: String) -> String:
	var base_id: String = label.strip_edges().to_lower().to_snake_case()
	var regex: RegEx = RegEx.new()
	regex.compile("[^a-z0-9_]+")
	base_id = regex.sub(base_id, "_", true).trim_prefix("_").trim_suffix("_")
	if base_id.is_empty():
		base_id = fallback
	var candidate: String = base_id
	var suffix: int = 2
	while existing.has(candidate):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1
	return candidate


func _add_action_data(preset_id: String, requested_id: String, mark_change: bool = true) -> String:
	var existing: Array = _actions().keys()
	var action_id: String = _unique_id(requested_id, existing, "action")
	var preset: Dictionary = ACTION_PRESETS.get(preset_id, ACTION_PRESETS["custom"]) as Dictionary
	var directions: Dictionary = {}
	var frame_count: int = maxi(1, int(preset.get("frames", 1)))
	for direction_id: String in DIRECTIONS:
		var frames_value: Array = []
		for _frame_number: int in range(frame_count):
			frames_value.append(_new_frame())
		var textures: Dictionary = {}
		for bone_value: Variant in _bones():
			var bone_data: Dictionary = bone_value as Dictionary
			textures[str(bone_data.get("id", ""))] = ""
		directions[direction_id] = {"frames": frames_value, "textures": textures}
	_actions()[action_id] = {"name": str(preset.get("name", action_id.capitalize())), "preset": preset_id, "directions": directions}
	_key_rest_pose(action_id)
	if mark_change:
		_mark_changed("Ação adicionada.")
	return action_id


func _key_rest_pose(action_id: String) -> void:
	for direction_id: String in DIRECTIONS:
		var direction_data: Dictionary = _direction_data(action_id, direction_id)
		var frames_value: Array = direction_data.get("frames", []) as Array
		if frames_value.is_empty():
			frames_value.append(_new_frame())
		var first_frame: Dictionary = frames_value[0] as Dictionary
		var keys: Dictionary = first_frame.get("keys", {}) as Dictionary
		for bone_value: Variant in _bones():
			var bone_data: Dictionary = bone_value as Dictionary
			keys[str(bone_data.get("id", ""))] = (bone_data.get("rest", {}) as Dictionary).duplicate(true)
		first_frame["keys"] = keys


func _resolved_transform(frame_index: int, bone_id: String) -> Dictionary:
	var bone_data: Dictionary = _bone_by_id(bone_id)
	var result: Dictionary = (bone_data.get("rest", _transform_dict(Vector2.ZERO, 0.0, Vector2.ZERO, 0, true)) as Dictionary).duplicate(true)
	var frames_value: Array = _frames()
	var last_index: int = mini(frame_index, frames_value.size() - 1)
	for index: int in range(last_index + 1):
		var frame_data: Dictionary = frames_value[index] as Dictionary
		var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
		if keys.has(bone_id):
			result = (keys[bone_id] as Dictionary).duplicate(true)
	return result


func _ensure_key(frame_index: int, bone_id: String) -> Dictionary:
	var frame_data: Dictionary = _frame_data(frame_index)
	var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
	if not keys.has(bone_id):
		keys[bone_id] = _resolved_transform(frame_index, bone_id)
	frame_data["keys"] = keys
	return keys[bone_id] as Dictionary


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.025, 0.028, 0.034, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 7)
	margin.add_child(outer)
	outer.add_child(_build_header())
	root_split = VSplitContainer.new()
	root_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_split.split_offset = 570
	outer.add_child(root_split)
	main_split = HSplitContainer.new()
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 285
	root_split.add_child(main_split)
	main_split.add_child(_panel(_build_left_panel(), Vector2(230, 300)))
	center_split = HSplitContainer.new()
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_split.split_offset = 850
	main_split.add_child(center_split)
	center_split.add_child(_panel(_build_preview_panel(), Vector2(380, 300)))
	center_split.add_child(_panel(_build_inspector(), Vector2(270, 300)))
	root_split.add_child(_panel(_build_timeline_panel(), Vector2(500, 210)))


func _build_header() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var title: Label = Label.new()
	title.text = "WYRD FRAME  •  OATHWAKE ANIMATION STUDIO"
	title.add_theme_font_size_override("font_size", 18)
	row.add_child(title)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("Novo", _new_project_dialog))
	row.add_child(_button("Abrir", _request_load_project))
	row.add_child(_button("Salvar", _request_save_project))
	row.add_child(_button("Desfazer", _undo))
	row.add_child(_button("Refazer", _redo))
	row.add_child(_button("Exportar frame", _request_export_frame))
	row.add_child(_button("Sequência", _request_export_all))
	row.add_child(_button("Sheet", _request_export_sheet))
	return row


func _build_left_panel() -> Control:
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var project_tab: VBoxContainer = VBoxContainer.new()
	project_tab.name = "Projeto"
	project_tab.add_theme_constant_override("separation", 6)
	project_name_edit = LineEdit.new()
	project_name_edit.placeholder_text = "Nome do projeto"
	project_name_edit.text_changed.connect(_on_project_name_changed)
	project_tab.add_child(project_name_edit)
	asset_name_edit = LineEdit.new()
	asset_name_edit.placeholder_text = "Nome interno do asset"
	asset_name_edit.text_changed.connect(_on_asset_name_changed)
	project_tab.add_child(asset_name_edit)
	entity_option = OptionButton.new()
	for entity_id: String in ENTITY_LABELS.keys():
		entity_option.add_item(str(ENTITY_LABELS[entity_id]))
		entity_option.set_item_metadata(entity_option.item_count - 1, entity_id)
	entity_option.item_selected.connect(_on_entity_selected)
	project_tab.add_child(entity_option)
	project_tree = Tree.new()
	project_tree.hide_root = true
	project_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	project_tree.item_selected.connect(_on_project_tree_selected)
	project_tab.add_child(project_tree)
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_child(_button("+ Ação", _add_custom_action))
	action_row.add_child(_button("Remover", _remove_current_action))
	project_tab.add_child(action_row)
	action_name_edit = LineEdit.new()
	action_name_edit.placeholder_text = "Renomear ação"
	action_name_edit.text_submitted.connect(_rename_current_action)
	project_tab.add_child(action_name_edit)
	var preset_row: HBoxContainer = HBoxContainer.new()
	action_option = OptionButton.new()
	for preset_id: String in ACTION_PRESETS.keys():
		var preset_data: Dictionary = ACTION_PRESETS[preset_id] as Dictionary
		action_option.add_item(str(preset_data.get("name", preset_id)))
		action_option.set_item_metadata(action_option.item_count - 1, preset_id)
	preset_row.add_child(action_option)
	preset_row.add_child(_button("Adicionar preset", _add_preset_action))
	project_tab.add_child(preset_row)
	tabs.add_child(project_tab)
	var rig_tab: VBoxContainer = VBoxContainer.new()
	rig_tab.name = "Rig"
	rig_tab.add_theme_constant_override("separation", 6)
	rig_tree = Tree.new()
	rig_tree.hide_root = true
	rig_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rig_tree.item_selected.connect(_on_rig_tree_selected)
	rig_tab.add_child(rig_tree)
	var bone_row: HBoxContainer = HBoxContainer.new()
	bone_row.add_child(_button("+ Bone", _add_bone))
	bone_row.add_child(_button("Remover", _remove_bone))
	rig_tab.add_child(bone_row)
	var custom_note: Label = Label.new()
	custom_note.text = "Presets são atalhos. O modo custom permanece disponível em ações, rig e sprites."
	custom_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_note.modulate = Color(0.65, 0.69, 0.75)
	rig_tab.add_child(custom_note)
	tabs.add_child(rig_tab)
	return tabs


func _build_preview_panel() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	var toolbar: HBoxContainer = HBoxContainer.new()
	direction_option = OptionButton.new()
	for direction_id: String in DIRECTIONS:
		direction_option.add_item(str(DIRECTION_LABELS[direction_id]))
		direction_option.set_item_metadata(direction_option.item_count - 1, direction_id)
	direction_option.item_selected.connect(_on_direction_selected)
	toolbar.add_child(direction_option)
	zoom_option = OptionButton.new()
	for zoom_value: int in range(1, 13):
		zoom_option.add_item("%dx" % zoom_value, zoom_value)
	zoom_option.select(5)
	zoom_option.item_selected.connect(_on_zoom_selected)
	toolbar.add_child(zoom_option)
	pixel_snap_check = CheckBox.new()
	pixel_snap_check.text = "Pixel-perfect"
	pixel_snap_check.button_pressed = true
	pixel_snap_check.toggled.connect(_on_view_setting_changed)
	toolbar.add_child(pixel_snap_check)
	column.add_child(toolbar)
	var onion_row: HBoxContainer = HBoxContainer.new()
	previous_check = CheckBox.new()
	previous_check.text = "Anterior vermelho"
	previous_check.button_pressed = true
	previous_check.toggled.connect(_on_view_setting_changed)
	onion_row.add_child(previous_check)
	previous_opacity = HSlider.new()
	previous_opacity.min_value = 0.0
	previous_opacity.max_value = 1.0
	previous_opacity.step = 0.01
	previous_opacity.value = 0.28
	previous_opacity.custom_minimum_size.x = 100
	previous_opacity.value_changed.connect(_on_view_setting_changed)
	onion_row.add_child(previous_opacity)
	next_check = CheckBox.new()
	next_check.text = "Posterior verde"
	next_check.button_pressed = true
	next_check.toggled.connect(_on_view_setting_changed)
	onion_row.add_child(next_check)
	next_opacity = HSlider.new()
	next_opacity.min_value = 0.0
	next_opacity.max_value = 1.0
	next_opacity.step = 0.01
	next_opacity.value = 0.28
	next_opacity.custom_minimum_size.x = 100
	next_opacity.value_changed.connect(_on_view_setting_changed)
	onion_row.add_child(next_opacity)
	column.add_child(onion_row)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	preview.gui_input.connect(_on_preview_input)
	center.add_child(preview)
	return column


func _build_inspector() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size.x = 250
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	bone_name_edit = LineEdit.new()
	bone_name_edit.text_submitted.connect(_rename_bone)
	column.add_child(_labeled("Bone / camada", bone_name_edit))
	parent_option = OptionButton.new()
	parent_option.item_selected.connect(_on_parent_selected)
	column.add_child(_labeled("Parent", parent_option))
	var texture_row: HBoxContainer = HBoxContainer.new()
	texture_row.add_child(_button("Carregar PNG", _request_load_texture))
	texture_row.add_child(_button("Limpar", _clear_texture))
	column.add_child(texture_row)
	texture_path_label = Label.new()
	texture_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(texture_path_label)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	position_x_spin = _spin_row(grid, "Posição X", -4096, 4096, 1)
	position_y_spin = _spin_row(grid, "Posição Y", -4096, 4096, 1)
	rotation_spin = _spin_row(grid, "Rotação", -720, 720, 1)
	pivot_x_spin = _spin_row(grid, "Pivô X", -4096, 4096, 1)
	pivot_y_spin = _spin_row(grid, "Pivô Y", -4096, 4096, 1)
	z_spin = _spin_row(grid, "Ordem Z", -4096, 4095, 1)
	column.add_child(grid)
	for control_value: Variant in [position_x_spin, position_y_spin, rotation_spin, pivot_x_spin, pivot_y_spin, z_spin]:
		var transform_spin: SpinBox = control_value as SpinBox
		transform_spin.value_changed.connect(_on_transform_changed)
	visible_check = CheckBox.new()
	visible_check.text = "Visível neste frame"
	visible_check.toggled.connect(_on_transform_changed)
	column.add_child(visible_check)
	locked_check = CheckBox.new()
	locked_check.text = "Bone bloqueado"
	locked_check.toggled.connect(_on_locked_changed)
	column.add_child(locked_check)
	var key_row: HBoxContainer = HBoxContainer.new()
	key_row.add_child(_button("Criar key", _create_key))
	key_row.add_child(_button("Remover key", _remove_key))
	column.add_child(key_row)
	return scroll


func _build_timeline_panel() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	var toolbar_scroll: ScrollContainer = ScrollContainer.new()
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(toolbar_scroll)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 5)
	toolbar_scroll.add_child(toolbar)
	toolbar.add_child(_button("|◀", _first_frame))
	toolbar.add_child(_button("◀", _previous_frame))
	play_button = _button("Play", _toggle_playback)
	toolbar.add_child(play_button)
	toolbar.add_child(_button("▶", _next_frame))
	toolbar.add_child(_button("▶|", _last_frame))
	frame_label = Label.new()
	frame_label.custom_minimum_size.x = 110
	toolbar.add_child(frame_label)
	toolbar.add_child(_button("+ Quadro", _add_frame))
	toolbar.add_child(_button("Duplicar", _duplicate_frame))
	toolbar.add_child(_button("Remover", _remove_frame))
	toolbar.add_child(_button("← Quadro", _move_frame_left))
	toolbar.add_child(_button("Quadro →", _move_frame_right))
	fps_spin = _spin(1, 60, 0.5)
	fps_spin.value_changed.connect(_on_fps_changed)
	toolbar.add_child(_labeled("FPS", fps_spin))
	loop_option = OptionButton.new()
	for loop_id: String in ["loop", "pingpong", "once"]:
		loop_option.add_item({"loop": "Loop", "pingpong": "Ping-pong", "once": "Uma vez"}[loop_id])
		loop_option.set_item_metadata(loop_option.item_count - 1, loop_id)
	loop_option.item_selected.connect(_on_loop_selected)
	toolbar.add_child(loop_option)
	use_duration_check = CheckBox.new()
	use_duration_check.text = "Duração por quadro"
	use_duration_check.toggled.connect(_on_duration_mode_changed)
	toolbar.add_child(use_duration_check)
	frame_duration_spin = _spin(0.01, 5.0, 0.01)
	frame_duration_spin.value_changed.connect(_on_frame_duration_changed)
	toolbar.add_child(frame_duration_spin)
	timeline_cell_width_spin = _spin(24, 128, 2)
	timeline_cell_width_spin.value = 42
	timeline_cell_width_spin.value_changed.connect(_rebuild_timeline_from_value)
	toolbar.add_child(_labeled("Célula", timeline_cell_width_spin))
	timeline_scroll = ScrollContainer.new()
	timeline_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(timeline_scroll)
	timeline_grid = GridContainer.new()
	timeline_grid.add_theme_constant_override("h_separation", 1)
	timeline_grid.add_theme_constant_override("v_separation", 1)
	timeline_scroll.add_child(timeline_grid)
	status_label = Label.new()
	status_label.modulate = Color(0.72, 0.8, 0.75)
	column.add_child(status_label)
	return column


func _panel(content: Control, minimum: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = minimum
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	margin.add_child(content)
	return panel


func _button(text_value: String, callback: Callable) -> Button:
	var result: Button = Button.new()
	result.text = text_value
	result.pressed.connect(callback)
	return result


func _labeled(text_value: String, control_value: Control) -> Control:
	var result: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = text_value
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
	parent.add_child(label)
	var result: SpinBox = _spin(minimum, maximum, step_value)
	parent.add_child(result)
	return result


func _build_rendering() -> void:
	render_viewport = SubViewport.new()
	render_viewport.transparent_bg = true
	render_viewport.disable_3d = true
	render_viewport.msaa_2d = Viewport.MSAA_DISABLED
	render_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(render_viewport)
	previous_root = Node2D.new()
	previous_root.z_index = -1000
	render_viewport.add_child(previous_root)
	current_root = Node2D.new()
	render_viewport.add_child(current_root)
	next_root = Node2D.new()
	next_root.z_index = -900
	render_viewport.add_child(next_root)
	node_maps = {"previous": {}, "current": {}, "next": {}}
	sprite_maps = {"previous": {}, "current": {}, "next": {}}
	preview.texture = render_viewport.get_texture()
	_rebuild_render_nodes()


func _build_runtime_helpers() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.dir_selected.connect(_on_directory_selected)
	file_dialog.canceled.connect(_on_file_dialog_canceled)
	add_child(file_dialog)
	playback_timer = Timer.new()
	playback_timer.one_shot = true
	playback_timer.timeout.connect(_on_playback_timeout)
	add_child(playback_timer)
	autosave_timer = Timer.new()
	autosave_timer.one_shot = true
	autosave_timer.wait_time = 0.8
	autosave_timer.timeout.connect(_write_autosave)
	add_child(autosave_timer)


func _rebuild_render_nodes() -> void:
	_clear_node_children(previous_root)
	_clear_node_children(current_root)
	_clear_node_children(next_root)
	for key_value: Variant in node_maps.keys():
		node_maps[key_value] = {}
		sprite_maps[key_value] = {}
	_build_render_group(previous_root, node_maps["previous"] as Dictionary, sprite_maps["previous"] as Dictionary)
	_build_render_group(current_root, node_maps["current"] as Dictionary, sprite_maps["current"] as Dictionary)
	_build_render_group(next_root, node_maps["next"] as Dictionary, sprite_maps["next"] as Dictionary)


func _clear_node_children(parent_node: Node) -> void:
	for child_value: Variant in parent_node.get_children():
		var child_node: Node = child_value as Node
		child_node.queue_free()


func _build_render_group(group_root: Node2D, nodes: Dictionary, sprites: Dictionary) -> void:
	var pending: Array = _bones().duplicate(true)
	var guard: int = 0
	while not pending.is_empty() and guard < _bones().size() * 3:
		guard += 1
		for index: int in range(pending.size() - 1, -1, -1):
			var bone_data: Dictionary = pending[index] as Dictionary
			var bone_id: String = str(bone_data.get("id", ""))
			var parent_id: String = str(bone_data.get("parent", ""))
			if not parent_id.is_empty() and not nodes.has(parent_id):
				continue
			var bone_node: Node2D = Node2D.new()
			bone_node.name = bone_id
			if parent_id.is_empty():
				group_root.add_child(bone_node)
			else:
				var parent_node: Node2D = nodes[parent_id] as Node2D
				parent_node.add_child(bone_node)
			nodes[bone_id] = bone_node
			if bool(bone_data.get("has_sprite", true)):
				var sprite: Sprite2D = Sprite2D.new()
				sprite.centered = true
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				bone_node.add_child(sprite)
				sprites[bone_id] = sprite
			pending.remove_at(index)


func _apply_render() -> void:
	var canvas_data: Dictionary = _canvas_section()
	var canvas_size: Vector2i = Vector2i(int(canvas_data.get("width", 64)), int(canvas_data.get("height", 64)))
	render_viewport.size = canvas_size
	_apply_render_group(node_maps["current"] as Dictionary, sprite_maps["current"] as Dictionary, current_frame, Color.WHITE)
	var has_previous: bool = current_frame > 0
	var has_next: bool = current_frame < _frames().size() - 1
	previous_root.visible = previous_check.button_pressed and has_previous
	next_root.visible = next_check.button_pressed and has_next
	if has_previous:
		_apply_render_group(node_maps["previous"] as Dictionary, sprite_maps["previous"] as Dictionary, current_frame - 1, Color(1.0, 0.18, 0.18, float(previous_opacity.value)))
	if has_next:
		_apply_render_group(node_maps["next"] as Dictionary, sprite_maps["next"] as Dictionary, current_frame + 1, Color(0.18, 1.0, 0.32, float(next_opacity.value)))
	_update_preview_size()


func _apply_render_group(nodes: Dictionary, sprites: Dictionary, frame_index: int, tint: Color) -> void:
	var canvas_data: Dictionary = _canvas_section()
	var canvas_size: Vector2 = Vector2(float(canvas_data.get("width", 64)), float(canvas_data.get("height", 64)))
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		if not nodes.has(bone_id):
			continue
		var transform_data: Dictionary = _resolved_transform(frame_index, bone_id)
		var local_position: Vector2 = _vec(transform_data.get("position", [0.0, 0.0]))
		var pivot: Vector2 = _vec(transform_data.get("pivot", [0.0, 0.0]))
		if pixel_snap_check.button_pressed:
			local_position = local_position.round()
			pivot = pivot.round()
		var bone_node: Node2D = nodes[bone_id] as Node2D
		bone_node.position = local_position
		if str(bone_data.get("parent", "")).is_empty():
			bone_node.position += canvas_size * 0.5
		bone_node.rotation_degrees = float(transform_data.get("rotation_degrees", 0.0))
		bone_node.z_index = clampi(int(transform_data.get("z_index", 0)), -4096, 4095)
		bone_node.visible = bool(transform_data.get("visible", true))
		if sprites.has(bone_id):
			var sprite: Sprite2D = sprites[bone_id] as Sprite2D
			sprite.offset = -pivot
			sprite.texture = _load_texture(_texture_path(bone_id), bone_id)
			sprite.modulate = tint


func _texture_path(bone_id: String) -> String:
	var textures: Dictionary = _direction_data().get("textures", {}) as Dictionary
	return str(textures.get(bone_id, ""))


func _load_texture(path: String, bone_id: String) -> Texture2D:
	if path.is_empty():
		return _placeholder_texture(bone_id)
	if texture_cache.has(path):
		return texture_cache[path] as Texture2D
	var texture: Texture2D = null
	if path.begins_with("res://") or path.begins_with("user://"):
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
	else:
		var image: Image = Image.new()
		if image.load(path) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		texture = _placeholder_texture(bone_id)
	texture_cache[path] = texture
	return texture


func _placeholder_texture(bone_id: String) -> Texture2D:
	if placeholder_cache.has(bone_id):
		return placeholder_cache[bone_id] as Texture2D
	var size_value: Vector2i = Vector2i(10, 14)
	if bone_id.contains("head"):
		size_value = Vector2i(18, 18)
	elif bone_id.contains("torso") or bone_id.contains("body"):
		size_value = Vector2i(16, 18)
	elif bone_id.contains("arm"):
		size_value = Vector2i(7, 18)
	elif bone_id.contains("leg"):
		size_value = Vector2i(7, 16)
	var image: Image = Image.create_empty(size_value.x, size_value.y, false, Image.FORMAT_RGBA8)
	var hue: float = float(abs(bone_id.hash()) % 360) / 360.0
	image.fill(Color.from_hsv(hue, 0.35, 0.72, 1.0))
	var result: Texture2D = ImageTexture.create_from_image(image)
	placeholder_cache[bone_id] = result
	return result


func _rebuild_all() -> void:
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
	_rebuild_render_nodes()
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
	texture_path_label.text = "Sem PNG: placeholder" if _texture_path(selected_bone).is_empty() else _texture_path(selected_bone)


func _rebuild_project_tree() -> void:
	project_tree.clear()
	var hidden_root: TreeItem = project_tree.create_item()
	var project_item: TreeItem = project_tree.create_item(hidden_root)
	project_item.set_text(0, str(_project_section().get("name", "Projeto")))
	project_item.set_metadata(0, {"kind": "project"})
	for action_id_value: Variant in _actions().keys():
		var action_id: String = str(action_id_value)
		var action_data: Dictionary = _action_data(action_id)
		var action_item: TreeItem = project_tree.create_item(project_item)
		action_item.set_text(0, str(action_data.get("name", action_id)))
		action_item.set_metadata(0, {"kind": "action", "action": action_id})
		for direction_id: String in DIRECTIONS:
			var direction_item: TreeItem = project_tree.create_item(action_item)
			direction_item.set_text(0, str(DIRECTION_LABELS[direction_id]))
			direction_item.set_metadata(0, {"kind": "direction", "action": action_id, "direction": direction_id})
	project_item.set_collapsed(false)


func _rebuild_rig_tree() -> void:
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
			item.set_text(0, str(bone_data.get("name", bone_id)))
			item.set_metadata(0, bone_id)
			item_map[bone_id] = item
			pending.remove_at(index)


func _rebuild_parent_option() -> void:
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


func _rebuild_timeline() -> void:
	for child_value: Variant in timeline_grid.get_children():
		var child: Node = child_value as Node
		child.queue_free()
	var frame_count: int = _frames().size()
	timeline_grid.columns = frame_count + 1
	var corner: Label = Label.new()
	corner.text = "BONES / FRAMES"
	corner.custom_minimum_size = Vector2(180, 30)
	timeline_grid.add_child(corner)
	var cell_width: float = timeline_cell_width_spin.value
	for frame_index: int in range(frame_count):
		var header: Button = Button.new()
		header.text = str(frame_index + 1)
		header.custom_minimum_size = Vector2(cell_width, 30)
		header.button_pressed = frame_index == current_frame
		header.pressed.connect(_select_frame.bind(frame_index))
		timeline_grid.add_child(header)
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		var row_label: Button = Button.new()
		row_label.text = str(bone_data.get("name", bone_id))
		row_label.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row_label.custom_minimum_size = Vector2(180, 28)
		row_label.pressed.connect(_select_bone.bind(bone_id))
		timeline_grid.add_child(row_label)
		for frame_index: int in range(frame_count):
			var cell: Button = Button.new()
			cell.text = "●" if _is_keyed(frame_index, bone_id) else "·"
			cell.custom_minimum_size = Vector2(cell_width, 28)
			cell.tooltip_text = "Clique: selecionar. Botão direito: remover key."
			cell.gui_input.connect(_on_timeline_cell_input.bind(frame_index, bone_id))
			timeline_grid.add_child(cell)


func _is_keyed(frame_index: int, bone_id: String) -> bool:
	var keys: Dictionary = _frame_data(frame_index).get("keys", {}) as Dictionary
	return keys.has(bone_id)


func _on_timeline_cell_input(event: InputEvent, frame_index: int, bone_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	current_frame = frame_index
	selected_bone = bone_id
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_record_history()
		var keys: Dictionary = _frame_data(frame_index).get("keys", {}) as Dictionary
		keys.erase(bone_id)
		_mark_changed("Key removida.")
	else:
		_rebuild_all()


func _select_option_by_metadata(option: OptionButton, metadata_value: Variant) -> void:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == metadata_value:
			option.select(index)
			return


func _vec(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array:
		var values: Array = value as Array
		if values.size() >= 2:
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


func _on_project_tree_selected() -> void:
	var item: TreeItem = project_tree.get_selected()
	if item == null:
		return
	var metadata_value: Variant = item.get_metadata(0)
	if not (metadata_value is Dictionary):
		return
	var metadata: Dictionary = metadata_value as Dictionary
	var kind: String = str(metadata.get("kind", ""))
	if kind == "action":
		current_action = str(metadata.get("action", current_action))
		current_frame = 0
	elif kind == "direction":
		current_action = str(metadata.get("action", current_action))
		current_direction = str(metadata.get("direction", current_direction))
		current_frame = 0
	_rebuild_all()


func _on_rig_tree_selected() -> void:
	var item: TreeItem = rig_tree.get_selected()
	if item != null:
		_select_bone(str(item.get_metadata(0)))


func _select_bone(bone_id: String) -> void:
	if _bone_by_id(bone_id).is_empty():
		return
	selected_bone = bone_id
	_rebuild_parent_option()
	_refresh_controls()
	_apply_render()


func _select_frame(frame_index: int) -> void:
	current_frame = clampi(frame_index, 0, maxi(0, _frames().size() - 1))
	_refresh_controls()
	_rebuild_timeline()
	_apply_render()
	_schedule_playback()


func _first_frame() -> void:
	_select_frame(0)


func _previous_frame() -> void:
	_select_frame(current_frame - 1)


func _next_frame() -> void:
	_select_frame(current_frame + 1)


func _last_frame() -> void:
	_select_frame(_frames().size() - 1)


func _add_frame() -> void:
	_record_history()
	var frames_value: Array = _frames()
	frames_value.insert(current_frame + 1, _new_frame())
	current_frame += 1
	_mark_changed("Quadro adicionado.")


func _duplicate_frame() -> void:
	_record_history()
	var duplicate_frame: Dictionary = _new_frame()
	var keys: Dictionary = {}
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		var bone_id: String = str(bone_data.get("id", ""))
		keys[bone_id] = _resolved_transform(current_frame, bone_id)
	duplicate_frame["keys"] = keys
	duplicate_frame["duration"] = float(_frame_data(current_frame).get("duration", 0.125))
	_frames().insert(current_frame + 1, duplicate_frame)
	current_frame += 1
	_mark_changed("Quadro duplicado.")


func _remove_frame() -> void:
	if _frames().size() <= 1:
		_set_status("A direção precisa manter pelo menos um quadro.", true)
		return
	_record_history()
	_frames().remove_at(current_frame)
	current_frame = mini(current_frame, _frames().size() - 1)
	_mark_changed("Quadro removido.")


func _move_frame_left() -> void:
	if current_frame <= 0:
		return
	_record_history()
	var frame_value: Variant = _frames().pop_at(current_frame)
	_frames().insert(current_frame - 1, frame_value)
	current_frame -= 1
	_mark_changed("Quadro movido para a esquerda.")


func _move_frame_right() -> void:
	if current_frame >= _frames().size() - 1:
		return
	_record_history()
	var frame_value: Variant = _frames().pop_at(current_frame)
	_frames().insert(current_frame + 1, frame_value)
	current_frame += 1
	_mark_changed("Quadro movido para a direita.")


func _add_custom_action() -> void:
	_record_history()
	current_action = _add_action_data("custom", "nova_acao", false)
	current_frame = 0
	_mark_changed("Ação custom criada.")


func _add_preset_action() -> void:
	var preset_id: String = str(action_option.get_selected_metadata())
	_record_history()
	current_action = _add_action_data(preset_id, preset_id, false)
	current_frame = 0
	_mark_changed("Preset adicionado como ação editável.")


func _remove_current_action() -> void:
	if _actions().size() <= 1:
		_set_status("O projeto precisa manter pelo menos uma ação.", true)
		return
	_record_history()
	_actions().erase(current_action)
	current_action = str(_actions().keys()[0])
	current_frame = 0
	_mark_changed("Ação removida.")


func _rename_current_action(new_name: String) -> void:
	if new_name.strip_edges().is_empty():
		return
	_record_history()
	_action_data()["name"] = new_name.strip_edges()
	_mark_changed("Ação renomeada.")


func _add_bone() -> void:
	_record_history()
	var existing_ids: Array = []
	for bone_value: Variant in _bones():
		existing_ids.append(str((bone_value as Dictionary).get("id", "")))
	var bone_id: String = _unique_id("novo_bone", existing_ids, "bone")
	_bones().append(_bone(bone_id, "Novo Bone", selected_bone, true, Vector2.ZERO, 0))
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_id: String in DIRECTIONS:
			var direction_data: Dictionary = directions.get(direction_id, {}) as Dictionary
			(direction_data.get("textures", {}) as Dictionary)[bone_id] = ""
	selected_bone = bone_id
	_mark_changed("Bone custom criado.")


func _remove_bone() -> void:
	if selected_bone == "root":
		_set_status("O Root não pode ser removido.", true)
		return
	_record_history()
	var parent_id: String = str(_bone_by_id(selected_bone).get("parent", "root"))
	for bone_value: Variant in _bones():
		var bone_data: Dictionary = bone_value as Dictionary
		if str(bone_data.get("parent", "")) == selected_bone:
			bone_data["parent"] = parent_id
	for index: int in range(_bones().size() - 1, -1, -1):
		if str((_bones()[index] as Dictionary).get("id", "")) == selected_bone:
			_bones().remove_at(index)
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_id: String in DIRECTIONS:
			var direction_data: Dictionary = directions.get(direction_id, {}) as Dictionary
			(direction_data.get("textures", {}) as Dictionary).erase(selected_bone)
			for frame_value: Variant in direction_data.get("frames", []) as Array:
				var frame_data: Dictionary = frame_value as Dictionary
				(frame_data.get("keys", {}) as Dictionary).erase(selected_bone)
	selected_bone = "root"
	_mark_changed("Bone removido.")


func _rename_bone(new_name: String) -> void:
	if new_name.strip_edges().is_empty():
		return
	_record_history()
	_bone_by_id(selected_bone)["name"] = new_name.strip_edges()
	_mark_changed("Bone renomeado.")


func _on_parent_selected(_index: int) -> void:
	if updating_ui or selected_bone == "root":
		return
	var new_parent: String = str(parent_option.get_selected_metadata())
	if new_parent == selected_bone or _would_create_cycle(selected_bone, new_parent):
		_set_status("Parent inválido: criaria ciclo.", true)
		_refresh_controls()
		return
	_record_history()
	_bone_by_id(selected_bone)["parent"] = new_parent
	_mark_changed("Parent atualizado.")


func _would_create_cycle(bone_id: String, candidate_parent: String) -> bool:
	var cursor: String = candidate_parent
	var guard: int = 0
	while not cursor.is_empty() and guard < 128:
		guard += 1
		if cursor == bone_id:
			return true
		cursor = str(_bone_by_id(cursor).get("parent", ""))
	return false


func _create_key() -> void:
	_record_history()
	_ensure_key(current_frame, selected_bone)
	_mark_changed("Key criada.")


func _remove_key() -> void:
	_record_history()
	var keys: Dictionary = _frame_data(current_frame).get("keys", {}) as Dictionary
	keys.erase(selected_bone)
	_mark_changed("Key removida.")


func _on_transform_changed(_value: Variant = null) -> void:
	if updating_ui:
		return
	var bone_data: Dictionary = _bone_by_id(selected_bone)
	if bool(bone_data.get("locked", false)):
		_refresh_controls()
		return
	_record_history()
	var position_value: Vector2 = Vector2(position_x_spin.value, position_y_spin.value)
	var pivot_value: Vector2 = Vector2(pivot_x_spin.value, pivot_y_spin.value)
	if pixel_snap_check.button_pressed:
		position_value = position_value.round()
		pivot_value = pivot_value.round()
	var transform_data: Dictionary = _transform_dict(position_value, rotation_spin.value, pivot_value, int(z_spin.value), visible_check.button_pressed)
	var keys: Dictionary = _frame_data(current_frame).get("keys", {}) as Dictionary
	keys[selected_bone] = transform_data
	_mark_changed()


func _on_locked_changed(value: bool) -> void:
	if updating_ui:
		return
	_record_history()
	_bone_by_id(selected_bone)["locked"] = value
	_mark_changed("Bloqueio do bone atualizado.")


func _on_project_name_changed(value: String) -> void:
	if updating_ui:
		return
	_project_section()["name"] = value
	_mark_changed()


func _on_asset_name_changed(value: String) -> void:
	if updating_ui:
		return
	_project_section()["asset_name"] = value
	_mark_changed()


func _on_entity_selected(_index: int) -> void:
	if updating_ui:
		return
	_project_section()["entity_type"] = str(entity_option.get_selected_metadata())
	_mark_changed("Tipo de projeto atualizado. A estrutura custom existente foi preservada.")


func _on_direction_selected(_index: int) -> void:
	if updating_ui:
		return
	current_direction = str(direction_option.get_selected_metadata())
	current_frame = 0
	_rebuild_all()


func _on_fps_changed(value: float) -> void:
	if updating_ui:
		return
	_playback_section()["fps"] = value
	_mark_changed()


func _on_loop_selected(_index: int) -> void:
	if updating_ui:
		return
	_playback_section()["loop_mode"] = str(loop_option.get_selected_metadata())
	_mark_changed()


func _on_duration_mode_changed(value: bool) -> void:
	if updating_ui:
		return
	_playback_section()["use_frame_durations"] = value
	_mark_changed()


func _on_frame_duration_changed(value: float) -> void:
	if updating_ui:
		return
	_frame_data(current_frame)["duration"] = maxf(0.01, value)
	_mark_changed()


func _on_view_setting_changed(_value: Variant = null) -> void:
	if updating_ui:
		return
	_apply_render()


func _on_zoom_selected(_index: int) -> void:
	_update_preview_size()


func _rebuild_timeline_from_value(_value: float) -> void:
	_rebuild_timeline()


func _update_preview_size() -> void:
	var canvas_data: Dictionary = _canvas_section()
	var zoom_value: int = maxi(1, zoom_option.get_selected_id())
	var preview_size: Vector2 = Vector2(float(canvas_data.get("width", 64)) * zoom_value, float(canvas_data.get("height", 64)) * zoom_value)
	preview.custom_minimum_size = preview_size
	preview.size = preview_size


func _on_preview_input(event: InputEvent) -> void:
	var zoom_value: float = float(maxi(1, zoom_option.get_selected_id()))
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				drag_active = true
				drag_start_canvas = mouse_event.position / zoom_value
				drag_start_position = _vec(_resolved_transform(current_frame, selected_bone).get("position", [0.0, 0.0]))
				_record_history()
			else:
				drag_active = false
	elif event is InputEventMouseMotion and drag_active:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		var canvas_position: Vector2 = motion_event.position / zoom_value
		var new_position: Vector2 = drag_start_position + (canvas_position - drag_start_canvas)
		if pixel_snap_check.button_pressed:
			new_position = new_position.round()
		var transform_data: Dictionary = _ensure_key(current_frame, selected_bone)
		transform_data["position"] = [new_position.x, new_position.y]
		_mark_changed()


func _toggle_playback() -> void:
	playing = not playing
	playback_direction = 1
	if not playing:
		playback_timer.stop()
	_refresh_controls()
	_schedule_playback()


func _schedule_playback() -> void:
	playback_timer.stop()
	if not playing:
		return
	var playback_data: Dictionary = _playback_section()
	var wait_time: float = 1.0 / maxf(1.0, float(playback_data.get("fps", 8.0)))
	if bool(playback_data.get("use_frame_durations", false)):
		wait_time = maxf(0.01, float(_frame_data(current_frame).get("duration", 0.125)))
	playback_timer.start(wait_time)


func _on_playback_timeout() -> void:
	if not playing:
		return
	var last_index: int = _frames().size() - 1
	var loop_mode: String = str(_playback_section().get("loop_mode", "loop"))
	if loop_mode == "pingpong":
		if current_frame >= last_index:
			playback_direction = -1
		elif current_frame <= 0:
			playback_direction = 1
		_select_frame(current_frame + playback_direction)
	elif loop_mode == "once":
		if current_frame >= last_index:
			playing = false
			_refresh_controls()
		else:
			_select_frame(current_frame + 1)
	else:
		_select_frame(posmod(current_frame + 1, _frames().size()))


func _new_project_dialog() -> void:
	_record_history()
	_create_new_document("character")
	_rebuild_all()
	_set_status("Novo projeto criado.")


func _request_load_texture() -> void:
	file_action = FileAction.LOAD_TEXTURE
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Carregar sprite do bone", ["*.png ; PNG"])


func _clear_texture() -> void:
	_record_history()
	var textures: Dictionary = _direction_data().get("textures", {}) as Dictionary
	textures[selected_bone] = ""
	texture_cache.clear()
	_mark_changed("Sprite removido desta ação e direção.")


func _request_save_project() -> void:
	if not current_project_path.is_empty():
		_write_project(current_project_path)
		return
	file_action = FileAction.SAVE_PROJECT
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Salvar projeto Wyrdframe", ["*.wyrd ; Wyrdframe Project"], _project_filename())


func _request_load_project() -> void:
	file_action = FileAction.LOAD_PROJECT
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Abrir projeto Wyrdframe", ["*.wyrd ; Wyrdframe Project", "*.json ; JSON legado"])


func _request_export_frame() -> void:
	file_action = FileAction.EXPORT_FRAME
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar frame", ["*.png ; PNG"], _frame_filename(current_frame))


func _request_export_all() -> void:
	file_action = FileAction.EXPORT_ALL
	_open_dialog(FileDialog.FILE_MODE_OPEN_DIR, "Exportar sequência PNG", [])


func _request_export_sheet() -> void:
	file_action = FileAction.EXPORT_SHEET
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Exportar sprite sheet", ["*.png ; PNG"], _sheet_filename())


func _open_dialog(mode: int, title_text: String, filters: Array[String], suggested: String = "") -> void:
	file_dialog.file_mode = mode
	file_dialog.title = title_text
	file_dialog.filters = PackedStringArray(filters)
	file_dialog.current_dir = ProjectSettings.globalize_path(DATA_DIR)
	file_dialog.current_file = suggested
	file_dialog.popup_centered_ratio(0.8)


func _on_file_selected(path: String) -> void:
	if file_action == FileAction.LOAD_TEXTURE:
		_load_texture_path(path)
	elif file_action == FileAction.SAVE_PROJECT:
		_write_project(_ensure_extension(path, FILE_EXTENSION))
	elif file_action == FileAction.LOAD_PROJECT:
		_load_project(path)
	elif file_action == FileAction.EXPORT_FRAME:
		await _export_frame(_ensure_extension(path, "png"))
	elif file_action == FileAction.EXPORT_SHEET:
		await _export_sheet(_ensure_extension(path, "png"))
	file_action = FileAction.NONE


func _on_directory_selected(path: String) -> void:
	if file_action == FileAction.EXPORT_ALL:
		await _export_all(path)
	file_action = FileAction.NONE


func _on_file_dialog_canceled() -> void:
	file_action = FileAction.NONE


func _load_texture_path(path: String) -> void:
	var test_image: Image = Image.new()
	if test_image.load(path) != OK:
		_set_status("Não foi possível carregar o PNG.", true)
		return
	var project_root: String = ProjectSettings.globalize_path("res://")
	var stored_path: String = ProjectSettings.localize_path(path) if path.begins_with(project_root) else path
	_record_history()
	var textures: Dictionary = _direction_data().get("textures", {}) as Dictionary
	textures[selected_bone] = stored_path
	texture_cache.clear()
	_mark_changed("PNG associado a %s / %s." % [_action_data().get("name", current_action), DIRECTION_LABELS[current_direction]])


func _write_project(path: String) -> void:
	var safe_path: String = _ensure_extension(path, FILE_EXTENSION)
	if _write_document(safe_path, document, true):
		current_project_path = safe_path
		dirty = false
		_update_window_title()


func _load_project(path: String) -> void:
	var loaded_document: Dictionary = _read_document(path)
	if loaded_document.is_empty():
		return
	if str(loaded_document.get("format", "")) != FORMAT_NAME:
		_set_status("Formato incompatível. Abra um projeto .wyrd válido.", true)
		return
	_record_history()
	document = loaded_document.duplicate(true)
	_normalize_document()
	current_project_path = path if path.get_extension().to_lower() == FILE_EXTENSION else ""
	current_action = str(_actions().keys()[0])
	current_direction = "south"
	current_frame = 0
	selected_bone = "torso" if not _bone_by_id("torso").is_empty() else "root"
	dirty = false
	texture_cache.clear()
	placeholder_cache.clear()
	_rebuild_all()
	_set_status("Projeto carregado.")


func _normalize_document() -> void:
	if not document.has("project"):
		document["project"] = {"name": "Projeto", "asset_name": "asset", "entity_type": "custom"}
	if not document.has("canvas"):
		document["canvas"] = {"width": 64, "height": 64, "feet_y": 60}
	if not document.has("playback"):
		document["playback"] = {"fps": 8.0, "loop_mode": "loop", "use_frame_durations": false}
	if not document.has("rig") or _bones().is_empty():
		document["rig"] = {"bones": _default_bones()}
	if not document.has("actions") or _actions().is_empty():
		document["actions"] = {}
		_add_action_data("custom", "custom", false)
	for action_value: Variant in _actions().values():
		var action_data: Dictionary = action_value as Dictionary
		var directions: Dictionary = action_data.get("directions", {}) as Dictionary
		for direction_id: String in DIRECTIONS:
			if not directions.has(direction_id):
				directions[direction_id] = {"frames": [_new_frame()], "textures": {}}
			var direction_data: Dictionary = directions[direction_id] as Dictionary
			var frames_value: Array = direction_data.get("frames", []) as Array
			if frames_value.is_empty():
				frames_value.append(_new_frame())
			var textures: Dictionary = direction_data.get("textures", {}) as Dictionary
			for bone_value: Variant in _bones():
				var bone_id: String = str((bone_value as Dictionary).get("id", ""))
				if not textures.has(bone_id):
					textures[bone_id] = ""


func _write_autosave() -> void:
	_write_document(AUTOSAVE_PATH, document, false)


func _write_document(path: String, data: Dictionary, report: bool) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		if report:
			_set_status("Não foi possível salvar o arquivo.", true)
		return false
	file.store_string(JSON.stringify(data, "\t", false))
	file.close()
	if report:
		_set_status("Salvo: %s" % path)
	return true


func _read_document(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Não foi possível abrir o arquivo.", true)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_set_status("Documento inválido.", true)
		return {}
	return parsed as Dictionary


func _render_frame(frame_index: int) -> Image:
	previous_root.visible = false
	next_root.visible = false
	_apply_render_group(node_maps["current"] as Dictionary, sprite_maps["current"] as Dictionary, frame_index, Color.WHITE)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = render_viewport.get_texture().get_image()
	_apply_render()
	return image


func _export_frame(path: String) -> void:
	var image: Image = await _render_frame(current_frame)
	var result: Error = image.save_png(path)
	_set_status("Frame exportado." if result == OK else "Falha ao exportar frame.", result != OK)


func _export_all(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var failures: int = 0
	for frame_index: int in range(_frames().size()):
		var image: Image = await _render_frame(frame_index)
		if image.save_png(directory.path_join(_frame_filename(frame_index))) != OK:
			failures += 1
	_set_status("Sequência exportada." if failures == 0 else "%d falhas na exportação." % failures, failures > 0)


func _export_sheet(path: String) -> void:
	var canvas_data: Dictionary = _canvas_section()
	var frame_size: Vector2i = Vector2i(int(canvas_data.get("width", 64)), int(canvas_data.get("height", 64)))
	var sheet: Image = Image.create_empty(frame_size.x * _frames().size(), frame_size.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for frame_index: int in range(_frames().size()):
		var image: Image = await _render_frame(frame_index)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, frame_size), Vector2i(frame_index * frame_size.x, 0))
	var result: Error = sheet.save_png(path)
	_set_status("Sprite sheet exportada." if result == OK else "Falha ao exportar sprite sheet.", result != OK)


func _project_filename() -> String:
	return "%s.%s" % [_safe_name(str(_project_section().get("asset_name", "asset")), "asset"), FILE_EXTENSION]


func _frame_filename(frame_index: int) -> String:
	return "%s_%s_%s_%02d.png" % [
		_safe_name(str(_project_section().get("asset_name", "asset")), "asset"),
		_safe_name(current_action, "action"),
		current_direction,
		frame_index + 1,
	]


func _sheet_filename() -> String:
	return "%s_%s_%s_sheet.png" % [
		_safe_name(str(_project_section().get("asset_name", "asset")), "asset"),
		_safe_name(current_action, "action"),
		current_direction,
	]


func _safe_name(value: String, fallback: String) -> String:
	var result: String = value.strip_edges().to_lower().to_snake_case()
	var regex: RegEx = RegEx.new()
	regex.compile("[^a-z0-9_]+")
	result = regex.sub(result, "_", true).trim_prefix("_").trim_suffix("_")
	return fallback if result.is_empty() else result


func _ensure_extension(path: String, extension: String) -> String:
	return path if path.get_extension().to_lower() == extension else "%s.%s" % [path, extension]


func _record_history() -> void:
	undo_stack.append(document.duplicate(true))
	if undo_stack.size() > 60:
		undo_stack.pop_front()
	redo_stack.clear()


func _undo() -> void:
	if undo_stack.is_empty():
		_set_status("Nada para desfazer.")
		return
	redo_stack.append(document.duplicate(true))
	document = undo_stack.pop_back()
	_normalize_document()
	current_action = str(_actions().keys()[0]) if not _actions().has(current_action) else current_action
	current_frame = clampi(current_frame, 0, _frames().size() - 1)
	_rebuild_all()
	_set_status("Desfeito.")


func _redo() -> void:
	if redo_stack.is_empty():
		_set_status("Nada para refazer.")
		return
	undo_stack.append(document.duplicate(true))
	document = redo_stack.pop_back()
	_normalize_document()
	current_action = str(_actions().keys()[0]) if not _actions().has(current_action) else current_action
	current_frame = clampi(current_frame, 0, _frames().size() - 1)
	_rebuild_all()
	_set_status("Refeito.")


func _mark_changed(message: String = "") -> void:
	dirty = true
	autosave_timer.start()
	_refresh_controls()
	_rebuild_timeline()
	_apply_render()
	if not message.is_empty():
		_set_status(message)


func _update_window_title() -> void:
	var marker: String = " *" if dirty else ""
	get_window().title = "%s  •  %s%s" % [PROGRAM_NAME, _project_section().get("name", "Projeto"), marker]


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.modulate = Color(1.0, 0.45, 0.4) if is_error else Color(0.72, 0.82, 0.75)


func _save_layout() -> void:
	if root_split == null:
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("window", "size", get_window().size)
	config.set_value("window", "position", get_window().position)
	config.set_value("layout", "root_split", root_split.split_offset)
	config.set_value("layout", "main_split", main_split.split_offset)
	config.set_value("layout", "center_split", center_split.split_offset)
	config.set_value("layout", "timeline_cell_width", timeline_cell_width_spin.value)
	config.save(LAYOUT_PATH)


func _restore_layout() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(LAYOUT_PATH) != OK:
		return
	var stored_size: Variant = config.get_value("window", "size", Vector2i(1500, 900))
	var stored_position: Variant = config.get_value("window", "position", Vector2i(80, 60))
	get_window().size = stored_size as Vector2i
	get_window().position = stored_position as Vector2i
	root_split.split_offset = int(config.get_value("layout", "root_split", 570))
	main_split.split_offset = int(config.get_value("layout", "main_split", 285))
	center_split.split_offset = int(config.get_value("layout", "center_split", 850))
	timeline_cell_width_spin.value = float(config.get_value("layout", "timeline_cell_width", 42.0))