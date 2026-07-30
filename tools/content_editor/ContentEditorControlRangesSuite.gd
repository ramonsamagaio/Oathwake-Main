extends "res://tools/content_editor/ContentEditorLightEmittersSuite.gd"

const AMBIENT_PARTICLE_ALPHA_MAX := 4.0
const AMBIENT_PARTICLE_ALPHA_FIELDS := [
	"world_particles_day_alpha",
	"world_particles_night_alpha",
]


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
