extends Control

const ProjectScript := preload("res://tools/sprite_pose_lab/scripts/WyrdframeProject.gd")
const CanvasScript := preload("res://tools/sprite_pose_lab/scripts/SpritePoseCanvasV2.gd")
const TimelineScript := preload("res://tools/sprite_pose_lab/scripts/WyrdframeTimeline.gd")
const DATA_DIR := "user://wyrdframe"
const AUTOSAVE_PATH := "user://wyrdframe/autosave.wyrd"
const LAYOUT_PATH := "user://wyrdframe/layout.cfg"
const PROGRAM_NAME := "Wyrdframe Studio"

const DIRECTION_LABELS := {
	"south": "Sul",
	"north": "Norte",
	"east": "Leste",
	"west": "Oeste",
}
const ENTITY_LABELS := {
	"character": "Personagem",
	"monster": "Monstro",
	"boss": "Boss",
	"custom": "Custom",
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

var pose_project
var selected_bone_id := "torso"
var selected_frame := 0
var updating_ui := false
var playing := false
var playback_direction := 1
var file_action := FileAction.NONE
var dirty := false
var current_project_path := ""

var render_viewport: SubViewport
var pose_canvas
var preview: TextureRect
var timeline
var rig_tree: Tree
var project_tree: Tree
var file_dialog: FileDialog
var playback_timer: Timer
var autosave_timer: Timer

var workspace_vsplit: VSplitContainer
var main_hsplit: HSplitContainer
var center_hsplit: HSplitContainer
var left_tabs: TabContainer

var entity_type_option: OptionButton
var project_name_edit: LineEdit
var asset_name_edit: LineEdit
var action_preset_option: OptionButton
var action_name_edit: LineEdit
var direction_option: OptionButton
var action_option: OptionButton
var frame_label: Label
var play_button: Button
var fps_spin: SpinBox
var loop_option: OptionButton
var use_frame_duration_check: CheckBox
var frame_duration_spin: SpinBox
var canvas_width_spin: SpinBox
var canvas_height_spin: SpinBox
var feet_y_spin: SpinBox
var zoom_option: OptionButton
var status_label: Label

var previous_check: CheckBox
var next_check: CheckBox
var previous_opacity: HSlider
var next_opacity: HSlider
var checker_check: CheckBox
var grid_check: CheckBox
var axis_check: CheckBox
var feet_line_check: CheckBox
var pixel_snap_check: CheckBox
var gizmo_check: CheckBox

var bone_name_edit: LineEdit
var parent_option: OptionButton
var texture_path_label: Label
var position_x_spin: SpinBox
var position_y_spin: SpinBox
var rotation_spin: SpinBox
var pivot_x_spin: SpinBox
var pivot_y_spin: SpinBox
var z_order_spin: SpinBox
var visible_check: CheckBox
var locked_check: CheckBox
var rotation_min_spin: SpinBox
var rotation_max_spin: SpinBox
var foot_contact_check: CheckBox
var keyed_label: Label

var drag_mode := ""
var drag_start_canvas := Vector2.ZERO
var drag_start_transform: Dictionary = {}
var drag_start_angle := 0.0
var undo_stack: Array = []
var redo_stack: Array = []
var history_suspended := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	_configure_window()
	pose_project = ProjectScript.new()
	call("_build_ui")
	call("_build_render_viewport")
	call("_build_dialogs_and_timers")
	call("_load_layout")
	call("_rebuild_everything")
	_set_status("Wyrdframe pronto. Crie ações, escolha uma direção e anime.")


func _exit_tree() -> void:
	call("_save_layout")


func _configure_window() -> void:
	var window := get_window()
	window.title = PROGRAM_NAME
	window.unresizable = false
	window.min_size = Vector2i(1050, 680)
	if window.size.x < 1300 or window.size.y < 760:
		window.size = Vector2i(1500, 900)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed and key_event.keycode == KEY_Z:
		call("_undo")
	elif key_event.ctrl_pressed and key_event.keycode == KEY_Y:
		call("_redo")
	elif key_event.ctrl_pressed and key_event.keycode == KEY_S:
		call("_request_save_project")
	elif key_event.alt_pressed and key_event.keycode == KEY_D:
		call("_duplicate_frame")
	elif key_event.keycode == KEY_INSERT:
		call("_add_frame")
	elif key_event.keycode == KEY_DELETE:
		call("_remove_frame")
	elif key_event.keycode == KEY_LEFT:
		call("_select_frame", selected_frame - 1)
	elif key_event.keycode == KEY_RIGHT:
		call("_select_frame", selected_frame + 1)
	elif key_event.keycode == KEY_SPACE:
		call("_toggle_playback")
		get_viewport().set_input_as_handled()


func _select_option_metadata(option: OptionButton, metadata_value: Variant) -> void:
	if option == null:
		return
	for index in range(option.item_count):
		if option.get_item_metadata(index) == metadata_value:
			option.select(index)
			return


func _panel(content: Control) -> PanelContainer:
	var result := PanelContainer.new()
	var margin := MarginContainer.new()
	for side_name in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side_name, 8)
	result.add_child(margin)
	margin.add_child(content)
	return result


func _scroll_wrap(content: Control, horizontal: bool = false) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_child(content)
	return scroll


func _section(text_value: String) -> Label:
	var result := _label(text_value)
	result.add_theme_font_size_override("font_size", 13)
	result.modulate = Color(0.86, 0.9, 0.95)
	return result


func _label(text_value: String) -> Label:
	var result := Label.new()
	result.text = text_value
	return result


func _labeled(text_value: String, control: Control) -> Control:
	var result := VBoxContainer.new()
	result.add_child(_label(text_value))
	result.add_child(control)
	return result


func _button(text_value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text_value
	result.pressed.connect(callback)
	return result


func _check(text_value: String, pressed: bool) -> CheckBox:
	var result := CheckBox.new()
	result.text = text_value
	result.button_pressed = pressed
	return result


func _spin(minimum: float, maximum: float, step_value: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step_value
	result.allow_greater = false
	result.allow_lesser = false
	return result


func _spin_row(parent: GridContainer, text_value: String, minimum: float, maximum: float, step_value: float) -> SpinBox:
	var result := _spin(minimum, maximum, step_value)
	parent.add_child(_label(text_value))
	parent.add_child(result)
	return result


func _vector_from(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Vector2:
		return value
	return Vector2.ZERO


func _safe_name(value: String, fallback: String) -> String:
	var result := value.strip_edges().to_lower().to_snake_case()
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]+")
	result = regex.sub(result, "_", true)
	return fallback if result.is_empty() else result


func _ensure_extension(path: String, extension: String) -> String:
	return path if path.get_extension().to_lower() == extension else "%s.%s" % [path, extension]


func _set_status(message: String, is_error: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.modulate = Color(1.0, 0.45, 0.4) if is_error else Color(0.72, 0.82, 0.75)


func _record_history() -> void:
	pass


func _mark_changed(_message: String = "") -> void:
	pass
