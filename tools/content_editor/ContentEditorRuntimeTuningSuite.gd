extends "res://tools/content_editor/ContentEditorUsabilitySuite.gd"

const MONSTER_RUNTIME_SPEED_FIELD := "runtime_monster_move_speed"
const EXISTING_MONSTER_SPEED_FIELDS := [
	"move_speed",
	"monster_move_speed",
	"locomotion_move_speed",
	MONSTER_RUNTIME_SPEED_FIELD,
]


func _build_monster_form() -> void:
	super._build_monster_form()
	if _find_existing_monster_speed_field().is_empty():
		var locomotion := _record_dictionary(current_record, "locomotion")
		var current_speed := float(locomotion.get("move_speed", current_record.get("move_speed", 45.0)))
		_add_subsection_title("Monster Locomotion")
		var note := Label.new()
		note.text = "Movement speed is stored in locomotion.move_speed and applied to living monsters immediately after Save."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		form_container.add_child(note)
		_add_float_spin_box("Movement Speed", MONSTER_RUNTIME_SPEED_FIELD, current_speed, 0.0, 1000.0, 0.5)


func _get_monster_form_record() -> Dictionary:
	var record := super._get_monster_form_record()
	if field_controls.has(MONSTER_RUNTIME_SPEED_FIELD):
		var movement_speed := _get_spin_box_value(MONSTER_RUNTIME_SPEED_FIELD)
		var locomotion := _record_dictionary(record, "locomotion")
		locomotion["move_speed"] = movement_speed
		record["locomotion"] = locomotion
		# Keep the legacy mirror for older scenes and tools while locomotion remains
		# the canonical runtime source.
		record["move_speed"] = movement_speed
	return record


func _on_save_pressed() -> void:
	var had_unsaved_changes := has_unsaved_changes
	super._on_save_pressed()
	if had_unsaved_changes and not has_unsaved_changes:
		call_deferred("_reload_runtime_content_after_save")


func _reload_runtime_content_after_save() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("load_all"):
		return
	content_db.call("load_all")
	_refresh_live_players()
	if status_label != null:
		status_label.text = "Saved and applied to the running game."


func _refresh_live_players() -> void:
	for player in get_tree().get_nodes_in_group("player"):
		if player == null or not is_instance_valid(player):
			continue
		for method_name in [
			"_load_player_tuning",
			"_apply_player_visual_tuning",
			"_apply_player_light_tuning",
			"_apply_player_directional_shadow",
			"_update_world_depth",
		]:
			if player.has_method(method_name):
				player.call(method_name)


func _find_existing_monster_speed_field() -> String:
	for field_name in EXISTING_MONSTER_SPEED_FIELDS:
		if field_controls.has(field_name):
			return field_name
	return ""