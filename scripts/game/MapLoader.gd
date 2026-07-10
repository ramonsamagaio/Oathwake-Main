## Loads one map scene at a time into an explicit map container.
class_name MapLoader
extends Node

const MAP_SCENE_PATHS := {
	"start_area": "res://scenes/maps/StartArea.tscn",
}

var current_map: Node2D
var current_map_id := ""


func load_map(map_id: String, parent_node: Node) -> Node2D:
	if parent_node == null:
		push_error("MapLoader requires a valid map parent.")
		return null
	var scene_path := str(MAP_SCENE_PATHS.get(map_id, ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("MapLoader could not find a scene for map_id: %s" % map_id)
		return null

	clear_current_map(parent_node)
	var map_scene := load(scene_path) as PackedScene
	if map_scene == null:
		push_error("MapLoader could not load map scene: %s" % scene_path)
		return null
	var loaded_map := map_scene.instantiate() as Node2D
	if loaded_map == null:
		push_error("MapLoader map root must inherit Node2D: %s" % scene_path)
		return null

	loaded_map.name = "MapRoot"
	loaded_map.set_meta("map_id", map_id)
	parent_node.add_child(loaded_map)
	current_map = loaded_map
	current_map_id = map_id
	return current_map


func clear_current_map(parent_node: Node = null) -> void:
	if current_map != null and is_instance_valid(current_map):
		current_map.queue_free()
	elif parent_node != null:
		for child in parent_node.get_children():
			child.queue_free()
	current_map = null
	current_map_id = ""
