extends "res://scripts/labs/alabaster/AlabasterBoneStudioPro.gd"

# Stable Bone Studio entry point. Live Tuning is loaded dynamically at runtime,
# while the preview itself starts with the exact BonesSystem used by gameplay.
# The workspace composition adds editor ergonomics without moving them into the
# gameplay runtime.

const LIVE_TUNING_PANEL_PATH = "res://scripts/labs/alabaster/AlabasterBoneStudioJunoBaseLiveTuning.gd"
const SharedJunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")
const SharedJunoBaseRigScript := preload("res://scripts/labs/alabaster/AlabasterJunoBaseRig.gd")
const SharedPlayableSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")
const SharedDefaultRigScript := preload("res://scripts/labs/alabaster/AlabasterDefaultPlayableSkinRig.gd")
const SharedAnimationLibrary := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")

const EDITOR_PROFILE_JUNO := "juno"
const EDITOR_PROFILE_JUNO_BASE := "juno_base"
const EDITOR_PROFILE_DUMMY := "male_dummy"
const EDITOR_PROFILE_DEFAULT := "default"
const EDITOR_PROFILE_ORDER := [
	EDITOR_PROFILE_JUNO,
	EDITOR_PROFILE_JUNO_BASE,
	EDITOR_PROFILE_DUMMY,
	EDITOR_PROFILE_DEFAULT,
]
const EDITOR_PROFILE_LABEL := {
	EDITOR_PROFILE_JUNO: "JUNO",
	EDITOR_PROFILE_JUNO_BASE: "JUNO BASE",
	EDITOR_PROFILE_DUMMY: "DUMMY",
	EDITOR_PROFILE_DEFAULT: "DEFAULT",
}

var _live_tuning_panel: Node = null
var _editor_preview_option: OptionButton = null
var _editor_preview_profile_id := EDITOR_PROFILE_JUNO
var _editor_preview_switching := false


func _build_preview_controls(parent: VBoxContainer) -> void:
	super._build_preview_controls(parent)
	_add_heading(parent, "Editor figure preview")
	_editor_preview_option = OptionButton.new()
	for profile_value in EDITOR_PROFILE_ORDER:
		var profile_id := str(profile_value)
		_editor_preview_option.add_item(str(EDITOR_PROFILE_LABEL.get(profile_id, profile_id.to_upper())))
		_editor_preview_option.set_item_metadata(_editor_preview_option.item_count - 1, profile_id)
	_editor_preview_option.select(0)
	_editor_preview_option.item_selected.connect(_on_editor_preview_selected)
	_editor_preview_option.tooltip_text = "Switch the body used by Import / Retarget and Manual Animator without changing the animation data being edited. LIVE TUNING has the same figures in its own Target figure row."
	_add_row(parent, "Preview body", _editor_preview_option)
	var hint := Label.new()
	hint.text = "IMPORT / RETARGET + ANIMATOR preview. Figure changes preserve the working preview animation when possible."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)


func _build_preview() -> void:
	rig = SharedJunoRigScript.new()
	rig.name = "JunoBoneStudioSharedRig"
	preview_world.add_child(rig)
	rig.scale = Vector2.ONE * 3.2
	if rig.has_method("set_sprite_opacity"):
		rig.call_deferred("set_sprite_opacity", opacity_slider.value)
	if rig.has_method("set_debug_enabled"):
		rig.call_deferred("set_debug_enabled", true)
	if rig.has_method("set_facing_from_vector"):
		rig.call_deferred("set_facing_from_vector", Vector2.DOWN)
	call_deferred("_populate_manual_bones")


func _ready() -> void:
	super._ready()
	_sync_editor_preview_selector(EDITOR_PROFILE_JUNO)
	var panel_script_value: Variant = load(LIVE_TUNING_PANEL_PATH)
	if panel_script_value == null:
		push_error("Bone Studio: Live Tuning workspace could not be loaded. Base editor remains available.")
		return
	if not panel_script_value is Script:
		push_error("Bone Studio: Live Tuning workspace resource is not a Script. Base editor remains available.")
		return
	var panel_value: Variant = (panel_script_value as Script).new()
	if not panel_value is Node:
		push_error("Bone Studio: Live Tuning workspace did not create a Node. Base editor remains available.")
		return
	_live_tuning_panel = panel_value as Node
	_live_tuning_panel.call("setup", self)


func _on_editor_preview_selected(index: int) -> void:
	if _editor_preview_switching or _editor_preview_option == null:
		return
	if index < 0 or index >= _editor_preview_option.item_count:
		return
	set_editor_preview_profile(str(_editor_preview_option.get_item_metadata(index)))


