extends RefCounted
class_name AlabasterBoneAnimationLibrary

const CUSTOM_BANK_PATH := "res://data/labs/alabaster/custom_bone_animations.json"
const JunoGameplayBank := preload("res://scripts/labs/alabaster/AlabasterJunoGameplayBank.gd")
const RepoSkinSource := preload("res://scripts/labs/alabaster/AlabasterExternalSkinSource.gd")
const CORE_ANIMATIONS := ["idle", "walk", "run", "atkSwordN1", "guard", "damage", "dead", "dash"]
const PROFILE_JUNO := "juno"
const PROFILE_DUMMY := "male_dummy"
const PROFILE_MALE := "male_temp"
const VALID_PROFILES := [PROFILE_JUNO, PROFILE_DUMMY, PROFILE_MALE]


static func load_custom_animations(profile_id: String = PROFILE_JUNO) -> Dictionary:
	var payload := _load_payload()
	var animations_value: Variant = payload.get("animations", {})
	if not animations_value is Dictionary:
		return {}
	var result := {}
	for animation_name_value in (animations_value as Dictionary).keys():
		var animation_name := str(animation_name_value)
		var animation_value: Variant = (animations_value as Dictionary)[animation_name_value]
		if not animation_value is Dictionary:
			continue
		var animation := animation_value as Dictionary
		var meta_value: Variant = animation.get("library_meta", {})
		var meta: Dictionary = meta_value as Dictionary if meta_value is Dictionary else {}
		# Legacy bank entries predate target profiles and were authored for Juno.
		var target_profile := str(meta.get("target_profile", PROFILE_JUNO))
		if profile_id.is_empty() or target_profile == profile_id:
			result[animation_name] = animation.duplicate(true)
	return result


static func load_builtin_animations(profile_id: String = PROFILE_JUNO) -> Dictionary:
	match profile_id:
		PROFILE_JUNO:
			# Use the repository-local gameplay/runtime pack that the working Juno
			# renderer already consumes. The old multipart 419-animation archive is
			# incomplete in this branch and must not be decoded from the editor path.
			return JunoGameplayBank.load_gameplay_bank()
		PROFILE_DUMMY, PROFILE_MALE:
			var figure := RepoSkinSource.load_skin_figure(profile_id)
			var anims_value: Variant = figure.get("anims", {})
			return (anims_value as Dictionary).duplicate(true) if anims_value is Dictionary else {}
		_:
			return {}


static func get_animation_record(profile_id: String, animation_name: String) -> Dictionary:
	var clean_name := animation_name.strip_edges()
	if clean_name.is_empty():
		return {}
	var builtins := load_builtin_animations(profile_id)
	var builtin_value: Variant = builtins.get(clean_name, {})
	if builtin_value is Dictionary and not (builtin_value as Dictionary).is_empty():
		return {
			"name": clean_name,
			"data": (builtin_value as Dictionary).duplicate(true),
			"source": "builtin",
			"read_only": true,
			"target_profile": profile_id,
		}
	var custom := load_custom_animations(profile_id)
	var custom_value: Variant = custom.get(clean_name, {})
	if custom_value is Dictionary and not (custom_value as Dictionary).is_empty():
		return {
			"name": clean_name,
			"data": (custom_value as Dictionary).duplicate(true),
			"source": "custom",
			"read_only": false,
			"target_profile": profile_id,
		}
	return {}


static func get_animation_records(profile_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var builtins := load_builtin_animations(profile_id)
	var builtin_names: Array = builtins.keys()
	builtin_names.sort()
	for name_value in builtin_names:
		result.append({
			"name": str(name_value),
			"source": "builtin",
			"read_only": true,
			"target_profile": profile_id,
		})
	var custom := load_custom_animations(profile_id)
	var custom_names: Array = custom.keys()
	custom_names.sort()
	for name_value in custom_names:
		result.append({
			"name": str(name_value),
			"source": "custom",
			"read_only": false,
			"target_profile": profile_id,
		})
	return result


static func is_builtin_animation(profile_id: String, animation_name: String) -> bool:
	return load_builtin_animations(profile_id).has(animation_name.strip_edges())


static func save_custom_animation(animation_name: String, animation_data: Dictionary, source_meta: Dictionary = {}) -> bool:
	var clean_name := animation_name.strip_edges()
	if clean_name.is_empty() or animation_data.is_empty():
		return false
	var target_profile := str(source_meta.get("target_profile", PROFILE_JUNO)).strip_edges()
	if target_profile not in VALID_PROFILES:
		target_profile = PROFILE_JUNO
	if is_builtin_animation(target_profile, clean_name):
		push_error("AlabasterBoneAnimationLibrary: refusing to overwrite read-only Alabaster source animation '%s' for profile=%s. Save it with a copy name." % [clean_name, target_profile])
		return false

	var payload := _load_payload()
	var animations: Dictionary = payload.get("animations", {})
	if animations.has(clean_name):
		var existing_value: Variant = animations[clean_name]
		if existing_value is Dictionary:
			var existing_meta_value: Variant = (existing_value as Dictionary).get("library_meta", {})
			var existing_meta: Dictionary = existing_meta_value as Dictionary if existing_meta_value is Dictionary else {}
			var existing_profile := str(existing_meta.get("target_profile", PROFILE_JUNO))
			if existing_profile != target_profile:
				push_error("AlabasterBoneAnimationLibrary: custom animation '%s' already belongs to profile=%s. Choose another copy name for profile=%s." % [clean_name, existing_profile, target_profile])
				return false

	var stored := animation_data.duplicate(true)
	var meta := source_meta.duplicate(true)
	meta["target_profile"] = target_profile
	stored["library_meta"] = meta
	animations[clean_name] = stored
	payload["animations"] = animations
	payload["version"] = 2
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


static func get_builtin_animation_names(profile_id: String = PROFILE_JUNO) -> Array[String]:
	var names: Array[String] = []
	var bank := load_builtin_animations(profile_id)
	for key in bank.keys():
		names.append(str(key))
	if profile_id == PROFILE_JUNO:
		for fallback in CORE_ANIMATIONS:
			if bank.has(fallback) and not names.has(fallback):
				names.append(fallback)
	names.sort()
	return names


static func get_all_animation_names(profile_id: String = PROFILE_JUNO) -> Array[String]:
	var names := get_builtin_animation_names(profile_id)
	for key in load_custom_animations(profile_id).keys():
		var clean := str(key)
		if not names.has(clean):
			names.append(clean)
	names.sort()
	return names


static func _load_payload() -> Dictionary:
	if not FileAccess.file_exists(CUSTOM_BANK_PATH):
		return {"version": 2, "format": "alabaster_bone_animation_bank", "animations": {}}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CUSTOM_BANK_PATH))
	if parsed is Dictionary:
		var payload: Dictionary = (parsed as Dictionary).duplicate(true)
		if not payload.get("animations", {}) is Dictionary:
			payload["animations"] = {}
		return payload
	return {"version": 2, "format": "alabaster_bone_animation_bank", "animations": {}}


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
