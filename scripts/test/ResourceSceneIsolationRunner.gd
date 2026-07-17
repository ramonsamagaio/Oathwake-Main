extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var kind := _get_kind()
	var configuration := _get_configuration(kind)
	if configuration.is_empty():
		push_error("Unknown resource isolation kind: %s" % kind)
		quit(2)
		return

	var scene_path := str(configuration.get("scene_path", ""))
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Could not load resource isolation scene: %s" % scene_path)
		quit(3)
		return
	var instance := packed_scene.instantiate()
	instance.set("resource_id", "isolation_%s" % kind)
	instance.set("resource_type_id", str(configuration.get("resource_type_id", "")))
	instance.set("resource_name", str(configuration.get("resource_name", kind.capitalize())))
	root.add_child(instance)
	print("RESOURCE_ISOLATION_READY:%s" % kind)
	for _frame_index in range(90):
		await process_frame
	print("RESOURCE_ISOLATION_PASS:%s" % kind)
	quit(0)


func _get_kind() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--kind="):
			return argument.trim_prefix("--kind=").strip_edges().to_lower()
	return "fiber"


func _get_configuration(kind: String) -> Dictionary:
	match kind:
		"tree":
			return {"scene_path": "res://scenes/Tree.tscn", "resource_type_id": "tree", "resource_name": "Wood"}
		"oak":
			return {"scene_path": "res://scenes/Tree.tscn", "resource_type_id": "oak_tree", "resource_name": "Oak Tree"}
		"rock":
			return {"scene_path": "res://scenes/Rock.tscn", "resource_type_id": "rock", "resource_name": "Stone"}
		"coal":
			return {"scene_path": "res://scenes/Rock.tscn", "resource_type_id": "coal_node", "resource_name": "Coal Node"}
		"fiber":
			return {"scene_path": "res://scenes/ResourceBush.tscn", "resource_type_id": "fiber_bush", "resource_name": "Fiber Bush"}
		"herb":
			return {"scene_path": "res://scenes/ResourceBush.tscn", "resource_type_id": "herb_bush", "resource_name": "Herb Bush"}
		"berry":
			return {"scene_path": "res://scenes/ResourceBush.tscn", "resource_type_id": "berry_bush", "resource_name": "Berry Bush"}
		_:
			return {}
