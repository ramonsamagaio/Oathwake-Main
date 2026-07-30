extends "res://tools/content_editor/ContentEditorLightEmittersSuite.gd"

const ShadowProfileLibraryScript := preload("res://scripts/effects/ShadowProfileLibrary.gd")
const AMBIENT_PARTICLE_ALPHA_MAX := 4.0
const AMBIENT_PARTICLE_ALPHA_FIELDS := [
	"world_particles_day_alpha",
	"world_particles_night_alpha",
]
const SPRITE_SHADOW_PROFILE_FIELD := "sprite_shadow_profile_id"


func _build_sprite_form() -> void:
	super._build_sprite_form()
	_add_subsection_title("Solar Shadow Profile")
	var note := Label.new()
	note.text = "Auto uses the universal classifier. Choose a specific profile when this authored sprite needs a deliberate shadow shape, such as a stump using Tree / Trunk or a fence using Thin Post / Fence Segment."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	var options: Array = ["auto"]
	options.append_array(ShadowProfileLibraryScript.get_profile_ids())
	_add_string_option_button(
		"Profile Override",
		SPRITE_SHADOW_PROFILE_FIELD,
		options,
		str(current_record.get("shadow_profile_id", "auto"))
	)


func _get_sprite_form_record() -> Dictionary:
	var record := super._get_sprite_form_record()
	if field_controls.has(SPRITE_SHADOW_PROFILE_FIELD):
		record["shadow_profile_id"] = _selected_option_value(SPRITE_SHADOW_PROFILE_FIELD, "auto")
	return record


func _add_float_spin_box(
	label_text: String,
	field_name: String,
	value: float,
	minimum: float,
	maximum: float,
	step: float
) -> SpinBox:
	# Set the ambient-particle range when the control is created. The previous
	# post-build patch was timing-dependent because Post Effects rebuilds and hides
	# form rows after the inherited form has already been assembled.
	var resolved_maximum := AMBIENT_PARTICLE_ALPHA_MAX if AMBIENT_PARTICLE_ALPHA_FIELDS.has(field_name) else maximum
	var spin_box := super._add_float_spin_box(label_text, field_name, value, minimum, resolved_maximum, step)
	if AMBIENT_PARTICLE_ALPHA_FIELDS.has(field_name):
		spin_box.max_value = AMBIENT_PARTICLE_ALPHA_MAX
		spin_box.tooltip_text = "Visibility multiplier. Values above 1.0 make subtle ambient particles more prominent without changing the saved current value."
		spin_box.set_meta("ambient_particle_alpha_max", AMBIENT_PARTICLE_ALPHA_MAX)
	return spin_box
