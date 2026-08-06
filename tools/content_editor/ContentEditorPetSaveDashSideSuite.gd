extends "res://tools/content_editor/ContentEditorButterflyParticleDefaultsSuite.gd"

const PLAYER_STAMINA_REGEN_FIELD := "runtime_player_stamina_regeneration_per_second"
const PLAYER_STAMINA_REGEN_DELAY_FIELD := "runtime_player_stamina_regeneration_delay_seconds"
const FIXED_DASH_STAMINA_COST := 10.0
const DEFAULT_STAMINA_REGEN_PER_SECOND := 30.0
const DEFAULT_STAMINA_REGEN_DELAY_SECONDS := 0.65

const PARTICLE_MODE_OPTIONS := ["attached", "trail"]
const MONSTER_PARTICLE_MODE_FIELD := "runtime_monster_particles_mode"
const MONSTER_PARTICLE_SIZE_FIELD := "runtime_monster_particles_size_multiplier"
const MONSTER_PARTICLE_SCALE_WITH_VISUAL_FIELD := "runtime_monster_particles_scale_with_visual"
const MONSTER_PARTICLE_FADE_FIELD := "runtime_monster_particles_fade_out"

const PET_PARTICLE_ENABLED_FIELD := "pet_particles_enabled"
const PET_PARTICLE_MODE_FIELD := "pet_particles_mode"
const PET_PARTICLE_AMOUNT_FIELD := "pet_particles_amount"
const PET_PARTICLE_COLOR_FIELD := "pet_particles_color"
const PET_PARTICLE_LIFETIME_FIELD := "pet_particles_lifetime"
const PET_PARTICLE_RADIUS_FIELD := "pet_particles_radius"
const PET_PARTICLE_SPEED_MIN_FIELD := "pet_particles_speed_min"
const PET_PARTICLE_SPEED_MAX_FIELD := "pet_particles_speed_max"
const PET_PARTICLE_SIZE_FIELD := "pet_particles_size_multiplier"
const PET_PARTICLE_SCALE_WITH_VISUAL_FIELD := "pet_particles_scale_with_visual"
const PET_PARTICLE_FADE_FIELD := "pet_particles_fade_out"
const PET_PARTICLE_OFFSET_X_FIELD := "pet_particles_offset_x"
const PET_PARTICLE_OFFSET_Y_FIELD := "pet_particles_offset_y"


func _update_action_buttons() -> void:
	super._update_action_buttons()
	if current_section != SECTION_PETS:
		return

	# Pets are stored in the supplemental pet_items.json file and therefore are
	# not part of ContentEditorData.SECTIONS. Explicitly grant the same editing
	# controls as the regular data-backed sections.
	var has_record := not current_record.is_empty()
	new_button.disabled = has_unsaved_changes
	duplicate_button.disabled = has_unsaved_changes or current_original_id.is_empty()
	delete_button.disabled = true
	save_button.disabled = not has_record
	revert_button.disabled = not has_record
	reload_current_button.disabled = not has_record


func _build_monster_form() -> void:
	super._build_monster_form()
	var particles := _dictionary_value(current_record.get("particles", {}))
	var is_butterfly := str(current_record.get("content_group", "")) == "butterflies"
	var default_mode := "trail" if is_butterfly else "attached"

	_add_subsection_title("Particle Behavior")
	var note := Label.new()
	note.text = "Attached particles travel with the monster. Trail particles remain in world space where the sprite passed, move only a few pixels and fade away."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_string_option_button(
		"Particle Type",
		MONSTER_PARTICLE_MODE_FIELD,
		PARTICLE_MODE_OPTIONS,
		_normalize_particle_mode(str(particles.get("mode", default_mode)))
	)
	var size_control := _add_float_spin_box(
		"Particle Size Multiplier",
		MONSTER_PARTICLE_SIZE_FIELD,
		float(particles.get("size_multiplier", 1.0)),
		0.05,
		16.0,
		0.05
	)
	size_control.tooltip_text = "Multiplies the configured particle size without changing the monster sprite."
	_add_check_box(
		"Match Monster Visual Scale",
		MONSTER_PARTICLE_SCALE_WITH_VISUAL_FIELD,
		bool(particles.get("scale_with_visual", is_butterfly))
	)
	_add_check_box(
		"Fade Out",
		MONSTER_PARTICLE_FADE_FIELD,
		bool(particles.get("fade_out", _normalize_particle_mode(str(particles.get("mode", default_mode))) == "trail"))
	)


