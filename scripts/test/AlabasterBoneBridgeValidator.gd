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

	# Regression from the recorded walk: V9 could preserve the skeleton while
	# still choosing the wrong forward hemisphere and leaving ankle twist free.
	# V10 must derive both from REST geometry before sampling the clip.
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
	if not str(meta.get("retarget_profile", "")).contains("V10"):
		_fail("Walking retarget did not report the V10 REST-calibrated profile.")
		return
	if int(meta.get("rest_calibration_version", 0)) != 10:
		_fail("Walking retarget did not persist V10 REST calibration metadata.")
		return

	# The committed Mixamo Walking.fbx and Juno use opposite semantic handedness.
	# A positive bridge determinant recreates the exact moonwalk from the video.
	var bridge_determinant := float(meta.get("source_to_target_determinant", 1.0))
	if bridge_determinant >= -0.5:
		_fail("Walking forward calibration lost the required handedness reflection (det=%.3f)." % bridge_determinant)
		return

	# Feet and terminal toes must use the two-vector plane solve. A one-vector
	# shortest swing leaves axial twist undefined and can point the foot backward.
	var plane_counts_value: Variant = meta.get("plane_solved_counts", {})
	if not plane_counts_value is Dictionary:
		_fail("Walking retarget did not report limb-plane calibration coverage.")
		return
	var plane_counts := plane_counts_value as Dictionary
	for foot_target in ["footL", "toeL", "footR", "toeR"]:
		if int(plane_counts.get(foot_target, 0)) <= 0:
			_fail("Walking V10 did not resolve %s with a two-vector REST plane." % foot_target)
			return

	var valid_targets := {}
	var bone_names_value: Variant = rig.call("get_bone_names")
	if bone_names_value is Array:
		for bone_value in bone_names_value:
			valid_targets[str(bone_value)] = true
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array or (transforms_value as Array).is_empty():
		_fail("Walking V10 retarget contains no transform frames.")
		return
	for frame_value in transforms_value as Array:
		if not frame_value is Dictionary:
			continue
		var node_xfm_value: Variant = (frame_value as Dictionary).get("nodeXfm", {})
		if not node_xfm_value is Dictionary:
			continue
		for target_value in (node_xfm_value as Dictionary).keys():
			var target := str(target_value)
			if target.begins_with("@fold:"):
				_fail("Walking V10 leaked pseudo target into runtime nodeXfm: %s" % target)
				return
			if not valid_targets.has(target):
				_fail("Walking V10 emitted unknown Juno target: %s" % target)
				return

	print("ALABASTER_BONE_BRIDGE_VALIDATION_OK tabs=%d walking_frames=%d juno_bones=%d punching_segments=%d bridge_det=%.3f foot_plane=%d/%d" % [
		tabs.get_child_count(),
		(transforms_value as Array).size(),
		valid_targets.size(),
		drawable_segments,
		bridge_determinant,
		int(plane_counts.get("footL", 0)),
		int(plane_counts.get("footR", 0)),
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
