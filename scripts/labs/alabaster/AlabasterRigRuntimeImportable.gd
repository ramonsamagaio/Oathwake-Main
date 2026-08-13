extends "res://scripts/labs/alabaster/AlabasterRigRuntimeSourceLive.gd"
class_name AlabasterRigRuntimeImportable

const BoneAnimationLibrary := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")


func _ready() -> void:
	super._ready()
	_merge_custom_animation_library()


func _merge_custom_animation_library() -> void:
	var custom := BoneAnimationLibrary.load_custom_animations()
	for animation_name_variant in custom.keys():
		var animation_name := str(animation_name_variant)
		var animation_data: Variant = custom[animation_name_variant]
		if animation_data is Dictionary:
			install_runtime_animation(animation_name, animation_data as Dictionary)
	if not custom.is_empty():
		print("ALABASTER_CUSTOM_BANK_OK animations=%d" % custom.size())


func install_runtime_animation(animation_name: String, animation_data: Dictionary) -> bool:
	var clean_name := animation_name.strip_edges()
	if clean_name.is_empty() or animation_data.is_empty():
		return false
	if not animation_data.has("frameCnt") or not animation_data.has("transforms"):
		push_warning("Alabaster runtime animation '%s' is missing frameCnt/transforms." % clean_name)
		return false
	_anims[clean_name] = animation_data.duplicate(true)
	_figure["anims"] = _anims
	_track_cache.clear()
	return true


func remove_runtime_animation(animation_name: String) -> bool:
	if not _anims.has(animation_name):
		return false
	_anims.erase(animation_name)
	_figure["anims"] = _anims
	_track_cache.clear()
	if current_animation == animation_name:
		set_animation("idle")
	return true
