extends SceneTree

const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const WALKING_SOURCE := "res://assets/anims/Walking.fbx"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) != 1920:
		_fail("Bone Studio project viewport width is not 1920.")
		return
	if int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) != 1080:
		_fail("Bone Studio project viewport height is not 1080.")
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

	var juno_list := _find_named(studio, "JunoBoneList") as ItemList
	if juno_list == null:
		_fail("Juno target bone inspector was not installed beside the preview.")
		return

	var rig_value: Variant = studio.get("rig")
	if not rig_value is Object:
		_fail("Bone Studio did not expose a live Juno target rig.")
		return
	var rig := rig_value as Object
	for required_method in ["install_runtime_animation", "set_animation", "seek_animation_frame", "get_bone_names", "get_bone_parent_map", "get_bone_rest_local_positions"]:
		if not rig.has_method(str(required_method)):
			_fail("Juno target rig is missing required method: %s" % str(required_method))
			return
	var rest_value: Variant = rig.call("get_bone_rest_local_positions")
	if not rest_value is Dictionary or (rest_value as Dictionary).is_empty():
		_fail("Juno target rig did not expose authored rest vectors.")
		return

	# Regression case from the real Bone Bridge capture: load the exact Mixamo
	# Walking.fbx committed to the repository and exercise the production V9 path.
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
		_fail("Walking retarget did not use the V9 target-rest limb solver.")
		return
	if not str(meta.get("retarget_profile", "")).contains("V9"):
		_fail("Walking retarget did not report the V9 target profile.")
		return

	var valid_targets := {}
	var bone_names_value: Variant = rig.call("get_bone_names")
	if bone_names_value is Array:
		for bone_value in bone_names_value:
			valid_targets[str(bone_value)] = true
	var transforms_value: Variant = result.get("transforms", [])
	if not transforms_value is Array or (transforms_value as Array).is_empty():
		_fail("Walking V9 retarget contains no transform frames.")
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
				_fail("Walking V9 leaked pseudo target into runtime nodeXfm: %s" % target)
				return
			if not valid_targets.has(target):
				_fail("Walking V9 emitted unknown Juno target: %s" % target)
				return

	print("ALABASTER_BONE_BRIDGE_VALIDATION_OK tabs=%d walking_frames=%d juno_bones=%d" % [
		tabs.get_child_count(),
		(transforms_value as Array).size(),
		valid_targets.size(),
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


func _fail(message: String) -> void:
	printerr("ALABASTER_BONE_BRIDGE_VALIDATION_FAILURE: %s" % message)
	quit(1)
