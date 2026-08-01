extends SceneTree

const PixelVFXScript: Script = preload("res://scripts/effects/PixelVFX.gd")
const ContentEditorScript: Script = preload("res://tools/content_editor/ContentEditorControlRangesSuite.gd")
const HitSparksPreviewScript: Script = preload("res://tools/content_editor/previews/HitSparksPreview.gd")

var failures: Array[String] = []


class MockContentDB:
	extends Node

	var profiles: Dictionary = {}

	func has_vfx_profile(profile_id: String) -> bool:
		return profiles.has(profile_id)

	func get_vfx_profile(profile_id: String) -> Dictionary:
		var value: Variant = profiles.get(profile_id, {})
		return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_script_chain()
	await _validate_runtime_contact_lights()
	await _validate_profile_inheritance()
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


func _validate_profile_inheritance() -> void:
	var existing_content_db: Node = root.get_node_or_null("ContentDB")
	var existing_content_db_name := ""
	if existing_content_db != null:
		existing_content_db_name = existing_content_db.name
		existing_content_db.name = "ContentDBValidationBackup"

	var content_db := MockContentDB.new()
	content_db.name = "ContentDB"
	content_db.profiles = {
		"hit_sparks": {
			"pixel_count": 0,
			"contact_light_enabled": true,
			"contact_light_color": "#FFD78AFF",
			"contact_light_energy": 0.8,
			"contact_light_radius": 40.0,
			"contact_light_duration": 1.0,
		},
		"critical_hit_sparks": {
			"pixel_count": 0,
			"contact_light_energy": 9.0,
			"contact_light_radius": 200.0,
			"contact_light_duration": 5.0,
			"contact_light_critical_multiplier": 2.0,
		},
	}
	root.add_child(content_db)

	var pixel_vfx := PixelVFXScript.new() as Node
	pixel_vfx.name = "ProfileInheritancePixelVFX"
	root.add_child(pixel_vfx)
	pixel_vfx.call("spawn_world_hit_sparks", Vector2(80.0, 96.0), false)
	pixel_vfx.call("spawn_world_hit_sparks", Vector2(100.0, 96.0), true)
	await process_frame

	var normal_light := root.get_node_or_null("HitContactLight") as PointLight2D
	var critical_light := root.get_node_or_null("CriticalHitContactLight") as PointLight2D
	if normal_light == null or critical_light == null:
		failures.append("Profile-driven hit path did not create both contact lights.")
	else:
		var normal_peak := float(normal_light.get_meta("peak_energy", -1.0))
		var critical_peak := float(critical_light.get_meta("peak_energy", -1.0))
		if not is_equal_approx(normal_peak, 0.8):
			failures.append("Normal profile base energy was not used by the real hit path.")
		if not is_equal_approx(critical_peak, normal_peak * 2.0):
			failures.append("Critical hit did not inherit normal base energy before multiplying it.")
		if not is_equal_approx(float(critical_light.get_meta("radius", -1.0)), 40.0):
			failures.append("Critical hit did not inherit the normal contact-light radius.")
		if not is_equal_approx(float(critical_light.get_meta("duration", -1.0)), 1.0):
			failures.append("Critical hit did not inherit the normal contact-light duration.")

	if normal_light != null:
		normal_light.queue_free()
	if critical_light != null:
		critical_light.queue_free()
	pixel_vfx.queue_free()
	content_db.queue_free()
	await process_frame
	if existing_content_db != null:
		existing_content_db.name = existing_content_db_name


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
