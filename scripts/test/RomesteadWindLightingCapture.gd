extends SceneTree

const LAB_SCENE := preload("res://scenes/labs/RomesteadWorldSystemsLab.tscn")
const OUTPUT_PATH := "res://artifacts/romestead_world_lab/RomesteadWindLightingPass.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	var environment := lab.get_node("Environment") as RomesteadEnvironmentController
	var weather := lab.get_node("Weather") as AlabasterWeatherController
	environment.time_paused = true
	environment.set_time(23.0)
	weather.set_weather("windy")
	weather._transition_elapsed = 0.0
	weather._process(weather.TRANSITION_SECONDS)
	for index in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	if error != OK:
		push_error("Could not save wind/lighting capture: %s" % error_string(error))
		quit(1)
		return
	print("ROMESTEAD_WIND_LIGHTING_CAPTURE_OK %s" % absolute_output)
	quit(0)
