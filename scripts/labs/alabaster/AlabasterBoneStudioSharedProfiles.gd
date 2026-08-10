extends "res://scripts/labs/alabaster/AlabasterBoneStudioProfiles.gd"
class_name AlabasterBoneStudioSharedProfiles

# Thin editor-only presentation layer. Dummy/Male rendering, depth, sockets and
# Juno animation retargeting all live in AlabasterPlayableSkinRig, the exact same
# runtime class used by gameplay. This file only exposes that shared runtime bank
# cleanly in the LOAD EXISTING UI.


func _replace_preview_rig() -> void:
	super._replace_preview_rig()
	if _active_profile == PROFILE_JUNO or rig == null:
		return
	if rig.has_method("has_animation") and bool(rig.call("has_animation", "idle")):
		rig.call("set_animation", "idle")
		if rig.has_method("set_editor_animation_paused"):
			rig.call("set_editor_animation_paused", true)


func _refresh_existing_animation_list() -> void:
	if _existing_option == null:
		return
	_existing_records.clear()
	_existing_option.clear()

	# Native Alabaster source clips + Oathwake custom clips.
	for record in ProfileLibrary.get_animation_records(_active_profile):
		_existing_records.append(record.duplicate(true))

	# Dummy/Male additionally expose every Juno animation actually installed by
	# their shared gameplay rig. Native names may intentionally coexist with a
	# retarget record of the same name: source=builtin loads the untouched native
	# clip, source=retarget loads the Juno-driven version used by gameplay.
	if _active_profile != PROFILE_JUNO and rig != null and rig.has_method("get_animation_catalog") and rig.has_method("get_animation_data"):
		var catalog_value: Variant = rig.call("get_animation_catalog")
		if catalog_value is Array:
			for entry_value in catalog_value as Array:
				if not entry_value is Dictionary:
					continue
				var name := str((entry_value as Dictionary).get("name", ""))
				if name.is_empty() or name.begins_with("native__"):
					continue
				var data_value: Variant = rig.call("get_animation_data", name)
				if not data_value is Dictionary:
					continue
				var meta_value: Variant = (data_value as Dictionary).get("retarget_meta", {})
				if not meta_value is Dictionary:
					continue
				var meta := meta_value as Dictionary
				if str(meta.get("source_profile", "")) != "juno" or bool(meta.get("compat_alias", false)):
					continue
				_existing_records.append({
					"name": name,
					"source": "retarget",
					"read_only": true,
					"target_profile": _active_profile,
				})

	_existing_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var source_order := {"builtin": 0, "retarget": 1, "custom": 2}
		var name_cmp := str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", "")))
		if name_cmp != 0:
			return name_cmp < 0
		return int(source_order.get(str(a.get("source", "custom")), 9)) < int(source_order.get(str(b.get("source", "custom")), 9))
	)

	for record in _existing_records:
		var source := str(record.get("source", "custom"))
		var tag := "ALABASTER ORIGINAL · LOCKED" if source == "builtin" else ("JUNO RETARGET · LOCKED" if source == "retarget" else "CUSTOM · EDITABLE")
		_existing_option.add_item("%s   [%s]" % [str(record.get("name", "")), tag])
		_existing_option.set_item_metadata(_existing_option.item_count - 1, record.duplicate(true))

	if _existing_option.item_count > 0:
		_existing_option.select(0)
		_on_existing_selected(0)
	else:
		_existing_source_label.text = "No animations available for %s." % str(PROFILE_LABELS[_active_profile])
