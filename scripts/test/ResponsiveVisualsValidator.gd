extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_responsive_project_settings()
	await _validate_slime_visuals()
	_validate_world_item_shadow_and_pickup()
	await _validate_global_glow()
	await _validate_world_lighting_contract()
	await _validate_build_menu_contract()
	_validate_content_editor_contract()
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
	await process_frame
	var shadow := slime.get_node_or_null("GroundShadow") as Polygon2D
	var glow := slime.get_node_or_null("ContentGlow") as Node2D
	var sprite := slime.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if shadow == null or not shadow.visible or shadow.color.a < 0.25:
		failures.append("Slime projected shadow is missing or too transparent.")
	elif not bool(shadow.get_meta("directional_shadow", false)):
		failures.append("Slime still uses the legacy contact shadow instead of its sprite silhouette.")
	elif shadow.polygon.size() < 4 or shadow.texture == null:
		failures.append("Slime projected shadow did not copy the current animated sprite frame.")
	if glow == null or not glow.visible:
		failures.append("Slime ContentGlow was not created from monsters.json.")
	else:
		var aura := glow.get_node_or_null("TextureGlow") as Sprite2D
		var light := glow.get_node_or_null("PointLight2D") as PointLight2D
		if aura == null or not aura.visible:
			failures.append("Slime additive aura is not visible.")
		elif sprite != null and aura.z_index <= sprite.z_index:
			failures.append("Slime additive aura must render above its animated sprite.")
		if light == null or not light.enabled or light.energy <= 0.0:
			failures.append("Slime PointLight2D is not emitting real light.")
	if sprite == null or shadow == null or sprite.z_index <= shadow.z_index:
		failures.append("Slime sprite must render above its ground shadow.")
	var monster_file := FileAccess.get_file_as_string("res://data/monsters.json")
	if not monster_file.contains("\"glow\"") or not monster_file.contains("\"shadow\""):
		failures.append("Monster glow and shadow are not stored in content data.")
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
	if shadow == null or shadow.z_index != 0 or shadow.color.a < 0.25:
		failures.append("Dropped item projected shadow is not authored above the map floor with visible opacity.")
	elif not bool(shadow.get_meta("directional_shadow", false)):
		failures.append("Dropped item still uses a legacy contact ellipse.")
	if sprite == null or shadow == null or sprite.z_index <= shadow.z_index:
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
	if glow_rect == null or not (glow_rect.material is ShaderMaterial):
		failures.append("Global Gaussian glow material is missing.")
	else:
		var material := glow_rect.material as ShaderMaterial
		if material.shader == null or not material.shader.code.contains("colored_glow_boost"):
			failures.append("Global glow shader does not include the player-friendly color contribution.")
	screen_effects.queue_free()
	await process_frame


func _validate_world_lighting_contract() -> void:
	var glow_scene := load("res://scenes/effects/GlowOverlay.tscn") as PackedScene
	if glow_scene == null:
		failures.append("GlowOverlay scene could not be loaded.")
		return
	var glow := glow_scene.instantiate()
	root.add_child(glow)
	await process_frame
	var point_light := glow.get_node_or_null("PointLight2D") as PointLight2D
	var texture_glow := glow.get_node_or_null("TextureGlow") as Sprite2D
	if not bool(glow.get("use_point_light")) or point_light == null or not point_light.enabled:
		failures.append("Authored map GlowOverlay does not emit PointLight2D by default.")
	if texture_glow == null or texture_glow.z_index < 20:
		failures.append("Authored glow overlay is not drawn above world actors.")
	if float(glow.get("day_light_multiplier")) <= 0.0:
		failures.append("World lights make no contribution during daytime.")
	glow.queue_free()
	await process_frame

	var player_scene := load("res://scenes/Player.tscn") as PackedScene
	var player := player_scene.instantiate() if player_scene != null else null
	if player == null:
		failures.append("Player scene could not be loaded for night light validation.")
		return
	root.add_child(player)
	await process_frame
	var night_light := player.get_node_or_null("NightLight")
	if night_light == null or not bool(night_light.get("use_point_light")) or not bool(night_light.get("visual_enabled")):
		failures.append("Player light must emit real light and draw its tuning-controlled small aura.")
	player.queue_free()
	await process_frame

	var cycle_script := FileAccess.get_file_as_string("res://scripts/world/DayNightCycle.gd")
	if not cycle_script.contains("world_light_emitter") or not cycle_script.contains("set_day_night_strength"):
		failures.append("DayNightCycle does not drive registered world light emitters.")
	if not cycle_script.contains("0.95"):
		failures.append("Daylight is still fully white, so daytime emitters cannot add contrast.")


func _validate_build_menu_contract() -> void:
	var game_scene := load("res://scenes/game/Game.tscn") as PackedScene
	if game_scene == null:
		failures.append("Game scene could not be loaded for building menu validation.")
		return
	var game := game_scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	var build_system := game.get_node_or_null("Systems/BuildSystem")
	var menu := game.get_node_or_null("UI/BuildMenuUI")
	if build_system == null or not build_system.has_method("get_build_catalog"):
		failures.append("Lighting-aware BuildSystem is not installed.")
	elif (build_system.call("get_build_catalog") as Array).is_empty():
		failures.append("Provisional building menu has no content catalog.")
	if menu == null:
		failures.append("Provisional BuildMenuUI was not installed under the game UI.")
	var buildings_text := FileAccess.get_file_as_string("res://data/buildings.json")
	if not buildings_text.contains("\"campfire\"") or not buildings_text.contains("\"light_energy\""):
		failures.append("Campfire real light configuration is missing from buildings.json.")
	game.queue_free()
	await process_frame


func _validate_content_editor_contract() -> void:
	var editor_script := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorLightingSuite.gd")
	if editor_script.is_empty():
		failures.append("Content Editor lighting extension is missing.")
		return
	for required_text in [
		"func _build_monster_form",
		"func _get_monster_form_record",
		"func _build_building_form",
		"func _get_building_form_record",
		"Real Light Enabled",
		"Day Light Multiplier",
		"Aura Blur / Softness",
	]:
		if not editor_script.contains(required_text):
			failures.append("Content Editor lighting contract is incomplete: %s" % required_text)


func _validate_pickup_profile() -> void:
	var file := FileAccess.open("res://data/sfx_profiles.json", FileAccess.READ)
	if file == null:
		failures.append("SFX profile file could not be opened.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		failures.append("SFX profile JSON is invalid.")
		return
	var profiles := parsed as Dictionary
	if not profiles.has("item_pickup") or not (profiles["item_pickup"] is Dictionary):
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
