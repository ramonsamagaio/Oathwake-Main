extends RefCounted
class_name AlabasterBoneAnimationLibrary

const CUSTOM_BANK_PATH := "res://data/labs/alabaster/custom_bone_animations.json"
const AnimationBank := preload("res://scripts/labs/alabaster/AlabasterAnimationBank.gd")
const CORE_ANIMATIONS := ["idle", "walk", "run", "atkSwordN1", "guard", "damage", "dead", "dash"]


static func load_custom_animations() -> Dictionary:
	if not FileAccess.file_exists(CUSTOM_BANK_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CUSTOM_BANK_PATH))
	if not parsed is Dictionary:
		return {}
	var animations: Variant = (parsed as Dictionary).get("animations", {})
	return (animations as Dictionary).duplicate(true) if animations is Dictionary else {}


static func save_custom_animation(animation_name: String, animation_data: Dictionary, source_meta: Dictionary = {}) -> bool:
	var clean_name := animation_name.strip_edges()
	if clean_name.is_empty() or animation_data.is_empty():
		return false
	var payload := _load_payload()
	var animations: Dictionary = payload.get("animations", {})
	var stored := animation_data.duplicate(true)
	if not source_meta.is_empty():
		stored["library_meta"] = source_meta.duplicate(true)
	animations[clean_name] = stored
	payload["animations"] = animations
	payload["version"] = 1
	payload["format"] = "alabaster_bone_animation_bank"
	return _write_payload(payload)


static func remove_custom_animation(animation_name: String) -> bool:
	var payload := _load_payload()
	var animations: Dictionary = payload.get("animations", {})
	if not animations.has(animation_name):
		return false
	animations.erase(animation_name)
	payload["animations"] = animations
	return _write_payload(payload)


static func get_builtin_animation_names() -> Array[String]:
	var names: Array[String] = []
	var bank := AnimationBank.load_full_animation_bank()
	for key in bank.keys():
		names.append(str(key))
	for fallback in CORE_ANIMATIONS:
		if not names.has(fallback):
			names.append(fallback)
	names.sort()
	return names


static func get_all_animation_names() -> Array[String]:
	var names := get_builtin_animation_names()
	for key in load_custom_animations().keys():
		var clean := str(key)
		if not names.has(clean):
			names.append(clean)
	names.sort()
	return names


static func _load_payload() -> Dictionary:
	if not FileAccess.file_exists(CUSTOM_BANK_PATH):
		return {"version": 1, "format": "alabaster_bone_animation_bank", "animations": {}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CUSTOM_BANK_PATH))
	if parsed is Dictionary:
		var payload: Dictionary = (parsed as Dictionary).duplicate(true)
		if not payload.get("animations", {}) is Dictionary:
			payload["animations"] = {}
		return payload
	return {"version": 1, "format": "alabaster_bone_animation_bank", "animations": {}}


static func _write_payload(payload: Dictionary) -> bool:
	var absolute_path := ProjectSettings.globalize_path(CUSTOM_BANK_PATH)
	var directory := absolute_path.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(directory)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_error("Could not create Alabaster animation bank directory: %s" % directory)
		return false
	var file := FileAccess.open(CUSTOM_BANK_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write Alabaster animation bank: %s" % CUSTOM_BANK_PATH)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	return true
