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
	var retarget_mode := str(info.get("retarget_mode", "generic_track"))
	if profile == "mixamo":
		import_reference_pose.button_pressed = false
		if retarget_mode == "mixamo_anatomical_v4":
			import_reference_pose.disabled = true
			import_reference_pose.tooltip_text = "Mixamo Anatomical V4 evaluates the real FBX Skeleton3D pose and fits anatomical segments to the Default target chain. Frame-zero subtraction is not used."
		else:
			import_reference_pose.disabled = false
			import_reference_pose.tooltip_text = "No Skeleton3D was exposed by this import, so only the lower-fidelity track fallback is available."
	else:
		import_reference_pose.disabled = false
		import_reference_pose.tooltip_text = "Subtract frame zero from the imported source motion."

	_rebuild_mapping_table()

	if source_clip_option.item_count > 0:
		source_clip_option.select(0)
		import_name_edit.text = "OW_%s" % _sanitize_name(str(source_clip_option.get_item_metadata(0)))

	var kind := str(info.get("resource_kind", "godot_resource"))
	if retarget_mode == "mixamo_anatomical_v4":
		_set_status("Mixamo Anatomical V4 detected: %d clips, %d bones. Default shoulder/hip nodes are treated as attachment pivots; Arm/ForeArm and UpLeg/Leg are fitted to the actual Alabaster limb segments from the evaluated FBX pose." % [source_clip_option.item_count, source_bones.size()])
	elif profile == "mixamo":
		_set_status("Mixamo detected, but this resource exposes no Skeleton3D. Track-only fallback is available; importing the raw FBX as a scene is recommended.")
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
			option.set_item_tooltip(option.item_count - 1, "This Mixamo joint is an endpoint/helper used by the anatomical solve for %s. It does not independently overwrite an Alabaster transform." % fold_target)
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
	var result := RobustImporter.import_scene_clip(
		source_path,
		clip_name,
		import_fps.value,
		import_loop.button_pressed,
		0.0,
		_get_mapping(),
		_get_import_settings()
	)
	if result.is_empty():
		_set_status("The clip was found but could not be converted. For Mixamo, keep the automatic mapping unchanged so Anatomical V4 can use the evaluated FBX Skeleton3D.", true)
	return result
