extends SceneTree

const WORLD_SCENE := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const OUTPUT_PATH := "res://artifacts/romestead_game/RomesteadForestLayersCurrent.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var world := WORLD_SCENE.instantiate()
	# Visual regression fixture only. Production remains 240x140; this smaller
	# fixture preserves the same generators while keeping iteration practical.
	world.world_size_tiles = Vector2i(120, 80)
	root.add_child(world)
	for _index in range(8):
		await process_frame
	var tree_left := world.get("_forest_tree_left") as Dictionary
	var barriers := world.get("_forest_barriers") as Dictionary
	var target := Vector2i.ZERO
	if not tree_left.is_empty():
		for cell_value in tree_left.keys():
			var cell := cell_value as Vector2i
			if cell.y > target.y:
				target = cell
	elif not barriers.is_empty():
		target = barriers.keys()[barriers.size() / 2] as Vector2i
	var camera := Camera2D.new()
	camera.position = world.to_global(Vector2(target * 16) + Vector2(8, -32))
	camera.zoom = Vector2(2.5, 2.5)
	root.add_child(camera)
	for _index in range(4):
		await process_frame
	var image := root.get_texture().get_image()
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var error := image.save_png(absolute_output)
	print("ROMESTEAD_FOREST_LAYER_CAPTURE %s target=%s tree_pairs=%d barriers=%d" % [
		absolute_output, target, tree_left.size(), barriers.size(),
	])
	quit(0 if error == OK else 1)
