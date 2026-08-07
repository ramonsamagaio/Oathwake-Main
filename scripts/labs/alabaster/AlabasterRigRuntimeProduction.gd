extends "res://scripts/labs/alabaster/AlabasterRigRuntimeImportable.gd"
class_name AlabasterRigRuntimeProduction

# Final Oathwake correction layer. The source-derived renderer remains intact;
# only camera-dependent CanvasItem depth and editor-only inspection controls
# are resolved here.

const NO_LAYER_OVERRIDE := 999999
const SIDE_DEPTH_EPSILON := 0.015

var editor_camera_enabled := false
var editor_camera_pitch_degrees := -45.0
var editor_animation_paused := false


func _process(delta: float) -> void:
	if editor_animation_paused:
		_apply_pose()
		return
	super._process(delta)


func set_editor_camera_enabled(enabled: bool) -> void:
	editor_camera_enabled = enabled
	_apply_pose()


func set_editor_camera_pitch_degrees(value: float) -> void:
	editor_camera_pitch_degrees = clampf(value, -80.0, -10.0)
	if editor_camera_enabled:
		_apply_pose()


func set_editor_animation_paused(paused: bool) -> void:
	editor_animation_paused = paused


func seek_animation_frame(frame: float) -> void:
	if not _anims.has(current_animation):
		return
	var anim: Dictionary = _anims[current_animation]
	var frame_count := maxf(float(anim.get("frameCnt", 1.0)), 1.0)
	var frame_repeat := maxf(float(anim.get("frameRepeat", 1.0)), 0.001)
	var anim_start := float(anim.get("animStart", 0.0))
	var resolved_frame := clampf(frame, anim_start, frame_count)
	animation_time = maxf((resolved_frame - anim_start) * frame_repeat / SRC_FPS, 0.0)
	_apply_pose()


func get_current_source_frame() -> float:
	return _src_frame


func _project_world(world: Vector3) -> Vector2:
	if not editor_camera_enabled:
		return super._project_world(world)
	# Editor-only vertical camera orbit. Horizontal orbit still uses the actual
	# figure facing angle, which preserves the same sprite-facing selection as
	# gameplay. This projection changes only inspection camera pitch.
	var x := world.x * (TILE_W / TILE_H)
	var y := -world.y + CAMERA_SKEW * world.z
	var z := world.z
	var camera_rotation := deg_to_rad(editor_camera_pitch_degrees)
	var c := cos(camera_rotation)
	var s := sin(camera_rotation)
	var view_y := y * c - z * s
	var view_z := y * s + z * c - CAMERA_Z
	var w := maxf(-view_z, 0.001)
	var f := 1.0 / tan(deg_to_rad(FOV_DEG) * 0.5)
	var aspect := SCREEN_W / SCREEN_H
	var ndc_x := (f / aspect) * x / w
	var ndc_y := f * view_y / w
	return Vector2(SCREEN_W * 0.5 * ndc_x, -SCREEN_H * 0.5 * ndc_y)


func _apply_directional_layer_override(record: Dictionary, sprite: Sprite2D) -> void:
	var node_name := String(record.get("node", ""))

	# Juno's floating hair ornament must cover the skull when seen from the
	# NORTH. SOUTH intentionally keeps the source-authored layer, which places
	# the ornament behind the head. Diagonals/profile also stay authored.
	if node_name == "headGear":
		if _angular_distance(facing_degrees, 0.0) <= 11.26:
			_set_logical_layer(sprite, 3)
		return

	# Keep the proven braid/tail ordering from the source correction layer.
	if node_name == "tailEnd":
		var north_distance := _angular_distance(facing_degrees, 0.0)
		if north_distance <= 67.5:
			_set_logical_layer(sprite, 3)
		elif north_distance <= 112.5:
			_set_logical_layer(sprite, 1)
		return

	# Legs: choose front/back from the actual 3D hip anchors after facing has
	# been applied. Larger global Y is closer under the source camera formula.
	# This fixes W/E and NW/SW without hardcoding anatomical left/right.
	if node_name == "legL" or node_name == "legR":
		var side := "L" if node_name.ends_with("L") else "R"
		var front_state := _side_front_state("hipL", "hipR", side)
		if front_state == 1:
			_offset_logical_layer(sprite, 1)
		elif front_state == -1:
			_offset_logical_layer(sprite, -1)
		return

	# Arms/hands/fingers move as one visual chain. Shoulder depth remains stable
	# while hands swing, preventing the rear arm from crossing in front of the
	# torso in SW/NW profile-like views.
	if node_name in ["armL", "handL", "fingerL", "armR", "handR", "fingerR"]:
		var side := "L" if node_name.ends_with("L") else "R"
		var front_state := _side_front_state("shoulderL", "shoulderR", side)
		if front_state == 1:
			_offset_logical_layer(sprite, 1)
		elif front_state == -1:
			_offset_logical_layer(sprite, -4)
		return


func _side_front_state(left_anchor: String, right_anchor: String, requested_side: String) -> int:
	if not _states.has(left_anchor) or not _states.has(right_anchor):
		return 0
	var left_state: Dictionary = _states[left_anchor]
	var right_state: Dictionary = _states[right_anchor]
	var left_pos: Vector3 = left_state.get("g_self", Vector3.ZERO)
	var right_pos: Vector3 = right_state.get("g_self", Vector3.ZERO)
	var delta := left_pos.y - right_pos.y
	if absf(delta) <= SIDE_DEPTH_EPSILON:
		return 0
	var left_is_front := delta > 0.0
	if requested_side == "L":
		return 1 if left_is_front else -1
	return -1 if left_is_front else 1


func _set_logical_layer(sprite: Sprite2D, logical_layer: int) -> void:
	if _embedded_world_mode:
		sprite.z_as_relative = true
		sprite.z_index = clampi(logical_layer, -32, 32)
	else:
		sprite.z_as_relative = false
		var figure_global_z := int(_figure.get("globalZOrder", 0))
		sprite.z_index = clampi((figure_global_z + logical_layer) * 16, -4096, 4096)
	sprite.set_meta("alabaster_layer_override", logical_layer)


func _offset_logical_layer(sprite: Sprite2D, logical_offset: int) -> void:
	if logical_offset == 0:
		return
	if _embedded_world_mode:
		sprite.z_as_relative = true
		sprite.z_index = clampi(sprite.z_index + logical_offset, -32, 32)
	else:
		sprite.z_as_relative = false
		sprite.z_index = clampi(sprite.z_index + logical_offset * 16, -4096, 4096)
	sprite.set_meta("alabaster_layer_offset", logical_offset)
