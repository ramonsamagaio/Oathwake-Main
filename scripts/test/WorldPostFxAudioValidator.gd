extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_game_layers()
	_validate_world_item_shadow()
	_validate_audio_routing()
	_validate_fog_contract()
	_validate_attack_audio_contract()
	if _failures.is_empty():
		print("WORLD_POSTFX_AUDIO_VALIDATION_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("WORLD_POSTFX_AUDIO_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_game_layers() -> void:
	var packed := load("res://scenes/game/Game.tscn") as PackedScene
	if packed == null:
		_failures.append("Game scene could not be loaded.")
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var player := game.get_node_or_null("RuntimeEntities/Player")
	if player == null:
		_failures.append("Game player is missing.")
	elif player.get_node_or_null("ScreenEffects") != null:
		_failures.append("ScreenEffects is still parented to Player after startup.")
	var fog := game.get_node_or_null("WorldPostEffects/MapFogOverlay") as CanvasLayer
	var screen_effects := game.get_node_or_null("WorldPostEffects/ScreenEffects") as CanvasLayer
	var ui := game.get_node_or_null("UI") as CanvasLayer
	if fog == null or fog.layer != 4:
		_failures.append("Global fog must exist at CanvasLayer 4.")
	if screen_effects == null or screen_effects.layer != 5:
		_failures.append("Global glow must exist at CanvasLayer 5.")
	if ui == null or ui.layer <= 5:
		_failures.append("UI must remain above all post effects.")
	game.queue_free()
	await process_frame


func _validate_world_item_shadow() -> void:
	var packed := load("res://scenes/items/WorldItem.tscn") as PackedScene
	if packed == null:
		_failures.append("WorldItem scene could not be loaded.")
		return
	var item := packed.instantiate()
	var shadow := item.get_node_or_null("GroundShadow") as Polygon2D
	var sprite := item.get_node_or_null("Sprite2D") as Sprite2D
	if shadow == null:
		_failures.append("WorldItem GroundShadow is missing.")
	elif not shadow.show_behind_parent or shadow.z_index != 0 or shadow.color.a <= 0.0:
		_failures.append("WorldItem GroundShadow must sit above the map floor at local z 0.")
	elif sprite == null or sprite.z_index <= shadow.z_index:
		_failures.append("WorldItem sprite must remain above its GroundShadow.")
	item.free()


func _validate_audio_routing() -> void:
	var manager := root.get_node_or_null("SFXManager")
	if manager == null:
		_failures.append("SFXManager autoload is missing.")
		return
	var enemy := Node2D.new()
	root.add_child(enemy)
	enemy.add_to_group("enemy")
	var resource := Node2D.new()
	root.add_child(resource)
	resource.add_to_group("resource_node")
	if str(manager.call("_resolve_hit_profile", enemy)) != "generic_enemy_hit":
		_failures.append("Enemy hit routing is not generic_enemy_hit.")
	if str(manager.call("_resolve_hit_profile", resource)) != "hit_resource":
		_failures.append("Resource hit routing is not hit_resource.")
	if not manager.has_profile("generic_enemy_hit"):
		_failures.append("generic_enemy_hit profile is missing from sfx_profiles.json.")
	enemy.queue_free()
	resource.queue_free()


func _validate_fog_contract() -> void:
	var shader := load("res://shaders/map_fog_overlay_2d.gdshader") as Shader
	if shader == null:
		_failures.append("Fog shader could not be loaded.")
		return
	if not shader.code.contains("camera_offset") or not shader.code.contains("world_anchor_strength"):
		_failures.append("Fog shader does not expose world anchoring uniforms.")
	var fog_script := FileAccess.get_file_as_string("res://scripts/effects/MapFogOverlay.gd")
	if not fog_script.contains("get_canvas_transform().affine_inverse()"):
		_failures.append("Fog controller does not derive movement from the world canvas transform.")


func _validate_attack_audio_contract() -> void:
	var player_script := FileAccess.get_file_as_string("res://scripts/player/PlayerWorldFeedbackSuite.gd")
	if player_script.is_empty():
		_failures.append("PlayerWorldFeedbackSuite could not be read.")
		return
	if not player_script.contains("if not hit_any_target") or not player_script.contains("player_attack_swing"):
		_failures.append("Empty swing audio is not gated by a no-hit result.")
	var start_index := player_script.find("func _start_attack_cycle")
	var hit_index := player_script.find("func _perform_attack_hits")
	if start_index < 0 or hit_index < 0:
		_failures.append("Attack cycle override is incomplete.")
		return
	var start_block := player_script.substr(start_index, hit_index - start_index)
	if start_block.contains("player_attack_swing"):
		_failures.append("player_attack_swing still plays before hit resolution.")
