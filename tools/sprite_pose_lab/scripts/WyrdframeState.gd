extends Control

const CanvasScript: Script = preload("res://tools/sprite_pose_lab/scripts/WyrdframeCanvas.gd")

const PROGRAM_NAME: String = "Wyrdframe Studio"
const FORMAT_NAME: String = "wyrdframe_project"
const FORMAT_VERSION: int = 5
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
var rebuilding_trees: bool = false
var playing: bool = false
var playback_direction: int = 1
var file_action: FileAction = FileAction.NONE
var drag_active: bool = false
var drag_start_canvas: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO
var drag_history_recorded: bool = false

var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

var root_split: VSplitContainer
var main_split: HSplitContainer
var center_split: HSplitContainer
var project_tree: Tree
var rig_tree: Tree
var action_preset_option: OptionButton
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
var checkerboard_check: CheckBox
var show_bones_check: CheckBox
var bone_opacity_slider: HSlider
var show_sprites_check: CheckBox
var sprite_opacity_slider: HSlider
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
var bone_editor_visible_check: CheckBox
var file_dialog: FileDialog
var playback_timer: Timer
var autosave_timer: Timer
var render_viewport: SubViewport
var canvas_renderer: WyrdframeCanvas


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
		var preset_id: String = str(preset_value)
		_add_action_data(preset_id, preset_id, false)
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
		"editor_visible": true,
		"rest": _transform_dict(position_value, 0.0, Vector2.ZERO, order, true),
		"constraints": {
			"rotation_min": -180.0,
			"rotation_max": 180.0,
			"foot_contact": id_value.ends_with("leg"),
		},
	}

func _transform_dict(position_value: Vector2, rotation_value: float, pivot_value: Vector2, order: int, visible_value: bool) -> Dictionary:
	return {
		"position": [position_value.x, position_value.y],
		"rotation_degrees": rotation_value,
		"pivot": [pivot_value.x, pivot_value.y],
		"z_index": order,
		"visible": visible_value,
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
	var target_action: String = current_action if action_id.is_empty() else action_id
	return _actions().get(target_action, {}) as Dictionary

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
	var suffix_value: int = 2
	while existing.has(candidate):
		candidate = "%s_%d" % [base_id, suffix_value]
		suffix_value += 1
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
	_actions()[action_id] = {
		"name": str(preset.get("name", action_id.capitalize())),
		"preset": preset_id,
		"directions": directions,
	}
	_key_rest_pose(action_id)
	_apply_motion_preset(action_id, preset_id)
	if mark_change:
		call("_mark_changed", "Ação adicionada.", true)
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

func _apply_motion_preset(action_id: String, preset_id: String) -> void:
	if preset_id == "custom":
		return
	for direction_id: String in DIRECTIONS:
		var direction_data: Dictionary = _direction_data(action_id, direction_id)
		var frames_value: Array = direction_data.get("frames", []) as Array
		for frame_index_value: int in range(frames_value.size()):
			var phase: float = float(frame_index_value) / float(maxi(1, frames_value.size())) * TAU
			var frame_data: Dictionary = frames_value[frame_index_value] as Dictionary
			var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
			for bone_value: Variant in _bones():
				var bone_data: Dictionary = bone_value as Dictionary
				var bone_id: String = str(bone_data.get("id", ""))
				var pose: Dictionary = (bone_data.get("rest", {}) as Dictionary).duplicate(true)
				var position_value: Vector2 = _vec(pose.get("position", [0.0, 0.0]))
				if preset_id == "idle":
					if bone_id == "torso" or bone_id == "head":
						position_value.y += roundf(sin(phase))
				elif preset_id == "walk" or preset_id == "run":
					var amplitude: float = 18.0 if preset_id == "walk" else 30.0
					if bone_id == "left_arm" or bone_id == "right_leg":
						pose["rotation_degrees"] = sin(phase) * amplitude
					elif bone_id == "right_arm" or bone_id == "left_leg":
						pose["rotation_degrees"] = -sin(phase) * amplitude
					elif bone_id == "torso":
						position_value.y += roundf(abs(sin(phase)) * (1.0 if preset_id == "walk" else 2.0))
				elif preset_id.begins_with("attack") or preset_id == "attack":
					if bone_id == "right_arm":
						pose["rotation_degrees"] = lerpf(-35.0, 70.0, float(frame_index_value) / float(maxi(1, frames_value.size() - 1)))
				elif preset_id == "cast" and (bone_id == "left_arm" or bone_id == "right_arm"):
					pose["rotation_degrees"] = -35.0 if bone_id == "left_arm" else 35.0
				pose["position"] = [position_value.x, position_value.y]
				keys[bone_id] = pose
			frame_data["keys"] = keys

func _resolved_transform(frame_index_value: int, bone_id: String) -> Dictionary:
	var bone_data: Dictionary = _bone_by_id(bone_id)
	var fallback: Dictionary = _transform_dict(Vector2.ZERO, 0.0, Vector2.ZERO, 0, true)
	var result: Dictionary = (bone_data.get("rest", fallback) as Dictionary).duplicate(true)
	var frames_value: Array = _frames()
	var last_index: int = mini(frame_index_value, frames_value.size() - 1)
	for index: int in range(last_index + 1):
		var frame_data: Dictionary = frames_value[index] as Dictionary
		var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
		if keys.has(bone_id):
			result = (keys[bone_id] as Dictionary).duplicate(true)
	return result

func _ensure_key(frame_index_value: int, bone_id: String) -> Dictionary:
	var frame_data: Dictionary = _frame_data(frame_index_value)
	var keys: Dictionary = frame_data.get("keys", {}) as Dictionary
	if not keys.has(bone_id):
		keys[bone_id] = _resolved_transform(frame_index_value, bone_id)
	frame_data["keys"] = keys
	return keys[bone_id] as Dictionary

func _record_history() -> void:
	undo_stack.append(document.duplicate(true))
	if undo_stack.size() > 60:
		undo_stack.pop_front()
	redo_stack.clear()

func _mark_changed(message: String = "", rebuild_structure: bool = false) -> void:
	dirty = true
	if autosave_timer != null:
		autosave_timer.start()
	if rebuild_structure:
		call("_rebuild_structure")
	else:
		call("_refresh_context")
	if not message.is_empty():
		_set_status(message)

func _set_status(message: String, is_error: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.modulate = Color(1.0, 0.42, 0.38) if is_error else Color(0.67, 0.86, 0.73)

func _update_window_title() -> void:
	var marker: String = " *" if dirty else ""
	get_window().title = "%s  •  %s%s" % [PROGRAM_NAME, _project_section().get("name", "Projeto"), marker]

func _texture_path(bone_id: String) -> String:
	var textures: Dictionary = _direction_data().get("textures", {}) as Dictionary
	return str(textures.get(bone_id, ""))
