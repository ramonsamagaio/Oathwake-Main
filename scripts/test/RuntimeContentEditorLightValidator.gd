extends SceneTree

const GLOW_SCENE := preload("res://scenes/effects/GlowOverlay.tscn")
const GAME_SCENE := preload("res://scenes/game/Game.tscn")
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
	var player_editor := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorPlayerVisualSuite.gd")
	for label in ["World Occlusion", "Biome Ambient Particles"]:
		if not player_editor.contains(label):
			failures.append("Content Editor is missing %s." % label)
	var environment_editor := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorEnvironmentSuite.gd")
	for label in ["Layered World Fog", "Forest Light Shafts"]:
		if not environment_editor.contains(label):
			failures.append("Content Editor is missing %s." % label)


func _validate_runtime_editor_button() -> void:
	var game := GAME_SCENE.instantiate()
	var button := game.get_node_or_null("UI/ContentEditorButton") as Button
	if button == null:
		failures.append("Game scene has no Content Editor gear button.")
		game.free()
		return
	if button.text != "⚙":
		failures.append("Content Editor button is not presented as a gear.")
	var script := button.get_script() as Script
	if script == null or script.resource_path != "res://scripts/ui/RuntimeContentEditorButton.gd":
		failures.append("Content Editor gear button is not wired to the runtime launcher.")
	var launcher_text := FileAccess.get_file_as_string("res://scripts/ui/RuntimeContentEditorButton.gd")
	for token in ["ContentEditor.tscn", "SECTION_VFX_PROFILES", "ContentDB", "FileAccess.get_md5"]:
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
