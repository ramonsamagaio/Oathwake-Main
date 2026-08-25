extends SceneTree

const BONE_STUDIO_SCENE := "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn"
const Library := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const TEMP_NAME := "__ci_custom_bank_refresh__"

var _had_bank := false
var _bank_backup := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_backup_bank()
	Library.remove_custom_animation(TEMP_NAME)

	var studio_scene_value: Variant = load(BONE_STUDIO_SCENE)
	if not studio_scene_value is PackedScene:
		_restore_and_fail("Could not load Bone Studio scene.")
		return
	var studio := (studio_scene_value as PackedScene).instantiate()
	root.add_child(studio)
	for _i in range(10):
		await process_frame

	var panel_value: Variant = studio.get("_live_tuning_panel")
	if not panel_value is Node:
		studio.queue_free()
		_restore_and_fail("Bone Studio did not expose the composed Live Tuning panel.")
		return
	var panel := panel_value as Node
	if not panel.has_method("refresh_animation_bank"):
		studio.queue_free()
		_restore_and_fail("Live Tuning panel has no refresh_animation_bank().")
		return

	var sample := {
		"category": "DEFAULT",
		"frameCnt": 2,
		"frameRepeat": 1.0,
		"animStart": 0,
		"loopStart": 0,
		"repeat": true,
		"transforms": [
			{
				"frame": 0,
				"spline": "LINEAR",
				"nodeXfm": {
					"root": {"rot": [0.0, 0.0, 0.0], "trans": [0.0, 0.0, 0.0], "scale": 1.0}
				}
			}
		],
		"nodes": {},
	}
	if not Library.save_custom_animation(TEMP_NAME, sample, {"target_profile": "juno", "source": "ci_bank_refresh"}):
		studio.queue_free()
		_restore_and_fail("Could not save temporary custom animation.")
		return

	panel.call("refresh_animation_bank", TEMP_NAME, "juno")
	await process_frame

	var option_value: Variant = panel.get("animation_option")
	var filter_value: Variant = panel.get("filter_option")
	if not option_value is OptionButton or not filter_value is OptionButton:
		studio.queue_free()
		_restore_and_fail("Live Tuning did not expose animation/filter OptionButtons.")
		return
	var option := option_value as OptionButton
	var filter := filter_value as OptionButton
	var selected_index := option.selected
	if selected_index < 0 or selected_index >= option.item_count:
		studio.queue_free()
		_restore_and_fail("Refresh left the animation list with no selected entry.")
		return
	var selected_meta: Variant = option.get_item_metadata(selected_index)
	if not selected_meta is Dictionary:
		studio.queue_free()
		_restore_and_fail("Selected animation row has no record metadata.")
		return
	var record := selected_meta as Dictionary
	if str(record.get("name", "")) != TEMP_NAME:
		studio.queue_free()
		_restore_and_fail("Refresh selected '%s' instead of the newly saved custom animation." % str(record.get("name", "")))
		return
	if str(record.get("source", "")) != "custom" or str(record.get("source_profile", "")) != "juno":
		studio.queue_free()
		_restore_and_fail("Selected record is not JUNO/CUSTOM: %s" % str(record))
		return
	var filter_meta := str(filter.get_item_metadata(filter.selected)) if filter.selected >= 0 else ""
	if filter_meta != "CUSTOM":
		studio.queue_free()
		_restore_and_fail("Refresh did not switch the animation list to CUSTOM filter. Current=%s" % filter_meta)
		return

	print("ALABASTER_CUSTOM_BANK_REFRESH_OK name=%s source=%s profile=%s filter=%s" % [
		str(record.get("name", "")),
		str(record.get("source", "")),
		str(record.get("source_profile", "")),
		filter_meta,
	])
	studio.queue_free()
	await process_frame
	_restore_bank()
	quit(0)


func _backup_bank() -> void:
	_had_bank = FileAccess.file_exists(Library.CUSTOM_BANK_PATH)
	_bank_backup = FileAccess.get_file_as_string(Library.CUSTOM_BANK_PATH) if _had_bank else ""


func _restore_bank() -> void:
	if _had_bank:
		var file := FileAccess.open(Library.CUSTOM_BANK_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_bank_backup)
			file.flush()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Library.CUSTOM_BANK_PATH))


func _restore_and_fail(message: String) -> void:
	_restore_bank()
	printerr("ALABASTER_CUSTOM_BANK_REFRESH_FAILURE: %s" % message)
	quit(1)
