extends SceneTree

const SCREEN_EFFECTS_SCENE := preload("res://scenes/effects/ScreenEffects.tscn")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	_validate_project_contract()
	_validate_shader_contract()
	_validate_editor_contract()
	await _validate_runtime_contract()

	if failures.is_empty():
		print("PIXELATION_POST_PROCESS_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PIXELATION_POST_PROCESS_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_project_contract() -> void:
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	if not project_text.contains("PixelationPostProcess=\"*res://scripts/effects/PixelationPostProcess.gd\""):
		failures.append("Pixelation controller is not registered as an autoload.")
	var controller_text := FileAccess.get_file_as_string("res://scripts/effects/PixelationPostProcess.gd")
	for token in ["PixelFilterButton", "PIXEL FILTER: ON", "PIXEL FILTER: OFF", "LoadButton", "screen_effects"]:
		if not controller_text.contains(token):
			failures.append("Pixelation controller is missing %s." % token)
	for forbidden in ["BackBufferCopy.new", "ShaderMaterial.new", "PIXELATION_SHADER", "PixelationPostProcessLayer"]:
		if controller_text.contains(forbidden):
			failures.append("Pixelation controller still owns a second renderer: %s." % forbidden)
	if FileAccess.file_exists("res://shaders/pixelation_post_process.gdshader"):
		failures.append("Obsolete standalone pixelation shader still exists and can trigger a second screen-read variant.")


func _validate_shader_contract() -> void:
	var shader_text := FileAccess.get_file_as_string("res://shaders/gaussian_glow_screen.gdshader")
	for token in [
		"pixelation_enabled", "pixelation_pixel_size", "pixelation_strength",
		"pixelation_aspect", "pixelation_color_steps", "pixelation_dither_strength",
		"oath_pixelated_uv", "sample_uv", "oath_quantize_pixel_color",
	]:
		if not shader_text.contains(token):
			failures.append("Unified compositor is missing pixelation token %s." % token)
	if shader_text.contains("uniform sampler2D pixelation"):
		failures.append("Unified compositor introduced a second pixelation screen sampler.")
	if shader_text.contains("for ("):
		failures.append("Unified compositor introduced a dynamic shader loop.")
	var scene_text := FileAccess.get_file_as_string("res://scenes/effects/ScreenEffects.tscn")
	if not scene_text.contains("ScreenEffectsPixelationSuite.gd"):
		failures.append("ScreenEffects scene is not using the integrated pixelation suite.")


func _validate_editor_contract() -> void:
	var editor_text := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorPostProcessSuite.gd")
	for token in [
		"Final Pixelation Filter",
		"Pixelation Enabled by Default",
		"Pixel Size",
		"Strength",
		"Pixel Aspect",
		"Color Steps",
		"Dither Strength",
		"Tamanho do bloco em pixels da tela",
		"Mistura entre a imagem normal e a pixelizada",
		"Reducao opcional de cores por canal RGB",
		"pixelation_pixel_size",
		"pixelation_strength",
		"pixelation_aspect",
		"pixelation_color_steps",
		"pixelation_dither_strength",
	]:
		if not editor_text.contains(token):
			failures.append("Content Editor pixelation controls are missing %s." % token)


func _validate_runtime_contract() -> void:
	var controller := root.get_node_or_null("PixelationPostProcess")
	if controller == null:
		failures.append("PixelationPostProcess controller autoload did not start.")
		return

	var screen_effects := SCREEN_EFFECTS_SCENE.instantiate()
	root.add_child(screen_effects)
	await process_frame
	await process_frame
	controller.call("_sync_screen_effects_target")

	controller.call("set_pixelation_runtime_enabled", true)
	await process_frame
	var compositor := screen_effects.get_node_or_null("GaussianGlow") as ColorRect
	var copy := screen_effects.get_node_or_null("BackBufferCopy") as BackBufferCopy
	if compositor == null or not (compositor.material is ShaderMaterial):
		failures.append("Unified ScreenEffects compositor has no ShaderMaterial.")
		_cleanup(screen_effects)
		return
	var material := compositor.material as ShaderMaterial
	if not bool(material.get_shader_parameter("pixelation_enabled")):
		failures.append("Runtime toggle did not enable pixelation on the unified compositor.")
	var settings: Dictionary = controller.call("get_pixelation_settings")
	if not is_equal_approx(float(material.get_shader_parameter("pixelation_pixel_size")), float(settings.get("pixel_size", -1.0))):
		failures.append("Pixel Size did not reach the unified compositor.")
	if not is_equal_approx(float(material.get_shader_parameter("pixelation_strength")), float(settings.get("strength", -1.0))):
		failures.append("Strength did not reach the unified compositor.")
	if not is_equal_approx(float(material.get_shader_parameter("pixelation_aspect")), float(settings.get("pixel_aspect", -1.0))):
		failures.append("Pixel Aspect did not reach the unified compositor.")
	if copy == null or copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED:
		failures.append("Existing ScreenEffects BackBufferCopy is not active while pixelation is enabled.")
	if not compositor.visible:
		failures.append("Unified compositor is hidden while pixelation is enabled.")

	var fake_scene := Node2D.new()
	fake_scene.name = "PixelationButtonProbe"
	root.add_child(fake_scene)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	fake_scene.add_child(ui)
	var load_button := Button.new()
	load_button.name = "LoadButton"
	load_button.anchor_left = 1.0
	load_button.anchor_top = 0.5
	load_button.anchor_right = 1.0
	load_button.anchor_bottom = 0.5
	load_button.offset_left = -180.0
	load_button.offset_top = 44.0
	load_button.offset_right = -16.0
	load_button.offset_bottom = 80.0
	ui.add_child(load_button)
	current_scene = fake_scene
	controller.call("_ensure_debug_button")
	await process_frame
	var pixel_button := ui.get_node_or_null("PixelFilterButton") as Button
	if pixel_button == null:
		failures.append("Runtime did not create PixelFilterButton beside the debug controls.")
	else:
		if not pixel_button.text.contains("PIXEL FILTER: ON"):
			failures.append("PixelFilterButton did not reflect the active state.")
		if pixel_button.offset_top <= load_button.offset_bottom:
			failures.append("PixelFilterButton was not placed below LoadButton.")

	controller.call("set_pixelation_runtime_enabled", false)
	await process_frame
	if bool(material.get_shader_parameter("pixelation_enabled")):
		failures.append("Unified compositor stayed pixelated after disabling the runtime filter.")

	current_scene = null
	fake_scene.queue_free()
	_cleanup(screen_effects)
	await process_frame


func _cleanup(screen_effects: Node) -> void:
	if is_instance_valid(screen_effects):
		screen_effects.queue_free()
