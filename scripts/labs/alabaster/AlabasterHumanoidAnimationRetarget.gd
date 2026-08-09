extends RefCounted
class_name AlabasterHumanoidAnimationRetarget

const JunoGameplayBank := preload("res://scripts/labs/alabaster/AlabasterJunoGameplayBank.gd")
const RepoSkinSource := preload("res://scripts/labs/alabaster/AlabasterExternalSkinSource.gd")

const RETARGET_NAMES := {
	"idle": "juno_idle_retarget",
	"walk": "juno_walk_retarget",
	"run": "juno_run_retarget",
}
const LOCOMOTION_CLIPS := ["idle", "walk", "run"]
const NATIVE_PREFIX := "native__"
const CORE_HUMANOID_NODES := [
	"root", "top", "head", "bottom",
	"hipL", "legL", "footL", "toeL",
	"hipR", "legR", "footR", "toeR",
	"shoulderL", "armL", "handL", "fingerL",
	"shoulderR", "armR", "handR", "fingerR",
]
const EXPECTED_GAMEPLAY_CLIPS := [
	"idle", "walk", "run", "idleJump1", "damage", "dead", "guard", "guardParry", "respawn", "castPoint",
	"atkSwordN1", "atkSwordN2", "atkSwordNFinisher", "atkSwordTripleSlash", "atkSwordCrossStrike",
	"atkHammer1fast", "atkHammer2", "atkHammer3", "atkSpear1", "atkTonfa1-punch",
]

static var _juno_bank_cache: Dictionary = {}


static func get_retarget_name(source_animation: String) -> String:
	return str(RETARGET_NAMES.get(source_animation, ""))


static func get_native_name(source_animation: String) -> String:
	return NATIVE_PREFIX + source_animation


static func get_juno_animation_bank() -> Dictionary:
	if not _juno_bank_cache.is_empty():
		return _juno_bank_cache.duplicate(true)
	_juno_bank_cache = JunoGameplayBank.load_gameplay_bank()
	return _juno_bank_cache.duplicate(true)


static func get_juno_locomotion_bank() -> Dictionary:
	var bank := get_juno_animation_bank()
	var result := {}
	for clip in LOCOMOTION_CLIPS:
		var clip_value: Variant = bank.get(clip, null)
		if clip_value is Dictionary and not (clip_value as Dictionary).is_empty():
			result[clip] = (clip_value as Dictionary).duplicate(true)
	return result


static func analyze_profile_compatibility(profile_id: String, rig: Object = null) -> Dictionary:
	var target_nodes := _target_node_set(profile_id, rig)
	var present_core := 0
	var missing_core: Array[String] = []
	for node_name in CORE_HUMANOID_NODES:
		if target_nodes.has(node_name):
			present_core += 1
		else:
			missing_core.append(node_name)

	var bank := get_juno_animation_bank()
	var animated_source_nodes: Dictionary = {}
	for animation_value in bank.values():
		if not animation_value is Dictionary:
			continue
		var transforms_value: Variant = (animation_value as Dictionary).get("transforms", [])
		if not transforms_value is Array:
			continue
		for key_value in transforms_value as Array:
			if not key_value is Dictionary:
				continue
			var node_xfm_value: Variant = (key_value as Dictionary).get("nodeXfm", {})
			if not node_xfm_value is Dictionary:
				continue
			for node_name_value in (node_xfm_value as Dictionary).keys():
				animated_source_nodes[str(node_name_value)] = true

	var transferable := 0
	var source_only: Array[String] = []
	for node_name_value in animated_source_nodes.keys():
		var node_name := str(node_name_value)
		if target_nodes.has(node_name):
			transferable += 1
		else:
			source_only.append(node_name)
	source_only.sort()
	var animated_total := animated_source_nodes.size()
	var coverage := float(transferable) / float(animated_total) if animated_total > 0 else 0.0
	return {
		"profile_id": profile_id,
		"target_node_count": target_nodes.size(),
		"core_present": present_core,
		"core_total": CORE_HUMANOID_NODES.size(),
		"missing_core": missing_core,
		"juno_animation_count": bank.size(),
		"juno_animated_nodes": animated_total,
		"transferable_animated_nodes": transferable,
		"source_only_nodes": source_only,
		"coverage": coverage,
		"structurally_compatible": missing_core.is_empty(),
		"bank_source": JunoGameplayBank.get_source_name(),
	}


