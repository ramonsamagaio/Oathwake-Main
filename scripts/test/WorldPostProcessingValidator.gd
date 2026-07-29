extends SceneTree

const SCREEN_EFFECTS_SCENE := preload("res://scenes/effects/ScreenEffects.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var post := _validate_content_contract()
	_validate_shader_contract()
	await _validate_runtime_contract(post)
	if failures.is_empty():
		print("WORLD_POST_PROCESSING_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("WORLD_POST_PROCESSING_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_content_contract() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx_profiles.json"))
	if not (parsed is Dictionary):
		failures.append("vfx_profiles.json is invalid.")
		return {}
	var default_profile: Variant = (parsed as Dictionary).get("default", {})
	var world_visuals: Variant = (default_profile as Dictionary).get("world_visuals", {}) if default_profile is Dictionary else {}
	var post: Variant = (world_visuals as Dictionary).get("post_processing", {}) if world_visuals is Dictionary else {}
	if not (post is Dictionary):
		failures.append("Default VFX profile has no post_processing block.")
		return {}
	var post_data := post as Dictionary
	for required_key in [
		"bloom_enabled", "selective_bloom_enabled", "emissive_chroma_threshold",
		"neutral_suppression", "grading_enabled", "day_tint", "night_tint",
		"warm_light_preservation",
	]:
		if not post_data.has(required_key):
			failures.append("post_processing is missing %s." % required_key)
	if not bool(post_data.get("selective_bloom_enabled", false)):
		failures.append("Selective bloom is disabled in the default profile.")
	if not bool(post_data.get("grading_enabled", false)):
		failures.append("Time-aware grading is disabled in the default profile.")
	if float(post_data.get("neutral_suppression", 0.0)) <= 0.0:
		failures.append("Neutral terrain suppression is disabled.")
	if float(post_data.get("warm_light_preservation", 0.0)) <= 0.0:
		failures.append("Warm light preservation is disabled.")
	var editor_text := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorPostProcessSuite.gd")
	for label in ["Selective Emissive Bloom", "Time-Aware Color Grading", "Warm Light Preservation", "Local Light Night Mask", "Protect Player-Lit Area"]:
		if not editor_text.contains(label):
			failures.append("Content Editor post-processing controls are missing %s." % label)
	return post_data


func _validate_shader_contract() -> void:
	var shader_text := FileAccess.get_file_as_string("res://shaders/gaussian_glow_screen.gdshader")
	for token in [
		"selective_bloom_enabled", "emissive_chroma_threshold", "neutral_suppression",
		"apply_world_grading", "night_strength", "warm_light_preservation",
		"night_cool_shadow_strength", "local_light_grading_mask_enabled",
		"oath_local_light_mask", "local_light_grading_protection",
	]:
		if not shader_text.contains(token):
			failures.append("Unified screen shader is missing %s." % token)
	if shader_text.contains("for ("):
		failures.append("Screen compositor introduced a dynamic shader loop.")


func _validate_runtime_contract(post: Dictionary) -> void:
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	var screen_effects := SCREEN_EFFECTS_SCENE.instantiate()
	root.add_child(screen_effects)
	await process_frame
	await process_frame
	var compositor := screen_effects.get_node_or_null("GaussianGlow") as ColorRect
	var back_buffer := screen_effects.get_node_or_null("BackBufferCopy") as BackBufferCopy
	if compositor == null or not (compositor.material is ShaderMaterial):
		failures.append("ScreenEffects has no unified compositor material.")
		_cleanup(screen_effects, player)
		return
	var material := compositor.material as ShaderMaterial
	if not compositor.visible:
		failures.append("Unified compositor is not visible while grading is enabled.")
	if back_buffer == null or back_buffer.copy_mode == BackBufferCopy.COPY_MODE_DISABLED:
		failures.append("BackBufferCopy is disabled while post-processing is enabled.")
	if not bool(material.get_shader_parameter("selective_bloom_enabled")):
		failures.append("Runtime material did not enable selective bloom.")
	if not bool(material.get_shader_parameter("grading_enabled")):
		failures.append("Runtime material did not enable color grading.")
	if not is_equal_approx(float(material.get_shader_parameter("neutral_suppression")), float(post.get("neutral_suppression", -1.0))):
		failures.append("Runtime neutral suppression does not match content data.")
	if not is_equal_approx(float(material.get_shader_parameter("warm_light_preservation")), float(post.get("warm_light_preservation", -1.0))):
		failures.append("Runtime warm light preservation does not match content data.")
	if not bool(material.get_shader_parameter("local_light_grading_mask_enabled")):
		failures.append("Runtime local-light grading mask is disabled.")

	if screen_effects.has_method("set_day_night_strength"):
		screen_effects.set_process(false)
		var player_light := player.get_node_or_null("NightLight")
		if player_light != null and player_light.has_method("set_day_night_strength"):
			player_light.call("set_day_night_strength", 1.0)
		screen_effects.call("set_day_night_strength", 1.0)
		screen_effects.call("_sync_local_light_grading_mask")
		if not is_equal_approx(float(material.get_shader_parameter("night_strength")), 1.0):
			failures.append("Screen compositor did not receive full night strength.")
		if not bool(material.get_shader_parameter("local_light_source_active")):
			failures.append("Player PointLight2D did not activate the night-grading protection mask.")
		var mask_radius_value: Variant = material.get_shader_parameter("local_light_radius_uv")
		if not (mask_radius_value is Vector2) or (mask_radius_value as Vector2).x <= 0.0 or (mask_radius_value as Vector2).y <= 0.0:
			failures.append("Player light protection mask has no elliptical radius.")
		elif player_light is Node2D and (player_light as Node2D).scale.y < (player_light as Node2D).scale.x:
			var viewport_size := root.get_visible_rect().size
			var pixel_radius := Vector2((mask_radius_value as Vector2).x * viewport_size.x, (mask_radius_value as Vector2).y * viewport_size.y)
			if pixel_radius.y >= pixel_radius.x:
				failures.append("Player night mask did not follow the emitted light perspective ellipse.")
		if float(material.get_shader_parameter("local_light_source_strength")) <= 0.0:
			failures.append("Player light protection mask has no strength.")
		screen_effects.call("set_day_night_strength", 0.0)
		if not is_equal_approx(float(material.get_shader_parameter("night_strength")), 0.0):
			failures.append("Screen compositor did not return to day grading.")
	else:
		failures.append("ScreenEffects does not expose day/night strength control.")
	_cleanup(screen_effects, player)
	await process_frame


func _cleanup(screen_effects: Node, player: Node) -> void:
	if is_instance_valid(screen_effects):
		screen_effects.queue_free()
	if is_instance_valid(player):
		player.queue_free()
