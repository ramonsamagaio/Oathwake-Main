extends SceneTree

const GAME_SCENE := preload("res://scenes/game/Game.tscn")
const OUTPUT_PATH := "res://artifacts/romestead_game/RomesteadGameIntegration.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var session := root.get_node_or_null("GameSession")
	if session != null:
		session.start_new_session("romestead_capture", "Capture Hero", "Romestead Capture")
	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	for _index in range(5):
		await process_frame
	game.day_night_cycle.set_time_of_day(0.25)
	game.alabaster_weather.set_weather("windy")
	game.alabaster_weather._transition_elapsed = 0.0
	game.alabaster_weather._process(game.alabaster_weather.TRANSITION_SECONDS)
	for _index in range(12):
		await process_frame
	var image := root.get_texture().get_image()
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	if error != OK:
		push_error("Could not save integrated GAME capture: %s" % error_string(error))
		quit(1)
		return
	print("ROMESTEAD_GAME_CAPTURE_OK %s" % absolute_output)
	quit(0)
