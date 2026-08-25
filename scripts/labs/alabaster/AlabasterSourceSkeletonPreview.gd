extends Control

# Lightweight diagnostic view of a real imported Skeleton3D.
# The source scene/AnimationPlayer is evaluated normally, but only the skeleton is
# drawn here so Mixamo/Rokoko/Cascadeur/etc. can be compared with Juno's green
# Bone Studio view without Blender's octahedral bone display getting in the way.
#
# Navigation deliberately follows familiar DCC viewport behavior:
#   RMB drag    = orbit around the skeleton
#   Mouse wheel = zoom
#   MMB drag    = pan

const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")

signal pose_updated(time_seconds: float)

const BONE_COLOR := Color(0.10, 1.0, 0.72, 0.95)
const BONE_SHADOW := Color(0.02, 0.18, 0.14, 0.90)
const JOINT_COLOR := Color(1.0, 0.61, 0.08, 1.0)
const SELECTED_COLOR := Color(1.0, 0.94, 0.35, 1.0)
const LABEL_COLOR := Color(0.90, 1.0, 0.96, 1.0)
const ORBIT_SENSITIVITY := 0.008
const PAN_SENSITIVITY := 1.0
const ZOOM_STEP := 1.12
const MIN_ZOOM := 0.18
const MAX_ZOOM := 8.0
const MAX_PITCH := deg_to_rad(89.0)
const GEOMETRY_EPS := 0.000001

var _opened: Dictionary = {}
var _source_root: Node = null
var _player: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _clip_name := ""
var _clip_length := 0.0
var _time := 0.0
var _playing := true
var _speed := 1.0
var _selected_bone := ""
var _status := "No Skeleton3D loaded"
var _source_kind := ""

# View state. These affect only the diagnostic projection, never the imported
# skeleton or animation data.
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _orbiting := false
var _panning := false
var _rest_points: Array[Vector3] = []
var _pose_points: Array[Vector3] = []
var _rest_center := Vector3.ZERO
var _view_min := Vector2(-1.0, -1.0)
var _view_max := Vector2(1.0, 1.0)
var _using_rest_pose_fallback := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	set_process(true)
	queue_redraw()


func _exit_tree() -> void:
	clear_source()


func load_source(source_path: String, clip_name: String) -> Dictionary:
	clear_source()
	if source_path.strip_edges().is_empty():
		_status = "No source selected"
		queue_redraw()
		return {"ok": false, "error": _status}

	# For the visual diagnostic viewport, prefer Godot's already-imported scene.
	# The production retargeter still opens the raw FBX independently, so this does
	# not weaken the authoritative REST->POSE conversion path. The imported scene
	# is simply much more reliable for live AnimationPlayer/Skeleton3D evaluation.
	_opened = _open_visual_source(source_path)
	if not bool(_opened.get("ok", false)):
		_status = str(_opened.get("error", "Could not open source."))
		queue_redraw()
		return {"ok": false, "error": _status}

	_source_root = _opened.get("root") as Node
	_player = _opened.get("player") as AnimationPlayer
	_skeleton = _opened.get("skeleton") as Skeleton3D
	_source_kind = str(_opened.get("kind", "unknown"))
	if _source_root == null or _player == null or _skeleton == null:
		_status = "Source does not expose a live AnimationPlayer + Skeleton3D."
		clear_source()
		queue_redraw()
		return {"ok": false, "error": _status}

	# Keep the hierarchy intact so AnimationPlayer NodePaths continue to resolve.
	# VisualInstance3D children are hidden because this viewport intentionally draws
	# a clean diagnostic skeleton in 2D instead of the imported mesh.
	if _source_root.get_parent() != null:
		_source_root.get_parent().remove_child(_source_root)
	add_child(_source_root)
	_source_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_skeleton.process_mode = Node.PROCESS_MODE_ALWAYS
	_hide_3d_visuals(_source_root)
	_compute_rest_geometry()
	_reset_view()
	if not set_clip(clip_name):
		var animations := _player.get_animation_list()
		if not animations.is_empty():
			set_clip(str(animations[0]))
	_refresh_pose_geometry()
	_status = "%d Skeleton3D bones" % _skeleton.get_bone_count()
	queue_redraw()
	return {
		"ok": true,
		"bone_count": _skeleton.get_bone_count(),
		"bones": get_bone_names(),
		"clip": _clip_name,
		"clip_length": _clip_length,
		"source_kind": _source_kind,
		"drawable_segments": get_drawable_segment_count(),
	}


