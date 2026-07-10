## Creates resource nodes from ContentDB scene_path with a stable generic fallback.
class_name ResourceSceneFactory
extends RefCounted

const FALLBACK_SCENE_PATH := "res://scenes/resources/ResourceNodeBase.tscn"


func get_scene_path_for_resource(resource_type_id: String) -> String:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var content_db := scene_tree.root.get_node_or_null("ContentDB") if scene_tree != null else null
	if content_db != null and content_db.has_method("has_resource") and content_db.has_resource(resource_type_id):
		var resource_data: Dictionary = content_db.get_resource(resource_type_id)
		var scene_path := str(resource_data.get("scene_path", ""))
		if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
			return scene_path
	return FALLBACK_SCENE_PATH


func instantiate_resource(resource_type_id: String, resource_id: String, position: Vector2) -> Node2D:
	var scene_path := get_scene_path_for_resource(resource_type_id)
	var resource_scene := load(scene_path) as PackedScene
	if resource_scene == null:
		push_error("ResourceSceneFactory could not load resource scene: %s" % scene_path)
		return null
	var resource_node := resource_scene.instantiate() as Node2D
	if resource_node == null:
		push_error("Resource scene must inherit Node2D: %s" % scene_path)
		return null

	resource_node.set("resource_type_id", resource_type_id)
	resource_node.set("resource_id", resource_id)
	resource_node.position = position
	return resource_node
