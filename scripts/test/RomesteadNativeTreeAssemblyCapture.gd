extends SceneTree

const RESOURCE_SCENE := preload("res://scenes/resources/ResourceNodeBase.tscn")
const OUTPUT_PATH := "res://artifacts/romestead_game/RomesteadNativeTreeAssembly.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("8fb744")
	backdrop.position = Vector2(-400, -250)
	backdrop.size = Vector2(800, 500)
	root.add_child(backdrop)
	for spec in [
		{"id": "tree41", "position": Vector2(-55, 25)},
		{"id": "tree42", "position": Vector2(55, 25)},
	]:
		var resource := RESOURCE_SCENE.instantiate()
		resource.resource_id = "tree_assembly_%s" % spec["id"]
		resource.resource_type_id = spec["id"]
		resource.position = spec["position"]
		root.add_child(resource)
	var camera := Camera2D.new()
	camera.zoom = Vector2(4.0, 4.0)
	root.add_child(camera)
	for _index in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	print("ROMESTEAD_NATIVE_TREE_ASSEMBLY %s" % absolute_output)
	quit(0 if error == OK else 1)