func _get_monster_form_record() -> Dictionary:
	var record := super._get_monster_form_record()
	if not field_controls.has(MONSTER_PARTICLE_MODE_FIELD):
		return record
	var particles := _dictionary_value(record.get("particles", {}))
	particles["mode"] = _normalize_particle_mode(str(_get_option_button_metadata(MONSTER_PARTICLE_MODE_FIELD)))
	particles["size_multiplier"] = maxf(_get_spin_box_value(MONSTER_PARTICLE_SIZE_FIELD), 0.05)
	particles["scale_with_visual"] = _check_box_value(MONSTER_PARTICLE_SCALE_WITH_VISUAL_FIELD, false)
	particles["fade_out"] = _check_box_value(MONSTER_PARTICLE_FADE_FIELD, particles["mode"] == "trail")
	record["particles"] = particles
	return record


func _build_pet_form() -> void:
	super._build_pet_form()
	var particles := _dictionary_value(current_record.get("particles", {}))
	var is_butterfly := str(current_record.get("pet_family", "butterfly")) == "butterfly"
	var default_mode := "trail" if is_butterfly else "attached"
	var mode := _normalize_particle_mode(str(particles.get("mode", default_mode)))

	_add_subsection_title("Optional Pet Particles")
	var note := Label.new()
	note.text = "Trail leaves fading pixels behind the pet in world space. Attached keeps particles bound to the pet. Match Pet Visual Scale prevents particles from looking oversized when the sprite is reduced."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_check_box("Enabled", PET_PARTICLE_ENABLED_FIELD, bool(particles.get("enabled", is_butterfly)))
	_add_string_option_button("Particle Type", PET_PARTICLE_MODE_FIELD, PARTICLE_MODE_OPTIONS, mode)
	_add_spin_box("Amount", PET_PARTICLE_AMOUNT_FIELD, int(particles.get("amount", 8 if mode == "trail" else 5)), 1, 128, 1)
	_add_line_edit("Color", PET_PARTICLE_COLOR_FIELD, str(particles.get("color", "#DDEEFFB3")))
	_add_float_spin_box("Lifetime", PET_PARTICLE_LIFETIME_FIELD, float(particles.get("lifetime", 0.90 if mode == "trail" else 0.70)), 0.05, 10.0, 0.05)
	_add_float_spin_box("Emission Radius", PET_PARTICLE_RADIUS_FIELD, float(particles.get("emission_radius", 2.0 if mode == "trail" else 5.0)), 0.0, 256.0, 0.5)
	_add_float_spin_box("Speed Min", PET_PARTICLE_SPEED_MIN_FIELD, float(particles.get("speed_min", 0.8 if mode == "trail" else 3.0)), 0.0, 1000.0, 0.1)
	_add_float_spin_box("Speed Max", PET_PARTICLE_SPEED_MAX_FIELD, float(particles.get("speed_max", 2.5 if mode == "trail" else 9.0)), 0.0, 1000.0, 0.1)
	_add_float_spin_box("Particle Size Multiplier", PET_PARTICLE_SIZE_FIELD, float(particles.get("size_multiplier", 1.0)), 0.05, 16.0, 0.05)
	_add_check_box("Match Pet Visual Scale", PET_PARTICLE_SCALE_WITH_VISUAL_FIELD, bool(particles.get("scale_with_visual", is_butterfly)))
	_add_check_box("Fade Out", PET_PARTICLE_FADE_FIELD, bool(particles.get("fade_out", mode == "trail")))
	_add_float_spin_box("Offset X", PET_PARTICLE_OFFSET_X_FIELD, float(particles.get("offset_x", 0.0)), -512.0, 512.0, 0.5)
	_add_float_spin_box("Offset Y", PET_PARTICLE_OFFSET_Y_FIELD, float(particles.get("offset_y", -18.0)), -512.0, 512.0, 0.5)


func _save_current_pet() -> void:
	if field_controls.has(PET_PARTICLE_ENABLED_FIELD):
		current_record["particles"] = _pet_particle_record_from_form()
	super._save_current_pet()


