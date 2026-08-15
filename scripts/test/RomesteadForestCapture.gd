extends SceneTree

const GAME_SCENE := preload("res://scenes/game/Game.tscn")
const OUTPUT_PATH := "res://artifacts/romestead_game/RomesteadForestBiome.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var session := root.get_node_or_null("GameSession")
	if session != null:
		session.start_new_session("romestead_forest_capture", "Capture Hero", "Romestead Forest Capture")
	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	for _index in range(10):
		await process_frame
	var world := get_first_node_in_group("procedural_resource_world") as Node2D
	var player := get_first_node_in_group("player") as Node2D
	if world == null or player == null:
		quit(1)
		return
	var biomes: Dictionary = world.get("_biomes")
	var target := Vector2i.ZERO
	for cell_value in biomes.keys():
		var cell := cell_value as Vector2i
		if int(biomes[cell]) == 7:
			target = cell
			break
	player.global_position = world.to_global(Vector2(target * 16) + Vector2(8, 8))
	for _index in range(12):
		await process_frame
	var image := root.get_texture().get_image()
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	print("ROMESTEAD_FOREST_CAPTURE %s biome_cell=%s" % [absolute_output, target])
	quit(0 if error == OK else 1)
