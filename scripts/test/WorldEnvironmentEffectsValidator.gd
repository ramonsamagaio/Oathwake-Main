extends SceneTree

const GAME_SCENE := preload("res://scenes/game/Game.tscn")
const START_AREA_SCENE := preload("res://scenes/maps/StartArea.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const FOG_SCENE := preload("res://scenes/effects/MapFogOverlay.tscn")
const SHAFT_SCENE := preload("res://scenes/effects/LightShaftOverlay.tscn")
const WATER_SCENE := preload("res://scenes/effects/WaterSurface2D.tscn")
const TEST_TEXTURE := preload("res://assets/generated/functional_ground_tile.svg")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_visuals := _validate_content_contract()
	_validate_shader_contract()
	await _validate_effect_scenes(world_visuals)
	await _validate_map_environment_runtime()
	if failures.is_empty():
		print("WORLD_ENVIRONMENT_EFFECTS_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("WORLD_ENVIRONMENT_EFFECTS_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_content_contract() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx_profiles.json"))
	if not (parsed is Dictionary):
		failures.append("vfx_profiles.json is invalid.")
		return {}
	var default_profile: Variant = (parsed as Dictionary).get("default", {})
	var world_value: Variant = (default_profile as Dictionary).get("world_visuals", {}) if default_profile is Dictionary else {}
	if not (world_value is Dictionary):
		failures.append("Default VFX profile has no world_visuals block.")
		return {}
	var world_visuals := world_value as Dictionary
	for key in ["layered_fog", "light_shafts", "water", "micro_motion"]:
		if not (world_visuals.get(key, {}) is Dictionary):
			failures.append("world_visuals is missing %s." % key)
	var fog := world_visuals.get("layered_fog", {}) as Dictionary
	if float(fog.get("ground_density", 0.0)) <= 0.0 or float(fog.get("depth_density", 0.0)) <= 0.0:
		failures.append("Layered fog does not configure ground mist and depth haze.")
	var fog_speed_value: Variant = fog.get("speed", {})
	var fog_speed := Vector2.ZERO
	if fog_speed_value is Dictionary:
		fog_speed = Vector2(float((fog_speed_value as Dictionary).get("x", 0.0)), float((fog_speed_value as Dictionary).get("y", 0.0)))
	if fog_speed.length() <= 0.0001:
		failures.append("Layered fog has no configured drift speed.")
	var shafts := world_visuals.get("light_shafts", {}) as Dictionary
	if not bool(shafts.get("enabled", false)) or float(shafts.get("intensity", 0.0)) <= 0.0:
		failures.append("Forest light shafts are disabled.")
	var water := world_visuals.get("water", {}) as Dictionary
	if float(water.get("ripple_strength", 0.0)) <= 0.0 or float(water.get("reflection_strength", 0.0)) <= 0.0:
		failures.append("Water ripple or reflection strength is disabled.")
	var micro := world_visuals.get("micro_motion", {}) as Dictionary
	if not bool(micro.get("enabled", false)) or float(micro.get("flower_scale_amount", 0.0)) <= 0.0:
		failures.append("Environmental micro motion is disabled.")
	var editor_text := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorEnvironmentSuite.gd")
	for label in ["Layered World Fog", "Forest Light Shafts", "Water Surface", "Environmental Micro Motion"]:
		if not editor_text.contains(label):
			failures.append("Content Editor is missing %s controls." % label)
	return world_visuals


func _validate_shader_contract() -> void:
	var fog_shader := FileAccess.get_file_as_string("res://shaders/map_fog_overlay_2d.gdshader")
	for token in ["ground_density", "middle_density", "depth_density", "night_multiplier", "motion_time", "slow_wander"]:
		if not fog_shader.contains(token):
			failures.append("Layered fog shader is missing %s." % token)
	var shaft_shader := FileAccess.get_file_as_string("res://shaders/light_shafts_overlay_2d.gdshader")
	for token in ["beam_count", "world_anchor_strength", "night_strength"]:
		if not shaft_shader.contains(token):
			failures.append("Light shaft shader is missing %s." % token)
	var water_shader := FileAccess.get_file_as_string("res://shaders/water_surface_2d.gdshader")
	for token in ["ripple_strength", "reflection_strength", "caustic_strength", "night_strength"]:
		if not water_shader.contains(token):
			failures.append("Water shader is missing %s." % token)


func _validate_effect_scenes(world_visuals: Dictionary) -> void:
	var fog := FOG_SCENE.instantiate()
	root.add_child(fog)
	await process_frame
	var fog_rect := fog.get_node_or_null("FogRect") as ColorRect
	if fog_rect == null or not (fog_rect.material is ShaderMaterial):
		failures.append("MapFogOverlay has no layered fog material.")
	else:
		var fog_material := fog_rect.material as ShaderMaterial
		if float(fog_material.get_shader_parameter("ground_density")) <= 0.0:
			failures.append("MapFogOverlay did not apply ground fog content values.")
		if float(fog_material.get_shader_parameter("depth_density")) <= 0.0:
			failures.append("MapFogOverlay did not apply depth haze content values.")
		var initial_motion_time := float(fog_material.get_shader_parameter("motion_time"))
		fog.call("_process", 0.75)
		var advanced_motion_time := float(fog_material.get_shader_parameter("motion_time"))
		if advanced_motion_time <= initial_motion_time:
			failures.append("MapFogOverlay does not advance its procedural fog motion.")
		if absf(float(fog.get_meta("fog_motion_time", -1.0)) - advanced_motion_time) > 0.001:
			failures.append("MapFogOverlay motion time is not published consistently to the shader.")

	var shafts := SHAFT_SCENE.instantiate()
	root.add_child(shafts)
	await process_frame
	var shaft_rect := shafts.get_node_or_null("ShaftRect") as ColorRect
	if shaft_rect == null or not (shaft_rect.material is ShaderMaterial):
		failures.append("LightShaftOverlay has no shaft material.")
	else:
		var shaft_material := shaft_rect.material as ShaderMaterial
		if float(shaft_material.get_shader_parameter("intensity")) <= 0.0:
			failures.append("LightShaftOverlay did not apply its content intensity.")
		if int(shafts.layer) >= 10:
			failures.append("Light shafts render above the HUD layer.")

	var water := WATER_SCENE.instantiate()
	root.add_child(water)
	await process_frame
	var surface := water.get_node_or_null("Surface") as Polygon2D
	if surface == null or not (surface.material is ShaderMaterial):
		failures.append("WaterSurface2D has no water material.")
	else:
		var water_material := surface.material as ShaderMaterial
		var water_config := world_visuals.get("water", {}) as Dictionary
		if not is_equal_approx(float(water_material.get_shader_parameter("ripple_strength")), float(water_config.get("ripple_strength", -1.0))):
			failures.append("WaterSurface2D ripple strength does not match content data.")
		if float(water_material.get_shader_parameter("reflection_strength")) <= 0.0:
			failures.append("WaterSurface2D reflection is disabled at runtime.")

	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	if game.get_node_or_null("WorldPostEffects/LightShaftOverlay") == null:
		failures.append("Game scene did not install LightShaftOverlay.")
	game.queue_free()
	fog.queue_free()
	shafts.queue_free()
	water.queue_free()
	await process_frame


func _validate_map_environment_runtime() -> void:
	var map := START_AREA_SCENE.instantiate()
	root.add_child(map)
	var player := PLAYER_SCENE.instantiate() as Node2D
	root.add_child(player)
	await process_frame
	await process_frame
	var director := get_first_node_in_group("world_visual_director")
	if director == null:
		failures.append("Map did not create WorldVisualDirector.")
		_cleanup(map, player)
		return
	for method_name in ["configure_water_canvas_item", "register_micro_target", "register_authored_environment_layer"]:
		if not director.has_method(method_name):
			failures.append("WorldVisualDirector is missing %s." % method_name)

	var water_sprite := Sprite2D.new()
	water_sprite.name = "RiverWaterValidator"
	water_sprite.texture = TEST_TEXTURE
	map.add_child(water_sprite)
	director.call("register_authored_sprite", water_sprite)
	if not water_sprite.has_meta("world_water_surface") or not (water_sprite.material is ShaderMaterial):
		failures.append("Authored water sprite was not wired automatically.")
	else:
		var water_material := water_sprite.material as ShaderMaterial
		if water_material.shader == null or not water_material.shader.code.contains("water_wave"):
			failures.append("Authored water sprite did not receive the water shader.")

	var flower := Node2D.new()
	flower.name = "FlowerValidator"
	map.add_child(flower)
	var base_rotation := flower.rotation
	var base_scale := flower.scale
	director.call("register_micro_target", flower, flower, "flower")
	if not flower.has_meta("world_micro_motion"):
		failures.append("Micro motion target was not registered.")
	else:
		director.call("_process", 0.71)
		director.call("_process", 0.53)
		if is_equal_approx(flower.rotation, base_rotation) and flower.scale.is_equal_approx(base_scale):
			failures.append("Environmental micro motion did not alter the registered flower transform.")

	_cleanup(map, player)
	await process_frame


func _cleanup(map: Node, player: Node) -> void:
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(map):
		map.queue_free()
