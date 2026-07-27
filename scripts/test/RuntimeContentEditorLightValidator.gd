extends SceneTree

const GLOW_SCENE := preload("res://scenes/effects/GlowOverlay.tscn")
const GAME_SCENE := preload("res://scenes/game/Game.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const CONTENT_EDITOR_SCENE := preload("res://tools/content_editor/ContentEditor.tscn")
const NIGHT_SPAWNER_SCRIPT := preload("res://scripts/enemies/NightEnemySpawner.gd")
const SPAWN_ZONE_SCRIPT := preload("res://scripts/systems/MonsterSpawnZone.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_content_editor_sections()
	_validate_runtime_editor_button()
	_validate_runtime_editor_window_contract()
	_validate_player_light_content()
	_validate_camera_display_content()
	_validate_borderless_fullscreen_contract()
	_validate_debug_action_panel()
	_validate_hit_shake_contract()
	await _validate_independent_content_editor_runtime()
	await _validate_camera_zoom_runtime()
	await _validate_night_only_light_runtime()
	await _validate_global_spawn_lock_runtime()
	if failures.is_empty():
		print("RUNTIME_CONTENT_EDITOR_LIGHT_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("RUNTIME_CONTENT_EDITOR_LIGHT_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_content_editor_sections() -> void:
	var independent_editor := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorIndependentTabsSuite.gd")
	for token in ["SECTION_WORLD_SHADOWS", "SECTION_POST_EFFECTS", "SECTION_CAMERA_DISPLAY", "World Shadows", "Post Effects", "Camera & Display", "_install_independent_sidebar_buttons"]:
		if not independent_editor.contains(token):
			failures.append("Content Editor is missing independent section token %s." % token)
	for label in ["Projected Shadows Enabled", "Normal Hit Screen Shake", "Mouse Wheel Camera Zoom", "Desktop-Filling Fullscreen"]:
		if not independent_editor.contains(label):
			failures.append("Independent Content Editor tabs are missing %s." % label)
	var player_editor := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorPlayerVisualSuite.gd")
	for label in ["World Occlusion", "Biome Ambient Particles"]:
		if not player_editor.contains(label):
			failures.append("Post Effects inherited controls are missing %s." % label)
	var environment_editor := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorEnvironmentSuite.gd")
	for label in ["Layered World Fog", "Forest Light Shafts"]:
		if not environment_editor.contains(label):
			failures.append("Post Effects inherited controls are missing %s." % label)
	var editor_scene := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditor.tscn")
	if not editor_scene.contains("ContentEditorIndependentTabsSuite.gd"):
		failures.append("ContentEditor.tscn is not using the independent tab suite.")


func _validate_runtime_editor_button() -> void:
	var game := GAME_SCENE.instantiate()
	var button := game.get_node_or_null("UI/ContentEditorButton") as Button
	if button == null:
		failures.append("Game scene has no Content Editor button in the centered debug controls.")
		game.free()
		return
	if not button.text.contains("⚙"):
		failures.append("Content Editor button is not presented with a gear.")
	var script := button.get_script() as Script
	if script == null or script.resource_path != "res://scripts/ui/RuntimeContentEditorButton.gd":
		failures.append("Content Editor gear button is not wired to the runtime launcher.")
	var launcher_text := FileAccess.get_file_as_string("res://scripts/ui/RuntimeContentEditorButton.gd")
	for token in ["ContentEditor.tscn", "post_effects", "ContentDB", "FileAccess.get_md5"]:
		if not launcher_text.contains(token):
			failures.append("Runtime Content Editor launcher is missing %s." % token)
	game.free()


func _validate_runtime_editor_window_contract() -> void:
	var launcher_text := FileAccess.get_file_as_string("res://scripts/ui/RuntimeContentEditorButton.gd")
	var required_tokens := [
		"root_window.gui_embed_subwindows = false",
		"close_requested.connect(_close_content_editor)",
		"unresizable = false",
		"borderless = false",
		"KEY_ESCAPE",
		"_restore_game_window_state",
	]
	for token in required_tokens:
		if not launcher_text.contains(token):
			failures.append("Runtime Content Editor window contract is missing %s." % token)


func _validate_player_light_content() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/player_tuning.json"))
	if not (parsed is Dictionary):
		failures.append("player_tuning.json is invalid.")
		return
	var default_value: Variant = (parsed as Dictionary).get("default", {})
	var light_value: Variant = (default_value as Dictionary).get("light", {}) if default_value is Dictionary else {}
	if not (light_value is Dictionary):
		failures.append("Player tuning has no light block.")
		return
	if not is_zero_approx(float((light_value as Dictionary).get("day_multiplier", -1.0))):
		failures.append("Player light day multiplier is not zero.")
	var player_scene_text := FileAccess.get_file_as_string("res://scenes/Player.tscn")
	if not player_scene_text.contains("visual_uses_day_night_multiplier = true"):
		failures.append("Player aura is not configured to follow day/night strength.")


func _validate_camera_display_content() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/player_tuning.json"))
	if not (parsed is Dictionary):
		return
	var default_value: Variant = (parsed as Dictionary).get("default", {})
	if not default_value is Dictionary:
		return
	var camera: Variant = (default_value as Dictionary).get("camera", {})
	if not camera is Dictionary:
		failures.append("Player tuning has no camera block.")
		return
	for key in ["wheel_zoom_enabled", "default_zoom", "minimum_zoom", "maximum_zoom", "zoom_step", "zoom_smoothing_speed"]:
		if not (camera as Dictionary).has(key):
			failures.append("Camera tuning is missing %s." % key)
	var camera_text := FileAccess.get_file_as_string("res://scripts/camera/CameraShake2D.gd")
	for token in ["MOUSE_BUTTON_WHEEL_UP", "MOUSE_BUTTON_WHEEL_DOWN", "target_zoom_level", "request_hit_shake"]:
		if not camera_text.contains(token):
			failures.append("Camera runtime is missing %s." % token)


func _validate_borderless_fullscreen_contract() -> void:
	var settings_text := FileAccess.get_file_as_string("res://scripts/systems/SettingsManager.gd")
	if not settings_text.contains("WINDOW_MODE_FULLSCREEN"):
		failures.append("SettingsManager has no desktop-filling borderless fullscreen mode.")
	if settings_text.contains("WINDOW_MODE_EXCLUSIVE_FULLSCREEN"):
		failures.append("SettingsManager uses exclusive fullscreen, which locks normal desktop window switching.")
	var shortcut_text := FileAccess.get_file_as_string("res://scripts/ui/DisplayShortcut.gd")
	if not shortcut_text.contains("KEY_F11") or not shortcut_text.contains("toggle_borderless_fullscreen"):
		failures.append("Game does not expose F11 borderless fullscreen toggling.")


func _validate_debug_action_panel() -> void:
	var game := GAME_SCENE.instantiate()
	for child_name in ["SpawnMonsterButton", "ContentEditorButton", "SaveButton", "LoadButton"]:
		var button := game.get_node_or_null("UI/%s" % child_name) as Button
		if button == null:
			failures.append("Centered debug controls are missing %s." % child_name)
		elif not is_equal_approx(button.anchor_top, 0.5) or not is_equal_approx(button.anchor_bottom, 0.5):
			failures.append("%s is not anchored to the vertical center of the screen." % child_name)
	game.free()


func _validate_hit_shake_contract() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx_profiles.json"))
	if not parsed is Dictionary:
		failures.append("vfx_profiles.json is invalid.")
		return
	var default_value: Variant = (parsed as Dictionary).get("default", {})
	if not default_value is Dictionary:
		return
	var normal_strength := float((default_value as Dictionary).get("normal_shake_strength", 0.0))
	var critical_strength := float((default_value as Dictionary).get("critical_shake_strength", 0.0))
	if normal_strength <= 0.0:
		failures.append("Normal hit shake is disabled by default.")
	if critical_strength <= normal_strength:
		failures.append("Critical hit shake is not stronger than normal hit shake.")
	var spawner_text := FileAccess.get_file_as_string("res://scripts/ui/FloatingCombatTextSpawner.gd")
	if not spawner_text.contains("_request_hit_screen_shake(is_critical)"):
		failures.append("Damage events do not request both normal and critical screen shake.")


func _validate_independent_content_editor_runtime() -> void:
	var editor := CONTENT_EDITOR_SCENE.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	var expectations := {
		"world_shadows": "shadow_opacity",
		"post_effects": "normal_shake_strength",
		"camera_display": "camera_zoom_step",
	}
	for section in expectations.keys():
		editor.call("_select_section", section, true)
		await process_frame
		var controls_value: Variant = editor.get("field_controls")
		if not controls_value is Dictionary or not (controls_value as Dictionary).has(str(expectations[section])):
			failures.append("Independent Content Editor section %s did not build expected control %s." % [section, expectations[section]])
	if editor.get("sidebar_buttons") is Dictionary:
		var sidebar := editor.get("sidebar_buttons") as Dictionary
		for section in expectations.keys():
			if not sidebar.has(section):
				failures.append("Independent Content Editor sidebar is missing %s." % section)
	editor.queue_free()
	await process_frame


func _validate_camera_zoom_runtime() -> void:
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		failures.append("Player scene has no Camera2D for zoom validation.")
		player.queue_free()
		return
	var initial_target := float(camera.get("target_zoom_level"))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	camera.call("_unhandled_input", event)
	await process_frame
	if float(camera.get("target_zoom_level")) <= initial_target:
		failures.append("Mouse wheel up does not increase the camera zoom target.")
	var game := GAME_SCENE.instantiate()
	var ui := game.get_node_or_null("UI") as CanvasLayer
	if ui == null:
		failures.append("HUD is no longer isolated in a CanvasLayer from camera zoom.")
	game.free()
	player.queue_free()
	await process_frame


func _validate_night_only_light_runtime() -> void:
	var glow := GLOW_SCENE.instantiate()
	glow.set("visual_enabled", true)
	glow.set("visual_uses_day_night_multiplier", true)
	glow.set("day_light_multiplier", 0.0)
	glow.set("night_light_multiplier", 1.0)
	root.add_child(glow)
	await process_frame
	await process_frame
	glow.call("set_day_night_strength", 0.0)
	await process_frame
	var texture_glow := glow.get_node_or_null("TextureGlow") as Sprite2D
	var point_light := glow.get_node_or_null("PointLight2D") as PointLight2D
	if texture_glow == null or point_light == null:
		failures.append("GlowOverlay scene is missing visual or PointLight2D nodes.")
		glow.queue_free()
		return
	if texture_glow.visible:
		failures.append("Player aura remains visible during full daylight.")
	if point_light.enabled or point_light.energy > 0.001:
		failures.append("Player PointLight2D remains active during full daylight.")
	glow.call("set_day_night_strength", 0.5)
	await process_frame
	if not texture_glow.visible:
		failures.append("Player aura does not appear during dusk.")
	if not point_light.enabled or point_light.energy <= 0.001:
		failures.append("Player PointLight2D does not appear during dusk.")
	glow.queue_free()
	await process_frame


func _validate_global_spawn_lock_runtime() -> void:
	var controller := NIGHT_SPAWNER_SCRIPT.new()
	controller.set("natural_spawn_enabled", false)
	root.add_child(controller)
	var zone := SPAWN_ZONE_SCRIPT.new()
	root.add_child(zone)
	await process_frame
	if not controller.is_in_group("natural_monster_spawn_controller"):
		failures.append("NightEnemySpawner is not registered as the global natural spawn controller.")
	if bool(zone.call("_is_global_natural_spawn_enabled")):
		failures.append("MonsterSpawnZone ignores the disabled global natural spawn controller.")
	controller.call("set_natural_spawn_enabled", true)
	await process_frame
	if not bool(zone.call("_is_global_natural_spawn_enabled")):
		failures.append("MonsterSpawnZone does not resume when natural spawning is enabled.")
	var start_area_text := FileAccess.get_file_as_string("res://scenes/maps/StartArea.tscn")
	for zone_name in ["SlimeSpawnZone", "SkeletonSpawnZone"]:
		if not start_area_text.contains(zone_name):
			failures.append("StartArea no longer exposes expected spawn zone %s." % zone_name)
	zone.queue_free()
	controller.queue_free()
	await process_frame