static func retarget_juno_animation(profile_id: String, source_animation: String, rig: Object = null) -> Dictionary:
	var bank := get_juno_animation_bank()
	var source_value: Variant = bank.get(source_animation, null)
	if not source_value is Dictionary or (source_value as Dictionary).is_empty():
		return {}
	var target_nodes := _target_node_set(profile_id, rig)
	if target_nodes.is_empty():
		return {}
	return _retarget_animation_data(source_value as Dictionary, source_animation, profile_id, target_nodes)


static func install_juno_gameplay(rig: Object, profile_id: String) -> Dictionary:
	var installed: Array[String] = []
	var preserved_native: Array[String] = []
	var aliases: Array[String] = []
	if rig == null or not rig.has_method("install_runtime_animation") or not rig.has_method("get_animation_data"):
		return {"ok": false, "installed": installed, "preserved_native": preserved_native, "aliases": aliases}

	var target_nodes := _target_node_set(profile_id, rig)
	if target_nodes.is_empty():
		return {"ok": false, "installed": installed, "preserved_native": preserved_native, "aliases": aliases}

	# Preserve every authored Dummy/Male clip before Juno names are overlaid. The
	# browser/editor can still A/B them as native__walk, native__run, etc., while
	# gameplay and the mechanic lab both use the same Juno animation names.
	var native_names: Array[String] = []
	if rig.has_method("get_animation_catalog"):
		var catalog_value: Variant = rig.call("get_animation_catalog")
		if catalog_value is Array:
			for entry_value in catalog_value as Array:
				if entry_value is Dictionary:
					var native_name := str((entry_value as Dictionary).get("name", ""))
					if not native_name.is_empty() and not native_name.begins_with(NATIVE_PREFIX):
						native_names.append(native_name)
	for native_name in native_names:
		var native_value: Variant = rig.call("get_animation_data", native_name)
		if not native_value is Dictionary or (native_value as Dictionary).is_empty():
			continue
		var native_copy := (native_value as Dictionary).duplicate(true)
		native_copy["native_meta"] = {
			"source_profile": profile_id,
			"source_animation": native_name,
			"preserved_before_juno_overlay": true,
		}
		var preserved_name := get_native_name(native_name)
		if bool(rig.call("install_runtime_animation", preserved_name, native_copy)):
			preserved_native.append(preserved_name)

	var bank := get_juno_animation_bank()
	var source_names: Array = bank.keys()
	source_names.sort()
	for source_name_value in source_names:
		var source_name := str(source_name_value)
		var source_value: Variant = bank[source_name_value]
		if not source_value is Dictionary:
			continue
		var retargeted := _retarget_animation_data(source_value as Dictionary, source_name, profile_id, target_nodes)
		if retargeted.is_empty():
			continue
		# Use the original Juno animation name. This is the crucial shared contract:
		# Lab hotkeys, gameplay action maps and equipment-specific attack names all
		# resolve through the exact same animation namespace on the same rig class.
		if bool(rig.call("install_runtime_animation", source_name, retargeted)):
			installed.append(source_name)

	# Keep the three old locomotion aliases alive so existing saves/branches do not
	# break while the canonical names above become authoritative.
	for source_name in LOCOMOTION_CLIPS:
		if source_name not in installed:
			continue
		var alias_name := get_retarget_name(source_name)
		if alias_name.is_empty():
			continue
		var alias_value: Variant = rig.call("get_animation_data", source_name)
		if alias_value is Dictionary and not (alias_value as Dictionary).is_empty():
			var alias_copy := (alias_value as Dictionary).duplicate(true)
			var meta_value: Variant = alias_copy.get("retarget_meta", {})
			var meta: Dictionary = meta_value as Dictionary if meta_value is Dictionary else {}
			meta["compat_alias"] = true
			meta["alias_of"] = source_name
			alias_copy["retarget_meta"] = meta
			if bool(rig.call("install_runtime_animation", alias_name, alias_copy)):
				aliases.append(alias_name)

	var missing_expected: Array[String] = []
	for expected_name in EXPECTED_GAMEPLAY_CLIPS:
		if expected_name not in installed:
			missing_expected.append(expected_name)

	var compatibility := analyze_profile_compatibility(profile_id, rig)
	print("ALABASTER_JUNO_SHARED_RETARGET profile=%s source=%s source_anims=%d installed=%d native_saved=%d missing_expected=%s coverage=%.3f core=%d/%d" % [
		profile_id,
		JunoGameplayBank.get_source_name(),
		bank.size(),
		installed.size(),
		preserved_native.size(),
		str(missing_expected),
		float(compatibility.get("coverage", 0.0)),
		int(compatibility.get("core_present", 0)),
		int(compatibility.get("core_total", 0)),
	])
	return {
		"ok": installed.has("walk") and installed.has("run"),
		"source": JunoGameplayBank.get_source_name(),
		"source_animation_count": bank.size(),
		"installed": installed,
		"installed_count": installed.size(),
		"preserved_native": preserved_native,
		"aliases": aliases,
		"missing_expected": missing_expected,
		"compatibility": compatibility,
	}


