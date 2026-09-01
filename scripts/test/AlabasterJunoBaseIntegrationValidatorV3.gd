extends "res://scripts/test/AlabasterJunoBaseIntegrationValidatorV2.gd"

const COMPLETE_BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const EXPECTED_PREVIEW_PROFILES := ["juno", "juno_base", "male_dummy", "default"]


func _validate_live_tuning() -> bool:
	if not await super._validate_live_tuning():
		return false
	return await _validate_complete_figure_previews()


func _validate_complete_figure_previews() -> bool:
	var packed := load(COMPLETE_BONE_STUDIO_SCENE) as PackedScene
	if packed == null:
		_fail("Bone Studio scene failed to load for complete preview validation")
		return false
	var studio := packed.instantiate()
	root.add_child(studio)
	for _i in range(12):
		await process_frame

	if not studio.has_method("get_editor_preview_profiles") or not studio.has_method("set_editor_preview_profile"):
		_fail("Bone Studio exposes no shared editor figure selector API")
		return false
	var profiles_value: Variant = studio.call("get_editor_preview_profiles")
	if not profiles_value is Array:
		_fail("Bone Studio preview profile list is invalid")
		return false
	var profiles := profiles_value as Array
	if profiles.size() != EXPECTED_PREVIEW_PROFILES.size():
		_fail("Bone Studio editor preview expected four figures, got %s" % str(profiles))
		return false
	for expected in EXPECTED_PREVIEW_PROFILES:
		if not profiles.has(expected):
			_fail("Bone Studio editor preview missing profile %s" % expected)
			return false

	for profile_value in EXPECTED_PREVIEW_PROFILES:
		var profile_id := str(profile_value)
		if not bool(studio.call("set_editor_preview_profile", profile_id)):
			_fail("Bone Studio could not switch editor preview to %s" % profile_id)
			return false
		for _i in range(3):
			await process_frame
		if str(studio.call("get_editor_preview_profile_id")) != profile_id:
			_fail("Bone Studio selector did not retain profile %s" % profile_id)
			return false
		var rig_value: Variant = studio.get("rig")
		if not rig_value is Node2D or not is_instance_valid(rig_value):
			_fail("Bone Studio editor rig invalid for %s" % profile_id)
			return false
		var rig := rig_value as Node2D
		if not rig.has_method("get_bone_names"):
			_fail("Bone Studio editor rig has no bones for %s" % profile_id)
			return false
		var bones_value: Variant = rig.call("get_bone_names")
		if not bones_value is Array or (bones_value as Array).is_empty():
			_fail("Bone Studio editor rig has empty skeleton for %s" % profile_id)
			return false
		if profile_id == "juno_base":
			var summary_value: Variant = rig.call("get_juno_base_profile_summary") if rig.has_method("get_juno_base_profile_summary") else {}
			if not summary_value is Dictionary or not bool((summary_value as Dictionary).get("compact_atlas_active", false)):
				_fail("JunoBase editor preview is not using compact atlas")
				return false
		elif profile_id == "default":
			if str(rig.get("skin_profile_id")) != "default":
				_fail("DEFAULT editor preview instantiated wrong skin")
				return false
		elif profile_id == "male_dummy":
			if str(rig.get("skin_profile_id")) != "male_dummy":
				_fail("DUMMY editor preview instantiated wrong skin")
				return false

	var panel_value: Variant = studio.get("_live_tuning_panel")
	if not panel_value is Control:
		_fail("complete Live Tuning panel failed to initialize")
		return false
	var panel := panel_value as Control
	var targets_value: Variant = panel.get("target_buttons")
	if not targets_value is Dictionary:
		_fail("complete Live Tuning exposes no target buttons")
		return false
	var targets := targets_value as Dictionary
	if targets.has("male_temp"):
		_fail("complete Live Tuning still exposes legacy Male")
		return false
	for expected in EXPECTED_PREVIEW_PROFILES:
		if not targets.has(expected):
			_fail("complete Live Tuning missing target %s" % expected)
			return false

	# Exercise the two newly completed targets through the real Live Tuning path.
	panel.call("_on_target_pressed", "default")
	for _i in range(4):
		await process_frame
	var default_rig_value: Variant = studio.get("rig")
	if not default_rig_value is Node2D or str((default_rig_value as Node2D).get("skin_profile_id")) != "default":
		_fail("Live Tuning DEFAULT target did not instantiate production Default rig")
		return false
	if str(studio.call("get_editor_preview_profile_id")) != "default":
		_fail("Live Tuning DEFAULT target did not synchronize preview selector")
		return false

	panel.call("_on_target_pressed", "juno_base")
	for _i in range(4):
		await process_frame
	var base_rig_value: Variant = studio.get("rig")
	if not base_rig_value is Node2D or not (base_rig_value as Node2D).has_method("get_juno_base_profile_summary"):
		_fail("Live Tuning JunoBase target did not instantiate JunoBase rig")
		return false
	var base_summary_value: Variant = (base_rig_value as Node2D).call("get_juno_base_profile_summary")
	if not base_summary_value is Dictionary or not bool((base_summary_value as Dictionary).get("compact_atlas_active", false)):
		_fail("Live Tuning JunoBase target is not using compact atlas")
		return false
	if str(studio.call("get_editor_preview_profile_id")) != "juno_base":
		_fail("Live Tuning JunoBase target did not synchronize preview selector")
		return false

	print("ALABASTER_BONE_STUDIO_FIGURE_PREVIEWS_OK editor=4 live=4 profiles=juno,juno_base,male_dummy,default male_removed=true")
	studio.queue_free()
	await process_frame
	return true
