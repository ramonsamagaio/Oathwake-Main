extends "res://scripts/labs/alabaster/AlabasterBoneStudioLiveTuningV2.gd"
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

	var profile_records: Array = ProfileLibrary.get_animation_records(_active_profile)
	for record_value in profile_records:
		if record_value is Dictionary:
			_existing_records.append((record_value as Dictionary).duplicate(true))

	if _active_profile != PROFILE_JUNO and rig != null and rig.has_method("get_animation_catalog") and rig.has_method("get_animation_data"):
		var catalog_value = rig.call("get_animation_catalog")
		if catalog_value is Array:
			var catalog: Array = catalog_value
			for entry_value in catalog:
				if not entry_value is Dictionary:
					continue
				var entry: Dictionary = entry_value
				var animation_name := str(entry.get("name", ""))
				if animation_name.is_empty() or animation_name.begins_with("native__"):
					continue
				var data_value = rig.call("get_animation_data", animation_name)
				if not data_value is Dictionary:
					continue
				var data: Dictionary = data_value
				var meta_value = data.get("retarget_meta", {})
				if not meta_value is Dictionary:
					continue
				var meta: Dictionary = meta_value
				if str(meta.get("source_profile", "")) != "juno":
					continue
				if bool(meta.get("compat_alias", false)):
					continue
				_existing_records.append({
					"name": animation_name,
					"source": "retarget",
					"read_only": true,
					"target_profile": _active_profile
				})

	_existing_records.sort_custom(_shared_animation_record_less)

	for record_value in _existing_records:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var source := str(record.get("source", "custom"))
		var tag := "CUSTOM · EDITABLE"
		if source == "builtin":
			tag = "ALABASTER ORIGINAL · LOCKED"
		elif source == "retarget":
			tag = "JUNO RETARGET · LOCKED"
		_existing_option.add_item("%s   [%s]" % [str(record.get("name", "")), tag])
		_existing_option.set_item_metadata(_existing_option.item_count - 1, record.duplicate(true))

	if _existing_option.item_count > 0:
		_existing_option.select(0)
		_on_existing_selected(0)
	else:
		_existing_source_label.text = "No animations available for %s." % str(PROFILE_LABELS.get(_active_profile, _active_profile))


func _shared_animation_record_less(a: Dictionary, b: Dictionary) -> bool:
	var name_cmp := str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", "")))
	if name_cmp != 0:
		return name_cmp < 0
	var source_order := {"builtin": 0, "retarget": 1, "custom": 2}
	var a_order := int(source_order.get(str(a.get("source", "custom")), 9))
	var b_order := int(source_order.get(str(b.get("source", "custom")), 9))
	return a_order < b_order
