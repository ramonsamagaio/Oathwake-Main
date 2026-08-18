extends SceneTree

const GAME_SCENE := preload("res://scenes/game/Game.tscn")
const OUTPUT_PATH := "res://artifacts/romestead_game/CurrentGameOptimization.png"
const NIGHT_OUTPUT_PATH := "res://artifacts/romestead_game/PlayerGlobalNight.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var session := root.get_node_or_null("GameSession")
	if session != null:
		session.start_new_session("optimization_capture_%d" % Time.get_ticks_usec(), "Capture", "Optimization")
	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	for _frame in range(20):
		await process_frame
	game.weather_panel.show()
	for _frame in range(3):
		await process_frame
	var image := root.get_texture().get_image()
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	if error != OK:
		push_error("Could not save optimization capture: %s" % error_string(error))
		quit(1)
		return
	game.weather_panel.hide()
	game.day_night_cycle.set_time_of_day(0.75)
	for _frame in range(3):
		await process_frame
	var night_image := root.get_texture().get_image()
	var night_output := ProjectSettings.globalize_path(NIGHT_OUTPUT_PATH)
	var night_error := night_image.save_png(night_output)
	if night_error != OK:
		push_error("Could not save night capture: %s" % error_string(night_error))
		quit(1)
		return
	print("CURRENT_GAME_OPTIMIZATION_CAPTURE_OK %s" % absolute_output)
	quit(0)
