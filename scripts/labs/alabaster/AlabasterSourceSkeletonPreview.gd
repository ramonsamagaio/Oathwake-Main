extends Control

# Lightweight 2D diagnostic view of a real imported Skeleton3D.
# The source scene/AnimationPlayer is evaluated normally, but only the skeleton is
# drawn here so Mixamo/Rokoko/Cascadeur/etc. can be compared with Juno's green
# Bone Studio view without Blender's octahedral bone display getting in the way.

const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")

signal pose_updated(time_seconds: float)

const BONE_COLOR := Color(0.10, 1.0, 0.72, 0.95)
const BONE_SHADOW := Color(0.02, 0.18, 0.14, 0.90)
const JOINT_COLOR := Color(1.0, 0.61, 0.08, 1.0)
const SELECTED_COLOR := Color(1.0, 0.94, 0.35, 1.0)
const LABEL_COLOR := Color(0.90, 1.0, 0.96, 1.0)

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
var _rest_min := Vector2(-1.0, -1.0)
var _rest_max := Vector2(1.0, 1.0)
var _status := "No Skeleton3D loaded"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
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

	_opened = SourceAdapter.open_preview_source(source_path)
	if not bool(_opened.get("ok", false)):
		_status = str(_opened.get("error", "Could not open source."))
		queue_redraw()
		return {"ok": false, "error": _status}

	_source_root = _opened.get("root") as Node
	_player = _opened.get("player") as AnimationPlayer
	_skeleton = _opened.get("skeleton") as Skeleton3D
	if _source_root == null or _player == null or _skeleton == null:
		_status = "Source does not expose a live AnimationPlayer + Skeleton3D."
		clear_source()
		queue_redraw()
		return {"ok": false, "error": _status}

	# Keep the imported hierarchy alive so AnimationPlayer NodePaths resolve, but
	# hide any cameras/meshes. The Bone Bridge intentionally renders only bones.
	if _source_root.get_parent() != null:
		_source_root.get_parent().remove_child(_source_root)
	add_child(_source_root)
	_hide_3d_visuals(_source_root)
	_compute_rest_bounds()
	set_clip(clip_name)
	_status = "%d Skeleton3D bones" % _skeleton.get_bone_count()
	queue_redraw()
	return {
		"ok": true,
		"bone_count": _skeleton.get_bone_count(),
		"bones": get_bone_names(),
		"clip": _clip_name,
		"clip_length": _clip_length,
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
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.065, 0.065, 1.0), true)
	if _skeleton == null:
		draw_string(ThemeDB.fallback_font, Vector2(18.0, 30.0), _status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.72, 0.78, 0.78))
		return

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

	var footer := "%s  ·  %.2fs / %.2fs" % [_clip_name, _time, _clip_length]
	draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 12.0), footer, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.66, 0.78, 0.74))


func _pose_point(bone_index: int) -> Vector2:
	if _skeleton == null:
		return size * 0.5
	var pose := _skeleton.get_bone_global_pose(bone_index)
	return _project_to_canvas(pose.origin)


func _project_to_canvas(point_3d: Vector3) -> Vector2:
	# Godot's humanoid convention is Y-up. Looking at the skeleton from the front
	# therefore maps X horizontally and -Y vertically, matching the useful Blender
	# armature view while ignoring depth for this comparison panel.
	var p := Vector2(point_3d.x, -point_3d.y)
	var span := _rest_max - _rest_min
	span.x = maxf(span.x, 0.001)
	span.y = maxf(span.y, 0.001)
	var available := Vector2(maxf(size.x - 36.0, 1.0), maxf(size.y - 54.0, 1.0))
	var fit_scale := minf(available.x / span.x, available.y / span.y)
	var rest_center := (_rest_min + _rest_max) * 0.5
	var view_center := Vector2(size.x * 0.5, size.y * 0.5 - 4.0)
	return view_center + (p - rest_center) * fit_scale


func _compute_rest_bounds() -> void:
	if _skeleton == null or _skeleton.get_bone_count() <= 0:
		_rest_min = Vector2(-1.0, -1.0)
		_rest_max = Vector2(1.0, 1.0)
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for bone_index in range(_skeleton.get_bone_count()):
		var rest := _skeleton.get_bone_global_rest(bone_index)
		var p := Vector2(rest.origin.x, -rest.origin.y)
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	if not is_finite(min_p.x) or not is_finite(min_p.y):
		min_p = Vector2(-1.0, -1.0)
		max_p = Vector2(1.0, 1.0)
	var padding := maxf((max_p - min_p).length() * 0.06, 0.05)
	_rest_min = min_p - Vector2.ONE * padding
	_rest_max = max_p + Vector2.ONE * padding


func _hide_3d_visuals(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = false
	if node is Camera3D:
		(node as Camera3D).current = false
	for child_value in node.get_children():
		var child := child_value as Node
		if child != null:
			_hide_3d_visuals(child)
