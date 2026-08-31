extends SceneTree

const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const MECHANIC_LAB_SCENE := "res://scenes/labs/alabaster/AlabasterMechanicLab.tscn"
const AUDIT_PATH := "res://data/labs/alabaster/juno_base_sprite_audit.json"
const JunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")
const JunoBaseRigScript := preload("res://scripts/labs/alabaster/AlabasterJunoBaseRig.gd")
const JunoBaseProfile := preload("res://scripts/labs/alabaster/AlabasterJunoBaseProfile.gd")
const Library := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const TICK_RATE := 60.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _validate_audit_contract():
		return
	if not await _validate_juno_base_runtime():
		return
	if not await _validate_mechanic_lab():
		return
	if not await _validate_live_tuning():
		return
	print("ALABASTER_JUNO_BASE_INTEGRATION_OK audit=505/286/219 core=16 male_removed=true active_green=true")
	quit(0)


func _validate_audit_contract() -> bool:
	if not FileAccess.file_exists(AUDIT_PATH):
		_fail("JunoBase audit report is missing")
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDIT_PATH))
	if not parsed is Dictionary:
		_fail("JunoBase audit report is invalid JSON")
		return false
	var report := parsed as Dictionary
	if int(report.get("defined_source_cells", 0)) != 505:
		_fail("unexpected Juno source-cell count: %s" % str(report.get("defined_source_cells", null)))
		return false
	if int(report.get("core_used_cells", 0)) != 286:
		_fail("unexpected JunoBase core-cell count: %s" % str(report.get("core_used_cells", null)))
		return false
	if int(report.get("excluded_cells", 0)) != 219:
		_fail("unexpected JunoBase excluded-cell count: %s" % str(report.get("excluded_cells", null)))
		return false
	if int(report.get("core_animation_count", 0)) != JunoBaseProfile.core_animation_names().size():
		_fail("audit/core profile animation counts disagree")
		return false
	return true


func _validate_juno_base_runtime() -> bool:
	var juno := JunoRigScript.new() as Node2D
	var base := JunoBaseRigScript.new() as Node2D
	if juno == null or base == null:
		_fail("could not instantiate Juno/JunoBase runtimes")
		return false
	root.add_child(juno)
	root.add_child(base)
	await process_frame
	await process_frame
	juno.set_process(false)
	base.set_process(false)

	var summary_value: Variant = base.call("get_juno_base_profile_summary")
	if not summary_value is Dictionary:
		_fail("JunoBase exposes no profile summary")
		return false
	var summary := summary_value as Dictionary
	if not bool(summary.get("core_atlas_active", false)):
		_fail("JunoBase did not load the generated core atlas")
		return false

	var builtin := Library.load_builtin_animations("juno_base")
	if builtin.size() != 16:
		_fail("JunoBase library expected 16 builtin clips, got %d" % builtin.size())
		return false
	for animation_name in JunoBaseProfile.core_animation_names():
		if not builtin.has(animation_name) or not bool(base.call("has_animation", animation_name)):
			_fail("JunoBase core animation missing: %s" % animation_name)
			return false

	var juno_bones_value: Variant = juno.call("get_bone_names")
	var base_bones_value: Variant = base.call("get_bone_names")
	if not juno_bones_value is Array or not base_bones_value is Array or juno_bones_value != base_bones_value:
		_fail("JunoBase skeleton bone names differ from Juno")
		return false
	var juno_rest_value: Variant = juno.call("get_bone_rest_local_positions")
	var base_rest_value: Variant = base.call("get_bone_rest_local_positions")
	if not juno_rest_value is Dictionary or not base_rest_value is Dictionary or not _vector_dictionary_matches(juno_rest_value as Dictionary, base_rest_value as Dictionary):
		_fail("JunoBase authored REST positions differ from Juno")
		return false

	var core_atlas_value: Variant = base.get("_atlas")
	if not core_atlas_value is Texture2D:
		_fail("JunoBase core atlas texture unavailable")
		return false
	var core_image := (core_atlas_value as Texture2D).get_image()
	if core_image == null or core_image.is_empty():
		_fail("JunoBase core atlas image unavailable")
		return false
	core_image.convert(Image.FORMAT_RGBA8)
	var alpha_cache: Dictionary = {}
	var sampled_frames := 0

	for animation_name in JunoBaseProfile.core_animation_names():
		var animation_value: Variant = base.call("get_animation_data", animation_name)
		if not animation_value is Dictionary:
			_fail("cannot read JunoBase animation data: %s" % animation_name)
			return false
		var animation := animation_value as Dictionary
		var start_frame := int(animation.get("animStart", 0))
		var frame_count := maxi(int(animation.get("frameCnt", start_frame + 1)), start_frame + 1)
		var frame_repeat := maxf(float(animation.get("frameRepeat", 1.0)), 1.0)
		for facing_index in range(16):
			var radians := deg_to_rad(float(facing_index) * 22.5)
			var direction := Vector2(sin(radians), -cos(radians))
			juno.call("set_facing_from_vector", direction)
			base.call("set_facing_from_vector", direction)
			for frame in range(start_frame, frame_count):
				var time := float(frame - start_frame) * frame_repeat / TICK_RATE
				_set_pose_frame(juno, animation_name, time)
				_set_pose_frame(base, animation_name, time)
				var juno_signature := _visible_region_signature(juno)
				var base_signature := _visible_region_signature(base)
				if juno_signature != base_signature:
					_fail("JunoBase visual mapping diverged from Juno at %s frame=%d facing=%d" % [animation_name, frame, facing_index])
					return false
				if not _visible_regions_have_pixels(base, core_image, alpha_cache):
					_fail("JunoBase core atlas contains a transparent active cell at %s frame=%d facing=%d" % [animation_name, frame, facing_index])
					return false
				sampled_frames += 1

	print("ALABASTER_JUNO_BASE_RUNTIME_OK animations=16 sampled_pose_frames=%d atlas_regions=%d" % [sampled_frames, alpha_cache.size()])
	juno.queue_free()
	base.queue_free()
	await process_frame
	return true


