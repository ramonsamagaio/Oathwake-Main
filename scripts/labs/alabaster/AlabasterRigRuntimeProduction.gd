extends "res://scripts/labs/alabaster/AlabasterRigRuntimeImportable.gd"
class_name AlabasterRigRuntimeProduction

# Final Oathwake correction layer. The source-derived renderer remains intact;
# only camera-dependent CanvasItem depth and editor-only inspection controls
# are resolved here.

const NO_LAYER_OVERRIDE := 999999
const SIDE_DEPTH_EPSILON := 0.015
const PROFILE_FACING_EPSILON := 11.26
const CARDINAL_FACING_EPSILON := 11.26
const CARDINAL_STANCE_MIN_HALF_HIP_RATIO := 0.38
const CARDINAL_STANCE_MIN_PX := 1.5
const CARDINAL_STANCE_MAX_SHIFT_PX := 8.0
const CARDINAL_STANCE_MAX_SHIFT_HIP_RATIO := 0.90
const CARDINAL_STANCE_LEG_WEIGHT := 0.45

var editor_camera_enabled := false
var editor_camera_pitch_degrees := -45.0
var editor_animation_paused := false
var _cardinal_stance_debug: Dictionary = {}


func _process(delta: float) -> void:
	if editor_animation_paused:
		_apply_pose()
		return
	super._process(delta)


func _apply_pose() -> void:
	# Let the source renderer and all existing directional corrections finish
	# first. Camera-dependent presentation guards need final sprite positions and
	# z values, not guesses based on authored REST data.
	super._apply_pose()
	_apply_profile_front_arm_over_legs()
	_apply_cardinal_walk_leg_corridor()


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


func get_cardinal_stance_debug() -> Dictionary:
	return _cardinal_stance_debug.duplicate(true)


func get_bone_visual_state(node_name: String) -> Dictionary:
	if not _states.has(node_name):
		return {}
	var state: Dictionary = (_states[node_name] as Dictionary).duplicate(true)
	var pose := get_bone_screen_pose(node_name)
	state["screen_position"] = pose.get("screen_position", Vector2.ZERO)
	state["screen_origin"] = pose.get("screen_origin", Vector2.ZERO)
	state["screen_rotation"] = pose.get("rotation", 0.0)
	state["world_position"] = pose.get("world_position", Vector3.ZERO)
	state["frame_key"] = int(state.get("frame_key", 0))
	state["pitch"] = int(state.get("pitch", 4))
	state["facing_yaw"] = float(state.get("facing_yaw", facing_degrees))
	state["yaw_flipped"] = bool(state.get("yaw_flipped", false))
	# External figures (weapons/equipment) need the same accumulated 3D bone
	# rotation/scale that the body renderer uses for local gfx offsets.
	state["g_rot"] = state.get("dir", Quaternion.IDENTITY)
	state["g_scale"] = float(state.get("scale", 1.0))
	return state


func project_external_world(world: Vector3) -> Vector2:
	return _project_world(world)


func project_external_node_offset(node_name: String, local_offset: Vector3) -> Vector2:
	if not _states.has(node_name):
		return Vector2.ZERO
	var state: Dictionary = _states[node_name]
	var offset := local_offset
	var node_scale := float(state.get("scale", 1.0))
	if node_scale != 1.0:
		offset *= node_scale
	if bool(state.get("rotated", false)):
		offset = _figure_transform(offset, state.get("dir", Quaternion.IDENTITY))
	# state.g_self is already in figure-global coordinates. Rotate the local
	# offset by the same rounded root facing before adding it to that anchor.
	var global_offset := _globalize(offset)
	var world: Vector3 = state.get("g_self", Vector3.ZERO) + global_offset
	return _project_world(world)


func resolve_external_facing(mode: String, angle: float, flip_roll: bool = false) -> Dictionary:
	return _select_facing_source(mode, angle, flip_roll)


func resolve_external_texture_row(entries: Dictionary, frame_key: int, pitch: int) -> Dictionary:
	var result := _find_texture_row(entries, frame_key, pitch)
	if result.is_empty() and frame_key != 0:
		result = _find_texture_row(entries, 0, pitch)
	return result


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


func _apply_profile_front_arm_over_legs() -> void:
	# At exact E/W profile the anatomical near-side arm must sit above the legs.
	# This is a camera/depth rule, not a locomotion-name rule. Bone Bridge installs
	# retargets under names such as __bone_bridge_preview, so the old idle/walk/run
	# whitelist silently skipped the correction precisely while authoring imports.
	# Diagonals still retain their authored crossing order.
	var is_east := _angular_distance(facing_degrees, 90.0) <= PROFILE_FACING_EPSILON
	var is_west := _angular_distance(facing_degrees, 270.0) <= PROFILE_FACING_EPSILON
	if not is_east and not is_west:
		return

	var left_front := _side_front_state("shoulderL", "shoulderR", "L")
	if left_front == 0:
		return
	var front_suffix := "L" if left_front == 1 else "R"
	var front_nodes := ["arm" + front_suffix, "hand" + front_suffix, "finger" + front_suffix]

	var leg_top := -4096
	var front_arm_bottom := 4096
	var has_leg := false
	var has_front_arm := false
	for record in _sprite_records:
		var sprite: Sprite2D = record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var node_name := String(record.get("node", ""))
		if node_name == "legL" or node_name == "legR":
			leg_top = maxi(leg_top, sprite.z_index)
			has_leg = true
		elif node_name in front_nodes:
			front_arm_bottom = mini(front_arm_bottom, sprite.z_index)
			has_front_arm = true

	if not has_leg or not has_front_arm or front_arm_bottom > leg_top:
		return

	var layer_step := 1 if _embedded_world_mode else 16
	var required_shift := (leg_top + layer_step) - front_arm_bottom
	for record in _sprite_records:
		var node_name := String(record.get("node", ""))
		if node_name not in front_nodes:
			continue
		var sprite: Sprite2D = record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		sprite.z_index = clampi(sprite.z_index + required_shift, -4096, 4096)
		sprite.set_meta("alabaster_profile_arm_over_leg", true)


