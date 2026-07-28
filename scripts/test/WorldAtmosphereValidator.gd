extends SceneTree

const START_AREA_SCENE := preload("res://scenes/maps/StartArea.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const TREE_SCENE := preload("res://scenes/Tree.tscn")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_content_contract()
	await _validate_runtime_contract()
	if failures.is_empty():
		print("WORLD_ATMOSPHERE_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("WORLD_ATMOSPHERE_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_content_contract() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx_profiles.json"))
	if not (parsed is Dictionary):
		failures.append("vfx_profiles.json is not a dictionary.")
		return
	var default_profile: Variant = (parsed as Dictionary).get("default", {})
	if not (default_profile is Dictionary):
		failures.append("Default VFX profile is missing.")
		return
	var world_visuals: Variant = (default_profile as Dictionary).get("world_visuals", {})
	if not (world_visuals is Dictionary):
		failures.append("Default VFX profile has no world_visuals block.")
		return
	for key in ["occlusion", "wind", "particles"]:
		if not (world_visuals as Dictionary).get(key, {}) is Dictionary:
			failures.append("world_visuals is missing %s configuration." % key)
	var wind := (world_visuals as Dictionary).get("wind", {}) as Dictionary
	if float(wind.get("strength", 0.0)) <= 0.0:
		failures.append("Shared world wind has no strength.")
	var particles := (world_visuals as Dictionary).get("particles", {}) as Dictionary
	if int(particles.get("pollen_count", 0)) + int(particles.get("firefly_count", 0)) + int(particles.get("leaf_count", 0)) <= 0:
		failures.append("Biome particle field has no particles configured.")
	var editor_text := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorPlayerVisualSuite.gd")
	for label in ["World Occlusion", "Shared World Wind", "Biome Ambient Particles"]:
		if not editor_text.contains(label):
			failures.append("Content Editor is missing %s controls." % label)
	var particle_text := FileAccess.get_file_as_string("res://scripts/effects/AmbientParticleField.gd")
	for token in ["top_level = true", "get_particle_world_positions", "_wrap_position(position_value, recycle_center)"]:
		if not particle_text.contains(token):
			failures.append("Ambient particle field is missing world-anchor contract %s." % token)


func _validate_runtime_contract() -> void:
	var map := START_AREA_SCENE.instantiate()
	root.add_child(map)
	var player := PLAYER_SCENE.instantiate() as Node2D
	root.add_child(player)
	await process_frame
	await process_frame
	await physics_frame

	var director := get_first_node_in_group("world_visual_director")
	if director == null:
		failures.append("MapRoot did not install WorldVisualDirector.")
		_cleanup(map, player)
		return
	var ambient := director.get_node_or_null("AmbientParticleField") as Node2D
	if ambient == null or not ambient.is_processing():
		failures.append("WorldVisualDirector did not create an active ambient particle field.")
	else:
		if not ambient.has_method("is_world_anchored") or not bool(ambient.call("is_world_anchored")):
			failures.append("Ambient particles are not fixed to world coordinates.")
		player.global_position += Vector2(96.0, 48.0)
		await process_frame
		if not ambient.global_position.is_zero_approx():
			failures.append("Ambient particles followed the player/camera instead of remaining on the map.")
	if not director.has_method("get_wind_vector") or (director.call("get_wind_vector") as Vector2).length() <= 0.0:
		failures.append("WorldVisualDirector does not publish active shared wind.")

	var authored_tree := map.find_child("Tree01", true, false) as Sprite2D
	if authored_tree == null:
		failures.append("Authored Tree01 was not found for visual atmosphere validation.")
	else:
		if not (authored_tree.material is ShaderMaterial):
			failures.append("Authored tree did not receive the shared foliage wind material.")
		else:
			var material := authored_tree.material as ShaderMaterial
			if material.shader == null or not material.shader.code.contains("wind_direction"):
				failures.append("Authored tree material is not using the shared wind shader.")
		if not authored_tree.has_meta("world_occlusion_target"):
			failures.append("Authored tree was not registered for player occlusion.")
		else:
			var depth_y := float(authored_tree.get_meta("world_depth_y", authored_tree.global_position.y))
			player.global_position = Vector2(authored_tree.global_position.x, depth_y - 18.0)
			for _index in range(18):
				await process_frame
			var faded_alpha := authored_tree.modulate.a
			if faded_alpha >= 0.90 or not bool(authored_tree.get_meta("world_occluded", false)):
				failures.append("Authored tree did not fade when the player moved beneath its canopy.")
			player.global_position = Vector2(authored_tree.global_position.x, depth_y + 96.0)
			for _index in range(18):
				await process_frame
			if authored_tree.modulate.a <= faded_alpha:
				failures.append("Authored tree did not restore opacity after the player left its canopy.")

	var resource_tree := TREE_SCENE.instantiate()
	map.add_child(resource_tree)
	resource_tree.global_position = Vector2(120.0, 120.0)
	await process_frame
	await process_frame
	var crown := resource_tree.get_node_or_null("Crown") as CanvasItem
	var content_sprite := resource_tree.find_child("ContentSprite", true, false) as CanvasItem
	var resource_target := content_sprite if content_sprite != null and content_sprite.visible else crown
	if resource_target == null or not resource_target.has_meta("world_occlusion_target"):
		failures.append("Content resource tree was not registered for occlusion.")
	resource_tree.queue_free()
	_cleanup(map, player)
	await process_frame


func _cleanup(map: Node, player: Node) -> void:
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(map):
		map.queue_free()