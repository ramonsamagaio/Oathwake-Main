extends "res://tools/content_editor/ContentEditorUsabilitySuite.gd"

const MONSTER_RUNTIME_SPEED_FIELD := "runtime_monster_move_speed"
const MONSTER_ATTACK_CONTACT_FRAME_FIELD := "runtime_monster_attack_contact_frame"
const EXISTING_MONSTER_SPEED_FIELDS := [
	"move_speed",
	"monster_move_speed",
	"locomotion_move_speed",
	MONSTER_RUNTIME_SPEED_FIELD,
]
const EMBEDDED_MAXIMIZE_MARGIN := 8

var _runtime_shutting_down := false
var _embedded_editor_maximized := false
var _embedded_restore_position := Vector2i.ZERO
var _embedded_restore_size := Vector2i.ZERO


func prepare_for_runtime_close() -> void:
	if _runtime_shutting_down:
		return
	_runtime_shutting_down = true
	animation_preview_playing = false
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	process_mode = Node.PROCESS_MODE_DISABLED
	for window_value in [texture_file_dialog, batch_sprite_file_dialog, batch_sprite_window]:
		if window_value is Window and is_instance_valid(window_value):
			(window_value as Window).hide()


func _exit_tree() -> void:
	_runtime_shutting_down = true
	animation_preview_playing = false


func _process(delta: float) -> void:
	if _runtime_shutting_down or not is_inside_tree():
		return
	super._process(delta)


func _fit_root_to_viewport() -> void:
	if _runtime_shutting_down or not is_inside_tree():
		return
	super._fit_root_to_viewport()


func _install_workspace_usability() -> void:
	if _runtime_shutting_down or not is_inside_tree():
		return
	super._install_workspace_usability()


func _request_close_editor() -> void:
	prepare_for_runtime_close()
	super._request_close_editor()


func _toggle_editor_maximize() -> void:
	if _runtime_shutting_down:
		return
	var window := get_window()
	if window == null:
		return
	if not window.is_embedded():
		super._toggle_editor_maximize()
		return

	var embedder := window.get_parent() as Window
	if embedder == null:
		return
	if _embedded_editor_maximized:
		if _embedded_restore_size.x > 0 and _embedded_restore_size.y > 0:
			window.size = _embedded_restore_size
			window.position = _embedded_restore_position
		_embedded_editor_maximized = false
		if _maximize_button != null:
			_maximize_button.text = "Maximize Editor"
		return

	_embedded_restore_position = window.position
	_embedded_restore_size = window.size
	var available_size := Vector2i(embedder.get_visible_rect().size)
	if available_size.x <= 0 or available_size.y <= 0:
		available_size = embedder.size
	window.position = Vector2i(EMBEDDED_MAXIMIZE_MARGIN, EMBEDDED_MAXIMIZE_MARGIN)
	window.size = Vector2i(
		maxi(1, available_size.x - EMBEDDED_MAXIMIZE_MARGIN * 2),
		maxi(1, available_size.y - EMBEDDED_MAXIMIZE_MARGIN * 2)
	)
	_embedded_editor_maximized = true
	if _maximize_button != null:
		_maximize_button.text = "Restore Editor"


func _build_monster_form() -> void:
	super._build_monster_form()
	if _find_existing_monster_speed_field().is_empty():
		var locomotion := _record_dictionary(current_record, "locomotion")
		var current_speed := float(locomotion.get("move_speed", current_record.get("move_speed", 45.0)))
		_add_subsection_title("Monster Locomotion")
		var note := Label.new()
		note.text = "Movement speed is stored in locomotion.move_speed and applied to living monsters immediately after Save. Monsters outside the active camera view remain idle until they enter the screen."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		form_container.add_child(note)
		_add_float_spin_box("Movement Speed", MONSTER_RUNTIME_SPEED_FIELD, current_speed, 0.0, 1000.0, 0.5)

	_add_subsection_title("Attack Contact")
	var attack_note := Label.new()
	attack_note.text = "Choose the visible attack-animation frame that actually touches the player. Frame 1 is the first frame; preparation frames before the selected contact frame do not deal damage."
	attack_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(attack_note)
	var fallback_frame := 5 if str(current_record.get("id", "")) == "slime" else (2 if str(current_record.get("id", "")) == "skeleton" else 1)
	_add_spin_box(
		"Attack Contact Frame",
		MONSTER_ATTACK_CONTACT_FRAME_FIELD,
		maxi(int(current_record.get("attack_hit_frame", fallback_frame)), 1),
		1,
		64,
		1
	)


func _get_monster_form_record() -> Dictionary:
	var record := super._get_monster_form_record()
	var speed_field := _find_existing_monster_speed_field()
	if not speed_field.is_empty():
		var movement_speed := _get_spin_box_value(speed_field)
		var locomotion := _record_dictionary(record, "locomotion")
		locomotion["move_speed"] = movement_speed
		record["locomotion"] = locomotion
		# Keep the legacy mirror for older scenes and tools while locomotion remains
		# the canonical runtime source.
		record["move_speed"] = movement_speed
	if field_controls.has(MONSTER_ATTACK_CONTACT_FRAME_FIELD):
		record["attack_hit_frame"] = maxi(_get_spin_box_int(MONSTER_ATTACK_CONTACT_FRAME_FIELD), 1)
	return record


func _on_save_pressed() -> void:
	if _runtime_shutting_down:
		return
	var had_unsaved_changes := has_unsaved_changes
	super._on_save_pressed()
	if had_unsaved_changes and not has_unsaved_changes:
		call_deferred("_reload_runtime_content_after_save")


func _reload_runtime_content_after_save() -> void:
	if _runtime_shutting_down or not is_inside_tree():
		return
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("load_all"):
		return
	content_db.call("load_all")
	_refresh_live_players()
	if status_label != null:
		status_label.text = "Saved and applied to the running game."


func _refresh_live_players() -> void:
	if _runtime_shutting_down or get_tree() == null:
		return
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