func clear_source() -> void:
	if not _opened.is_empty():
		SourceAdapter.close_preview_source(_opened)
	_opened.clear()
	_source_root = null
	_player = null
	_skeleton = null
	_clip_name = ""
	_clip_length = 0.0
	_time = 0.0
	_selected_bone = ""
	_status = "No Skeleton3D loaded"
	_source_kind = ""
	_rest_points.clear()
	_pose_points.clear()
	_rest_center = Vector3.ZERO
	_using_rest_pose_fallback = false
	_reset_view()
	queue_redraw()


func set_clip(clip_name: String) -> bool:
	if _player == null or clip_name.is_empty() or not _player.has_animation(clip_name):
		return false
	_clip_name = clip_name
	var animation := _player.get_animation(clip_name)
	_clip_length = maxf(animation.length if animation != null else 0.0, 0.000001)
	_time = 0.0
	_player.stop()
	_player.play(_clip_name)
	_player.pause()
	_player.seek(0.0, true)
	_flush_skeleton_pose()
	queue_redraw()
	pose_updated.emit(_time)
	return true


func set_playing(enabled: bool) -> void:
	_playing = enabled


func is_playing() -> bool:
	return _playing


func set_speed(value: float) -> void:
	_speed = clampf(value, 0.05, 4.0)


func get_speed() -> float:
	return _speed


func set_time(time_seconds: float) -> void:
	if _player == null or _clip_name.is_empty():
		return
	if _clip_length > 0.0:
		_time = fposmod(time_seconds, _clip_length)
	else:
		_time = maxf(time_seconds, 0.0)
	_player.seek(_time, true)
	_flush_skeleton_pose()
	queue_redraw()
	pose_updated.emit(_time)


func get_time() -> float:
	return _time


func get_clip_length() -> float:
	return _clip_length


func get_bone_names() -> Array[String]:
	var result: Array[String] = []
	if _skeleton == null:
		return result
	for bone_index in range(_skeleton.get_bone_count()):
		result.append(str(_skeleton.get_bone_name(bone_index)))
	return result


func get_drawable_segment_count() -> int:
	if _skeleton == null:
		return 0
	_refresh_pose_geometry()
	var count := 0
	for bone_index in range(_skeleton.get_bone_count()):
		var parent_index := _skeleton.get_bone_parent(bone_index)
		if parent_index < 0 or bone_index >= _pose_points.size() or parent_index >= _pose_points.size():
			continue
		if _pose_points[bone_index].distance_squared_to(_pose_points[parent_index]) > GEOMETRY_EPS:
			count += 1
	return count


func is_using_rest_pose_fallback() -> bool:
	return _using_rest_pose_fallback


func select_bone(bone_name: String) -> void:
	_selected_bone = bone_name
	queue_redraw()


func get_selected_bone() -> String:
	return _selected_bone


