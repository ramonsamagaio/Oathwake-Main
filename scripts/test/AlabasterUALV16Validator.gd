extends SceneTree

const STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const UAL_SOURCE := "res://assets/anims/UAL1_Standard.glb"
const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const Profile := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetProfile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(UAL_SOURCE):
		_fail("UAL1 source missing")
		return
	var inspection := SourceAdapter.inspect_scene(UAL_SOURCE)
	if not bool(inspection.get("ok", false)):
		_fail("UAL1 inspection failed: %s" % str(inspection))
		return
	var bones_value: Variant = inspection.get("bones", [])
	if not bones_value is Array:
		_fail("UAL1 exposed no bone list")
		return
	var bones: Array[String] = []
	for value in bones_value as Array:
		bones.append(str(value))
	if not Profile.detect_ual(bones):
		_fail("UAL1 skeleton was not detected as Unreal/UAL: %s" % str(bones))
		return
	if not Profile.detect(bones):
		_fail("UAL1 aliases do not satisfy canonical humanoid requirements")
		return
	var auto_map := Profile.make_auto_map(bones)
	for source_name in ["pelvis", "spine_03", "upperarm_l", "lowerarm_l", "thigh_l", "calf_l", "foot_l", "ball_l"]:
		if not auto_map.has(source_name):
			_fail("UAL1 auto-map missing %s" % source_name)
			return

	var packed := load(STUDIO_SCENE) as PackedScene
	if packed == null:
		_fail("Bone Studio scene failed to load")
		return
	var studio := packed.instantiate()
	root.add_child(studio)
	for _i in range(8):
		await process_frame
	studio.call("_on_source_selected", UAL_SOURCE)
	for _i in range(4):
		await process_frame

	var option := studio.get("source_clip_option") as OptionButton
	if option == null or option.item_count != 43:
		_fail("UAL1 Bone Studio clip catalog expected 43, got %d" % (option.item_count if option != null else -1))
		return
	var loop_toggle := studio.get("source_loop_toggle") as CheckButton
	var succeeded := 0
	var total_keys := 0
	var min_det := 999.0
	var max_det := -999.0
	for index in range(option.item_count):
		option.select(index)
		var clip_name := option.get_item_text(index)
		if loop_toggle != null:
			loop_toggle.button_pressed = clip_name.ends_with("_Loop")
		var result_value: Variant = studio.call("_build_import_animation")
		if not result_value is Dictionary or (result_value as Dictionary).is_empty():
			_fail("UAL1 V16 retarget failed for %s (%d/43)" % [clip_name, index + 1])
			return
		var result := result_value as Dictionary
		var meta_value: Variant = result.get("import_meta", {})
		if not meta_value is Dictionary:
			_fail("UAL1 %s has no import metadata" % clip_name)
			return
		var meta := meta_value as Dictionary
		if str(meta.get("source_profile", "")) != "ual_unreal":
			_fail("UAL1 %s did not pass through semantic adapter" % clip_name)
			return
		if int(meta.get("rotation_codec_version", 0)) != 16:
			_fail("UAL1 %s did not inherit runtime codec V16" % clip_name)
			return
		if int(meta.get("rest_calibration_version", 0)) != 10:
			_fail("UAL1 %s did not inherit REST/handedness calibration V10" % clip_name)
			return
		var determinant := float(meta.get("source_to_target_determinant", 0.0))
		if determinant >= -0.5:
			_fail("UAL1 %s lost Claude's reflected handedness bridge det=%.3f" % [clip_name, determinant])
			return
		var transforms_value: Variant = result.get("transforms", [])
		if not transforms_value is Array or (transforms_value as Array).is_empty():
			_fail("UAL1 %s generated no Juno transforms" % clip_name)
			return
		var keys := (transforms_value as Array).size()
		if int(result.get("frameCnt", 0)) <= 0 or keys <= 0:
			_fail("UAL1 %s generated invalid frame/key count" % clip_name)
			return
		succeeded += 1
		total_keys += keys
		min_det = minf(min_det, determinant)
		max_det = maxf(max_det, determinant)
		print("ALABASTER_UAL_CLIP_OK clip=%s index=%d/43 frames=%d keys=%d det=%.3f codec=16 loop=%s" % [
			clip_name, index + 1, int(result.get("frameCnt", 0)), keys, determinant,
			str(bool(result.get("repeat", false))),
		])

	if succeeded != 43:
		_fail("UAL1 expected 43 successful retargets, got %d" % succeeded)
		return
	print("ALABASTER_UAL_V16_VALIDATION_OK clips=%d total_keys=%d det_range=%.3f..%.3f" % [succeeded, total_keys, min_det, max_det])
	studio.queue_free()
	await process_frame
	quit(0)

func _fail(message: String) -> void:
	printerr("ALABASTER_UAL_V16_VALIDATION_FAILURE: %s" % message)
	quit(1)
