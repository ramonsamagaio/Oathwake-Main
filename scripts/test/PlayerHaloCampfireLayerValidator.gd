extends SceneTree

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_player_halo_removed()
	await _validate_campfire_embers_above_visual()
	if failures.is_empty():
		print("PLAYER_HALO_CAMPFIRE_LAYER_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PLAYER_HALO_CAMPFIRE_LAYER_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_player_halo_removed() -> void:
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var night_light := player.get_node_or_null("NightLight")
	if night_light == null:
		failures.append("Player is missing NightLight node used by the readability system.")
	else:
		if bool(night_light.get("visual_enabled")):
			failures.append("Player TextureGlow halo is still enabled.")
		if bool(night_light.get("use_point_light")):
			failures.append("Player PointLight2D halo is still enabled.")
		var texture_glow := night_light.get_node_or_null("TextureGlow") as Sprite2D
		var procedural_glow := night_light.get_node_or_null("ProceduralGlow") as Sprite2D
		var point_light := night_light.get_node_or_null("PointLight2D") as PointLight2D
		if texture_glow != null and texture_glow.visible:
			failures.append("Player TextureGlow remains visible at runtime.")
		if procedural_glow != null and procedural_glow.visible:
			failures.append("Player ProceduralGlow remains visible at runtime.")
		if point_light != null and (point_light.enabled or point_light.visible or point_light.energy > 0.001):
			failures.append("Player PointLight2D remains active at runtime.")
	if not player.has_method("is_player_night_readability_enabled") or not bool(player.call("is_player_night_readability_enabled")):
		failures.append("Removing the halo also disabled player-only night readability.")
	player.queue_free()
	await process_frame


func _validate_campfire_embers_above_visual() -> void:
	var campfire := BUILDING_SCENE.instantiate()
	campfire.set("building_id", "campfire")
	root.add_child(campfire)
	await process_frame
	await process_frame
	await process_frame
	var emitter := campfire.get_node_or_null("EmberEmitter") as Node2D
	if emitter == null:
		failures.append("Constructed campfire did not create EmberEmitter.")
	else:
		var authored_z := int(emitter.get("z_index_value"))
		if authored_z <= 0:
			failures.append("Campfire EmberEmitter z_index_value is not above the building visual.")
		if emitter.z_index != authored_z:
			failures.append("Campfire EmberEmitter process loop overwrote its foreground z-index.")
		if not emitter.z_as_relative:
			failures.append("Campfire EmberEmitter is not layered relative to its building.")
		var visual_z := 0
		var fallback_visual := campfire.get_node_or_null("FallbackVisual") as CanvasItem
		if fallback_visual != null:
			visual_z = maxi(visual_z, fallback_visual.z_index)
		var content_sprite := campfire.get_node_or_null("ContentSprite") as CanvasItem
		if content_sprite != null:
			visual_z = maxi(visual_z, content_sprite.z_index)
		if emitter.z_index <= visual_z:
			failures.append("Campfire embers are not rendered above the campfire sprite.")
		if not emitter.visible or not emitter.is_processing():
			failures.append("Campfire EmberEmitter is not active.")
	campfire.queue_free()
	await process_frame