func _process(delta: float) -> void:
	if _player == null or _clip_name.is_empty():
		return
	if _playing:
		set_time(_time + delta * _speed)
	else:
		_flush_skeleton_pose()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = button.pressed
				if button.pressed:
					grab_focus()
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_panning = button.pressed
				if button.pressed:
					grab_focus()
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom = clampf(_zoom * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
					queue_redraw()
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom = clampf(_zoom / ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
					queue_redraw()
				accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			_orbit_yaw = wrapf(_orbit_yaw - motion.relative.x * ORBIT_SENSITIVITY, -PI, PI)
			_orbit_pitch = clampf(_orbit_pitch - motion.relative.y * ORBIT_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
			queue_redraw()
			accept_event()
		elif _panning:
			_pan += motion.relative * PAN_SENSITIVITY
			queue_redraw()
			accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.065, 0.065, 1.0), true)
	if _skeleton == null:
		draw_string(ThemeDB.fallback_font, Vector2(18.0, 30.0), _status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.72, 0.78, 0.78))
		return

	_refresh_pose_geometry()
	_update_view_bounds()

	# Draw parent-child segments first, then joints so the same cyan/green + orange
	# visual language used by Juno remains readable even on dense Mixamo fingers.
	for bone_index in range(_skeleton.get_bone_count()):
		var parent_index := _skeleton.get_bone_parent(bone_index)
		if parent_index < 0:
			continue
		var child_pos := _pose_point(bone_index)
		var parent_pos := _pose_point(parent_index)
		draw_line(parent_pos, child_pos, BONE_SHADOW, 7.0, true)
		draw_line(parent_pos, child_pos, BONE_COLOR, 3.0, true)

	for bone_index in range(_skeleton.get_bone_count()):
		var bone_name := str(_skeleton.get_bone_name(bone_index))
		var point := _pose_point(bone_index)
		var selected := bone_name == _selected_bone
		draw_circle(point, 5.0 if selected else 3.5, SELECTED_COLOR if selected else JOINT_COLOR)
		if selected:
			draw_circle(point, 9.0, Color(1.0, 0.94, 0.35, 0.28), false, 2.0)
			draw_string(ThemeDB.fallback_font, point + Vector2(10.0, -8.0), bone_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, LABEL_COLOR)

	var nav_hint := "RMB orbit  ·  Wheel zoom  ·  MMB pan"
	draw_string(ThemeDB.fallback_font, Vector2(12.0, 22.0), nav_hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.52, 0.62, 0.60))
	var pose_label := "REST fallback" if _using_rest_pose_fallback else "LIVE pose"
	var footer := "%s  ·  %.2fs / %.2fs  ·  %.2fx  ·  %s" % [_clip_name, _time, _clip_length, _zoom, pose_label]
	draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 12.0), footer, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.66, 0.78, 0.74))


func _pose_point(bone_index: int) -> Vector2:
	if bone_index < 0 or bone_index >= _pose_points.size():
		return size * 0.5
	return _project_to_canvas(_pose_points[bone_index])


func _project_to_canvas(point_3d: Vector3) -> Vector2:
	var rotated := _rotate_view_point(point_3d)
	var p := Vector2(rotated.x, -rotated.y)
	var span := _view_max - _view_min
	span.x = maxf(span.x, 0.001)
	span.y = maxf(span.y, 0.001)
	var available := Vector2(maxf(size.x - 42.0, 1.0), maxf(size.y - 72.0, 1.0))
	var fit_scale := minf(available.x / span.x, available.y / span.y) * _zoom
	var view_bounds_center := (_view_min + _view_max) * 0.5
	var view_center := Vector2(size.x * 0.5, size.y * 0.5 - 2.0) + _pan
	return view_center + (p - view_bounds_center) * fit_scale


func _rotate_view_point(point_3d: Vector3) -> Vector3:
	var local := point_3d - _rest_center
	# Yaw around the humanoid's Y-up axis, then pitch around local X. This is a
	# camera-like orbit while the actual imported Skeleton3D remains untouched.
	local = local.rotated(Vector3.UP, _orbit_yaw)
	local = local.rotated(Vector3.RIGHT, _orbit_pitch)
	return local


func _compute_rest_geometry() -> void:
	_rest_points.clear()
	_rest_center = Vector3.ZERO
	if _skeleton == null or _skeleton.get_bone_count() <= 0:
		_rest_points.append(Vector3(-1.0, -1.0, 0.0))
		_rest_points.append(Vector3(1.0, 1.0, 0.0))
		return

	# Reconstruct the hierarchy from LOCAL rest transforms instead of trusting the
	# cached global-rest array. This also sidesteps historical Skeleton3D global-rest
	# cache regressions and makes the preview deterministic for runtime-generated FBX.
	var rest_globals: Array[Transform3D] = []
	rest_globals.resize(_skeleton.get_bone_count())
	for bone_index in range(_skeleton.get_bone_count()):
		var local_rest := _skeleton.get_bone_rest(bone_index)
		var parent_index := _skeleton.get_bone_parent(bone_index)
		var global_rest := local_rest
		if parent_index >= 0 and parent_index < rest_globals.size():
			global_rest = rest_globals[parent_index] * local_rest
		rest_globals[bone_index] = global_rest
		_rest_points.append(global_rest.origin)
		_rest_center += global_rest.origin
	_rest_center /= float(maxi(_rest_points.size(), 1))


