extends SceneTree

const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_value: Variant = load(BONE_STUDIO_SCENE)
	if not scene_value is PackedScene:
		_fail("Could not load Bone Studio scene: %s" % BONE_STUDIO_SCENE)
		return
	var studio := (scene_value as PackedScene).instantiate()
	if studio == null:
		_fail("Could not instantiate Bone Studio.")
		return
	root.add_child(studio)

	# Bone Studio composes Live Tuning, Retarget Debug and Bone Bridge through
	# deferred initialization. Give those controllers several process turns.
	for _frame in range(6):
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

	var rig_value: Variant = studio.get("rig")
	if not rig_value is Object:
		_fail("Bone Studio did not expose a live Juno target rig.")
		return
	var rig := rig_value as Object
	for required_method in ["install_runtime_animation", "set_animation", "seek_animation_frame", "get_bone_names"]:
		if not rig.has_method(str(required_method)):
			_fail("Juno target rig is missing required method: %s" % str(required_method))
			return

	print("ALABASTER_BONE_BRIDGE_VALIDATION_OK tabs=%d" % tabs.get_child_count())
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


func _fail(message: String) -> void:
	printerr("ALABASTER_BONE_BRIDGE_VALIDATION_FAILURE: %s" % message)
	quit(1)