func set_editor_preview_profile(profile_id: String) -> bool:
	if not EDITOR_PROFILE_ORDER.has(profile_id):
		return false
	if _editor_preview_switching:
		return false
	if rig != null and is_instance_valid(rig) and _editor_preview_profile_id == profile_id:
		_sync_editor_preview_selector(profile_id)
		return true

	_editor_preview_switching = true
	var transfer_name := ""
	var transfer_data: Dictionary = {}
	var transfer_time := 0.0
	if rig != null and is_instance_valid(rig):
		transfer_name = str(rig.get("current_animation"))
		transfer_time = float(rig.get("animation_time"))
		if not transfer_name.is_empty() and rig.has_method("get_animation_data"):
			var data_value: Variant = rig.call("get_animation_data", transfer_name)
			if data_value is Dictionary:
				transfer_data = (data_value as Dictionary).duplicate(true)

	var new_rig := _create_editor_preview_rig(profile_id)
	if new_rig == null:
		_editor_preview_switching = false
		_sync_editor_preview_selector(_editor_preview_profile_id)
		return false

	var old_rig = rig
	if old_rig != null and is_instance_valid(old_rig):
		if old_rig.get_parent() != null:
			old_rig.get_parent().remove_child(old_rig)
		old_rig.queue_free()

	preview_world.add_child(new_rig)
	rig = new_rig
	_editor_preview_profile_id = profile_id
	_apply_editor_preview_state(new_rig)

	# Unsaved Import/Retarget and Manual Animator previews live only in memory.
	# Carry that data to the new figure so body switching is a visual operation,
	# not a destructive reset of the animation currently being judged.
	if not transfer_name.is_empty():
		var target_has_animation := bool(new_rig.call("has_animation", transfer_name)) if new_rig.has_method("has_animation") else false
		if not target_has_animation and not transfer_data.is_empty() and new_rig.has_method("install_runtime_animation"):
			new_rig.call("install_runtime_animation", transfer_name, transfer_data)
		if new_rig.has_method("has_animation") and bool(new_rig.call("has_animation", transfer_name)) and new_rig.has_method("set_animation"):
			new_rig.call("set_animation", transfer_name)
			new_rig.set("animation_time", transfer_time)
			if new_rig.has_method("_apply_pose"):
				new_rig.call("_apply_pose")

	call_deferred("_populate_manual_bones")
	call_deferred("_rebuild_mapping_table")
	_sync_editor_preview_selector(profile_id)
	_editor_preview_switching = false
	_set_status("Editor preview body: %s." % str(EDITOR_PROFILE_LABEL.get(profile_id, profile_id.to_upper())))
	return true


func _create_editor_preview_rig(profile_id: String) -> Node2D:
	match profile_id:
		EDITOR_PROFILE_JUNO:
			var juno := SharedJunoRigScript.new() as Node2D
			if juno != null:
				juno.name = "JunoBoneStudioSharedRig"
			return juno
		EDITOR_PROFILE_JUNO_BASE:
			var juno_base := SharedJunoBaseRigScript.new() as Node2D
			if juno_base != null:
				juno_base.name = "JunoBaseBoneStudioSharedRig"
			return juno_base
		EDITOR_PROFILE_DUMMY:
			var dummy := SharedPlayableSkinRigScript.new() as Node2D
			if dummy != null:
				dummy.call("configure_skin_profile", EDITOR_PROFILE_DUMMY)
				dummy.name = "DummyBoneStudioSharedRig"
			return dummy
		EDITOR_PROFILE_DEFAULT:
			var default_rig := SharedDefaultRigScript.new() as Node2D
			if default_rig != null:
				default_rig.name = "DefaultBoneStudioSharedRig"
			return default_rig
	return null


func _apply_editor_preview_state(target: Node2D) -> void:
	target.scale = Vector2.ONE * 3.2
	if target.has_method("set_sprite_opacity") and opacity_slider != null:
		target.call("set_sprite_opacity", opacity_slider.value)
	if target.has_method("set_debug_enabled"):
		target.call("set_debug_enabled", bone_visibility_check == null or bone_visibility_check.button_pressed)
	if target.has_method("set_facing_from_vector"):
		var direction := Vector2.DOWN
		if facing_option != null and facing_option.selected >= 0:
			var direction_value: Variant = facing_option.get_item_metadata(facing_option.selected)
			if direction_value is Vector2:
				direction = direction_value as Vector2
		target.call("set_facing_from_vector", direction)


func _sync_editor_preview_selector(profile_id: String) -> void:
	_editor_preview_profile_id = profile_id
	if _editor_preview_option == null:
		return
	for index in range(_editor_preview_option.item_count):
		if str(_editor_preview_option.get_item_metadata(index)) == profile_id:
			_editor_preview_option.select(index)
			return


func get_editor_preview_profile_id() -> String:
	return _editor_preview_profile_id


func get_editor_preview_profiles() -> Array[String]:
	var result: Array[String] = []
	for value in EDITOR_PROFILE_ORDER:
		result.append(str(value))
	return result


func get_editor_preview_summary() -> Dictionary:
	var runtime_summary: Dictionary = {}
	if rig != null and is_instance_valid(rig) and rig.has_method("get_runtime_summary"):
		var value: Variant = rig.call("get_runtime_summary")
		if value is Dictionary:
			runtime_summary = (value as Dictionary).duplicate(true)
	return {
		"profile": _editor_preview_profile_id,
		"profiles": get_editor_preview_profiles(),
		"rig_valid": rig != null and is_instance_valid(rig),
		"runtime": runtime_summary,
	}


# Import/Retarget and Manual Animator write the same persistent custom bank used
# by LIVE TUNING. Notify the composed panel immediately after a successful save
# so users do not need to restart Bone Studio just to see the new copy.
func _save_import() -> void:
	var animation_name := _sanitize_name(import_name_edit.text)
	super._save_import()
	_queue_live_tuning_bank_refresh(animation_name, "juno")


func _save_manual() -> void:
	var animation_name := _sanitize_name(manual_name_edit.text)
	super._save_manual()
	_queue_live_tuning_bank_refresh(animation_name, "juno")


func _queue_live_tuning_bank_refresh(animation_name: String, profile_id: String) -> void:
	if animation_name.is_empty():
		return
	var record: Dictionary = SharedAnimationLibrary.get_animation_record(profile_id, animation_name)
	if record.is_empty() or str(record.get("source", "")) != "custom":
		return
	call_deferred("_refresh_live_tuning_bank", animation_name, profile_id)


func _refresh_live_tuning_bank(animation_name: String, profile_id: String) -> void:
	if _live_tuning_panel == null or not is_instance_valid(_live_tuning_panel):
		return
	if not _live_tuning_panel.has_method("refresh_animation_bank"):
		return
	_live_tuning_panel.call("refresh_animation_bank", animation_name, profile_id)