static func install_juno_locomotion(rig: Object, profile_id: String) -> Dictionary:
	# Backward-compatible entry point. Locomotion is no longer a special lab-only
	# feature: the entire shared Juno gameplay bank is installed on the playable
	# skin rig so gameplay and every lab/editor see the same animation namespace.
	return install_juno_gameplay(rig, profile_id)


static func _retarget_animation_data(source: Dictionary, source_animation: String, profile_id: String, target_nodes: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var filtered_transforms: Array = []
	var transforms_value: Variant = source.get("transforms", [])
	if transforms_value is Array:
		for key_value in transforms_value as Array:
			if not key_value is Dictionary:
				continue
			var key := (key_value as Dictionary).duplicate(true)
			var filtered_node_xfm := {}
			var node_xfm_value: Variant = key.get("nodeXfm", {})
			if node_xfm_value is Dictionary:
				for node_name_value in (node_xfm_value as Dictionary).keys():
					var node_name := str(node_name_value)
					if target_nodes.has(node_name):
						filtered_node_xfm[node_name] = (node_xfm_value as Dictionary)[node_name_value]
			key["nodeXfm"] = filtered_node_xfm
			filtered_transforms.append(key)
	result["transforms"] = filtered_transforms

	var filtered_nodes := {}
	var nodes_value: Variant = source.get("nodes", {})
	if nodes_value is Dictionary:
		for node_name_value in (nodes_value as Dictionary).keys():
			var node_name := str(node_name_value)
			if target_nodes.has(node_name):
				filtered_nodes[node_name] = (nodes_value as Dictionary)[node_name_value]
	result["nodes"] = filtered_nodes
	result["retarget_meta"] = {
		"source_profile": "juno",
		"target_profile": profile_id,
		"source_animation": source_animation,
		"method": "shared_humanoid_node_filter",
		"bank_source": JunoGameplayBank.get_source_name(),
	}
	return result


static func _target_node_set(profile_id: String, rig: Object = null) -> Dictionary:
	var result := {}
	if rig != null and rig.has_method("get_bone_names"):
		var names_value: Variant = rig.call("get_bone_names")
		if names_value is Array:
			for node_name_value in names_value as Array:
				result[str(node_name_value)] = true
	if result.is_empty():
		var figure := RepoSkinSource.load_skin_figure(profile_id)
		var nodes_value: Variant = figure.get("nodes", {})
		if nodes_value is Dictionary:
			for node_name_value in (nodes_value as Dictionary).keys():
				result[str(node_name_value)] = true
	# These sockets are part of the shared playable rig contract even though the
	# source Dummy/Male JSONs do not author them themselves.
	for socket_name in ["weaponR", "weaponL", "weaponBelt"]:
		result[socket_name] = true
	return result


static func clear_cache() -> void:
	_juno_bank_cache.clear()
	JunoGameplayBank.clear_cache()
