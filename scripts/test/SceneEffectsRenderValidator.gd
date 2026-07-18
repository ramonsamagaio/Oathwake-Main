extends SceneTree

const TEST_WIDTH := 320
const TEST_HEIGHT := 240
const ARTIFACT_DIRECTORY := "res://test_artifacts/scene_effects"

var _test_viewport: SubViewport
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIRECTORY))
	_test_viewport = SubViewport.new()
	_test_viewport.name = "SceneEffectsValidationViewport"
	_test_viewport.size = Vector2i(TEST_WIDTH, TEST_HEIGHT)
	_test_viewport.disable_3d = true
	_test_viewport.transparent_bg = false
	_test_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_test_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_test_viewport)

	await _wait_for_render(3)
	await _validate_world_item_outline()
	await _validate_map_fog()
	await _validate_gaussian_glow()

	if _failures.is_empty():
		print("SCENE_EFFECTS_VALIDATION_PASS: outline, fog and Gaussian glow rendered successfully.")
		quit(0)
		return

	for failure in _failures:
		push_error("SCENE_EFFECTS_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_world_item_outline() -> void:
	await _clear_viewport()
	var background_color := Color(0.025, 0.028, 0.035, 1.0)
	_add_rect(Rect2(Vector2.ZERO, Vector2(TEST_WIDTH, TEST_HEIGHT)), background_color)

	var item_scene := load("res://scenes/items/WorldItem.tscn") as PackedScene
	if item_scene == null:
		_failures.append("WorldItem.tscn could not be loaded.")
		return
	var item := item_scene.instantiate()
	item.set("spawn_jump_enabled", false)
	item.set("hover_enabled", false)
	item.position = Vector2(TEST_WIDTH * 0.5, TEST_HEIGHT * 0.5)
	_test_viewport.add_child(item)
	await process_frame

	var source_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	source_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for pixel_y in range(4, 12):
		for pixel_x in range(4, 12):
			source_image.set_pixel(pixel_x, pixel_y, Color(0.92, 0.16, 0.14, 1.0))
	var source_texture := ImageTexture.create_from_image(source_image)
	var sprite := item.get_node_or_null("Sprite2D") as Sprite2D
	var outline_settings := item.get_node_or_null("OutlineSettings")
	if sprite == null or outline_settings == null:
		_failures.append("WorldItem scene is missing Sprite2D or OutlineSettings.")
		return
	sprite.texture = source_texture
	sprite.scale = Vector2(3.0, 3.0)
	outline_settings.set("effect_enabled", true)
	outline_settings.set("outline_color", Color(0.08, 1.0, 0.18, 1.0))
	outline_settings.set("outline_size", 0.035)
	outline_settings.set("alpha_threshold", 0.5)
	outline_settings.set("samples", 12)
	item.call("_sync_outline_visual")

	var rendered := await _capture_image("outline.png")
	if rendered == null:
		return
	var green_outline_pixels := 0
	var red_item_pixels := 0
	for pixel_y in range(TEST_HEIGHT):
		for pixel_x in range(TEST_WIDTH):
			var pixel := rendered.get_pixel(pixel_x, pixel_y)
			if pixel.g > 0.55 and pixel.g > pixel.r * 1.8 and pixel.a > 0.4:
				green_outline_pixels += 1
			if pixel.r > 0.55 and pixel.r > pixel.g * 2.0 and pixel.a > 0.4:
				red_item_pixels += 1
	if red_item_pixels < 250:
		_failures.append("World item sprite did not render with the expected visible area (%d red pixels)." % red_item_pixels)
	if green_outline_pixels < 40:
		_failures.append("World item outline did not render outside the item (%d outline pixels)." % green_outline_pixels)


func _validate_map_fog() -> void:
	await _clear_viewport()
	var background_color := Color(0.055, 0.075, 0.11, 1.0)
	_add_rect(Rect2(Vector2.ZERO, Vector2(TEST_WIDTH, TEST_HEIGHT)), background_color)

	var fog_scene := load("res://scenes/effects/MapFogOverlay.tscn") as PackedScene
	if fog_scene == null:
		_failures.append("MapFogOverlay.tscn could not be loaded.")
		return
	var fog := fog_scene.instantiate()
	_test_viewport.add_child(fog)
	await process_frame
	if not bool(fog.get("effect_enabled")):
		_failures.append("Map fog is not enabled in its authored scene.")
	fog.set("effect_enabled", true)
	fog.set("density", 0.82)
	fog.set("speed", Vector2.ZERO)
	fog.set("fog_color", Color(0.58, 0.70, 0.86, 0.42))
	fog.set("fog_scale", 3.6)
	fog.set("coverage", 0.46)
	fog.set("softness", 0.26)
	fog.set("detail_mix", 0.45)
	fog.call("refresh_from_settings")

	var rendered := await _capture_image("fog.png")
	if rendered == null:
		return
	var sample_count := 0
	var difference_sum := 0.0
	var minimum_luminance := 10.0
	var maximum_luminance := -10.0
	var average_luminance := 0.0
	for pixel_y in range(0, TEST_HEIGHT, 4):
		for pixel_x in range(0, TEST_WIDTH, 4):
			var pixel := rendered.get_pixel(pixel_x, pixel_y)
			var luminance := _luminance(pixel)
			minimum_luminance = minf(minimum_luminance, luminance)
			maximum_luminance = maxf(maximum_luminance, luminance)
			average_luminance += luminance
			difference_sum += absf(pixel.r - background_color.r) + absf(pixel.g - background_color.g) + absf(pixel.b - background_color.b)
			sample_count += 1
	average_luminance /= maxf(float(sample_count), 1.0)
	var average_difference := difference_sum / maxf(float(sample_count), 1.0)
	if average_difference < 0.012:
		_failures.append("Fog rendered no measurable overlay (average RGB difference %.5f)." % average_difference)
	if maximum_luminance - minimum_luminance < 0.012:
		_failures.append("Fog rendered as a flat wash instead of spatially varying mist (range %.5f)." % (maximum_luminance - minimum_luminance))
	if average_luminance > 0.50 or maximum_luminance > 0.78:
		_failures.append("Fog washed out the scene (average %.4f, maximum %.4f)." % [average_luminance, maximum_luminance])


func _validate_gaussian_glow() -> void:
	await _clear_viewport()
	var background_color := Color(0.018, 0.022, 0.032, 1.0)
	_add_rect(Rect2(Vector2.ZERO, Vector2(TEST_WIDTH, TEST_HEIGHT)), background_color)
	_add_rect(Rect2(Vector2(120, 80), Vector2(80, 80)), Color(1.0, 0.82, 0.50, 1.0))
	var baseline := await _capture_image("glow_before.png")
	if baseline == null:
		return

	var effects_scene := load("res://scenes/effects/ScreenEffects.tscn") as PackedScene
	if effects_scene == null:
		_failures.append("ScreenEffects.tscn could not be loaded.")
		return
	var effects := effects_scene.instantiate()
	_test_viewport.add_child(effects)
	await process_frame
	var settings := effects.get_node_or_null("Settings")
	if settings == null:
		_failures.append("ScreenEffects scene is missing its Settings node.")
		return
	if not bool(settings.get("glow_enabled")):
		_failures.append("Gaussian glow is not enabled in its authored settings scene.")
	settings.set("glow_enabled", true)
	settings.set("bloom_threshold", 0.30)
	settings.set("bloom_intensity", 1.45)
	settings.set("blur_iterations", 2)
	settings.set("blur_size", 0.006)
	settings.set("blur_subdivisions", 10)
	settings.set("glow_mix_amount", 0.72)
	effects.call("refresh_from_settings")

	var rendered := await _capture_image("glow_after.png")
	if rendered == null:
		return
	var halo_regions := [
		Rect2i(104, 90, 13, 60),
		Rect2i(203, 90, 13, 60),
		Rect2i(130, 64, 60, 13),
		Rect2i(130, 163, 60, 13),
	]
	var baseline_halo := 0.0
	var rendered_halo := 0.0
	for region in halo_regions:
		baseline_halo += _average_region_luminance(baseline, region)
		rendered_halo += _average_region_luminance(rendered, region)
	baseline_halo /= float(halo_regions.size())
	rendered_halo /= float(halo_regions.size())
	var halo_gain := rendered_halo - baseline_halo
	var corner_luminance := _average_region_luminance(rendered, Rect2i(0, 0, 32, 32))
	var baseline_average := _average_image_luminance(baseline)
	var rendered_average := _average_image_luminance(rendered)
	if halo_gain < 0.006:
		_failures.append("Gaussian glow produced no measurable halo outside the bright source (gain %.5f)." % halo_gain)
	if corner_luminance > 0.18:
		_failures.append("Gaussian glow brightened a distant dark corner too much (%.4f)." % corner_luminance)
	if rendered_average - baseline_average > 0.14 or rendered_average > 0.42:
		_failures.append("Gaussian glow washed out the full screen (baseline %.4f, result %.4f)." % [baseline_average, rendered_average])


func _add_rect(rect: Rect2, color: Color) -> ColorRect:
	var color_rect := ColorRect.new()
	color_rect.position = rect.position
	color_rect.size = rect.size
	color_rect.color = color
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_test_viewport.add_child(color_rect)
	return color_rect


func _capture_image(file_name: String) -> Image:
	await _wait_for_render(5)
	var viewport_texture := _test_viewport.get_texture()
	if viewport_texture == null:
		_failures.append("Validation viewport returned no texture for %s." % file_name)
		return null
	var image := viewport_texture.get_image()
	if image == null or image.is_empty() or image.get_width() <= 0 or image.get_height() <= 0:
		_failures.append("Validation viewport returned an empty image for %s." % file_name)
		return null
	var save_path := "%s/%s" % [ARTIFACT_DIRECTORY, file_name]
	var save_error := image.save_png(save_path)
	if save_error != OK:
		_failures.append("Could not save validation image %s (error %d)." % [save_path, save_error])
	return image


func _wait_for_render(frame_count: int) -> void:
	for _frame_index in range(maxi(frame_count, 1)):
		await process_frame
		await RenderingServer.frame_post_draw


func _clear_viewport() -> void:
	for child in _test_viewport.get_children():
		child.queue_free()
	await process_frame
	await process_frame


func _average_region_luminance(image: Image, region: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	var start_x := clampi(region.position.x, 0, image.get_width())
	var start_y := clampi(region.position.y, 0, image.get_height())
	var end_x := clampi(region.end.x, 0, image.get_width())
	var end_y := clampi(region.end.y, 0, image.get_height())
	for pixel_y in range(start_y, end_y):
		for pixel_x in range(start_x, end_x):
			sum += _luminance(image.get_pixel(pixel_x, pixel_y))
			count += 1
	return sum / maxf(float(count), 1.0)


func _average_image_luminance(image: Image) -> float:
	var sum := 0.0
	var count := 0
	for pixel_y in range(0, image.get_height(), 4):
		for pixel_x in range(0, image.get_width(), 4):
			sum += _luminance(image.get_pixel(pixel_x, pixel_y))
			count += 1
	return sum / maxf(float(count), 1.0)


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
