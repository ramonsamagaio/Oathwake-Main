extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_responsive_project_settings()
	await _validate_slime_visuals()
	_validate_world_item_shadow_and_pickup()
	_validate_global_glow()
	_validate_pickup_profile()

	if failures.is_empty():
		print("RESPONSIVE_VISUALS_VALIDATION_PASS")
		quit(0)
		return

	for failure in failures:
		push_error("RESPONSIVE_VISUALS_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_responsive_project_settings() -> void:
	if str(ProjectSettings.get_setting("display/window/stretch/mode", "")) != "viewport":
		failures.append("Stretch mode must be viewport so the 1600x900 composition scales as one canvas.")
	if str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) != "keep":
		failures.append("Stretch aspect must be keep so layout proportions do not drift.")
	if str(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) != "fractional":
		failures.append("Stretch scale mode must be fractional for arbitrary maximized window sizes.")
	if int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) != 1600:
		failures.append("Responsive base viewport width changed from 1600.")
	if int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) != 900:
		failures.append("Responsive base viewport height changed from 900.")


func _validate_slime_visuals() -> void:
	var packed := load("res://scenes/enemies/Slime.tscn") as PackedScene
	if packed == null:
		failures.append("Slime scene could not be loaded.")
		return
	var slime := packed.instantiate()
	root.add_child(slime)
	await process_frame
	var shadow := slime.get_node_or_null("GroundShadow") as Polygon2D
	var glow := slime.get_node_or_null("SlimeGlow") as Sprite2D
	var sprite := slime.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if shadow == null or not shadow.visible or shadow.color.a < 0.30:
		failures.append("Slime ground shadow is missing or too transparent.")
	elif shadow.position.y > 16.0:
		failures.append("Slime ground shadow is too far below the sprite.")
	if glow == null or not glow.visible:
		failures.append("Slime glow option is not visible in the authored scene.")
	elif not glow.material is ShaderMaterial:
		failures.append("Slime glow is missing its local ShaderMaterial.")
	else:
		var glow_material := glow.material as ShaderMaterial
		if glow_material.shader == null or not glow_material.shader.resource_path.ends_with("slime_aura.gdshader"):
			failures.append("Slime glow still depends on the old screen-reading overlay.")
	if sprite == null or sprite.z_index <= shadow.z_index:
		failures.append("Slime sprite must render above its ground shadow.")
	if not _has_property(slime, "glow_enabled") or not _has_property(slime, "ground_shadow_enabled"):
		failures.append("Slime glow and shadow controls are not exposed on the scene root.")
	slime.queue_free()
	await process_frame


func _validate_world_item_shadow_and_pickup() -> void:
	var packed := load("res://scenes/items/WorldItem.tscn") as PackedScene
	if packed == null:
		failures.append("WorldItem scene could not be loaded.")
		return
	var item := packed.instantiate()
	var shadow := item.get_node_or_null("GroundShadow") as Polygon2D
	var sprite := item.get_node_or_null("Sprite2D") as Sprite2D
	if shadow == null or shadow.z_index != 0 or shadow.color.a < 0.40:
		failures.append("Dropped item shadow is not authored above the map floor with visible opacity.")
	if sprite == null or sprite.z_index <= shadow.z_index:
		failures.append("Dropped item sprite must remain above its shadow.")
	if not _has_property(item, "drop_shadow_enabled"):
		failures.append("Dropped item shadow toggle is not exposed.")
	item.free()

	var script_text := FileAccess.get_file_as_string("res://scripts/items/WorldItemFeedbackSuite.gd")
	if not script_text.contains("if not was_collected and collected"):
		failures.append("Pickup sound is not gated by successful inventory collection.")
	if not script_text.contains("play_profile(\"item_pickup\""):
		failures.append("WorldItem does not call the item_pickup SFX profile.")
	if not script_text.contains("_shadow.z_index = 0"):
		failures.append("Runtime item shadow can still fall back into the ground layer.")


func _validate_global_glow() -> void:
	var screen_scene := load("res://scenes/effects/ScreenEffects.tscn") as PackedScene
	if screen_scene == null:
		failures.append("ScreenEffects scene could not be loaded.")
		return
	var screen_effects := screen_scene.instantiate()
	root.add_child(screen_effects)
	await process_frame
	var settings := screen_effects.get_node_or_null("Settings")
	var glow_rect := screen_effects.get_node_or_null("GaussianGlow") as ColorRect
	if settings == null or not _has_property(settings, "colored_glow_boost"):
		failures.append("Colored Glow Boost is not exposed in screen effect settings.")
	elif float(settings.get("colored_glow_boost")) <= 0.0:
		failures.append("Colored Glow Boost is disabled, so dark player colors cannot feed bloom.")
	if glow_rect == null or not glow_rect.material is ShaderMaterial:
		failures.append("Global Gaussian glow material is missing.")
	else:
		var material := glow_rect.material as ShaderMaterial
		if material.shader == null or not material.shader.code.contains("colored_glow_boost"):
			failures.append("Global glow shader does not include the player-friendly color contribution.")
	screen_effects.queue_free()
	await process_frame


func _validate_pickup_profile() -> void:
	var file := FileAccess.open("res://data/sfx_profiles.json", FileAccess.READ)
	if file == null:
		failures.append("SFX profile file could not be opened.")
		return
	var parsed := JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("SFX profile JSON is invalid.")
		return
	var profiles := parsed as Dictionary
	if not profiles.has("item_pickup") or not profiles["item_pickup"] is Dictionary:
		failures.append("item_pickup SFX profile is missing.")
		return
	var profile := profiles["item_pickup"] as Dictionary
	var paths: Array = profile.get("stream_paths", [])
	if paths.is_empty() or not ResourceLoader.exists(str(paths[0])):
		failures.append("item_pickup SFX profile has no loadable audio stream.")


func _has_property(target: Object, property_name: String) -> bool:
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false
