## Bridges runtime gameplay objects with the separated player/world save documents.
class_name SaveCoordinator
extends Node

const WorldItemScene := preload("res://scenes/items/WorldItem.tscn")

var game_session: Node
var player: Node
var inventory
var equipment_system
var hotbar_ui
var map_root: Node2D
var build_system: Node
var settlement_manager: Node
var day_night_cycle: Node


func setup(context: Dictionary) -> void:
	game_session = context.get("game_session") as Node
	player = context.get("player") as Node
	inventory = context.get("inventory")
	equipment_system = context.get("equipment_system")
	hotbar_ui = context.get("hotbar_ui")
	map_root = context.get("map_root") as Node2D
	build_system = context.get("build_system") as Node
	settlement_manager = context.get("settlement_manager") as Node
	day_night_cycle = context.get("day_night_cycle") as Node


func save_all() -> bool:
	if game_session == null:
		push_error("SaveCoordinator requires GameSession before saving.")
		return false
	_collect_player_data()
	_collect_world_data()
	return game_session.save_all()


func load_session(slot_id: String) -> bool:
	if game_session == null:
		push_error("SaveCoordinator requires GameSession before loading.")
		return false
	return game_session.load_session(slot_id)


func apply_loaded_data() -> void:
	_apply_player_data()
	_apply_world_data()


func _collect_player_data() -> void:
	if game_session == null:
		return
	var data: Dictionary = game_session.get("player_data")
	if inventory != null and inventory.has_method("get_slots"):
		data["inventory_slots"] = inventory.get_slots()
	if equipment_system != null and equipment_system.has_method("get_slots_for_save"):
		data["equipment_slots"] = equipment_system.get_slots_for_save()
	if player != null:
		data["level"] = int(player.get("level"))
		data["current_xp"] = int(player.get("current_xp"))
		data["xp_to_next_level"] = int(player.get("xp_to_next_level"))
		data["health"] = int(player.get("health"))
		data["max_health"] = int(player.get("max_health"))
		if player.has_method("get_unlocked_tools"):
			data["unlocked_tools"] = player.get_unlocked_tools()
		if player.has_method("get_current_tool"):
			data["current_tool"] = player.get_current_tool()
		if player.has_method("get_debug_base_stats"):
			data["player_stats"] = {"base_stats": player.get_debug_base_stats()}
	if hotbar_ui != null:
		if hotbar_ui.has_method("get_hotbar_shortcuts"):
			data["hotbar_shortcuts"] = hotbar_ui.get_hotbar_shortcuts()
		data["selected_hotbar_slot"] = int(hotbar_ui.get("selected_slot"))
	game_session.set("player_data", data)


func _apply_player_data() -> void:
	if game_session == null:
		return
	var data: Dictionary = game_session.get("player_data")
	if inventory != null and inventory.has_method("set_slots"):
		var inventory_slots: Variant = data.get("inventory_slots", [])
		if inventory_slots is Array:
			inventory.set_slots(inventory_slots)
	if equipment_system != null and equipment_system.has_method("set_slots_from_save"):
		equipment_system.set_slots_from_save(data.get("equipment_slots", {}))
	if player != null:
		player.set("max_health", max(int(data.get("max_health", player.get("max_health"))), 1))
		player.set("health", clampi(int(data.get("health", player.get("max_health"))), 0, int(player.get("max_health"))))
		if player.has_method("load_progression_data"):
			player.load_progression_data({
				"level": data.get("level", 1),
				"current_xp": data.get("current_xp", 0),
				"xp_to_next_level": data.get("xp_to_next_level", 30),
			})
		if player.has_method("set_unlocked_tools"):
			var tools: Variant = data.get("unlocked_tools", [])
			player.set_unlocked_tools(tools if tools is Array else [])
		if player.has_method("set_current_tool"):
			player.set_current_tool(str(data.get("current_tool", "Hands")))
		_apply_player_base_stats(data)
	if hotbar_ui != null:
		if hotbar_ui.has_method("set_hotbar_shortcuts"):
			hotbar_ui.set_hotbar_shortcuts(data.get("hotbar_shortcuts", []))
		if hotbar_ui.has_method("select_slot"):
			hotbar_ui.select_slot(int(data.get("selected_hotbar_slot", 0)))
		if hotbar_ui.has_method("refresh"):
			hotbar_ui.refresh()


func _apply_player_base_stats(data: Dictionary) -> void:
	if player == null or not player.has_method("set_debug_base_stat"):
		return
	var player_stats: Variant = data.get("player_stats", {})
	if not player_stats is Dictionary:
		return
	var base_stats: Variant = player_stats.get("base_stats", {})
	if not base_stats is Dictionary:
		return
	for stat_name in base_stats.keys():
		player.set_debug_base_stat(str(stat_name), int(base_stats[stat_name]))


