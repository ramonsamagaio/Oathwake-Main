extends SceneTree

const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const WALKING_SOURCE := "res://assets/anims/Walking.fbx"
const LOWER_BONES := ["legL", "footL", "toeL", "legR", "footR", "toeR"]
const DIAG_ANIMATION := "__walk_continuity_diag"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_value: Variant = load(BONE_STUDIO_SCENE)
	if not scene_value is PackedScene:
		_fail("Could not load Bone Studio scene.")
		return
	var studio: Node = (scene_value as PackedScene).instantiate()
	if studio == null:
		_fail("Could not instantiate Bone Studio.")
		return
	root.add_child(studio)
	for _frame in range(8):
		await process_frame

	studio.call("_on_source_selected", WALKING_SOURCE)
	for _frame in range(3):
		await process_frame
	var result_value: Variant = studio.call("_build_import_animation")
	if not result_value is Dictionary or (result_value as Dictionary).is_empty():
		_fail("Walking.fbx produced no retarget result.")
		return
	var result: Dictionary = result_value as Dictionary
	var frame_count: int = int(result.get("frameCnt", 0))
	if frame_count < 4:
		_fail("Walking retarget frame count is invalid.")
		return

	var rig_value: Variant = studio.get("rig")
	if not rig_value is Object:
		_fail("Bone Studio exposed no target rig.")
		return
	var rig: Object = rig_value as Object
	for required_method in ["install_runtime_animation", "set_animation", "seek_animation_frame", "get_all_bone_screen_poses", "get_bone_visual_state"]:
		if not rig.has_method(str(required_method)):
			_fail("Target rig is missing %s." % str(required_method))
			return
	if not bool(rig.call("install_runtime_animation", DIAG_ANIMATION, result)):
		_fail("Could not install diagnostic Walking animation.")
		return
	rig.call("set_animation", DIAG_ANIMATION)
	if rig.has_method("set_editor_animation_paused"):
		rig.call("set_editor_animation_paused", true)
	if rig.has_method("set_facing_from_vector"):
		rig.call("set_facing_from_vector", Vector2.DOWN)

	var runtime_events: Array[Dictionary] = _measure_runtime_motion(rig, frame_count)
	var key_events: Array[Dictionary] = _measure_key_rotation_steps(result, frame_count)
	var key_window: Array[Dictionary] = _rotation_window(result, 36, 52)
	var snap_window: Array[Dictionary] = _measure_raw_vs_snapped_window(rig, 39.0, 44.0, 0.25)

	print("ALABASTER_WALK_RUNTIME_JERK_TOP %s" % str(runtime_events.slice(0, mini(runtime_events.size(), 12))))
	print("ALABASTER_WALK_KEY_ROTATION_TOP %s" % str(key_events.slice(0, mini(key_events.size(), 12))))
	print("ALABASTER_WALK_KEY_WINDOW_36_52 %s" % str(key_window))
	print("ALABASTER_WALK_RAW_VS_SNAPPED_39_44 %s" % str(snap_window))
	print("ALABASTER_WALK_CONTINUITY_DIAGNOSTIC_OK frames=%d" % frame_count)
	studio.queue_free()
	await process_frame
	quit(0)


func _measure_runtime_motion(rig: Object, frame_count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var previous_positions: Dictionary = {}
	var previous_steps: Dictionary = {}
	for frame in range(frame_count):
		rig.call("seek_animation_frame", float(frame))
		var poses_value: Variant = rig.call("get_all_bone_screen_poses")
		if not poses_value is Dictionary:
			continue
		var poses: Dictionary = poses_value as Dictionary
		for bone_name in LOWER_BONES:
			if not poses.has(bone_name):
				continue
			var pose_value: Variant = poses[bone_name]
			if not pose_value is Dictionary:
				continue
			var position_value: Variant = (pose_value as Dictionary).get("world_position", Vector3.ZERO)
			if not position_value is Vector3:
				continue
			var position: Vector3 = position_value as Vector3
			if previous_positions.has(bone_name):
				var previous_position: Vector3 = previous_positions[bone_name]
				var step: Vector3 = position - previous_position
				var acceleration: float = 0.0
				if previous_steps.has(bone_name):
					var previous_step: Vector3 = previous_steps[bone_name]
					acceleration = (step - previous_step).length()
				events.append({
					"frame": frame,
					"bone": bone_name,
					"step": step.length(),
					"accel": acceleration,
					"pos": position,
				})
				previous_steps[bone_name] = step
			previous_positions[bone_name] = position
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("accel", 0.0)) > float(b.get("accel", 0.0))
	)
	return events