func _validate_mechanic_lab() -> bool:
	var packed := load(MECHANIC_LAB_SCENE) as PackedScene
	if packed == null:
		_fail("Mechanic Lab scene failed to load")
		return false
	var lab := packed.instantiate()
	root.add_child(lab)
	for _i in range(4):
		await process_frame
	var buttons_value: Variant = lab.get("_profile_buttons")
	if not buttons_value is Dictionary:
		_fail("Mechanic Lab exposes no profile buttons")
		return false
	var buttons := buttons_value as Dictionary
	if not buttons.has("juno_base"):
		_fail("Mechanic Lab has no JunoBase button")
		return false
	if buttons.has("male_temp"):
		_fail("Mechanic Lab still exposes Male")
		return false
	lab.call("_replace_rig", "juno_base", true)
	await process_frame
	var rig_value: Variant = lab.get("rig")
	if not rig_value is Object:
		_fail("Mechanic Lab did not instantiate JunoBase")
		return false
	var runtime_summary_value: Variant = (rig_value as Object).call("get_runtime_summary")
	if not runtime_summary_value is Dictionary or str((runtime_summary_value as Dictionary).get("profile", "")) != "juno_base":
		_fail("Mechanic Lab JunoBase runtime summary is wrong")
		return false
	print("ALABASTER_JUNO_BASE_LAB_OK buttons=%d male=false" % buttons.size())
	lab.queue_free()
	await process_frame
	return true


func _validate_live_tuning() -> bool:
	var packed := load(BONE_STUDIO_SCENE) as PackedScene
	if packed == null:
		_fail("Bone Studio scene failed to load")
		return false
	var studio := packed.instantiate()
	root.add_child(studio)
	for _i in range(10):
		await process_frame
	var panel_value: Variant = studio.get("_live_tuning_panel")
	if not panel_value is Control:
		_fail("Bone Studio Live Tuning panel failed to initialize")
		return false
	var panel := panel_value as Control
	var targets_value: Variant = panel.get("target_buttons")
	if not targets_value is Dictionary:
		_fail("Live Tuning exposes no target buttons")
		return false
	var targets := targets_value as Dictionary
	if not targets.has("juno_base") or targets.has("male_temp"):
		_fail("Live Tuning target list is wrong: %s" % str(targets.keys()))
		return false
	var filter := panel.get("filter_option") as OptionButton
	if filter == null:
		_fail("Live Tuning filter is missing")
		return false
	for index in range(filter.item_count):
		if str(filter.get_item_metadata(index)) == "MALE":
			_fail("Live Tuning still exposes MALE filter")
			return false

	panel.call("_on_target_pressed", "juno_base")
	for _i in range(3):
		await process_frame
	panel.call("_select_default_idle")
	for _i in range(2):
		await process_frame
	panel.call("_refresh_atlas_inspector", true)
	await process_frame

	var live_rig_value: Variant = studio.get("rig")
	if not live_rig_value is Node2D:
		_fail("Live Tuning JunoBase rig is missing")
		return false
	var live_rig := live_rig_value as Node2D
	var active_regions := _active_unique_regions(live_rig)
	if active_regions.size() <= 1:
		_fail("Live Tuning test frame has too few active regions")
		return false
	var highlight_layer := panel.get("_atlas_highlight_layer") as Control
	if highlight_layer == null:
		_fail("Live Tuning atlas highlight layer is missing")
		return false
	var green_count := _live_child_count(highlight_layer)
	if green_count != active_regions.size():
		_fail("green masks do not cover all active cells: masks=%d active=%d" % [green_count, active_regions.size()])
		return false

	var selected_node := _first_visible_node(live_rig)
	if selected_node.is_empty():
		_fail("could not select a visible JunoBase part")
		return false
	panel.set("selected_part", selected_node)
	if live_rig.has_method("set_selected_sprite_part"):
		live_rig.call("set_selected_sprite_part", selected_node)
	panel.call("_refresh_atlas_inspector", true)
	await process_frame
	var selected_green_count := _live_child_count(highlight_layer)
	if selected_green_count != active_regions.size():
		_fail("selecting one bone hid other active green masks: masks=%d active=%d" % [selected_green_count, active_regions.size()])
		return false

	print("ALABASTER_LIVE_GREEN_MASK_OK active_cells=%d selected=%s masks=%d" % [active_regions.size(), selected_node, selected_green_count])
	studio.queue_free()
	await process_frame
	return true


