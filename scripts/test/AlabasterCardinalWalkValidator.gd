extends SceneTree

const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const WALKING_SOURCE := "res://assets/anims/Walking.fbx"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_value: Variant = load(BONE_STUDIO_SCENE)
	if not scene_value is PackedScene:
		_fail("Could not load Bone Studio scene.")
		return
	var studio := (scene_value as PackedScene).instantiate()
	if studio == null:
		_fail("Could not instantiate Bone Studio.")
		return
	root.add_child(studio)
	for _frame in range(8):
		await process_frame

	if not FileAccess.file_exists(WALKING_SOURCE):
		_fail("Walking regression source is missing: %s" % WALKING_SOURCE)
		return
	studio.call("_on_source_selected", WALKING_SOURCE)
	for _frame in range(3):
		await process_frame
	var result_value: Variant = studio.call("_build_import_animation")
	if not result_value is Dictionary or (result_value as Dictionary).is_empty():
		_fail("Walking.fbx did not produce a retargeted animation.")
		return
	var result := result_value as Dictionary
	var frame_count := int(result.get("frameCnt", 0))
	if frame_count <= 1:
		_fail("Walking.fbx produced an invalid frame count: %d" % frame_count)
		return

	var rig_value: Variant = studio.get("rig")
	if not rig_value is Object:
		_fail("Bone Studio did not expose the playable target rig.")
		return
	var rig := rig_value as Object
	for required_method in [
		"install_runtime_animation",
		"set_animation",
		"set_facing_from_vector",
		"seek_animation_frame",
		"get_cardinal_stance_debug",
		"get_bone_corridor_debug",
		"get_bone_visual_state",
	]:
		if not rig.has_method(str(required_method)):
			_fail("Target rig is missing cardinal-walk regression method: %s" % str(required_method))
			return

	var preview_name := "__bone_bridge_cardinal_preview"
	if not bool(rig.call("install_runtime_animation", preview_name, result)):
		_fail("Could not install Walking result for cardinal stance regression.")
		return
	rig.call("set_animation", preview_name)

	# The recorded defect is visible in exact SOUTH/front view. The old guard moved
	# only Sprite2D pieces, so the bone overlay still crossed the sagittal centerline
	# and kicked back outward. Sweep the real Walking.fbx and require the correction
	# to live on foot/leg BONE states before Production's sprite-only fallback runs.
	rig.call("set_facing_from_vector", Vector2.DOWN)
	var active_frames := 0
	var corrected_frames := 0
	var max_applied_shift := 0.0
	var max_raw_intrusion := 0.0
	var max_residual_sprite_shift := 0.0
	var worst_debug: Dictionary = {}
	var first_inactive_debug: Dictionary = {}
	for frame in range(frame_count):
		rig.call("seek_animation_frame", frame)
		var debug_value: Variant = rig.call("get_bone_corridor_debug")
		if not debug_value is Dictionary:
			_fail("Bone-state cardinal corridor debug disappeared at frame %d." % frame)
			return
		var debug := debug_value as Dictionary
		if not bool(debug.get("active", false)):
			if first_inactive_debug.is_empty():
				first_inactive_debug = debug.duplicate(true)
			continue
		active_frames += 1
		if str(debug.get("correction_space", "")) != "bone_state":
			_fail("Cardinal correction fell back to sprite space at frame %d: %s" % [frame, str(debug)])
			return

		var min_half_stance := float(debug.get("min_half_stance", 0.0))
		var left_raw := float(debug.get("left_raw_lateral", 0.0))
		var right_raw := float(debug.get("right_raw_lateral", 0.0))
		var left_corrected := float(debug.get("left_corrected_lateral", left_raw))
		var right_corrected := float(debug.get("right_corrected_lateral", right_raw))
		var left_shift := absf(float(debug.get("left_shift", 0.0)))
		var right_shift := absf(float(debug.get("right_shift", 0.0)))
		var frame_shift := maxf(left_shift, right_shift)
		max_applied_shift = maxf(max_applied_shift, frame_shift)
		max_raw_intrusion = maxf(max_raw_intrusion, maxf(min_half_stance - left_raw, min_half_stance - right_raw))
		if frame_shift > 0.05:
			corrected_frames += 1
			if worst_debug.is_empty() or frame_shift > maxf(absf(float(worst_debug.get("left_shift", 0.0))), absf(float(worst_debug.get("right_shift", 0.0)))):
				worst_debug = debug.duplicate(true)

		if left_corrected + 0.03 < left_raw or right_corrected + 0.03 < right_raw:
			_fail("Bone-state stance correction moved a foot farther inward at frame %d: %s" % [frame, str(debug)])
			return
		if left_raw + 0.03 < min_half_stance and left_corrected + 0.08 < min_half_stance:
			_fail("Left foot bone remained inside the sagittal corridor at frame %d: %s" % [frame, str(debug)])
			return
		if right_raw + 0.03 < min_half_stance and right_corrected + 0.08 < min_half_stance:
			_fail("Right foot bone remained inside the sagittal corridor at frame %d: %s" % [frame, str(debug)])
			return
		if left_shift > float(debug.get("max_shift", 0.0)) + 0.05 or right_shift > float(debug.get("max_shift", 0.0)) + 0.05:
			_fail("Bone-state stance correction exceeded its safety cap at frame %d: %s" % [frame, str(debug)])
			return

		# Prove the shift is carried by the actual state returned to the overlay and
		# attachments, rather than a second hidden Sprite2D nudge.
		if left_shift > 0.05:
			var left_state_value: Variant = rig.call("get_bone_visual_state", "footL")
			if not left_state_value is Dictionary or absf(float((left_state_value as Dictionary).get("alabaster_bone_corridor_shift_px", 0.0))) <= 0.05:
				_fail("Left foot correction did not reach the live bone state at frame %d." % frame)
				return
		if right_shift > 0.05:
			var right_state_value: Variant = rig.call("get_bone_visual_state", "footR")
			if not right_state_value is Dictionary or absf(float((right_state_value as Dictionary).get("alabaster_bone_corridor_shift_px", 0.0))) <= 0.05:
				_fail("Right foot correction did not reach the live bone state at frame %d." % frame)
				return

		# Production still contains the former sprite-only corridor as a safety net.
		# Once bones are corrected it should have virtually nothing left to do.
		var presentation_debug_value: Variant = rig.call("get_cardinal_stance_debug")
		if presentation_debug_value is Dictionary:
			var presentation_debug := presentation_debug_value as Dictionary
			max_residual_sprite_shift = maxf(
				max_residual_sprite_shift,
				maxf(absf(float(presentation_debug.get("left_shift", 0.0))), absf(float(presentation_debug.get("right_shift", 0.0))))
			)

	if active_frames < frame_count - 1:
		var pose_debug := {
			"hipL": rig.call("get_bone_visual_state", "hipL"),
			"hipR": rig.call("get_bone_visual_state", "hipR"),
			"footL": rig.call("get_bone_visual_state", "footL"),
			"footR": rig.call("get_bone_visual_state", "footR"),
			"profile": rig.get("skin_profile_id"),
			"current_animation": rig.get("current_animation"),
		}
		_fail("Bone-state cardinal corridor was not active through the SOUTH walk cycle: active=%d/%d first=%s poses=%s." % [active_frames, frame_count, str(first_inactive_debug), str(pose_debug)])
		return
	if corrected_frames <= 0:
		_fail("SOUTH Walking never triggered the bone-state centerline guard; the recorded foot-crossing regression is not covered.")
		return
	if max_applied_shift > 8.01:
		_fail("Bone-state cardinal correction became too large: %.3f px." % max_applied_shift)
		return
	if max_residual_sprite_shift > 0.10:
		_fail("Sprite-only fallback still had meaningful work after bone correction: %.3f px." % max_residual_sprite_shift)
		return

	# This remains a cardinal-view articulation rule. Profile must stay untouched,
	# otherwise fixing front view could regress the now-good E/W silhouette.
	rig.call("set_facing_from_vector", Vector2.RIGHT)
	rig.call("seek_animation_frame", floori(float(frame_count) * 0.42))
	var profile_debug_value: Variant = rig.call("get_bone_corridor_debug")
	if profile_debug_value is Dictionary and bool((profile_debug_value as Dictionary).get("active", false)):
		_fail("Bone-state cardinal corridor leaked into E/W profile: %s" % str(profile_debug_value))
		return

	print("ALABASTER_CARDINAL_WALK_VALIDATION_OK frames=%d active=%d corrected=%d raw_intrusion=%.3f bone_shift=%.3f residual_sprite=%.3f worst=%s" % [
		frame_count,
		active_frames,
		corrected_frames,
		max_raw_intrusion,
		max_applied_shift,
		max_residual_sprite_shift,
		str(worst_debug),
	])
	studio.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("ALABASTER_CARDINAL_WALK_VALIDATION_FAILURE: %s" % message)
	quit(1)
