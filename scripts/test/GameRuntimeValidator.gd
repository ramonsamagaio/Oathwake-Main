extends SceneTree

const GameScene := preload("res://scenes/game/Game.tscn")
const WorldItemSpawner := preload("res://scripts/systems/WorldItemSpawner.gd")
const SavePaths := preload("res://scripts/save/SavePaths.gd")
const PlayerProfileSave := preload("res://scripts/save/PlayerProfileSave.gd")
const WorldSave := preload("res://scripts/save/WorldSave.gd")
const SaveSession := preload("res://scripts/save/SaveSession.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	_check(game != null, "Game instance exists")
	_check(game.current_map is MapRoot, "Game loaded MapRoot")
	var map: MapRoot = game.current_map as MapRoot
	_check(not map.get_ground_layer().get_used_cells().is_empty(), "GroundLayer has usable cells")
	_check(map.get_build_layer() != null and map.get_resources_root() != null and map.get_enemies_root() != null, "Map runtime roots exist")
	_check(map.get_npcs_root() != null and map.get_world_items_root() != null and map.get_spawn_point("PlayerSpawn") != null, "Map NPC/item/spawn roots exist")
	_check(game.player != null and game.build_system != null and game.crafting_system != null, "Game player/build/crafting systems exist")
	_check(game.housing_system != null and game.settlement_manager != null and game.day_night_cycle != null and game.night_enemy_spawner != null, "Game world systems exist")
	_check(game.inventory_ui != null and game.hotbar_ui != null and game.storage_ui != null and game.workbench_ui != null, "Game UI systems exist")

	var appearance := {"gender": "feminino", "hair": "hair_f_02", "skin": "skin_02", "eyes": "eyes_02"}
	game.game_session.start_new_session("runtime_validation", "Test Hero", "Validation World", appearance)
	game.add_resource("wood", 20)
	var before_wood: int = int(game.inventory.get_count("wood"))
	var built := bool(game.build_system.call("_try_place_building", Vector2i(20, 20), "wall"))
	var buildings: Array = game.build_system.get_built_buildings()
	_check(built and not buildings.is_empty(), "BuildSystem places a wall on GroundLayer")
	_check(game.inventory.get_count("wood") < before_wood, "BuildSystem spends resources")
	game.save_coordinator.save_all()
	var map_data: Dictionary = game.game_session.get_current_map_data()
	_check(map_data.get("buildings", []) is Array and not map_data.get("buildings", []).is_empty(), "WorldSave map data contains buildings")
	_check(not game.game_session.player_data.has("buildings"), "PlayerSave data excludes buildings")
	game.build_system.load_built_buildings([])
	game.build_system.load_built_buildings(buildings)
	_check(not game.build_system.get_built_buildings().is_empty(), "BuildSystem restores saved buildings")

	WorldItemSpawner.set_world_items_root(map.get_world_items_root())
	WorldItemSpawner.spawn_item_near_position("wood", 1, game.player.global_position)
	await process_frame
	_check(map.get_world_items_root().get_child_count() > 0, "World item spawns in current map root")
	var spawned_item := map.get_world_items_root().get_child(map.get_world_items_root().get_child_count() - 1)
	var wood_before_pickup: int = int(game.inventory.get_count("wood"))
	spawned_item.call("_try_collect")
	await process_frame
	_check(game.inventory.get_count("wood") > wood_before_pickup, "Player collects world item through Game API")
	var resource_node := map.get_resources_root().get_child(0)
	var items_before_resource_drop := map.get_world_items_root().get_child_count()
	resource_node.call("take_damage", 9999)
	await process_frame
	_check(map.get_world_items_root().get_child_count() > items_before_resource_drop, "ResourceNode drops item into current map root")
	game.save_coordinator.save_all()
	map_data = game.game_session.get_current_map_data()
	_check(map_data.get("world_items", []) is Array and not map_data.get("world_items", []).is_empty(), "WorldSave map data contains world items")
	_check(not game.game_session.player_data.has("world_items"), "PlayerSave data excludes world items")
	_check(FileAccess.file_exists(SavePaths.get_player_path(game.game_session.active_player_id)), "PlayerSave file exists separately")
	_check(FileAccess.file_exists(SavePaths.get_world_path(game.game_session.active_world_id)), "WorldSave file exists separately")
	var player_result := PlayerProfileSave.new().load_profile(game.game_session.active_player_id)
	_check(bool(player_result.get("ok", false)) and str(player_result.get("data", {}).get("display_name", "")) == "Test Hero", "PlayerSave preserves display name")
	_check(player_result.get("data", {}).get("appearance", {}) == appearance, "PlayerSave preserves appearance")
	var world_result := WorldSave.new().load_world(game.game_session.active_world_id)
	_check(bool(world_result.get("ok", false)) and world_result.get("data", {}).get("player_states", {}).has(game.game_session.active_player_id), "WorldSave contains player state")
	var session_result := SaveSession.new().load_session("runtime_validation")
	var session_data: Dictionary = session_result.get("data", {})
	_check(bool(session_result.get("ok", false)) and session_data.keys().size() == 5 and session_data.has("slot_id") and session_data.has("player_id") and session_data.has("world_id"), "SessionSave stores only session link fields")
	_check(map.get_resources_root().get_child_count() > 0, "StartArea resource nodes are present")
	_check(game.crafting_system.main == game and game.crafting_system.workbench_ui == game.workbench_ui, "CraftingSystem received Game context")
	_check(game.housing_system.build_system == game.build_system and game.settlement_manager.player == game.player, "Housing and settlement received Game context")
	_check(game.day_night_cycle.canvas_modulate != null, "DayNightCycle received canvas modulate")

	if failures.is_empty():
		print("GAME_RUNTIME_VALIDATION: PASS")
		quit(0)
	else:
		push_error("GAME_RUNTIME_VALIDATION failures: %s" % "; ".join(failures))
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)
