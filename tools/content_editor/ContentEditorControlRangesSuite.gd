extends "res://tools/content_editor/ContentEditorLightEmittersSuite.gd"

const AMBIENT_PARTICLE_ALPHA_MAX := 4.0


func _build_vfx_profile_form() -> void:
	super._build_vfx_profile_form()
	_expand_ambient_particle_alpha_ranges()


func _build_post_effects_form() -> void:
	super._build_post_effects_form()
	_expand_ambient_particle_alpha_ranges()


func _expand_ambient_particle_alpha_ranges() -> void:
	for field_name in ["world_particles_day_alpha", "world_particles_night_alpha"]:
		var control: Variant = field_controls.get(field_name)
		if control is SpinBox:
			(control as SpinBox).max_value = AMBIENT_PARTICLE_ALPHA_MAX
			(control as SpinBox).tooltip_text = "Visibility multiplier. Values above 1.0 make subtle ambient particles more prominent without changing the saved current value."
