extends SceneTree

const STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const UAL_SOURCE := "res://assets/anims/UAL1_Standard.glb"
const BANK_PATH := "res://data/labs/alabaster/custom_bone_animations.json"
const PREFIX := "UAL1__"
const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
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
	var loop_toggle := studio.get("source_loop_toggle") as CheckButton
	if option == null or option.item_count != 43:
		_fail("expected 43 UAL1 clips, got %d" % (option.item_count if option != null else -1))
		return

	var opened := SourceAdapter.open_preview_source(UAL_SOURCE)
	var source_player := opened.get("player") as AnimationPlayer
	if not bool(opened.get("ok", false)) or source_player == null:
		_fail("could not open raw UAL1 source for loop metadata")
		return

	var payload := _load_existing_bank()
	var animations_value: Variant = payload.get("animations", {})
	var animations := (animations_value as Dictionary).duplicate(true) if animations_value is Dictionary else {}
	for old_name in animations.keys():
		if str(old_name).begins_with(PREFIX):
			animations.erase(old_name)

	var baked := 0
	var total_keys := 0
	for index in range(option.item_count):
		option.select(index)
		var clip_name := option.get_item_text(index)
		var source_anim := source_player.get_animation(clip_name) if source_player.has_animation(clip_name) else null
		var should_loop := source_anim != null and source_anim.loop_mode != Animation.LOOP_NONE
		if loop_toggle != null:
			loop_toggle.button_pressed = should_loop
		var result_value: Variant = studio.call("_build_import_animation")
		if not result_value is Dictionary or (result_value as Dictionary).is_empty():
			SourceAdapter.close_preview_source(opened)
			_fail("retarget failed while baking %s" % clip_name)
			return
		var stored := (result_value as Dictionary).duplicate(true)
		stored["category"] = "UAL1"
		var meta_value: Variant = stored.get("import_meta", {})
		var import_meta := (meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
		import_meta["source_pack"] = "UAL1_Standard"
		import_meta["source_clip"] = clip_name
		import_meta["baked_for_bonelab"] = true
		stored["import_meta"] = import_meta
		stored["library_meta"] = {
			"target_profile": "juno",
			"source_profile": "ual_unreal",
			"source_kind": "UAL1_Standard.glb",
			"source_animation": clip_name,
			"type": "ual1_v16_baked",
			"non_destructive": true,
		}
		var baked_name := PREFIX + clip_name
		animations[baked_name] = stored
		baked += 1
		var transforms_value: Variant = stored.get("transforms", [])
		if transforms_value is Array:
			total_keys += (transforms_value as Array).size()
		print("ALABASTER_UAL_BAKE_CLIP name=%s source=%s loop=%s %d/43" % [baked_name, clip_name, str(should_loop), index + 1])

	SourceAdapter.close_preview_source(opened)
	if baked != 43:
		_fail("expected 43 baked clips, got %d" % baked)
		return
	payload["version"] = 2
	payload["format"] = "alabaster_bone_animation_bank"
	payload["animations"] = animations
	if not _write_bank(payload):
		_fail("could not write %s" % BANK_PATH)
		return
	print("ALABASTER_UAL_BATCH_BAKE_OK clips=%d total_keys=%d bank_total=%d" % [baked, total_keys, animations.size()])
	studio.queue_free()
	await process_frame
	quit(0)

func _load_existing_bank() -> Dictionary:
	if not FileAccess.file_exists(BANK_PATH):
		return {"version": 2, "format": "alabaster_bone_animation_bank", "animations": {}}
	var parsed := JSON.parse_string(FileAccess.get_file_as_string(BANK_PATH))
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {"version": 2, "format": "alabaster_bone_animation_bank", "animations": {}}

func _write_bank(payload: Dictionary) -> bool:
	var file := FileAccess.open(BANK_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	return true

func _fail(message: String) -> void:
	printerr("ALABASTER_UAL_BATCH_BAKE_FAILURE: %s" % message)
	quit(1)