func _refresh_pose_geometry() -> void:
	_pose_points.clear()
	_using_rest_pose_fallback = false
	if _skeleton == null or _skeleton.get_bone_count() <= 0:
		return

	# Build globals from each bone's LOCAL animated pose. This avoids depending on
	# deferred global-pose cache timing after AnimationPlayer.seek(), which was the
	# reason the Bone Bridge could report 33 bones while drawing an empty viewport.
	var pose_globals: Array[Transform3D] = []
	pose_globals.resize(_skeleton.get_bone_count())
	var finite_count := 0
	for bone_index in range(_skeleton.get_bone_count()):
		var local_pose := _skeleton.get_bone_pose(bone_index)
		var parent_index := _skeleton.get_bone_parent(bone_index)
		var global_pose := local_pose
		if parent_index >= 0 and parent_index < pose_globals.size():
			global_pose = pose_globals[parent_index] * local_pose
		pose_globals[bone_index] = global_pose
		var point := global_pose.origin
		_pose_points.append(point)
		if _vector3_is_finite(point):
			finite_count += 1

	var pose_span := _point_span(_pose_points)
	if finite_count != _skeleton.get_bone_count() or pose_span <= GEOMETRY_EPS:
		_pose_points = _rest_points.duplicate()
		_using_rest_pose_fallback = true


func _flush_skeleton_pose() -> void:
	if _player != null:
		# seek(..., true) evaluates discrete tracks, while advance(0) flushes the
		# AnimationPlayer's property writes into the imported hierarchy immediately.
		_player.advance(0.0)
	if _skeleton != null and _skeleton.has_method("force_update_all_bone_transforms"):
		_skeleton.call("force_update_all_bone_transforms")
	_refresh_pose_geometry()


func _point_span(points: Array[Vector3]) -> float:
	if points.size() < 2:
		return 0.0
	var min_point := Vector3(INF, INF, INF)
	var max_point := Vector3(-INF, -INF, -INF)
	for point in points:
		if not _vector3_is_finite(point):
			continue
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		min_point.z = minf(min_point.z, point.z)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
		max_point.z = maxf(max_point.z, point.z)
	if not _vector3_is_finite(min_point) or not _vector3_is_finite(max_point):
		return 0.0
	return (max_point - min_point).length_squared()


func _vector3_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _update_view_bounds() -> void:
	if _rest_points.is_empty():
		_view_min = Vector2(-1.0, -1.0)
		_view_max = Vector2(1.0, 1.0)
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for point_3d in _rest_points:
		var rotated := _rotate_view_point(point_3d)
		var p := Vector2(rotated.x, -rotated.y)
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	if not is_finite(min_p.x) or not is_finite(min_p.y):
		min_p = Vector2(-1.0, -1.0)
		max_p = Vector2(1.0, 1.0)
	var span := max_p - min_p
	var padding := maxf(span.length() * 0.06, 0.05)
	_view_min = min_p - Vector2.ONE * padding
	_view_max = max_p + Vector2.ONE * padding


func _reset_view() -> void:
	_orbit_yaw = 0.0
	_orbit_pitch = 0.0
	_zoom = 1.0
	_pan = Vector2.ZERO
	_orbiting = false
	_panning = false
	queue_redraw()


func _open_visual_source(source_path: String) -> Dictionary:
	# ResourceLoader resolves an FBX path to Godot's imported PackedScene. Prefer
	# that for the VIEW only, because its AnimationPlayer/Skeleton3D are already in
	# the exact form the engine uses at runtime.
	if ResourceLoader.exists(source_path):
		var resource: Resource = load(source_path)
		if resource is PackedScene:
			var root := (resource as PackedScene).instantiate()
			if root != null:
				var player := _find_animation_player(root)
				var skeleton := _find_skeleton3d(root)
				if player != null and skeleton != null:
					return {
						"ok": true,
						"kind": "imported_preview_scene",
						"root": root,
						"player": player,
						"skeleton": skeleton,
					}
				root.free()
	return SourceAdapter.open_preview_source(source_path)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton3d(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_skeleton3d(child)
		if found != null:
			return found
	return null


func _hide_3d_visuals(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = false
	if node is Camera3D:
		(node as Camera3D).current = false
	for child_value in node.get_children():
		var child := child_value as Node
		if child != null:
			_hide_3d_visuals(child)
