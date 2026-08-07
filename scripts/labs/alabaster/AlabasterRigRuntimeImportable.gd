extends "res://scripts/labs/alabaster/AlabasterRigRuntimeSourceLive.gd"
class_name AlabasterRigRuntimeImportable


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
