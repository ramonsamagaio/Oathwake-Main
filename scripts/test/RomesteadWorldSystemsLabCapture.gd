extends SceneTree

const LAB_SCENE := preload("res://scenes/labs/RomesteadWorldSystemsLab.tscn")
const OUTPUT_PATH := "res://artifacts/romestead_world_lab/RomesteadReferencePass.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	await process_frame
	print("LAB_LIGHT_STATE ambient=%s sun_energy=%.3f sun_color=%s" % [
		lab.get_node("WorldModulate").color,
		lab.get_node("Sun").energy,
		lab.get_node("Sun").color,
	])
	var image := root.get_texture().get_image()
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	if error != OK:
		push_error("Could not save lab capture: %s" % error_string(error))
		quit(1)
		return
	print("ROMESTEAD_WORLD_SYSTEMS_LAB_CAPTURE_OK %s" % absolute_output)
	quit(0)
