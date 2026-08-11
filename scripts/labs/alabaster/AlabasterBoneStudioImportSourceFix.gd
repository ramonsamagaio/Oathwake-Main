extends "res://scripts/labs/alabaster/AlabasterBoneStudioSharedProfiles.gd"
class_name AlabasterBoneStudioImportSourceFix

const RobustImporter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")


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
	_rebuild_mapping_table()

	if source_clip_option.item_count > 0:
		source_clip_option.select(0)
		import_name_edit.text = "OW_%s" % _sanitize_name(str(source_clip_option.get_item_metadata(0)))
	var kind := str(info.get("resource_kind", "godot_resource"))
	_set_status("Loaded %d clips and %d source bones from %s." % [source_clip_option.item_count, source_bones.size(), kind])


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
		_set_status("The animation clip was found but could not be converted. Check the source bone mapping below.", true)
	return result