func _pet_particle_record_from_form() -> Dictionary:
	var previous := _dictionary_value(current_record.get("particles", {}))
	var mode := _normalize_particle_mode(str(_get_option_button_metadata(PET_PARTICLE_MODE_FIELD)))
	var minimum_speed := maxf(_get_spin_box_value(PET_PARTICLE_SPEED_MIN_FIELD), 0.0)
	var maximum_speed := maxf(_get_spin_box_value(PET_PARTICLE_SPEED_MAX_FIELD), minimum_speed)
	return {
		"enabled": _check_box_value(PET_PARTICLE_ENABLED_FIELD, true),
		"mode": mode,
		"amount": maxi(_get_spin_box_int(PET_PARTICLE_AMOUNT_FIELD), 1),
		"color": _get_line_edit_text(PET_PARTICLE_COLOR_FIELD).strip_edges(),
		"lifetime": maxf(_get_spin_box_value(PET_PARTICLE_LIFETIME_FIELD), 0.05),
		"emission_radius": maxf(_get_spin_box_value(PET_PARTICLE_RADIUS_FIELD), 0.0),
		"speed_min": minimum_speed,
		"speed_max": maximum_speed,
		"gravity_x": float(previous.get("gravity_x", 0.0)),
		"gravity_y": float(previous.get("gravity_y", 0.0 if mode == "trail" else 5.0)),
		"scale_min": maxf(float(previous.get("scale_min", 0.45 if mode == "trail" else 0.8)), 0.01),
		"scale_max": maxf(float(previous.get("scale_max", 0.80 if mode == "trail" else 1.3)), 0.01),
		"size_multiplier": maxf(_get_spin_box_value(PET_PARTICLE_SIZE_FIELD), 0.05),
		"scale_with_visual": _check_box_value(PET_PARTICLE_SCALE_WITH_VISUAL_FIELD, true),
		"fade_out": _check_box_value(PET_PARTICLE_FADE_FIELD, mode == "trail"),
		"offset_x": _get_spin_box_value(PET_PARTICLE_OFFSET_X_FIELD),
		"offset_y": _get_spin_box_value(PET_PARTICLE_OFFSET_Y_FIELD),
		"z_index": int(previous.get("z_index", 3)),
	}


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Stamina")
	var note := Label.new()
	note.text = "Every successful dash spends exactly 10 stamina and restarts the regeneration delay. This prevents the dash cooldown from refunding its full cost before the next dash."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_read_only_value("Dash Stamina Cost", "10")
	var regen_control := _add_float_spin_box(
		"Stamina Regeneration / Second",
		PLAYER_STAMINA_REGEN_FIELD,
		float(current_record.get("stamina_regeneration_per_second", DEFAULT_STAMINA_REGEN_PER_SECOND)),
		0.0,
		500.0,
		0.5
	)
	regen_control.tooltip_text = "How many stamina points recover per second after the regeneration delay finishes."
	var delay_control := _add_float_spin_box(
		"Regeneration Delay After Dash",
		PLAYER_STAMINA_REGEN_DELAY_FIELD,
		float(current_record.get("stamina_regeneration_delay_seconds", DEFAULT_STAMINA_REGEN_DELAY_SECONDS)),
		0.0,
		10.0,
		0.05
	)
	delay_control.suffix = " s"
	delay_control.tooltip_text = "Each successful dash restarts this timer. At 0.65 seconds, repeated dashes consume stamina instead of immediately recovering it."
	_add_read_only_value(
		"Dash Smoke Direction",
		"Derived from the lateral dash: left dash uses the left-facing sprite and right dash uses the right-facing sprite. Vertical dashes do not use this sheet."
	)


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	if field_controls.has(PLAYER_STAMINA_REGEN_FIELD):
		record["stamina_regeneration_per_second"] = maxf(_get_spin_box_value(PLAYER_STAMINA_REGEN_FIELD), 0.0)
	if field_controls.has(PLAYER_STAMINA_REGEN_DELAY_FIELD):
		record["stamina_regeneration_delay_seconds"] = maxf(_get_spin_box_value(PLAYER_STAMINA_REGEN_DELAY_FIELD), 0.0)
	record["max_stamina"] = maxf(float(record.get("max_stamina", 100.0)), 1.0)
	record["dash_stamina_cost"] = FIXED_DASH_STAMINA_COST
	record.erase("dash_smoke_facing")
	return record


func _normalize_particle_mode(value: String) -> String:
	return "attached" if value.strip_edges().to_lower() == "attached" else "trail"


func _dictionary_value(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _check_box_value(field_name: String, fallback: bool) -> bool:
	var control := field_controls.get(field_name) as CheckBox
	return control.button_pressed if control != null else fallback
