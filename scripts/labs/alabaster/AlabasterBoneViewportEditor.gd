extends Control
class_name AlabasterBoneViewportEditor

signal bone_selected(bone_name: String)
signal bone_transform_delta(bone_name: String, transform_mode: String, delta_value: Vector3)
signal orbit_delta(yaw_delta: float, pitch_delta: float)
signal zoom_requested(factor: float)

const MODE_MOVE := "move"
const MODE_ROTATE := "rotate"
const PICK_RADIUS := 13.0
const BONE_COLOR := Color("#66E6C5")
const BONE_DIM_COLOR := Color("#526E6D")
const SELECTED_COLOR := Color("#FFB84D")
const MOVE_X_COLOR := Color("#E96666")
const MOVE_Z_COLOR := Color("#66D98A")
const ROTATE_COLOR := Color("#A87BE8")

var rig: Node2D
var preview_origin := Vector2.ZERO
var transform_mode := MODE_ROTATE
var camera_locked := true
var selected_bone := ""
var _dragging_bone := false
var _orbiting := false
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL


func configure(target_rig: Node2D, origin: Vector2) -> void:
	rig = target_rig
	preview_origin = origin
	queue_redraw()


func set_preview_origin(origin: Vector2) -> void:
	preview_origin = origin
	queue_redraw()


func set_transform_mode(mode: String) -> void:
	transform_mode = MODE_MOVE if mode == MODE_MOVE else MODE_ROTATE
	queue_redraw()


func set_camera_locked(locked: bool) -> void:
	camera_locked = locked


func set_selected_bone(bone_name: String) -> void:
	selected_bone = bone_name
	queue_redraw()


func _process(_delta: float) -> void:
	if rig != null and is_instance_valid(rig):
		queue_redraw()


func _draw() -> void:
	if rig == null or not is_instance_valid(rig) or not rig.has_method("get_all_bone_screen_poses"):
		return
	var poses_value: Variant = rig.call("get_all_bone_screen_poses")
	if not poses_value is Dictionary:
		return
	var poses: Dictionary = poses_value
	var parents := {}
	if rig.has_method("get_bone_parent_map"):
		var parents_value: Variant = rig.call("get_bone_parent_map")
		if parents_value is Dictionary:
			parents = parents_value

	for bone_name_value in poses.keys():
		var bone_name := str(bone_name_value)
		var pose_value: Variant = poses[bone_name_value]
		if not pose_value is Dictionary:
			continue
		var p := _pose_to_canvas(pose_value as Dictionary)
		var parent_name := str(parents.get(bone_name, ""))
		if not parent_name.is_empty() and poses.has(parent_name) and poses[parent_name] is Dictionary:
			var pp := _pose_to_canvas(poses[parent_name] as Dictionary)
			draw_line(pp, p, BONE_COLOR if bone_name == selected_bone else BONE_DIM_COLOR, 1.5)

	for bone_name_value in poses.keys():
		var bone_name := str(bone_name_value)
		var pose_value: Variant = poses[bone_name_value]
		if not pose_value is Dictionary:
			continue
		var p := _pose_to_canvas(pose_value as Dictionary)
		var selected := bone_name == selected_bone
		draw_circle(p, 5.0 if selected else 3.0, SELECTED_COLOR if selected else BONE_COLOR)

	_draw_gizmo(poses)


func _draw_gizmo(poses: Dictionary) -> void:
	if selected_bone.is_empty() or not poses.has(selected_bone) or not poses[selected_bone] is Dictionary:
		return
	var center := _pose_to_canvas(poses[selected_bone] as Dictionary)
	if transform_mode == MODE_MOVE:
		draw_line(center, center + Vector2(28, 0), MOVE_X_COLOR, 2.0)
		draw_line(center + Vector2(28, 0), center + Vector2(22, -4), MOVE_X_COLOR, 2.0)
		draw_line(center + Vector2(28, 0), center + Vector2(22, 4), MOVE_X_COLOR, 2.0)
		draw_line(center, center + Vector2(0, -28), MOVE_Z_COLOR, 2.0)
		draw_line(center + Vector2(0, -28), center + Vector2(-4, -22), MOVE_Z_COLOR, 2.0)
		draw_line(center + Vector2(0, -28), center + Vector2(4, -22), MOVE_Z_COLOR, 2.0)
	else:
		draw_arc(center, 23.0, 0.0, TAU, 48, ROTATE_COLOR, 2.0)
		draw_line(center, center + Vector2(20, -12), ROTATE_COLOR, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			zoom_requested.emit(1.10)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			zoom_requested.emit(1.0 / 1.10)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				var picked := _pick_bone(button.position)
				if not picked.is_empty():
					selected_bone = picked
					bone_selected.emit(picked)
					_dragging_bone = true
					_last_mouse = button.position
					grab_focus()
					queue_redraw()
					accept_event()
			else:
				_dragging_bone = false
			return
		if button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed and not camera_locked:
				_orbiting = true
				_last_mouse = button.position
				grab_focus()
				accept_event()
			elif not button.pressed:
				_orbiting = false
			return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging_bone and not selected_bone.is_empty():
			var pixel_delta := motion.position - _last_mouse
			_last_mouse = motion.position
			if transform_mode == MODE_MOVE:
				var scale_factor := maxf(absf(rig.scale.x), 0.001) if rig != null else 1.0
				var world_per_pixel := 1.0 / (34.0 * scale_factor)
				var delta_value := Vector3(pixel_delta.x * world_per_pixel, 0.0, -pixel_delta.y * world_per_pixel)
				if motion.alt_pressed:
					delta_value = Vector3(pixel_delta.x * world_per_pixel, -pixel_delta.y * world_per_pixel, 0.0)
				bone_transform_delta.emit(selected_bone, MODE_MOVE, delta_value)
			else:
				var rotation_delta := Vector3(pixel_delta.x * 0.55, -pixel_delta.y * 0.55, 0.0)
				if motion.shift_pressed:
					rotation_delta = Vector3(0.0, 0.0, pixel_delta.x * 0.55)
				bone_transform_delta.emit(selected_bone, MODE_ROTATE, rotation_delta)
			accept_event()
			return
		if _orbiting and not camera_locked:
			var pixel_delta := motion.position - _last_mouse
			_last_mouse = motion.position
			orbit_delta.emit(pixel_delta.x * 0.35, pixel_delta.y * 0.25)
			accept_event()


func _pick_bone(mouse_position: Vector2) -> String:
	if rig == null or not rig.has_method("get_all_bone_screen_poses"):
		return ""
	var poses_value: Variant = rig.call("get_all_bone_screen_poses")
	if not poses_value is Dictionary:
		return ""
	var poses: Dictionary = poses_value
	var best_name := ""
	var best_distance := PICK_RADIUS
	for bone_name_value in poses.keys():
		var pose_value: Variant = poses[bone_name_value]
		if not pose_value is Dictionary:
			continue
		var p := _pose_to_canvas(pose_value as Dictionary)
		var distance := mouse_position.distance_to(p)
		if distance <= best_distance:
			best_distance = distance
			best_name = str(bone_name_value)
	return best_name


func _pose_to_canvas(pose: Dictionary) -> Vector2:
	var screen_position: Vector2 = pose.get("screen_position", Vector2.ZERO)
	var visual_scale := Vector2.ONE
	if rig != null:
		visual_scale = rig.scale
	return preview_origin + Vector2(screen_position.x * visual_scale.x, screen_position.y * visual_scale.y)
