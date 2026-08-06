extends "res://tools/content_editor/ContentEditorControlRangesSuite.gd"

const BUTTERFLY_PARTICLE_ENABLED_FIELD := "runtime_monster_particles_enabled"


func _load_record(record_id: String) -> void:
	super._load_record(record_id)
	_sync_butterfly_particle_default()


func _sync_butterfly_particle_default() -> void:
	if current_section != ContentEditorData.SECTION_MONSTERS:
		return
	if str(current_record.get("content_group", "")) != "butterflies":
		return
	var particles_value: Variant = current_record.get("particles", {})
	var particles := particles_value as Dictionary if particles_value is Dictionary else {}
	if particles.has("enabled"):
		return
	var control := field_controls.get(BUTTERFLY_PARTICLE_ENABLED_FIELD) as CheckBox
	if control == null:
		return
	control.set_pressed_no_signal(true)
	set_meta("butterfly_particle_default_synced", true)
