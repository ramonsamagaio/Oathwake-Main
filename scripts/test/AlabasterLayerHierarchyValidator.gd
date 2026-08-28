extends SceneTree

const DefaultRig := preload("res://scripts/labs/alabaster/AlabasterDefaultPlayableSkinRig.gd")
const PROBE_NAME := "__layer_guard_probe"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rig := DefaultRig.new()
	rig.call("configure_skin_profile", "default")
	root.add_child(rig)
	for _frame in range(5):
		await process_frame

	if not bool(rig.call("is_skin_ready")):
		_fail("DEFAULT production rig did not initialize.")
		return
	for method_name in ["get_animation_data", "install_runtime_animation", "set_animation", "set_facing_from_vector", "seek_animation_frame", "get_final_layer_guard_debug"]:
		if not rig.has_method(method_name):
			_fail("DEFAULT rig is missing layer regression method %s." % method_name)
			return

	var walk_value: Variant = rig.call("get_animation_data", "walk")
	if not walk_value is Dictionary or (walk_value as Dictionary).is_empty():
		_fail("DEFAULT walk data is unavailable.")
		return
	var walk := (walk_value as Dictionary).duplicate(true)
	# Rename the same pose data to prove the hierarchy rule is not accidentally
	# gated by canonical locomotion names. This reproduces Bone Bridge/custom-bank
	# behavior without involving the editor UI.
	if not bool(rig.call("install_runtime_animation", PROBE_NAME, walk)):
		_fail("Could not install transient layer-guard probe animation.")
		return
	rig.call("set_animation", PROBE_NAME)

	var frame_count := maxi(int(walk.get("frameCnt", 1)), 2)
	var sample_frames := [
		0,
		floori(float(frame_count - 1) * 0.20),
		floori(float(frame_count - 1) * 0.40),
		floori(float(frame_count - 1) * 0.60),
		floori(float(frame_count - 1) * 0.80),
		frame_count - 1,
	]
	var checked := 0
	var shifted_arm_frames := 0
	var shifted_head_frames := 0
	var worst_debug: Dictionary = {}

	for facing_value in [Vector2.RIGHT, Vector2.LEFT]:
		rig.call("set_facing_from_vector", facing_value)
		for frame in sample_frames:
			rig.call("seek_animation_frame", frame)
			var debug_value: Variant = rig.call("get_final_layer_guard_debug")
			if not debug_value is Dictionary:
				_fail("Final layer guard returned no debug at facing=%s frame=%d." % [str(facing_value), frame])
				return
			var debug := debug_value as Dictionary
			if not bool(debug.get("active", false)):
				_fail("Final layer guard was inactive at profile facing=%s frame=%d debug=%s" % [str(facing_value), frame, str(debug)])
				return
			if str(debug.get("front_suffix", "")).is_empty():
				_fail("Final layer guard could not resolve the near arm at facing=%s frame=%d." % [str(facing_value), frame])
				return
			if not bool(debug.get("lower_body_found", false)) or not bool(debug.get("front_arm_found", false)):
				_fail("Final layer guard could not inspect lower body/front arm: %s" % str(debug))
				return
			if int(debug.get("front_arm_min", -4096)) <= int(debug.get("lower_body_max", 4096)):
				_fail("Near arm still paints behind lower body at facing=%s frame=%d debug=%s" % [str(facing_value), frame, str(debug)])
				return
			if bool(debug.get("head_found", false)) and bool(debug.get("all_arms_found", false)) and int(debug.get("head_min", -4096)) <= int(debug.get("all_arms_max", 4096)):
				_fail("Head ceiling still paints behind an arm at facing=%s frame=%d debug=%s" % [str(facing_value), frame, str(debug)])
				return
			checked += 1
			if int(debug.get("front_arm_shift", 0)) != 0:
				shifted_arm_frames += 1
				worst_debug = debug.duplicate(true)
			if int(debug.get("head_shift", 0)) != 0:
				shifted_head_frames += 1

	if checked != sample_frames.size() * 2:
		_fail("Layer guard did not inspect every profile sample: checked=%d." % checked)
		return

	print("ALABASTER_LAYER_HIERARCHY_OK samples=%d arm_repairs=%d head_repairs=%d probe=%s worst=%s" % [
		checked,
		shifted_arm_frames,
		shifted_head_frames,
		PROBE_NAME,
		str(worst_debug),
	])
	rig.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("ALABASTER_LAYER_HIERARCHY_FAILURE: %s" % message)
	quit(1)
