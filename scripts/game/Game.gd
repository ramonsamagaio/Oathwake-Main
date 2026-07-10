## New gameplay root that composes a map, runtime entities and UI around GameSession.
extends Node2D

const InventoryScript := preload("res://scripts/Inventory.gd")
const EquipmentSystemScript := preload("res://scripts/systems/EquipmentSystem.gd")
const GameplayInventoryBridgeScript := preload("res://scripts/game/GameplayInventoryBridge.gd")

var inventory := InventoryScript.new()
var equipment_system := EquipmentSystemScript.new()
var game_session: Node
var current_map: Node2D
var inventory_bridge: GameplayInventoryBridge

@onready var current_map_root: Node2D = $CurrentMapRoot
@onready var runtime_entities: Node2D = $RuntimeEntities
@onready var player: CharacterBody2D = $RuntimeEntities/Player
@onready var map_loader: MapLoader = $Systems/MapLoader
@onready var build_system = $Systems/BuildSystem
@onready var save_coordinator: SaveCoordinator = $Systems/SaveCoordinator
@onready var inventory_ui = $UI/InventoryUI
@onready var hotbar_ui = $UI/HotbarUI
@onready var storage_ui = $UI/StorageUI
@onready var workbench_ui = $UI/WorkbenchUI
@onready var character_status_ui = $UI/CharacterStatusUI


func _ready() -> void:
	add_to_group("main") # Compatibility bridge for existing Player and item scripts.
	game_session = get_node_or_null("/root/GameSession")
	if game_session == null:
		push_error("Game requires the GameSession autoload.")
		return
	_ensure_development_session()
	inventory_bridge = GameplayInventoryBridgeScript.new()
	add_child(inventory_bridge)
	_setup_ui()
	_load_current_map()
	_configure_save_coordinator()
	save_coordinator.apply_loaded_data()


func add_item_to_inventory(item_id: String, amount: int, metadata: Dictionary = {}) -> int:
	return inventory_bridge.add_item(item_id, amount, metadata)


func can_spend_resource(item_id: String, amount: int) -> bool:
	return inventory_bridge.can_spend(item_id, amount)


func spend_resource(item_id: String, amount: int) -> bool:
	return inventory_bridge.spend(item_id, amount)


func open_storage(storage_node: Node) -> void:
	inventory_bridge.open_storage(storage_node)


func save_game() -> bool:
	return save_coordinator.save_all() if save_coordinator != null else false


func load_game(slot_id: String) -> bool:
	if save_coordinator == null or not save_coordinator.load_session(slot_id):
		return false
	_load_current_map()
	_configure_save_coordinator()
	save_coordinator.apply_loaded_data()
	return true


func _ensure_development_session() -> void:
	if not str(game_session.get("active_slot_id")).is_empty():
		return
	# This is intentionally isolated from SaveSlotSelect until its compatible migration.
	if not game_session.load_session("debug_slot"):
		push_error("Game could not create or load the development session.")


func _setup_ui() -> void:
	inventory_bridge.setup({
		"controller": self, "inventory": inventory, "equipment_system": equipment_system,
		"player": player, "inventory_ui": inventory_ui, "storage_ui": storage_ui,
		"hotbar_ui": hotbar_ui, "character_status_ui": character_status_ui,
		"workbench_ui": workbench_ui,
	})


func _load_current_map() -> void:
	var map_id := str(game_session.get("current_map_id"))
	if map_id.is_empty():
		map_id = "start_area"
		game_session.set_current_map_id(map_id)
	current_map = map_loader.load_map(map_id, current_map_root)
	if current_map == null:
		return
	_position_player_at_map_spawn(current_map)
	_connect_current_map_systems(current_map)


func _configure_save_coordinator() -> void:
	if save_coordinator == null:
		return
	save_coordinator.setup({
		"game_session": game_session,
		"player": player,
		"inventory": inventory,
		"equipment_system": equipment_system,
		"hotbar_ui": hotbar_ui,
		"map_root": current_map,
		"build_system": build_system,
	})


func _position_player_at_map_spawn(map_root: Node2D) -> void:
	if map_root.has_method("get_default_spawn_position"):
		player.global_position = map_root.get_default_spawn_position()
		return
	var spawn_node := map_root.find_child("PlayerSpawn", true, false) as Node2D
	if spawn_node != null:
		player.global_position = spawn_node.global_position
		return
	push_warning("Game map has no PlayerSpawn; keeping the Player scene position.")


func _connect_current_map_systems(map_root: Node2D) -> void:
	if build_system != null and build_system.has_method("setup") and map_root is MapRoot:
		var map := map_root as MapRoot
		build_system.setup({
			"controller": self,
			"player": player,
			"ground_layer": map.get_ground_layer(),
			"obstacle_layer": map.get_obstacle_layer(),
			"build_layer": map.get_build_layer(),
			"resources_root": map.get_resources_root(),
		})

	# TODO(migration): CraftingSystem, HousingSystem, DayNightCycle and
	# NightEnemySpawner currently require Main/World NodePaths. Move them to explicit
	# setup(context) APIs before they are instantiated under Game/Systems.
	# SaveCoordinator now restores resources, buildings, world items and static NPC data.
	# TODO(migration): persistent enemies need map-state adapters before WorldSave.maps
	# can restore them here.
	if map_root == null:
		return
