extends "res://scripts/labs/alabaster/AlabasterBoneStudioSharedProfiles.gd"
class_name AlabasterBoneStudioImportSourceFix

const RobustImporter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const FOLD_PREFIX := "@fold:"

func _on_source_selected(path: String) -> void:
	source_path = path
	source_path_label.text = path
	source_clip_option.clear()
	source_bones.clear()
	var info := RobustImporter.inspect_scene(path)
	if not bool(info.get("ok", false)):
		_rebuild_mapping_table()
		_set_status(str(info.get("error", "Could not inspect source animation.")), true)
		return
	for clip in info.get("clips", []):
		source_clip_option.add_item(str(clip))
		source_clip_option.set_item_metadata(source_clip_option.item_count - 1, str(clip))
	for bone in info.get("bones", []):
		source_bones.append(str(bone))

	var profile := str(info.get("retarget_profile", "generic"))
	if profile == "mixamo":
		# Godot's imported skeleton animation is already expressed as bone pose
		# motion. Subtracting frame zero turns the first punch pose into a fake rest
		# pose and destroys the intended stance, so keep it off for Mixamo by default.
		import_reference_pose.button_pressed = false
		import_reference_pose.tooltip_text = "Mixamo Smart Chain: OFF is recommended. Turn this on only if you intentionally want frame 0 neutralized."
	_rebuild_mapping_table()

	if source_clip_option.item_count > 0:
		source_clip_option.select(0)
		import_name_edit.text = "OW_%s" % _sanitize_name(str(source_clip_option.get_item_metadata(0)))
	var kind := str(info.get("resource_kind", "godot_resource"))
	if profile == "mixamo":
		_set_status("Mixamo Smart Chain detected: %d clips, %d source bones. Spine, neck and clavicle chains will be collapsed instead of overwriting the same Alabaster bone." % [source_clip_option.item_count, source_bones.size()])
	else:
		_set_status("Loaded %d clips and %d source bones from %s." % [source_clip_option.item_count, source_bones.size(), kind])

func _rebuild_mapping_table() -> void:
	mapping_controls.clear()
	for child in mapping_container.get_children():
		child.queue_free()
	var targets: Array = []
	if rig != null and rig.has_method("get_bone_names"):
		var runtime_names: Variant = rig.call("get_bone_names")
		if runtime_names is Array:
			targets = runtime_names.duplicate()
	var auto := RobustImporter.make_auto_retarget(source_bones)
	for source_bone in source_bones:
		var option := OptionButton.new()
		option.add_item("-- Ignore --")
		option.set_item_metadata(0, "")
		var selected := 0
		var auto_value := str(auto.get(source_bone, ""))
		if auto_value.begins_with(FOLD_PREFIX):
			var fold_target := auto_value.trim_prefix(FOLD_PREFIX)
			option.add_item("AUTO FOLD -> %s" % fold_target)
			option.set_item_metadata(option.item_count - 1, auto_value)
			option.set_item_tooltip(option.item_count - 1, "This Mixamo bone is composed with its chain into %s; it does not write a second independent transform." % fold_target)
			selected = option.item_count - 1
		for target_value in targets:
			var target := str(target_value)
			option.add_item(target)
			option.set_item_metadata(option.item_count - 1, target)
			if target == auto_value:
				selected = option.item_count - 1
		option.select(selected)
		_add_row(mapping_container, source_bone, option)
		mapping_controls[source_bone] = option

func _build_import_animation() -> Dictionary:
	if source_path.is_empty() or source_clip_option.item_count <= 0 or source_clip_option.selected < 0:
		_set_status("The source file is selected, but Godot exposed no animation clip. Reimport the FBX with Animation enabled and try again.", true)
		return {}
	var clip_name := _selected_clip()
	if clip_name.is_empty():
		_set_status("Select an animation clip first.", true)
		return {}
	var result := RobustImporter.import_scene_clip(source_path, clip_name, import_fps.value, import_loop.button_pressed, 0.0, _get_mapping(), _get_import_settings())
	if result.is_empty():
		_set_status("The animation clip was found but could not be converted. Check the source bone mapping below.", true)
	return result
