extends SceneTree

const LAB_SCENE := preload("res://scenes/labs/RomesteadWorldSystemsLab.tscn")
const WEATHER_IDS := ["clear", "windy", "rain", "storm", "snow", "embers"]


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame

	var world := lab.get_node("World") as RomesteadBiomeWorld2D
	var weather := lab.get_node("Weather") as AlabasterWeatherController
	var ground := lab.get_node("World/Ground") as TileMapLayer
	if world == null or weather == null or ground == null:
		_fail("required world/weather nodes are missing")
		return
	var expected_cells := world.world_size_tiles.x * world.world_size_tiles.y
	if ground.get_used_cells().size() != expected_cells:
		_fail("expected %d floor cells, found %d" % [expected_cells, ground.get_used_cells().size()])
		return
	if get_nodes_in_group("romestead_lab_lights").size() < 3:
		_fail("expected at least three local light rigs")
		return

	var native_topology_cases := {
		0: [],
		1: [3],
		7: [18],
		13: [24],
		15: [0],
		18: [6, 1],
		40: [9, 2],
		255: [0],
	}
	for surrounding_mask in native_topology_cases:
		var actual: Array[int] = world._surrounding_mask_to_piece_masks(surrounding_mask)
		var expected: Array = native_topology_cases[surrounding_mask]
		if actual != expected:
			_fail("native autotile mismatch for mask %d: expected %s, found %s" % [surrounding_mask, expected, actual])
			return

	var wind_pivots := get_nodes_in_group("romestead_wind_pivots")
	if wind_pivots.is_empty():
		_fail("expected grounded wind pivots for bushes and tree canopies")
		return
	var sample_pivot := wind_pivots[0] as Node2D
	var sample_sprite := sample_pivot.get_child(0) as Sprite2D
	if sample_sprite == null or sample_sprite.material != null:
		_fail("wind sprite must use normal canvas lighting without an unshaded material")
		return
	world.set_environment(0.0, 0.0, 0.82, 2.2, Vector2(1.0, 0.2), 17.0, 1.0)
	var previous_rotation := sample_pivot.rotation
	world._process(0.5)
	if is_equal_approx(sample_pivot.rotation, previous_rotation):
		_fail("native pivot wind did not rotate under a windy profile")
		return

	for weather_id in WEATHER_IDS:
		weather.set_weather(weather_id)
		weather._transition_elapsed = 0.0
		weather._process(weather.TRANSITION_SECONDS)
		if weather.target_weather != weather_id:
			_fail("weather profile did not activate: %s" % weather_id)
			return

	world.generate_world(91357)
	if ground.get_used_cells().size() != expected_cells:
		_fail("regeneration changed the expected floor cell count")
		return
	var generated_props := world.get_node("Props").get_child_count() + world.get_node("WindVegetation").get_child_count()
	var reserved_spots := (world.get("_entity_spots") as Dictionary).size()
	if generated_props >= reserved_spots:
		_fail("entity rolls must leave some reserved Romestead spots empty")
		return
	print("ROMESTEAD_WORLD_SYSTEMS_LAB_VALIDATION_OK cells=%d spots=%d props=%d lights=%d climates=%d" % [
		expected_cells,
		reserved_spots,
		generated_props,
		get_nodes_in_group("romestead_lab_lights").size(),
		WEATHER_IDS.size(),
	])
	quit(0)


func _fail(message: String) -> void:
	push_error("ROMESTEAD_WORLD_SYSTEMS_LAB_VALIDATION_FAILED: %s" % message)
	quit(1)
