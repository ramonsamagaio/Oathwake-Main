extends "res://tools/content_editor/ContentEditorPetSuite.gd"

const MONSTER_RUNTIME_SPEED_FIELD := "runtime_monster_move_speed"
const MONSTER_ATTACK_CONTACT_FRAME_FIELD := "runtime_monster_attack_contact_frame"
const MONSTER_PEACEFUL_FIELD := "runtime_monster_peaceful"
const MONSTER_FEARFUL_FIELD := "runtime_monster_fearful"
const MONSTER_VISUAL_SCALE_FIELD := "runtime_monster_visual_scale"
const MONSTER_PARTICLES_ENABLED_FIELD := "runtime_monster_particles_enabled"
const MONSTER_PARTICLES_AMOUNT_FIELD := "runtime_monster_particles_amount"
const MONSTER_PARTICLES_COLOR_FIELD := "runtime_monster_particles_color"
const MONSTER_PARTICLES_LIFETIME_FIELD := "runtime_monster_particles_lifetime"
const MONSTER_PARTICLES_RADIUS_FIELD := "runtime_monster_particles_radius"
const MONSTER_PARTICLES_SPEED_MIN_FIELD := "runtime_monster_particles_speed_min"
const MONSTER_PARTICLES_SPEED_MAX_FIELD := "runtime_monster_particles_speed_max"
const MONSTER_PARTICLES_GRAVITY_Y_FIELD := "runtime_monster_particles_gravity_y"
const MONSTER_PARTICLES_SCALE_MIN_FIELD := "runtime_monster_particles_scale_min"
const MONSTER_PARTICLES_SCALE_MAX_FIELD := "runtime_monster_particles_scale_max"
const MONSTER_PARTICLES_OFFSET_X_FIELD := "runtime_monster_particles_offset_x"
const MONSTER_PARTICLES_OFFSET_Y_FIELD := "runtime_monster_particles_offset_y"
const PLAYER_PARRY_STUN_FIELD := "runtime_player_parry_stun_seconds"
const PLAYER_DASH_SMOKE_SCALE_FIELD := "runtime_player_dash_smoke_scale"
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

	_add_subsection_title("Visual Size")
	_add_float_spin_box(
		"Sprite Scale Multiplier",
		MONSTER_VISUAL_SCALE_FIELD,
		float(current_record.get("visual_scale", 1.0)),
		0.05,
		16.0,
		0.05
	)

	_add_subsection_title("Disposition")
	var disposition_note := Label.new()
	disposition_note.text = "Peaceful monsters never attack the player. Fearful monsters flee while the player is inside their fear radius. Both flags may be enabled together for passive wildlife."
	disposition_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(disposition_note)
	_add_check_box("Peaceful", MONSTER_PEACEFUL_FIELD, bool(current_record.get("peaceful", false)))
	_add_check_box("Fearful", MONSTER_FEARFUL_FIELD, bool(current_record.get("fearful", false)))

	_add_subsection_title("Particle Emission")
	var particles := _record_dictionary(current_record, "particles")
	var particle_note := Label.new()
	particle_note.text = "Small continuous pixel particles attached to this monster. Enable this for subtle wildlife trails, spores, sparks or magical residue."
	particle_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(particle_note)
	_add_check_box("Enabled", MONSTER_PARTICLES_ENABLED_FIELD, bool(particles.get("enabled", false)))
	_add_spin_box("Amount", MONSTER_PARTICLES_AMOUNT_FIELD, int(particles.get("amount", 5)), 1, 128, 1)
	_add_line_edit("Color", MONSTER_PARTICLES_COLOR_FIELD, str(particles.get("color", "#DDEEFFB3")))
	_add_float_spin_box("Lifetime", MONSTER_PARTICLES_LIFETIME_FIELD, float(particles.get("lifetime", 0.70)), 0.05, 10.0, 0.05)
	_add_float_spin_box("Emission Radius", MONSTER_PARTICLES_RADIUS_FIELD, float(particles.get("emission_radius", 5.0)), 0.0, 256.0, 0.5)
	_add_float_spin_box("Speed Min", MONSTER_PARTICLES_SPEED_MIN_FIELD, float(particles.get("speed_min", 3.0)), 0.0, 1000.0, 0.5)
	_add_float_spin_box("Speed Max", MONSTER_PARTICLES_SPEED_MAX_FIELD, float(particles.get("speed_max", 9.0)), 0.0, 1000.0, 0.5)
	_add_float_spin_box("Gravity Y", MONSTER_PARTICLES_GRAVITY_Y_FIELD, float(particles.get("gravity_y", 5.0)), -1000.0, 1000.0, 0.5)
	_add_float_spin_box("Particle Scale Min", MONSTER_PARTICLES_SCALE_MIN_FIELD, float(particles.get("scale_min", 0.8)), 0.05, 16.0, 0.05)
	_add_float_spin_box("Particle Scale Max", MONSTER_PARTICLES_SCALE_MAX_FIELD, float(particles.get("scale_max", 1.3)), 0.05, 16.0, 0.05)
	_add_float_spin_box("Offset X", MONSTER_PARTICLES_OFFSET_X_FIELD, float(particles.get("offset_x", 0.0)), -512.0, 512.0, 0.5)
	_add_float_spin_box("Offset Y", MONSTER_PARTICLES_OFFSET_Y_FIELD, float(particles.get("offset_y", -18.0)), -512.0, 512.0, 0.5)

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
		record["move_speed"] = movement_speed
	if field_controls.has(MONSTER_VISUAL_SCALE_FIELD):
		record["visual_scale"] = maxf(_get_spin_box_value(MONSTER_VISUAL_SCALE_FIELD), 0.05)
	if field_controls.has(MONSTER_PEACEFUL_FIELD):
		var peaceful_control := field_controls[MONSTER_PEACEFUL_FIELD] as CheckBox
		if peaceful_control != null:
			record["peaceful"] = peaceful_control.button_pressed
	if field_controls.has(MONSTER_FEARFUL_FIELD):
		var fearful_control := field_controls[MONSTER_FEARFUL_FIELD] as CheckBox
		if fearful_control != null:
			record["fearful"] = fearful_control.button_pressed
	if field_controls.has(MONSTER_PARTICLES_ENABLED_FIELD):
		var enabled_control := field_controls[MONSTER_PARTICLES_ENABLED_FIELD] as CheckBox
		var min_speed := maxf(_get_spin_box_value(MONSTER_PARTICLES_SPEED_MIN_FIELD), 0.0)
		var max_speed := maxf(_get_spin_box_value(MONSTER_PARTICLES_SPEED_MAX_FIELD), min_speed)
		var min_scale := maxf(_get_spin_box_value(MONSTER_PARTICLES_SCALE_MIN_FIELD), 0.05)
		var max_scale := maxf(_get_spin_box_value(MONSTER_PARTICLES_SCALE_MAX_FIELD), min_scale)
		record["particles"] = {
			"enabled": enabled_control != null and enabled_control.button_pressed,
			"amount": maxi(_get_spin_box_int(MONSTER_PARTICLES_AMOUNT_FIELD), 1),
			"color": _get_line_edit_text(MONSTER_PARTICLES_COLOR_FIELD).strip_edges(),
			"lifetime": maxf(_get_spin_box_value(MONSTER_PARTICLES_LIFETIME_FIELD), 0.05),
			"emission_radius": maxf(_get_spin_box_value(MONSTER_PARTICLES_RADIUS_FIELD), 0.0),
			"speed_min": min_speed,
			"speed_max": max_speed,
			"gravity_y": _get_spin_box_value(MONSTER_PARTICLES_GRAVITY_Y_FIELD),
			"scale_min": min_scale,
			"scale_max": max_scale,
			"offset_x": _get_spin_box_value(MONSTER_PARTICLES_OFFSET_X_FIELD),
			"offset_y": _get_spin_box_value(MONSTER_PARTICLES_OFFSET_Y_FIELD),
			"z_index": 3,
		}
	if field_controls.has(MONSTER_ATTACK_CONTACT_FRAME_FIELD):
		record["attack_hit_frame"] = maxi(_get_spin_box_int(MONSTER_ATTACK_CONTACT_FRAME_FIELD), 1)
	return record


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Parry & Dash FX")
	var note := Label.new()
	note.text = "Parry stun controls how long the attacker remains stunned. The authored dash smoke plays exactly once per dash; running keeps the lightweight procedural puff."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_float_spin_box(
		"Parry Stun Duration",
		PLAYER_PARRY_STUN_FIELD,
		float(current_record.get("parry_stun_seconds", 1.0)),
		0.05,
		10.0,
		0.05
	)
	_add_float_spin_box(
		"Dash Smoke Sprite Scale",
		PLAYER_DASH_SMOKE_SCALE_FIELD,
		float(current_record.get("dash_smoke_scale", 0.55)),
		0.05,
		8.0,
		0.05
	)


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	if field_controls.has(PLAYER_PARRY_STUN_FIELD):
		record["parry_stun_seconds"] = maxf(_get_spin_box_value(PLAYER_PARRY_STUN_FIELD), 0.05)
	if field_controls.has(PLAYER_DASH_SMOKE_SCALE_FIELD):
		record["dash_smoke_scale"] = maxf(_get_spin_box_value(PLAYER_DASH_SMOKE_SCALE_FIELD), 0.05)
	record["dash_smoke_start_count"] = 0
	record["dash_smoke_end_count"] = 0
	record["dash_smoke_interval"] = maxf(float(record.get("dash_duration", 0.14)) + 1.0, 1.0)
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
