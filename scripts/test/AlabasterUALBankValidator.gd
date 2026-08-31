extends SceneTree

const LAB_SCENE := "res://scenes/labs/alabaster/AlabasterMechanicLab.tscn"
const Library := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const PREFIX := "UAL1__"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var custom: Dictionary = Library.load_custom_animations("juno")
	var ual_names: Array[String] = []
	var loops := 0
	var one_shots := 0
	for name_value in custom.keys():
		var name: String = str(name_value)
		if not name.begins_with(PREFIX):
			continue
		ual_names.append(name)
		var data_value: Variant = custom[name_value]
		if not data_value is Dictionary:
			_fail("persisted UAL entry is not an animation dictionary: %s" % name)
			return
		var data := data_value as Dictionary
		var meta_value: Variant = data.get("import_meta", {})
		if not meta_value is Dictionary:
			_fail("persisted UAL entry lost import metadata: %s" % name)
			return
		var meta := meta_value as Dictionary
		if int(meta.get("rotation_codec_version", 0)) != 16:
			_fail("persisted UAL entry lost V16 codec: %s" % name)
			return
		if int(meta.get("rest_calibration_version", 0)) != 10:
			_fail("persisted UAL entry lost V10 REST calibration: %s" % name)
			return
		if float(meta.get("source_to_target_determinant", 0.0)) >= -0.5:
			_fail("persisted UAL entry lost reflected handedness: %s" % name)
			return
		if str(data.get("category", "")) != "UAL1":
			_fail("persisted UAL entry lost UAL1 category: %s" % name)
			return
		if bool(data.get("repeat", false)):
			loops += 1
		else:
			one_shots += 1

	ual_names.sort()
	if ual_names.size() != 43:
		_fail("persisted Juno bank expected 43 UAL1 clips, got %d" % ual_names.size())
		return
	if loops != 19 or one_shots != 24:
		_fail("persisted loop contract expected 19/24, got %d/%d" % [loops, one_shots])
		return
	for required in ["UAL1__Walk_Loop", "UAL1__Jog_Fwd_Loop", "UAL1__Punch_Jab", "UAL1__Death01", "UAL1__Sword_Attack"]:
		if not custom.has(required):
			_fail("persisted UAL1 bank missing %s" % required)
			return
	if not bool((custom["UAL1__Walk_Loop"] as Dictionary).get("repeat", false)):
		_fail("Walk_Loop is not persisted as loop")
		return
	if bool((custom["UAL1__Punch_Jab"] as Dictionary).get("repeat", true)):
		_fail("Punch_Jab is incorrectly persisted as loop")
		return
	if bool((custom["UAL1__Death01"] as Dictionary).get("repeat", true)):
		_fail("Death01 is incorrectly persisted as loop")
		return

	var packed: PackedScene = load(LAB_SCENE) as PackedScene
	if packed == null:
		_fail("Mechanic Lab scene failed to load")
		return
	var lab: Node = packed.instantiate()
	root.add_child(lab)
	for _i in range(8):
		await process_frame
	lab.call("_replace_rig", "juno", true)
	for _i in range(4):
		await process_frame
	var rig_value: Variant = lab.get("rig")
	if not rig_value is Object:
		_fail("Mechanic Lab exposed no Juno rig")
		return
	var rig := rig_value as Object
	var playable := 0
	for name in ual_names:
		if not rig.has_method("has_animation") or not bool(rig.call("has_animation", name)):
			_fail("Mechanic Lab Juno did not install %s" % name)
			return
		playable += 1

	var catalog_value: Variant = lab.get("_catalog")
	if not catalog_value is Array:
		_fail("Mechanic Lab exposed no animation catalog")
		return
	var catalog_ual := 0
	for entry_value in catalog_value as Array:
		if entry_value is Dictionary and str((entry_value as Dictionary).get("name", "")).begins_with(PREFIX):
			catalog_ual += 1
	if catalog_ual != 43:
		_fail("Mechanic Lab catalog expected 43 UAL1 entries, got %d" % catalog_ual)
		return

	print("ALABASTER_UAL_BANK_VALIDATION_OK persisted=43 playable=%d catalog=%d loops=%d one_shots=%d custom_total=%d" % [
		playable, catalog_ual, loops, one_shots, custom.size(),
	])
	lab.queue_free()
	await process_frame
	quit(0)

func _fail(message: String) -> void:
	printerr("ALABASTER_UAL_BANK_VALIDATION_FAILURE: %s" % message)
	quit(1)
