extends SceneTree

const LAB_SCENE := preload("res://scenes/labs/RomesteadWorldSystemsLab.tscn")
const OUTPUT_DIR := "res://artifacts/romestead_world_lab/wind_motion_frames"
const FRAME_COUNT := 48


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
	environment.set_time(17.0)
	weather.set_weather("windy")
	weather._transition_elapsed = 0.0
	weather._process(weather.TRANSITION_SECONDS)
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	for frame_index in range(FRAME_COUNT):
		await process_frame
		var image := root.get_texture().get_image()
		var frame_path := absolute_dir.path_join("frame_%03d.png" % frame_index)
		var error := image.save_png(frame_path)
		if error != OK:
			push_error("Could not save wind frame: %s" % error_string(error))
			quit(1)
			return
	print("ROMESTEAD_WIND_MOTION_CAPTURE_OK frames=%d" % FRAME_COUNT)
	quit(0)
