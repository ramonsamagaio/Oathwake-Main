extends Node


func get_scene_path(monster_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_monster"):
		push_warning("MonsterSpawner could not access ContentDB.")
		return ""

	var monster_data: Dictionary = content_db.get_monster(monster_id)
	if monster_data.is_empty():
		return ""

	var scene_path := str(monster_data.get("scene_path", ""))
	if scene_path.is_empty():
		push_warning("MonsterSpawner missing scene_path for monster_id: %s" % monster_id)
		return ""

	if not ResourceLoader.exists(scene_path):
		push_warning("MonsterSpawner could not find monster scene: %s" % scene_path)
		return ""

	return scene_path


func spawn_monster(monster_id: String, position: Vector2) -> Node:
	var scene_path := get_scene_path(monster_id)
	if scene_path.is_empty():
		return null

	var scene := load(scene_path)
	if scene == null or not scene is PackedScene:
		push_warning("MonsterSpawner could not load monster scene: %s" % scene_path)
		return null

	var monster := (scene as PackedScene).instantiate()
	if monster == null:
		push_warning("MonsterSpawner could not instantiate monster scene: %s" % scene_path)
		return null

	monster.set("monster_id", monster_id)

	if monster is Node2D:
		(monster as Node2D).global_position = position

	return monster