func _apply_cardinal_walk_leg_corridor() -> void:
	_cardinal_stance_debug = {
		"active": false,
		"animation": current_animation,
		"facing": facing_degrees,
	}
	if not _cardinal_walk_corridor_enabled():
		return
	var is_north := _angular_distance(facing_degrees, 0.0) <= CARDINAL_FACING_EPSILON
	var is_south := _angular_distance(facing_degrees, 180.0) <= CARDINAL_FACING_EPSILON
	if not is_north and not is_south:
		return
	for required_node in ["hipL", "hipR", "footL", "footR"]:
		if not _states.has(required_node):
			return

	var hip_l := _project_state_anchor("hipL")
	var hip_r := _project_state_anchor("hipR")
	var foot_l := _project_state_anchor("footL")
	var foot_r := _project_state_anchor("footR")
	var center_x := (hip_l.x + hip_r.x) * 0.5
	var half_hip_span := absf(hip_l.x - hip_r.x) * 0.5
	if half_hip_span <= 0.25:
		return

	var min_half_stance := maxf(half_hip_span * CARDINAL_STANCE_MIN_HALF_HIP_RATIO, CARDINAL_STANCE_MIN_PX)
	var max_shift := minf(CARDINAL_STANCE_MAX_SHIFT_PX, half_hip_span * CARDINAL_STANCE_MAX_SHIFT_HIP_RATIO)
	var left_sign := signf(hip_l.x - center_x)
	var right_sign := signf(hip_r.x - center_x)
	if is_zero_approx(left_sign) or is_zero_approx(right_sign) or left_sign == right_sign:
		return

	var left_lateral := (foot_l.x - center_x) * left_sign
	var right_lateral := (foot_r.x - center_x) * right_sign
	var left_shift_mag := clampf(min_half_stance - left_lateral, 0.0, max_shift)
	var right_shift_mag := clampf(min_half_stance - right_lateral, 0.0, max_shift)
	var left_shift := left_shift_mag * left_sign
	var right_shift := right_shift_mag * right_sign
	_shift_cardinal_leg_sprites("L", left_shift)
	_shift_cardinal_leg_sprites("R", right_shift)

	_cardinal_stance_debug = {
		"active": true,
		"animation": current_animation,
		"facing": facing_degrees,
		"view": "north" if is_north else "south",
		"center_x": center_x,
		"hip_span": half_hip_span * 2.0,
		"min_half_stance": min_half_stance,
		"max_shift": max_shift,
		"left_raw_lateral": left_lateral,
		"right_raw_lateral": right_lateral,
		"left_shift": left_shift,
		"right_shift": right_shift,
		"left_corrected_lateral": left_lateral + left_shift_mag,
		"right_corrected_lateral": right_lateral + right_shift_mag,
	}


func _cardinal_walk_corridor_enabled() -> bool:
	# Bone Bridge can host the DEFAULT rig behind a workspace wrapper whose dynamic
	# property lookup does not expose skin_profile_id. The imported V13 animation
	# metadata is the authoritative signal here and keeps non-loop attacks/poses
	# completely untouched.
	if current_animation.begins_with("__bone_bridge_"):
		var bridge_anim_value: Variant = _anims.get(current_animation, {})
		if not bridge_anim_value is Dictionary:
			return false
		var bridge_anim := bridge_anim_value as Dictionary
		var bridge_meta_value: Variant = bridge_anim.get("import_meta", {})
		if not bridge_meta_value is Dictionary:
			return false
		var bridge_meta := bridge_meta_value as Dictionary
		return int(bridge_meta.get("presentation_calibration_version", 0)) >= 13 \
			and bool(bridge_meta.get("runtime_loop_closure_key", false)) \
			and bool(bridge_anim.get("repeat", false))

	# Canonical gameplay walk still requires a playable-skin identity. Runtime
	# summaries are reliable across DEFAULT subclasses whereas Object.get() is not.
	if current_animation != "walk" and current_animation != "juno_walk_retarget":
		return false
	var runtime_summary := get_runtime_summary()
	return not str(runtime_summary.get("skin_profile_id", "")).is_empty()


func _project_state_anchor(node_name: String) -> Vector2:
	if not _states.has(node_name):
		return Vector2.ZERO
	var state_value: Variant = _states[node_name]
	if not state_value is Dictionary:
		return Vector2.ZERO
	return _project_world((state_value as Dictionary).get("g_self", Vector3.ZERO))


func _shift_cardinal_leg_sprites(suffix: String, screen_shift: float) -> void:
	if absf(screen_shift) <= 0.001:
		return
	var leg_name := "leg" + suffix
	var foot_name := "foot" + suffix
	var toe_name := "toe" + suffix
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var node_name := str(record.get("node", ""))
		var weight := 0.0
		if node_name == leg_name:
			weight = CARDINAL_STANCE_LEG_WEIGHT
		elif node_name == foot_name or node_name == toe_name:
			weight = 1.0
		else:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		sprite.position.x += screen_shift * weight
		sprite.set_meta("alabaster_cardinal_stance_shift", screen_shift * weight)
		sprite.set_meta("alabaster_cardinal_stance_side", suffix)


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