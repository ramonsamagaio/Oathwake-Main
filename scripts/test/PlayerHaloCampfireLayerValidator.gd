extends SceneTree

# Covers the wide environment halo, compact player clarity, animated campfire flame,
# foreground embers and connected upper-floor visibility behavior.
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")
const FLOOR_VISIBILITY_SCRIPT := preload("res://scripts/systems/TibiaFloorVisibilityController.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_player_halo_and_readability()
	await _validate_campfire_flame_and_embers()
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
	var night_light := player.get_node_or_null("NightLight")
	if night_light == null:
		failures.append("Player is missing NightLight node used by the readability system.")
	else:
		if bool(night_light.get("visual_enabled")):
			failures.append("Player texture aura should stay disabled to avoid a visible hard-edged disc.")
		if not bool(night_light.get("use_point_light")):
			failures.append("Player wide environment PointLight2D halo is disabled.")
		var texture_glow := night_light.get_node_or_null("TextureGlow") as Sprite2D
		var procedural_glow := night_light.get_node_or_null("ProceduralGlow") as Sprite2D
		var point_light := night_light.get_node_or_null("PointLight2D") as PointLight2D
		if texture_glow != null and texture_glow.visible:
			failures.append("Player TextureGlow is visible instead of using the soft PointLight halo.")
		if procedural_glow != null and procedural_glow.visible:
			failures.append("Player ProceduralGlow is visible instead of using the soft PointLight halo.")
		if point_light == null or not point_light.enabled or not point_light.visible or point_light.energy < 0.5:
			failures.append("Player environment halo is not active or bright enough at runtime.")
		elif point_light.texture_scale < 2.5:
			failures.append("Player environment halo radius is still too small.")
	if not player.has_method("is_player_night_readability_enabled") or not bool(player.call("is_player_night_readability_enabled")):
		failures.append("Restoring the environment halo disabled player-only night readability.")
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
