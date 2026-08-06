extends SceneTree

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
		failures.append("PixelationPostProcess is not registered as an autoload.")
	var effect_text := FileAccess.get_file_as_string("res://scripts/effects/PixelationPostProcess.gd")
	for token in ["POST_PROCESS_LAYER := 6", "PixelFilterButton", "PIXEL FILTER: ON", "PIXEL FILTER: OFF", "LoadButton"]:
		if not effect_text.contains(token):
			failures.append("Pixelation runtime contract is missing %s." % token)


func _validate_shader_contract() -> void:
	var shader_text := FileAccess.get_file_as_string("res://shaders/pixelation_post_process.gdshader")
	for token in ["filter_nearest", "pixel_size", "strength", "pixel_aspect", "color_steps", "dither_strength", "snapped_uv"]:
		if not shader_text.contains(token):
			failures.append("Pixelation shader is missing %s." % token)
	if shader_text.contains("for ("):
		failures.append("Pixelation shader introduced a dynamic loop.")


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
	var effect := root.get_node_or_null("PixelationPostProcess")
	if effect == null:
		failures.append("PixelationPostProcess autoload did not start.")
		return
	if not effect.has_method("set_pixelation_runtime_enabled") or not effect.has_method("get_pixelation_settings"):
		failures.append("PixelationPostProcess does not expose runtime control methods.")
		return

	effect.call("set_pixelation_runtime_enabled", true)
	await process_frame
	var layer := effect.get_node_or_null("PixelationPostProcessLayer") as CanvasLayer
	if layer == null:
		failures.append("Pixelation CanvasLayer was not created.")
		return
	if layer.layer != 6:
		failures.append("Pixelation CanvasLayer must remain below gameplay UI layer 10 and above world compositor layer 5.")
	var copy := layer.get_node_or_null("PixelationBackBufferCopy") as BackBufferCopy
	var rect := layer.get_node_or_null("PixelationRect") as ColorRect
	if copy == null or copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED:
		failures.append("Pixelation BackBufferCopy did not enable with the runtime filter.")
	if rect == null or not rect.visible:
		failures.append("Pixelation ColorRect did not become visible with the runtime filter.")
	if rect != null and rect.material is ShaderMaterial:
		var material := rect.material as ShaderMaterial
		if not bool(material.get_shader_parameter("enabled")):
			failures.append("Pixelation shader did not receive enabled=true.")
		var settings: Dictionary = effect.call("get_pixelation_settings")
		if not is_equal_approx(float(material.get_shader_parameter("pixel_size")), float(settings.get("pixel_size", -1.0))):
			failures.append("Pixel Size did not reach the pixelation shader.")
		if not is_equal_approx(float(material.get_shader_parameter("strength")), float(settings.get("strength", -1.0))):
			failures.append("Strength did not reach the pixelation shader.")
		if not is_equal_approx(float(material.get_shader_parameter("pixel_aspect")), float(settings.get("pixel_aspect", -1.0))):
			failures.append("Pixel Aspect did not reach the pixelation shader.")
	else:
		failures.append("PixelationRect has no ShaderMaterial.")

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
	effect.call("_ensure_debug_button")
	await process_frame
	var pixel_button := ui.get_node_or_null("PixelFilterButton") as Button
	if pixel_button == null:
		failures.append("Runtime did not create PixelFilterButton beside the debug controls.")
	else:
		if not pixel_button.text.contains("PIXEL FILTER: ON"):
			failures.append("PixelFilterButton did not reflect the active state.")
		if pixel_button.offset_top <= load_button.offset_bottom:
			failures.append("PixelFilterButton was not placed below LoadButton.")

	effect.call("set_pixelation_runtime_enabled", false)
	await process_frame
	if copy != null and copy.copy_mode != BackBufferCopy.COPY_MODE_DISABLED:
		failures.append("Pixelation BackBufferCopy stayed active after disabling the filter.")
	if rect != null and rect.visible:
		failures.append("Pixelation ColorRect stayed visible after disabling the filter.")
	current_scene = null
	fake_scene.queue_free()
	await process_frame
