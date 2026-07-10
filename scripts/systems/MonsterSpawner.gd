extends Node

const GenericMonsterScene := preload("res://scenes/enemies/GenericMonster.tscn")


func get_scene_path(monster_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_monster"):
		push_warning("MonsterSpawner could not access ContentDB.")
		return GenericMonsterScene.resource_path

	var monster_data: Dictionary = content_db.get_monster(monster_id)
	if monster_data.is_empty():
		return GenericMonsterScene.resource_path

	var scene_path := str(monster_data.get("scene_path", ""))
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var custom_scene := load(scene_path)
		if custom_scene is PackedScene:
			return scene_path
		push_warning("MonsterSpawner scene is not a PackedScene: %s" % scene_path)
	elif not scene_path.is_empty():
		push_warning("MonsterSpawner could not find monster scene: %s" % scene_path)

	return GenericMonsterScene.resource_path


func spawn_monster(monster_id: String, position: Vector2) -> Node:
	var scene_path := get_scene_path(monster_id)
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("MonsterSpawner could not load monster scene: %s" % scene_path)
		return null

	var monster := scene.instantiate()
	if monster == null:
		push_warning("MonsterSpawner could not instantiate monster scene: %s" % scene_path)
		return null

	monster.set("monster_id", monster_id)

	if monster is Node2D:
		(monster as Node2D).global_position = position

	return monster
