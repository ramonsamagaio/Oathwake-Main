extends SceneTree

const PixelVFXScript: Script = preload("res://scripts/effects/PixelVFX.gd")
const ContentEditorScript: Script = preload("res://tools/content_editor/ContentEditorControlRangesSuite.gd")
const HitSparksPreviewScript: Script = preload("res://tools/content_editor/previews/HitSparksPreview.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_script_chain()
	await _validate_runtime_contact_lights()
	await _validate_preview()
	if failures.is_empty():
		print("HIT_CONTACT_LIGHT_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("HIT_CONTACT_LIGHT_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_script_chain() -> void:
	if not PixelVFXScript.can_instantiate():
		failures.append("PixelVFX script cannot instantiate.")
	if not ContentEditorScript.can_instantiate():
		failures.append("Content Editor contact-light suite cannot instantiate.")
	if not HitSparksPreviewScript.can_instantiate():
		failures.append("Hit-sparks live preview cannot instantiate.")


func _validate_runtime_contact_lights() -> void:
	var pixel_vfx := PixelVFXScript.new() as Node
	root.add_child(pixel_vfx)
	var world := Node2D.new()
	world.name = "HitContactLightValidationWorld"
	root.add_child(world)
	var profile: Dictionary = {
		"contact_light_enabled": true,
		"contact_light_color": "#FFD78AFF",
		"contact_light_energy": 0.8,
		"contact_light_radius": 40.0,
		"contact_light_duration": 1.0,
		"contact_light_critical_multiplier": 2.0,
	}
	var normal_energy := float(pixel_vfx.call("_resolve_contact_light_peak_energy", profile, false))
	var critical_energy := float(pixel_vfx.call("_resolve_contact_light_peak_energy", profile, true))
	if not is_equal_approx(normal_energy, 0.8):
		failures.append("Normal contact light did not preserve base energy.")
	if not is_equal_approx(critical_energy, normal_energy * 2.0):
		failures.append("Critical contact light is not exactly double normal energy.")

	var contact_position := Vector2(48.0, 72.0)
	var normal_light := pixel_vfx.call("_spawn_contact_light", world, contact_position, profile, false) as PointLight2D
	var critical_light := pixel_vfx.call("_spawn_contact_light", world, contact_position + Vector2(12.0, 0.0), profile, true) as PointLight2D
	if normal_light == null:
		failures.append("Normal hit did not create a PointLight2D.")
	else:
		if normal_light.texture == null or normal_light.texture.get_size() != Vector2(64.0, 64.0):
			failures.append("Normal hit light did not receive the reusable radial texture.")
		if not normal_light.global_position.is_equal_approx(contact_position):
			failures.append("Normal hit light was not placed at the exact contact position.")
		if not is_equal_approx(float(normal_light.get_meta("peak_energy", -1.0)), normal_energy):
			failures.append("Normal hit light metadata does not match resolved energy.")
	if critical_light == null:
		failures.append("Critical hit did not create a PointLight2D.")
	else:
		if not bool(critical_light.get_meta("critical", false)):
			failures.append("Critical hit light was not marked critical.")
		if not is_equal_approx(float(critical_light.get_meta("peak_energy", -1.0)), critical_energy):
			failures.append("Critical hit light did not use doubled peak energy.")

	await process_frame
	world.queue_free()
	pixel_vfx.queue_free()


func _validate_preview() -> void:
	var preview := HitSparksPreviewScript.new() as Control
	if preview == null:
		failures.append("Could not create hit-sparks preview control.")
		return
	preview.size = Vector2(360.0, 220.0)
	root.add_child(preview)
	var profile: Dictionary = {
		"pixel_count": 4,
		"lifetime": 0.12,
		"fade_out_time": 0.08,
		"speed_min": 20.0,
		"speed_max": 40.0,
		"distance": 12.0,
		"jitter_radius": 2.0,
		"horizontal_bias": 0.8,
		"upward_bias": 1.0,
		"gravity": 120.0,
		"size_min": 1.0,
		"size_max": 2.0,
		"contact_light_enabled": true,
		"contact_light_color": "#FFD78AFF",
		"contact_light_energy": 0.8,
		"contact_light_radius": 34.0,
		"contact_light_duration": 0.055,
		"contact_light_critical_multiplier": 2.0,
		"is_critical": true,
	}
	preview.call("set_profile", profile)
	await process_frame
	if not preview.is_processing():
		failures.append("Hit-sparks preview is not processing its light pulse.")
	preview.queue_free()
