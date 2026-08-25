extends "res://scripts/labs/alabaster/AlabasterBoneStudioWorkspaceViewportFix.gd"

# Keeps the LIVE TUNING global-bank selector synchronized with writes performed
# by the Import/Retarget and Manual Animator tabs during the same Bone Studio
# session. Previously those tabs wrote custom_bone_animations.json correctly,
# but animation_records remained frozen until the panel was rebuilt/reopened.


func refresh_animation_bank(preferred_name: String = "", preferred_profile: String = "juno") -> void:
	_rebuild_animation_records()

	if preferred_name.strip_edges().is_empty() or animation_option == null:
		_rebuild_animation_option()
		return

	# A save from the authoring tabs is explicitly a custom animation operation.
	# Surface that result immediately rather than leaving the user inside a SOURCE
	# filter where the newly saved record is invisible.
	if filter_option != null:
		for index in range(filter_option.item_count):
			if str(filter_option.get_item_metadata(index)) == "CUSTOM":
				filter_option.select(index)
				break
	_rebuild_animation_option()

	for index in range(animation_option.item_count):
		var meta_value: Variant = animation_option.get_item_metadata(index)
		if not meta_value is Dictionary:
			continue
		var record := meta_value as Dictionary
		if str(record.get("name", "")) != preferred_name:
			continue
		if str(record.get("source_profile", "")) != preferred_profile:
			continue
		if str(record.get("source", "")) != "custom":
			continue
		animation_option.select(index)
		_on_animation_selected(index)
		_set_status("Custom bank refreshed: %s is ready for editing." % preferred_name)
		return

	_set_status("Custom bank refreshed, but '%s' was not found for %s." % [preferred_name, preferred_profile], true)