func _collect_world_data() -> void:
	if game_session == null or map_root == null:
		return
	var world_data: Dictionary = game_session.get("world_data")
	var maps_value: Variant = world_data.get("maps", {})
	var maps: Dictionary = maps_value if maps_value is Dictionary else {}
	var map_id := str(game_session.get("current_map_id"))
	if map_id.is_empty():
		return
	var map_data := _get_map_save_data()
	if build_system != null and build_system.has_method("get_built_buildings"):
		map_data["buildings"] = build_system.get_built_buildings()
	map_data["world_items"] = _get_world_items_save_data()
	map_data["npcs"] = _get_npc_save_data()
	maps[map_id] = map_data
	world_data["current_map_id"] = map_id
	world_data["maps"] = maps
	if settlement_manager != null and settlement_manager.has_method("get_save_data"):
		world_data["settlement"] = settlement_manager.get_save_data()
	if day_night_cycle != null:
		world_data["time"] = {"time_of_day": float(day_night_cycle.get("time_of_day"))}
	game_session.set("world_data", world_data)


func _apply_world_data() -> void:
	if game_session == null or map_root == null:
		return
	var map_data: Dictionary = game_session.get_current_map_data() if game_session.has_method("get_current_map_data") else {}
	if map_root.has_method("load_map_save_data"):
		map_root.load_map_save_data(map_data)
	if build_system != null and build_system.has_method("load_built_buildings"):
		var buildings: Variant = map_data.get("buildings", [])
		if buildings is Array:
			build_system.load_built_buildings(buildings)
	_load_world_items(map_data.get("world_items", []))
	_load_npc_save_data(map_data.get("npcs", []))
	var world_data: Dictionary = game_session.get("world_data")
	if settlement_manager != null and settlement_manager.has_method("load_save_data"):
		settlement_manager.load_save_data(world_data.get("settlement", {}))
	if day_night_cycle != null:
		var time_data: Variant = world_data.get("time", {})
		if time_data is Dictionary:
			day_night_cycle.set("time_of_day", float(time_data.get("time_of_day", 0.0)))


func _get_map_save_data() -> Dictionary:
	if map_root.has_method("get_map_save_data"):
		var data: Variant = map_root.get_map_save_data()
		return data if data is Dictionary else {}
	return {"map_id": str(game_session.get("current_map_id"))}


func _get_world_items_save_data() -> Array:
	var saved_items := []
	var world_items_root := _get_map_child("WorldItems")
	if world_items_root == null:
		return saved_items
	for world_item in world_items_root.get_children():
		if world_item.has_method("is_collected") and world_item.is_collected():
			continue
		if world_item.has_method("get_save_data"):
			saved_items.append(world_item.get_save_data())
	return saved_items


func _load_world_items(saved_items: Variant) -> void:
	var world_items_root := _get_map_child("WorldItems")
	if world_items_root == null:
		return
	for child in world_items_root.get_children():
		child.queue_free()
	if not saved_items is Array:
		return
	for saved_item in saved_items:
		if not saved_item is Dictionary:
			continue
		var item_id := str(saved_item.get("item_id", ""))
		var amount := int(saved_item.get("amount", 0))
		var position_data: Variant = saved_item.get("position", {})
		if item_id.is_empty() or amount <= 0 or not position_data is Dictionary:
			continue
		var world_item := WorldItemScene.instantiate() as Node2D
		world_items_root.add_child(world_item)
		world_item.global_position = Vector2(float(position_data.get("x", 0.0)), float(position_data.get("y", 0.0)))
		var metadata: Variant = saved_item.get("metadata", {})
		world_item.setup(item_id, amount, metadata if metadata is Dictionary else {})


func _get_npc_save_data() -> Array:
	var saved_npcs := []
	var npcs_root := _get_map_child("NPCs")
	if npcs_root == null:
		return saved_npcs
	for npc in npcs_root.get_children():
		if npc.has_method("get_save_data"):
			saved_npcs.append(npc.get_save_data())
	return saved_npcs


func _load_npc_save_data(saved_npcs: Variant) -> void:
	if not saved_npcs is Array:
		return
	var npcs_root := _get_map_child("NPCs")
	if npcs_root == null:
		return
	var data_by_id := {}
	for npc_data in saved_npcs:
		if npc_data is Dictionary:
			var npc_id := str(npc_data.get("npc_instance_id", ""))
			if not npc_id.is_empty():
				data_by_id[npc_id] = npc_data
	for npc in npcs_root.get_children():
		if npc.has_method("get_npc_instance_id") and npc.has_method("load_save_data"):
			npc.load_save_data(data_by_id.get(str(npc.get_npc_instance_id()), {}))


func _get_map_child(node_name: String) -> Node2D:
	return map_root.get_node_or_null(NodePath(node_name)) as Node2D if map_root != null else null


# TODO(migration): add map flags, boss state and persistent enemies after their
# runtime spawners expose explicit map-root save/load APIs.