func _set_pose_frame(rig: Node2D, animation_name: String, time: float) -> void:
	rig.set("current_animation", animation_name)
	rig.set("animation_time", time)
	rig.call("_apply_pose")


func _visible_region_signature(rig: Node2D) -> String:
	var rows: Array[String] = []
	var records_value: Variant = rig.get("_sprite_records")
	if not records_value is Array:
		return ""
	for record_value in records_value as Array:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var region := sprite.region_rect
		rows.append("%s:%d:%d,%d,%d,%d:%s" % [
			str(record.get("node", "")), int(record.get("gfx_index", 0)),
			int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y),
			str(sprite.flip_h),
		])
	rows.sort()
	return "|".join(rows)


func _visible_regions_have_pixels(rig: Node2D, image: Image, cache: Dictionary) -> bool:
	var records_value: Variant = rig.get("_sprite_records")
	if not records_value is Array:
		return false
	for record_value in records_value as Array:
		if not record_value is Dictionary:
			continue
		var sprite := (record_value as Dictionary).get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var region := sprite.region_rect
		var rect := Rect2i(roundi(region.position.x), roundi(region.position.y), roundi(region.size.x), roundi(region.size.y))
		var key := "%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		if cache.has(key):
			if not bool(cache[key]):
				return false
			continue
		var has_pixel := _rect_has_alpha(image, rect)
		cache[key] = has_pixel
		if not has_pixel:
			return false
	return true


func _rect_has_alpha(image: Image, rect: Rect2i) -> bool:
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	var clipped := rect.intersection(bounds)
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			if image.get_pixel(x, y).a > 0.001:
				return true
	return false


func _active_unique_regions(rig: Node2D) -> Dictionary:
	var result: Dictionary = {}
	var records_value: Variant = rig.get("_sprite_records")
	if not records_value is Array:
		return result
	for record_value in records_value as Array:
		if not record_value is Dictionary:
			continue
		var sprite := (record_value as Dictionary).get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var region := sprite.region_rect
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			continue
		var key := "%d,%d,%d,%d" % [int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)]
		result[key] = true
	return result


func _first_visible_node(rig: Node2D) -> String:
	var records_value: Variant = rig.get("_sprite_records")
	if records_value is Array:
		for record_value in records_value as Array:
			if record_value is Dictionary:
				var record := record_value as Dictionary
				var sprite := record.get("sprite") as Sprite2D
				if sprite != null and sprite.visible:
					return str(record.get("node", ""))
	return ""


func _live_child_count(node: Node) -> int:
	var count := 0
	for child_value in node.get_children():
		var child := child_value as Node
		if child != null and not child.is_queued_for_deletion():
			count += 1
	return count


func _vector_dictionary_matches(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key_value in a.keys():
		if not b.has(key_value):
			return false
		var av: Variant = a[key_value]
		var bv: Variant = b[key_value]
		if av is Vector3 and bv is Vector3:
			if not (av as Vector3).is_equal_approx(bv as Vector3):
				return false
		elif av != bv:
			return false
	return true


func _fail(message: String) -> void:
	printerr("ALABASTER_JUNO_BASE_INTEGRATION_FAILURE: %s" % message)
	quit(1)
