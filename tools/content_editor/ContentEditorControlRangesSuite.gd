extends "res://tools/content_editor/ContentEditorLightEmittersSuite.gd"

const ShadowProfileLibraryScript := preload("res://scripts/effects/ShadowProfileLibrary.gd")
const AMBIENT_PARTICLE_ALPHA_MAX := 4.0
const AMBIENT_PARTICLE_ALPHA_FIELDS := [
	"world_particles_day_alpha",
	"world_particles_night_alpha",
]
const SPRITE_SHADOW_PROFILE_FIELD := "sprite_shadow_profile_id"
const HIT_CONTACT_LIGHT_ENABLED_FIELD := "contact_light_enabled"
const HIT_CONTACT_LIGHT_COLOR_FIELD := "contact_light_color"
const HIT_CONTACT_LIGHT_ENERGY_FIELD := "contact_light_energy"
const HIT_CONTACT_LIGHT_RADIUS_FIELD := "contact_light_radius"
const HIT_CONTACT_LIGHT_DURATION_FIELD := "contact_light_duration"
const HIT_CONTACT_LIGHT_CRITICAL_MULTIPLIER_FIELD := "contact_light_critical_multiplier"
const HIT_CONTACT_LIGHT_BASE_FIELDS := [
	HIT_CONTACT_LIGHT_ENABLED_FIELD,
	HIT_CONTACT_LIGHT_COLOR_FIELD,
	HIT_CONTACT_LIGHT_ENERGY_FIELD,
	HIT_CONTACT_LIGHT_RADIUS_FIELD,
	HIT_CONTACT_LIGHT_DURATION_FIELD,
]


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


func _add_hit_sparks_profile_fields() -> void:
	super._add_hit_sparks_profile_fields()
	var record_id := str(current_record.get("id", "hit_sparks"))
	if record_id == "critical_hit_sparks":
		_build_critical_hit_contact_light_fields()
		return
	_build_normal_hit_contact_light_fields()


func _build_normal_hit_contact_light_fields() -> void:
	_add_subsection_title("Hit Contact Light")
	var note := Label.new()
	note.text = "Creates a very short real PointLight2D exactly at the contact point. These are the shared base settings for both normal and critical hits."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_check_box(
		"Contact Light Enabled",
		HIT_CONTACT_LIGHT_ENABLED_FIELD,
		bool(current_record.get(HIT_CONTACT_LIGHT_ENABLED_FIELD, true))
	)
	_add_content_color_picker(
		"Contact Light Color",
		HIT_CONTACT_LIGHT_COLOR_FIELD,
		_color_from_value(current_record.get(HIT_CONTACT_LIGHT_COLOR_FIELD, "#FFD78AFF"), Color("#FFD78A"))
	)
	var energy_control := _add_float_spin_box(
		"Base Energy",
		HIT_CONTACT_LIGHT_ENERGY_FIELD,
		float(current_record.get(HIT_CONTACT_LIGHT_ENERGY_FIELD, 0.72)),
		0.0,
		8.0,
		0.01
	)
	energy_control.tooltip_text = "Peak energy of a normal hit. Critical hits use this exact same value multiplied by their critical multiplier."
	var radius_control := _add_float_spin_box(
		"Radius in Pixels",
		HIT_CONTACT_LIGHT_RADIUS_FIELD,
		float(current_record.get(HIT_CONTACT_LIGHT_RADIUS_FIELD, 34.0)),
		1.0,
		256.0,
		1.0
	)
	radius_control.tooltip_text = "World-space radius of the soft radial flash around the contact point."
	var duration_control := _add_float_spin_box(
		"Duration",
		HIT_CONTACT_LIGHT_DURATION_FIELD,
		float(current_record.get(HIT_CONTACT_LIGHT_DURATION_FIELD, 0.055)),
		0.005,
		0.5,
		0.005
	)
	duration_control.suffix = " s"
	duration_control.tooltip_text = "Around 0.04 to 0.08 seconds keeps the hit crisp instead of turning the contact into a lingering lamp."


func _build_critical_hit_contact_light_fields() -> void:
	_add_subsection_title("Critical Hit Contact Light")
	var note := Label.new()
	note.text = "Critical hits inherit Enabled, Color, Base Energy, Radius and Duration from VFX Profiles → Hit Sparks. Only the multiplier differs, so 2.0 always means exactly twice the normal peak light."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_read_only_value("Base Light Source", "VFX Profiles → Hit Sparks")
	var multiplier_control := _add_float_spin_box(
		"Critical Energy Multiplier",
		HIT_CONTACT_LIGHT_CRITICAL_MULTIPLIER_FIELD,
		float(current_record.get(HIT_CONTACT_LIGHT_CRITICAL_MULTIPLIER_FIELD, 2.0)),
		1.0,
		6.0,
		0.05
	)
	multiplier_control.tooltip_text = "2.0 produces exactly twice the peak light energy configured in Hit Sparks."


func _get_vfx_profile_form_record() -> Dictionary:
	var record := super._get_vfx_profile_form_record()
	var record_id := str(record.get("id", current_record.get("id", "")))
	if record_id == "hit_sparks":
		record[HIT_CONTACT_LIGHT_ENABLED_FIELD] = _get_check_box_pressed(HIT_CONTACT_LIGHT_ENABLED_FIELD)
		record[HIT_CONTACT_LIGHT_COLOR_FIELD] = _get_content_color_html(HIT_CONTACT_LIGHT_COLOR_FIELD)
		record[HIT_CONTACT_LIGHT_ENERGY_FIELD] = _get_spin_box_value(HIT_CONTACT_LIGHT_ENERGY_FIELD)
		record[HIT_CONTACT_LIGHT_RADIUS_FIELD] = _get_spin_box_value(HIT_CONTACT_LIGHT_RADIUS_FIELD)
		record[HIT_CONTACT_LIGHT_DURATION_FIELD] = _get_spin_box_value(HIT_CONTACT_LIGHT_DURATION_FIELD)
		record.erase(HIT_CONTACT_LIGHT_CRITICAL_MULTIPLIER_FIELD)
		return record
	if record_id == "critical_hit_sparks":
		for field_name: String in HIT_CONTACT_LIGHT_BASE_FIELDS:
			record.erase(field_name)
		record[HIT_CONTACT_LIGHT_CRITICAL_MULTIPLIER_FIELD] = _get_spin_box_value(HIT_CONTACT_LIGHT_CRITICAL_MULTIPLIER_FIELD)
	return record


func _load_any_image_texture(path: String) -> Texture2D:
	# Resource textures should stay on Godot's imported path. External files need
	# an ImageTexture, but Image.load() can transiently return OK with a zero-sized
	# image while an editor import or preview refresh is still settling. Never pass
	# that empty image into ImageTexture.create_from_image().
	if path.begins_with("res://") or path.begins_with("user://"):
		var resource := load(path)
		if resource is Texture2D:
			var resource_texture := resource as Texture2D
			var resource_size := resource_texture.get_size()
			if resource_size.x > 0.0 and resource_size.y > 0.0:
				return resource_texture
		return null

	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK or image.is_empty() or image.get_width() <= 0 or image.get_height() <= 0:
		return null
	return ImageTexture.create_from_image(image)


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
