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
const CORE_HUMANOID_NODES := [
	"root", "top", "head", "bottom",
	"hipL", "legL", "footL", "toeL",
	"hipR", "legR", "footR", "toeR",
	"shoulderL", "armL", "handL", "fingerL",
	"shoulderR", "armR", "handR", "fingerR",
]

static var _juno_bank_cache: Dictionary = {}


static func get_retarget_name(source_animation: String) -> String:
	return str(RETARGET_NAMES.get(source_animation, ""))


static func get_juno_locomotion_bank() -> Dictionary:
	if not _juno_bank_cache.is_empty():
		return _juno_bank_cache
	var bank := JunoGameplayBank.load_locomotion_bank()
	for clip in LOCOMOTION_CLIPS:
		var clip_value: Variant = bank.get(clip, null)
		if clip_value is Dictionary and not (clip_value as Dictionary).is_empty():
			_juno_bank_cache[clip] = (clip_value as Dictionary).duplicate(true)
	return _juno_bank_cache


static func analyze_profile_compatibility(profile_id: String) -> Dictionary:
	var figure := RepoSkinSource.load_skin_figure(profile_id)
	var nodes_value: Variant = figure.get("nodes", {})
	var target_nodes: Dictionary = nodes_value as Dictionary if nodes_value is Dictionary else {}
	var present_core := 0
	var missing_core: Array[String] = []
	for node_name in CORE_HUMANOID_NODES:
		if target_nodes.has(node_name):
			present_core += 1
		else:
			missing_core.append(node_name)

	var bank := get_juno_locomotion_bank()
	var animated_source_nodes: Dictionary = {}
	for clip in LOCOMOTION_CLIPS:
		var animation_value: Variant = bank.get(clip, {})
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
		"juno_locomotion_animated_nodes": animated_total,
		"transferable_animated_nodes": transferable,
		"source_only_nodes": source_only,
		"coverage": coverage,
		"structurally_compatible": missing_core.is_empty() and transferable >= CORE_HUMANOID_NODES.size(),
	}


static func retarget_juno_animation(profile_id: String, source_animation: String) -> Dictionary:
	var target_figure := RepoSkinSource.load_skin_figure(profile_id)
	var target_nodes_value: Variant = target_figure.get("nodes", {})
	if not target_nodes_value is Dictionary or (target_nodes_value as Dictionary).is_empty():
		return {}
	var target_nodes := target_nodes_value as Dictionary
	var bank := get_juno_locomotion_bank()
	var source_value: Variant = bank.get(source_animation, {})
	if not source_value is Dictionary or (source_value as Dictionary).is_empty():
		return {}
	var source := source_value as Dictionary
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
	}
	return result


static func install_juno_locomotion(rig: Object, profile_id: String) -> Dictionary:
	var installed: Array[String] = []
	var fallbacks: Array[String] = []
	if rig == null or not rig.has_method("install_runtime_animation"):
		return {"ok": false, "installed": installed, "fallbacks": fallbacks}

	for source_animation in LOCOMOTION_CLIPS:
		var retarget_name := get_retarget_name(source_animation)
		var animation := retarget_juno_animation(profile_id, source_animation)
		if animation.is_empty() and source_animation != "idle" and rig.has_method("get_animation_data"):
			var native_value: Variant = rig.call("get_animation_data", source_animation)
			if native_value is Dictionary and not (native_value as Dictionary).is_empty():
				animation = (native_value as Dictionary).duplicate(true)
				animation["retarget_meta"] = {
					"source_profile": profile_id,
					"target_profile": profile_id,
					"source_animation": source_animation,
					"method": "native_fallback",
				}
				fallbacks.append(source_animation)
		if animation.is_empty():
			continue
		if bool(rig.call("install_runtime_animation", retarget_name, animation)):
			installed.append(retarget_name)

	var compatibility := analyze_profile_compatibility(profile_id)
	print("ALABASTER_JUNO_RETARGET profile=%s installed=%s fallbacks=%s coverage=%.3f core=%d/%d source_only=%s" % [
		profile_id,
		str(installed),
		str(fallbacks),
		float(compatibility.get("coverage", 0.0)),
		int(compatibility.get("core_present", 0)),
		int(compatibility.get("core_total", 0)),
		str(compatibility.get("source_only_nodes", [])),
	])
	return {
		"ok": installed.has(get_retarget_name("walk")) and installed.has(get_retarget_name("run")),
		"installed": installed,
		"fallbacks": fallbacks,
		"compatibility": compatibility,
	}


static func clear_cache() -> void:
	_juno_bank_cache.clear()
	JunoGameplayBank.clear_cache()