func _measure_raw_vs_snapped_window(rig: Object, start_frame: float, end_frame: float, step_size: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var raw_prev: Dictionary = {}
	var raw_step_prev: Dictionary = {}
	var snapped_prev: Dictionary = {}
	var snapped_step_prev: Dictionary = {}
	var sample: float = start_frame
	while sample <= end_frame + 0.0001:
		rig.call("seek_animation_frame", sample)
		for bone_name in ["footR", "toeR", "footL", "toeL"]:
			var state_value: Variant = rig.call("get_bone_visual_state", bone_name)
			if not state_value is Dictionary:
				continue
			var state: Dictionary = state_value as Dictionary
			var raw_value: Variant = state.get("root_pos", Vector3.ZERO)
			var snapped_value: Variant = state.get("g_self", Vector3.ZERO)
			if not raw_value is Vector3 or not snapped_value is Vector3:
				continue
			var raw: Vector3 = raw_value as Vector3
			var snapped: Vector3 = snapped_value as Vector3
			var raw_step := Vector3.ZERO
			var raw_accel := 0.0
			var snapped_step := Vector3.ZERO
			var snapped_accel := 0.0
			if raw_prev.has(bone_name):
				raw_step = raw - (raw_prev[bone_name] as Vector3)
				if raw_step_prev.has(bone_name):
					raw_accel = (raw_step - (raw_step_prev[bone_name] as Vector3)).length()
				raw_step_prev[bone_name] = raw_step
			if snapped_prev.has(bone_name):
				snapped_step = snapped - (snapped_prev[bone_name] as Vector3)
				if snapped_step_prev.has(bone_name):
					snapped_accel = (snapped_step - (snapped_step_prev[bone_name] as Vector3)).length()
				snapped_step_prev[bone_name] = snapped_step
			rows.append({
				"frame": snappedf(sample, 0.001),
				"bone": bone_name,
				"raw": raw,
				"raw_step": raw_step.length(),
				"raw_accel": raw_accel,
				"snap": snapped,
				"snap_step": snapped_step.length(),
				"snap_accel": snapped_accel,
			})
			raw_prev[bone_name] = raw
			snapped_prev[bone_name] = snapped
		sample += step_size
	return rows


func _measure_key_rotation_steps(result: Dictionary, frame_count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var previous_quats: Dictionary = {}
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array:
		return events
	for frame_value in transforms_value as Array:
		if not frame_value is Dictionary:
			continue
		var frame_dict: Dictionary = frame_value as Dictionary
		var frame: int = int(frame_dict.get("frame", -1))
		if frame < 0 or frame >= frame_count:
			continue
		var nodes_value: Variant = frame_dict.get("nodeXfm", {})
		if not nodes_value is Dictionary:
			continue
		var nodes: Dictionary = nodes_value as Dictionary
		for bone_name in LOWER_BONES:
			if not nodes.has(bone_name):
				continue
			var xfm_value: Variant = nodes[bone_name]
			if not xfm_value is Dictionary:
				continue
			var rot_value: Variant = (xfm_value as Dictionary).get("rot", [0.0, 0.0, 0.0])
			var angles: Vector3 = _rot_array_to_vec3(rot_value)
			var q: Quaternion = _source_quat(angles)
			if previous_quats.has(bone_name):
				var previous_q: Quaternion = previous_quats[bone_name]
				var dot_value: float = clampf(absf(previous_q.dot(q)), 0.0, 1.0)
				var angular_step: float = rad_to_deg(2.0 * acos(dot_value))
				events.append({
					"frame": frame,
					"bone": bone_name,
					"q_step_deg": angular_step,
					"rot": angles,
				})
			previous_quats[bone_name] = q
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("q_step_deg", 0.0)) > float(b.get("q_step_deg", 0.0))
	)
	return events


func _rotation_window(result: Dictionary, start_frame: int, end_frame: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array:
		return rows
	for frame_value in transforms_value as Array:
		if not frame_value is Dictionary:
			continue
		var frame_dict: Dictionary = frame_value as Dictionary
		var frame: int = int(frame_dict.get("frame", -1))
		if frame < start_frame or frame > end_frame:
			continue
		var nodes_value: Variant = frame_dict.get("nodeXfm", {})
		if not nodes_value is Dictionary:
			continue
		var nodes: Dictionary = nodes_value as Dictionary
		var row: Dictionary = {"frame": frame}
		for bone_name in LOWER_BONES:
			if not nodes.has(bone_name):
				continue
			var xfm_value: Variant = nodes[bone_name]
			if xfm_value is Dictionary:
				row[bone_name] = _rot_array_to_vec3((xfm_value as Dictionary).get("rot", [0.0, 0.0, 0.0]))
		rows.append(row)
	return rows


func _rot_array_to_vec3(value: Variant) -> Vector3:
	if not value is Array:
		return Vector3.ZERO
	var array_value: Array = value as Array
	return Vector3(
		float(array_value[0]) if array_value.size() > 0 else 0.0,
		float(array_value[1]) if array_value.size() > 1 else 0.0,
		float(array_value[2]) if array_value.size() > 2 else 0.0
	)


func _source_quat(angles: Vector3) -> Quaternion:
	# Exact inverse consumer used by AlabasterRigRuntimeSource._source_quat:
	# Alabaster rot = [yaw, pitch, roll], glMatrix receives [pitch, roll, yaw].
	var x: float = deg_to_rad(angles.y) * 0.5
	var y: float = deg_to_rad(angles.z) * 0.5
	var z: float = deg_to_rad(angles.x) * 0.5
	var sx: float = sin(x)
	var cx: float = cos(x)
	var sy: float = sin(y)
	var cy: float = cos(y)
	var sz: float = sin(z)
	var cz: float = cos(z)
	return Quaternion(
		sx * cy * cz - cx * sy * sz,
		cx * sy * cz + sx * cy * sz,
		cx * cy * sz - sx * sy * cz,
		cx * cy * cz + sx * sy * sz
	).normalized()


func _fail(message: String) -> void:
	printerr("ALABASTER_WALK_CONTINUITY_DIAGNOSTIC_FAILURE: %s" % message)
	quit(1)
