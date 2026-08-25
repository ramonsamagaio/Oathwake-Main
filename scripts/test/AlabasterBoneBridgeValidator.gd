extends SceneTree

const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const WALKING_SOURCE := "res://assets/anims/Walking.fbx"
const PUNCHING_SOURCE := "res://assets/anims/Punching.fbx"
const MIXAMO_V10 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV10.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) != 1920:
		_fail("Bone Studio project viewport width is not 1920.")
		return
	if int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) != 1080:
		_fail("Bone Studio project viewport height is not 1080.")
		return

	var calibration_test := MIXAMO_V10.run_self_test()
	if not bool(calibration_test.get("ok", false)):
		_fail("V10 REST calibration self-test failed: %s" % str(calibration_test.get("failures", [])))
		return

	var scene_value: Variant = load(BONE_STUDIO_SCENE)
	if not scene_value is PackedScene:
		_fail("Could not load Bone Studio scene: %s" % BONE_STUDIO_SCENE)
		return
	var studio := (scene_value as PackedScene).instantiate()
	if studio == null:
		_fail("Could not instantiate Bone Studio.")
		return
	root.add_child(studio)

	# Bone Studio composes Live Tuning, Retarget Debug, Bone Bridge and the Juno
	# inspector through deferred initialization. Give those controllers time to
	# attach before validating the complete workspace.
	for _frame in range(8):
		await process_frame

	var tabs := _find_tabs(studio)
	if tabs == null:
		_fail("Bone Studio did not create its TabContainer.")
		return
	var bridge: Node = null
	for child_value in tabs.get_children():
		var child := child_value as Node
		if child != null and str(child.name) == "BONE BRIDGE":
			bridge = child
			break
	if bridge == null:
		_fail("BONE BRIDGE tab was not installed.")
		return

	var source_preview_value: Variant = bridge.get("source_preview")
	if not source_preview_value is Control:
		_fail("BONE BRIDGE source skeleton preview was not created.")
		return
	var source_preview := source_preview_value as Control
	if source_preview.focus_mode != Control.FOCUS_ALL:
		_fail("Source skeleton viewport is not focusable for orbit/pan input.")
		return
	for source_method in ["load_source", "get_drawable_segment_count", "get_bone_names"]:
		if not source_preview.has_method(str(source_method)):
			_fail("Source preview is missing regression method: %s" % str(source_method))
			return

	# Exact regression from the user's blank Bone Bridge capture: Punching.fbx
	# successfully populated 28 mappings while the source viewport itself drew
	# nothing. Loading it here must now produce real parent-child geometry, not
	# merely a non-null Skeleton3D object.
	if not FileAccess.file_exists(PUNCHING_SOURCE):
		_fail("Punching regression source is missing: %s" % PUNCHING_SOURCE)
		return
	var punching_preview_value: Variant = source_preview.call("load_source", PUNCHING_SOURCE, "mixamo_com")
	if not punching_preview_value is Dictionary or not bool((punching_preview_value as Dictionary).get("ok", false)):
		_fail("Punching.fbx could not be opened by the live source skeleton preview.")
		return
	for _frame in range(2):
		await process_frame
	var drawable_segments := int(source_preview.call("get_drawable_segment_count"))
	if drawable_segments < 12:
		_fail("Punching source preview collapsed to %d drawable segments; the viewport would appear blank." % drawable_segments)
		return
	var source_names_value: Variant = source_preview.call("get_bone_names")
	if not source_names_value is Array or (source_names_value as Array).size() < 20:
		_fail("Punching source preview did not expose a complete Mixamo skeleton.")
		return

	var juno_list := _find_named(studio, "JunoBoneList") as ItemList
	if juno_list == null:
		_fail("Juno target bone inspector was not installed beside the preview.")
		return

	# The Juno side of the same screenshot was blank after stretch was disabled to
	# silence a resize warning. The render texture must remain container-owned.
	var juno_holder := _find_subviewport_container(studio)
	if juno_holder == null:
		_fail("Live Juno preview has no SubViewportContainer.")
		return
	if not juno_holder.stretch:
		_fail("Live Juno preview stretch is disabled; this can produce a blank embedded Game View.")
		return
	var preview_world_value: Variant = studio.get("preview_world")
	if not preview_world_value is Node2D:
		_fail("Live Juno preview world is missing.")
		return
	var preview_world := preview_world_value as Node2D

	var rig_value: Variant = studio.get("rig")
	if not rig_value is Object:
		_fail("Bone Studio did not expose a live Juno target rig.")
		return
	var rig := rig_value as Object
	if rig is Node and (rig as Node).get_parent() != preview_world:
		_fail("Live Juno rig is detached from the preview world.")
		return
	for required_method in ["install_runtime_animation", "set_animation", "seek_animation_frame", "get_bone_names", "get_bone_parent_map", "get_bone_rest_local_positions"]:
		if not rig.has_method(str(required_method)):
			_fail("Juno target rig is missing required method: %s" % str(required_method))
			return
	var rest_value: Variant = rig.call("get_bone_rest_local_positions")
	if not rest_value is Dictionary or (rest_value as Dictionary).is_empty():
		_fail("Juno target rig did not expose authored rest vectors.")
		return

	# The polished Show bones switch must hide the ONE interactive overlay instead
	# of leaving a second skeleton visible. Keep the Control alive so orbit/pan
	# input still works while bones are hidden.
	var overlay_value: Variant = studio.get("_juno_overlay")
	if not overlay_value is Control:
		_fail("Juno interactive bone overlay was not attached.")
		return
	var overlay := overlay_value as Control
	studio.call("_on_bones_toggled", false)
	await process_frame
	if overlay.modulate.a > 0.01 or not overlay.visible:
		_fail("Show bones OFF did not hide the interactive overlay while keeping its input surface alive.")
		return
	studio.call("_on_bones_toggled", true)
	await process_frame
	if overlay.modulate.a < 0.99:
		_fail("Show bones ON did not restore the interactive overlay.")
		return

	# Regression from the recorded walk: V10 owns source/target forward and foot
	# plane calibration, V11 stabilizes the arms, V12 added the first Juno 2D
	# presentation pass, and V13 fixes the profile read + loop-foot seam without
	# reopening any of those solved structural layers.
	if not FileAccess.file_exists(WALKING_SOURCE):
		_fail("Walking regression source is missing: %s" % WALKING_SOURCE)
		return
	studio.call("_on_source_selected", WALKING_SOURCE)
	for _frame in range(3):
		await process_frame
	var clip_option := studio.get("source_clip_option") as OptionButton
	if clip_option == null or clip_option.item_count <= 0:
		_fail("Walking.fbx exposed no animation clip in Bone Studio.")
		return
	var result_value: Variant = studio.call("_build_import_animation")
	if not result_value is Dictionary or (result_value as Dictionary).is_empty():
		_fail("Walking.fbx did not produce a retargeted Juno animation.")
		return
	var result := result_value as Dictionary
	var meta_value: Variant = result.get("import_meta", {})
	if not meta_value is Dictionary:
		_fail("Walking retarget has no import metadata.")
		return
	var meta := meta_value as Dictionary
	if str(meta.get("limb_transfer_mode", "")) != "target_rest_swing":
		_fail("Walking retarget did not use the target-rest production solver.")
		return
	if not str(meta.get("retarget_profile", "")).contains("V13"):
		_fail("Walking retarget did not report the V13 profile/loop polish.")
		return
	if int(meta.get("rest_calibration_version", 0)) != 10:
		_fail("Walking retarget lost the V10 REST calibration metadata.")
		return
	if int(meta.get("presentation_calibration_version", 0)) != 13:
		_fail("Walking retarget did not persist V13 presentation metadata.")
		return
	if not bool(meta.get("v12_non_presentation_bones_preserved", false)):
		_fail("V13 did not certify preservation of V12 non-presentation bones.")
		return

	var patch_targets_value: Variant = meta.get("presentation_patch_targets", [])
	if not patch_targets_value is Array:
		_fail("V13 did not report its presentation patch targets.")
		return
	var patch_targets := patch_targets_value as Array
	for required_patch_target in ["top", "footL", "toeL", "footR", "toeR"]:
		if not patch_targets.has(required_patch_target):
			_fail("V13 presentation target list is missing %s." % required_patch_target)
			return

	var torso_bias := float(meta.get("torso_back_bias_degrees", 99.0))
	if torso_bias < 4.5 or torso_bias > 5.5:
		_fail("V13 torso profile correction is outside the intended ~5 degree window: %.2f." % torso_bias)
		return
	var foot_pitch_keep := float(meta.get("foot_pitch_keep", -1.0))
	if foot_pitch_keep < 0.70 or foot_pitch_keep > 0.85:
		_fail("V13 foot pitch relaxation is outside the gentle range: %.3f." % foot_pitch_keep)
		return
	var toe_pitch_keep := float(meta.get("toe_pitch_keep", -1.0))
	if toe_pitch_keep < 0.45 or toe_pitch_keep > 0.65:
		_fail("V13 total toe pitch relaxation is outside the intended profile range: %.3f." % toe_pitch_keep)
		return
	if str(meta.get("lower_foot_smoothing", "")) != "circular_1_2_1":
		_fail("V13 did not report the lower-foot 1-2-1 smoothing pass.")
		return
	if not bool(meta.get("runtime_loop_closure_key", false)):
		_fail("V13 did not append the exclusive runtime loop closure key.")
		return

	# The committed Mixamo Walking.fbx and Juno use opposite semantic handedness.
	# A positive bridge determinant recreates the exact moonwalk from the video.
	var bridge_determinant := float(meta.get("source_to_target_determinant", 1.0))
	if bridge_determinant >= -0.5:
		_fail("Walking forward calibration lost the required handedness reflection (det=%.3f)." % bridge_determinant)
		return

	# Feet and terminal toes must still originate from V10's two-vector plane
	# solve. V13 only relaxes their visible pitch/roll after this correct solve.
	var plane_counts_value: Variant = meta.get("plane_solved_counts", {})
	if not plane_counts_value is Dictionary:
		_fail("Walking retarget did not report limb-plane calibration coverage.")
		return
	var plane_counts := plane_counts_value as Dictionary
	for foot_target in ["footL", "toeL", "footR", "toeR"]:
		if int(plane_counts.get(foot_target, 0)) <= 0:
			_fail("Walking base solver did not resolve %s with a two-vector REST plane." % foot_target)
			return

	var valid_targets := {}
	var bone_names_value: Variant = rig.call("get_bone_names")
	if bone_names_value is Array:
		for bone_value in bone_names_value:
			valid_targets[str(bone_value)] = true
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array or (transforms_value as Array).is_empty():
		_fail("Walking V13 retarget contains no transform frames.")
		return
	var transforms := transforms_value as Array
	var frame_count := int(result.get("frameCnt", 0))
	var has_exclusive_closure := false
	for frame_value in transforms:
		if not frame_value is Dictionary:
			continue
		var frame_dict := frame_value as Dictionary
		if int(frame_dict.get("frame", -1)) == frame_count and bool(frame_dict.get("v13_exclusive_loop_closure", false)):
			has_exclusive_closure = true
		var node_xfm_value: Variant = frame_dict.get("nodeXfm", {})
		if not node_xfm_value is Dictionary:
			continue
		for target_value in (node_xfm_value as Dictionary).keys():
			var target := str(target_value)
			if target.begins_with("@fold:"):
				_fail("Walking V13 leaked pseudo target into runtime nodeXfm: %s" % target)
				return
			if not valid_targets.has(target):
				_fail("Walking V13 emitted unknown Juno target: %s" % target)
				return
	if not has_exclusive_closure:
		_fail("Walking V13 metadata claimed loop closure but no frameCnt closure key exists.")
		return
	if transforms.size() != frame_count + 1:
		_fail("Walking V13 should expose visible frames plus one exclusive closure: keys=%d frameCnt=%d." % [transforms.size(), frame_count])
		return

	# Exact regression for the user's remaining layer problem. Bone Bridge names
	# its transient animation `__bone_bridge_preview`, which used to bypass the
	# DEFAULT locomotion arm/pelvis policies. Force an E/W profile and prove that
	# the near arm finishes above the whole lower-body silhouette while the head
	# remains above the raised arm.
	if not bool(rig.call("install_runtime_animation", "__bone_bridge_preview", result)):
		_fail("Could not install V13 Walking result for layer-depth regression.")
		return
	rig.call("set_animation", "__bone_bridge_preview")
	if rig.has_method("set_facing_from_vector"):
		rig.call("set_facing_from_vector", Vector2.RIGHT)
	rig.call("seek_animation_frame", floori(float(frame_count) * 0.42))
	var depth_controller_value: Variant = studio.call("_ensure_bone_bridge_depth_polish")
	if not depth_controller_value is Object:
		_fail("Bone Bridge depth polish controller was not attached to the live target.")
		return
	var depth_controller := depth_controller_value as Object
	depth_controller.call("apply_now")
	var depth_debug_value: Variant = depth_controller.call("get_last_debug")
	if not depth_debug_value is Dictionary:
		_fail("Bone Bridge depth polish exposed no regression diagnostics.")
		return
	var depth_debug := depth_debug_value as Dictionary
	if str(depth_debug.get("front_suffix", "")).is_empty():
		_fail("Bone Bridge profile depth could not resolve the near arm.")
		return
	if not bool(depth_debug.get("lower_body_found", false)) or not bool(depth_debug.get("front_arm_found", false)):
		_fail("Bone Bridge profile depth did not expose visible lower-body/front-arm layers.")
		return
	if int(depth_debug.get("front_arm_min", -4096)) <= int(depth_debug.get("lower_body_max", 4096)):
		_fail("Bone Bridge near arm is still not above the lower body: %s" % str(depth_debug))
		return
	if bool(depth_debug.get("head_found", false)) and int(depth_debug.get("head_min", -4096)) <= int(depth_debug.get("front_arm_max", 4096)):
		_fail("Bone Bridge head ceiling was lost after raising the near arm: %s" % str(depth_debug))
		return

	print("ALABASTER_BONE_BRIDGE_VALIDATION_OK tabs=%d walking_keys=%d frameCnt=%d juno_bones=%d punching_segments=%d bridge_det=%.3f foot_plane=%d/%d torso_bias=%.2f foot_keep=%.2f toe_keep=%.2f depth=%s" % [
		tabs.get_child_count(),
		transforms.size(),
		frame_count,
		valid_targets.size(),
		drawable_segments,
		bridge_determinant,
		int(plane_counts.get("footL", 0)),
		int(plane_counts.get("footR", 0)),
		torso_bias,
		foot_pitch_keep,
		toe_pitch_keep,
		str(depth_debug),
	])
	studio.queue_free()
	await process_frame
	quit(0)


func _find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node as TabContainer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_tabs(child)
		if found != null:
			return found
	return null


func _find_named(node: Node, target_name: String) -> Node:
	if str(node.name) == target_name:
		return node
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_named(child, target_name)
		if found != null:
			return found
	return null


func _find_subviewport_container(node: Node) -> SubViewportContainer:
	if node is SubViewportContainer:
		return node as SubViewportContainer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_subviewport_container(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	printerr("ALABASTER_BONE_BRIDGE_VALIDATION_FAILURE: %s" % message)
	quit(1)
