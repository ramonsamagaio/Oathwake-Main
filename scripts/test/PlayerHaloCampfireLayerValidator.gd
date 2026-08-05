extends SceneTree

# Covers the broad ground-plane player light, animated campfire flame,
# foreground embers, connected upper-floor visibility and authoring-lab playtest player.
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")
const FLOOR_VISIBILITY_SCRIPT := preload("res://scripts/systems/TibiaFloorVisibilityController.gd")
const AUTHORING_PLAYTEST_SCRIPT := preload("res://scripts/systems/TerrainAuthoringPlaytestBootstrap.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_player_halo_and_readability()
	await _validate_campfire_flame_and_embers()
	await _validate_authoring_lab_player()
	_validate_tibia_floor_partitioning()
	if failures.is_empty():
		print("PLAYER_HALO_CAMPFIRE_LAYER_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PLAYER_HALO_CAMPFIRE_LAYER_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_player_halo_and_readability() -> void:
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var night_light := player.get_node_or_null("NightLight") as Node2D
	if night_light == null:
		failures.append("Player is missing NightLight node used by the readability system.")
	else:
		# The isolated validator has no DayNightCycle node. Explicitly put the
		# reusable GlowOverlay into full night before reading PointLight2D state.
		if night_light.has_method("set_day_night_strength"):
			night_light.call("set_day_night_strength", 1.0)
		await process_frame
		if bool(night_light.get("visual_enabled")):
			failures.append("Player texture aura should stay disabled to avoid a visible hard-edged disc.")
		if not bool(night_light.get("use_point_light")):
			failures.append("Player wide environment PointLight2D halo is disabled.")
		if night_light.scale.x < night_light.scale.y * 2.5:
			failures.append("Player light is not wide and flat enough to read as a projected ground ellipse.")
		if night_light.position.y < 8.0:
			failures.append("Player light is not shifted down onto the ground plane.")
		var texture_glow := night_light.get_node_or_null("TextureGlow") as Sprite2D
		var procedural_glow := night_light.get_node_or_null("ProceduralGlow") as Sprite2D
		var point_light := night_light.get_node_or_null("PointLight2D") as PointLight2D
		if texture_glow != null and texture_glow.visible:
			failures.append("Player TextureGlow is visible instead of using the soft PointLight halo.")
		if procedural_glow != null and procedural_glow.visible:
			failures.append("Player ProceduralGlow is visible instead of using the soft PointLight halo.")
		if point_light == null or not point_light.enabled or not point_light.visible or point_light.energy < 0.5:
			failures.append("Player environment halo is not active or bright enough at runtime.")
		elif point_light.texture_scale < 4.0:
			failures.append("Player environment halo radius is still too small for the authored ground ellipse.")
	if not player.has_method("is_player_night_readability_enabled") or not bool(player.call("is_player_night_readability_enabled")):
		failures.append("Ground light projection disabled the unshaded player readability material.")
	if not player.has_method("is_player_environment_halo_enabled") or not bool(player.call("is_player_environment_halo_enabled")):
		failures.append("Player did not report the wide environment halo as configured.")
	player.queue_free()
	await process_frame


func _validate_campfire_flame_and_embers() -> void:
	var campfire := BUILDING_SCENE.instantiate()
	campfire.set("building_id", "campfire")
	root.add_child(campfire)
	await process_frame
	await process_frame
	await process_frame
	var flame := campfire.get_node_or_null("AnimatedFlame") as AnimatedSprite2D
	var emitter := campfire.get_node_or_null("EmberEmitter") as Node2D
	if flame == null:
		failures.append("Constructed campfire did not create AnimatedFlame from the authored GIF sheet.")
	else:
		if not flame.visible or not flame.is_playing():
			failures.append("Constructed campfire flame is not visible and playing.")
		if flame.sprite_frames == null or not flame.sprite_frames.has_animation("burn"):
			failures.append("Constructed campfire flame is missing the burn animation.")
		elif flame.sprite_frames.get_frame_count("burn") != 8:
			failures.append("Constructed campfire flame does not contain the authored eight GIF frames.")
		if not flame.z_as_relative or flame.z_index <= 0:
			failures.append("Constructed campfire flame is not layered above its base sprite.")
	if emitter == null:
		failures.append("Constructed campfire did not create EmberEmitter.")
	else:
		var authored_z := int(emitter.get("z_index_value"))
		if authored_z <= 0 or emitter.z_index != authored_z:
			failures.append("Campfire EmberEmitter lost its stable foreground z-index.")
		if flame != null and emitter.z_index <= flame.z_index:
			failures.append("Campfire embers are not rendered above the animated flame.")
	campfire.queue_free()
	await process_frame


func _validate_authoring_lab_player() -> void:
	if not ProjectSettings.has_setting("autoload/TerrainAuthoringPlaytestBootstrap"):
		failures.append("Terrain authoring playtest bootstrap is not registered as an autoload.")
	var lab := Node2D.new()
	lab.name = "TerrainAuthoringLab"
	lab.add_child(Node2D.new())
	lab.get_child(0).name = "AuthoredGrassDirtTerrain"
	var instructions := CanvasLayer.new()
	instructions.name = "Instructions"
	lab.add_child(instructions)
	root.add_child(lab)
	var bootstrap := AUTHORING_PLAYTEST_SCRIPT.new()
	var player := bootstrap.call("ensure_player_for_test", lab) as CharacterBody2D
	await process_frame
	if player == null:
		failures.append("Terrain Authoring Lab did not receive a controllable Player.tscn instance.")
	else:
		if not bool(player.get_meta("authoring_lab_playtest_player", false)):
			failures.append("Terrain Authoring Lab player is missing its playtest marker.")
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera == null or not camera.enabled:
			failures.append("Terrain Authoring Lab player has no active follow camera.")
		elif not bool(camera.get_meta("authoring_lab_playtest_camera", false)):
			failures.append("Terrain Authoring Lab camera was not configured for map playtesting.")
		if instructions.get_node_or_null("PlaytestHelp") == null:
			failures.append("Terrain Authoring Lab did not receive movement instructions.")
		var duplicate := bootstrap.call("ensure_player_for_test", lab)
		if duplicate != player:
			failures.append("Terrain Authoring Lab bootstrap created duplicate player instances.")
	bootstrap.free()
	lab.queue_free()
	await process_frame


func _validate_tibia_floor_partitioning() -> void:
	if not ProjectSettings.has_setting("autoload/TibiaFloorVisibilityController"):
		failures.append("Tibia-style upper-floor visibility controller is not registered as an autoload.")
	var controller := FLOOR_VISIBILITY_SCRIPT.new()
	var partitions: Array = controller.call("partition_cells_for_test", [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(8, 8), Vector2i(8, 9),
	])
	if partitions.size() != 2:
		failures.append("Upper-floor coverage is not split into independent connected buildings.")
	controller.free()
