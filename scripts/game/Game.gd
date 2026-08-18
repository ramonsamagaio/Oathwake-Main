## New gameplay root that composes a map, runtime entities and UI around GameSession.
extends Node2D

const InventoryScript := preload("res://scripts/Inventory.gd")
const EquipmentSystemScript := preload("res://scripts/systems/EquipmentSystem.gd")
const GameplayInventoryBridgeScript := preload("res://scripts/game/GameplayInventoryBridge.gd")
const GameplayAudioControllerScript := preload("res://scripts/game/GameplayAudioController.gd")
const ResourceSceneFactoryScript := preload("res://scripts/resources/ResourceSceneFactory.gd")
const MonsterSpawnerScript := preload("res://scripts/systems/MonsterSpawner.gd")
const WorldItemSpawner := preload("res://scripts/systems/WorldItemSpawner.gd")
const AmbientParticleFieldScript := preload("res://scripts/effects/AmbientParticleField.gd")

var inventory := InventoryScript.new()
var equipment_system := EquipmentSystemScript.new()
var game_session: Node
var current_map: Node2D
var inventory_bridge: GameplayInventoryBridge
var audio_controller: GameplayAudioController
var monster_spawner := MonsterSpawnerScript.new()
var resource_scene_factory := ResourceSceneFactoryScript.new()
var ambient_particle_field: Node2D

@onready var current_map_root: Node2D = $CurrentMapRoot
@onready var runtime_entities: Node2D = $RuntimeEntities
@onready var player: CharacterBody2D = $RuntimeEntities/Player
@onready var map_loader: MapLoader = $Systems/MapLoader
@onready var build_system = $Systems/BuildSystem
@onready var save_coordinator: SaveCoordinator = $Systems/SaveCoordinator
@onready var crafting_system = $Systems/CraftingSystem
@onready var housing_system = $Systems/HousingSystem
@onready var settlement_manager = $Systems/SettlementManager
@onready var day_night_cycle = $Systems/DayNightCycle
@onready var romestead_environment = $Systems/RomesteadEnvironment
@onready var alabaster_weather = $Systems/AlabasterWeather
@onready var night_enemy_spawner = $Systems/NightEnemySpawner
@onready var inventory_ui = $UI/InventoryUI
@onready var hotbar_ui = $UI/HotbarUI
@onready var storage_ui = $UI/StorageUI
@onready var workbench_ui = $UI/WorkbenchUI
@onready var character_status_ui = $UI/CharacterStatusUI
@onready var hud_status_ui = $UI/HUDStatusUI
@onready var save_button: Button = $UI/SaveButton
@onready var load_button: Button = $UI/LoadButton
@onready var spawn_monster_button: Button = $UI/SpawnMonsterButton
@onready var weather_button: Button = $UI/WeatherButton
@onready var weather_panel: Panel = $UI/WeatherControlPanel
@onready var monster_spawn_panel: Panel = $UI/MonsterSpawnPanel
@onready var close_monster_spawn_button: Button = $UI/MonsterSpawnPanel/CloseButton
@onready var monster_spawn_list: VBoxContainer = $UI/MonsterSpawnPanel/SpawnScroll/MonsterList


func _ready() -> void:
	add_to_group("main") # Compatibility bridge for existing Player and item scripts.
	game_session = get_node_or_null("/root/GameSession")
	if game_session == null:
		push_error("Game requires the GameSession autoload.")
		return
	_ensure_development_session()
	inventory_bridge = GameplayInventoryBridgeScript.new()
	add_child(inventory_bridge)
	add_child(monster_spawner)
	_setup_ui()
	_configure_debug_action_buttons()
	_configure_monster_spawn_debug_ui()
	_load_current_map()
	_setup_runtime_systems()
	_configure_save_coordinator()
	save_coordinator.apply_loaded_data()
	_configure_weather_ui()
	_connect_player_status()
	audio_controller = GameplayAudioControllerScript.new()
	add_child(audio_controller)
	audio_controller.setup(current_map, player)


func add_item_to_inventory(item_id: String, amount: int, metadata: Dictionary = {}) -> int:
	return inventory_bridge.add_item(item_id, amount, metadata)


func can_spend_resource(item_id: String, amount: int) -> bool:
	return inventory_bridge.can_spend(item_id, amount)


func spend_resource(item_id: String, amount: int) -> bool:
	return inventory_bridge.spend(item_id, amount)


func open_storage(storage_node: Node) -> void:
	inventory_bridge.open_storage(storage_node)


func add_resource(resource_name: String, amount: int) -> void:
	var leftover := add_item_to_inventory(resource_name, amount)
	if leftover > 0:
		print("Inventory full. Could not add %d %s" % [leftover, resource_name])


func _on_resource_collected(_resource_id: String, _item_id: String, _amount: int) -> void:
	# Resource pickup is handled by world drops; this keeps the debug-spawned nodes compatible.
	pass


func drop_item_near_player(item_id: String, amount: int, metadata: Dictionary = {}) -> void:
	if item_id.is_empty() or amount <= 0:
		return
	WorldItemSpawner.spawn_item_near_position(item_id, amount, player.global_position, metadata)


func on_building_removed(building_type: String, _position: Vector2, metadata := {}) -> void:
	if building_type == "bed" and settlement_manager != null and settlement_manager.has_method("on_bed_removed"):
		settlement_manager.on_bed_removed(str(metadata.get("bed_id", "")))
	if housing_system != null:
		housing_system.validate_houses(false)
	if settlement_manager != null:
		settlement_manager.validate_assignments()


func save_game() -> bool:
	return save_coordinator.save_all() if save_coordinator != null else false


func load_game(slot_id: String) -> bool:
	if save_coordinator == null or not save_coordinator.load_session(slot_id):
		return false
	_load_current_map()
	_setup_runtime_systems()
	_configure_save_coordinator()
	save_coordinator.apply_loaded_data()
	return true


func _on_save_button_pressed() -> void:
	if save_game():
		print("Game saved for slot %s" % str(game_session.get("active_slot_id")))


func _on_load_button_pressed() -> void:
	var slot_id := str(game_session.get("active_slot_id"))
	if slot_id.is_empty():
		push_warning("Game could not load because there is no active session slot.")
		return
	if load_game(slot_id):
		print("Game loaded for slot %s" % slot_id)


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
	_resolve_current_map_from_player_state()
	var map_id := str(game_session.get("current_map_id"))
	if map_id.is_empty():
		map_id = "start_area"
		game_session.set_current_map_id(map_id)
	current_map = map_loader.load_map(map_id, current_map_root)
	if current_map == null:
		return
	_position_player_at_map_spawn(current_map)
	_connect_current_map_systems(current_map)
	if current_map is MapRoot:
		WorldItemSpawner.set_world_items_root((current_map as MapRoot).get_world_items_root())


func _resolve_current_map_from_player_state() -> void:
	var world_data: Dictionary = game_session.get("world_data")
	var player_states: Variant = world_data.get("player_states", {})
	if not player_states is Dictionary:
		return
	var player_state: Variant = player_states.get(str(game_session.get("active_player_id")), {})
	if player_state is Dictionary and bool(player_state.get("initialized", false)):
		var map_id := str(player_state.get("current_map_id", ""))
		if not map_id.is_empty():
			game_session.set_current_map_id(map_id)


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
		"settlement_manager": settlement_manager,
		"day_night_cycle": day_night_cycle,
	})


func _setup_runtime_systems() -> void:
	if not current_map is MapRoot:
		return
	var map := current_map as MapRoot
	crafting_system.setup({"controller": self, "player": player, "build_system": build_system, "workbench_ui": workbench_ui})
	housing_system.setup({"build_system": build_system})
	settlement_manager.setup({"controller": self, "player": player, "build_system": build_system, "housing_system": housing_system})
	day_night_cycle.setup({"canvas_modulate": $WorldTint})
	day_night_cycle.external_visual_control = true
	var lighting_callback := Callable(self, "_on_game_lighting_state_changed")
	if not day_night_cycle.lighting_state_changed.is_connected(lighting_callback):
		day_night_cycle.lighting_state_changed.connect(lighting_callback)
	var procedural_world := map.find_child("RomesteadProceduralGameWorld", true, false)
	romestead_environment.set_world(procedural_world)
	_setup_ambient_particle_field(procedural_world)
	_on_game_lighting_state_changed(
		day_night_cycle.time_of_day,
		day_night_cycle.get_night_strength(),
		day_night_cycle.get_daylight_strength(),
		day_night_cycle.get_sun_shadow_direction_degrees()
	)
	night_enemy_spawner.setup({"player": player, "day_night_cycle": day_night_cycle, "enemies_root": map.get_enemies_root(), "build_system": build_system, "world": map})


func _setup_ambient_particle_field(wind_source: Node) -> void:
	if ambient_particle_field == null or not is_instance_valid(ambient_particle_field):
		ambient_particle_field = AmbientParticleFieldScript.new()
		ambient_particle_field.name = "RomesteadAmbientParticles"
		add_child(ambient_particle_field)
	var particle_config := {
		"enabled": true,
		"area_size": {"x": 896.0, "y": 528.0},
		"day_alpha": 1.15,
		"night_alpha": 1.35,
		"firefly_count": 10,
		"leaf_count": 16,
		"pollen_count": 24,
		"firefly_color": "#FFE286FF",
		"leaf_color": "#758B4DFF",
		"pollen_color": "#D8D19AFF",
		"z_index": 3600,
	}
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		var profile: Dictionary = content_db.get_vfx_profile("default")
		var world_visuals_value: Variant = profile.get("world_visuals", {})
		if world_visuals_value is Dictionary:
			var configured_value: Variant = (world_visuals_value as Dictionary).get("particles", {})
			if configured_value is Dictionary:
				particle_config.merge((configured_value as Dictionary), true)
	ambient_particle_field.call("configure", particle_config, wind_source)


func _on_game_lighting_state_changed(normalized_time: float, _night_strength: float, _daylight_strength: float, _shadow_degrees: float) -> void:
	if romestead_environment != null:
		# Oathwake stores 0.0 as dawn and 0.5 as dusk. Romestead stores clock
		# hours, so preserve gameplay day/night semantics while changing visuals.
		romestead_environment.set_time(fposmod(normalized_time * 24.0 + 6.0, 24.0))


func _connect_player_status() -> void:
	if player.has_signal("health_changed"):
		player.health_changed.connect(func(current_health, max_health): hud_status_ui.set_health(current_health, max_health))
	if player.has_signal("xp_changed"):
		player.xp_changed.connect(func(current_xp, xp_next, level): hud_status_ui.set_xp(current_xp, xp_next, level))
	if player.has_signal("tool_changed"):
		player.tool_changed.connect(func(tool_name): hud_status_ui.set_current_tool(tool_name))
	hud_status_ui.set_health(player.health, player.max_health)
	hud_status_ui.set_xp(player.current_xp, player.xp_to_next_level, player.level)
	hud_status_ui.set_current_tool(player.get_current_tool())


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


func _configure_debug_action_buttons() -> void:
	save_button.focus_mode = Control.FOCUS_NONE
	load_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(_on_save_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)


func _configure_monster_spawn_debug_ui() -> void:
	spawn_monster_button.focus_mode = Control.FOCUS_NONE
	spawn_monster_button.text = "SPAWN"
	close_monster_spawn_button.focus_mode = Control.FOCUS_NONE
	monster_spawn_panel.visible = false
	spawn_monster_button.pressed.connect(_on_spawn_monster_button_pressed)
	close_monster_spawn_button.pressed.connect(_on_close_monster_spawn_pressed)
	_populate_spawn_debug_panel()


func _configure_weather_ui() -> void:
	weather_button.focus_mode = Control.FOCUS_NONE
	weather_button.pressed.connect(weather_panel.toggle_panel)
	weather_panel.setup(day_night_cycle, alabaster_weather)


func _populate_spawn_debug_panel() -> void:
	for child in monster_spawn_list.get_children():
		child.queue_free()

	_add_spawn_panel_title("Natural Spawn")
	var natural_spawn_toggle := CheckBox.new()
	natural_spawn_toggle.text = "Natural map spawn"
	natural_spawn_toggle.focus_mode = Control.FOCUS_NONE
	natural_spawn_toggle.button_pressed = _is_natural_spawn_enabled()
	natural_spawn_toggle.toggled.connect(_on_natural_spawn_toggled)
	monster_spawn_list.add_child(natural_spawn_toggle)

	_add_spawn_panel_title("Spawn Categories")
	_add_spawn_navigation_button("Monsters", _show_monster_spawn_category)
	_add_spawn_navigation_button("Trees / Wood", _show_resource_spawn_category.bind("wood"))
	_add_spawn_navigation_button("Ores / Rocks", _show_resource_spawn_category.bind("ore"))
	_add_spawn_navigation_button("Other Resources", _show_resource_spawn_category.bind("other"))
	_add_spawn_navigation_button("Items", _show_items_spawn_category)


func _add_spawn_panel_title(title_text: String) -> void:
	var label := Label.new()
	label.text = title_text
	monster_spawn_list.add_child(label)


func _add_spawn_navigation_button(label_text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label_text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	monster_spawn_list.add_child(button)


func _clear_spawn_panel_content(title_text: String, show_back_button := true) -> void:
	for child in monster_spawn_list.get_children():
		child.queue_free()

	if show_back_button:
		var back_button := Button.new()
		back_button.text = "Back"
		back_button.focus_mode = Control.FOCUS_NONE
		back_button.pressed.connect(_populate_spawn_debug_panel)
		monster_spawn_list.add_child(back_button)

	_add_spawn_panel_title(title_text)


func _show_monster_spawn_category() -> void:
	_clear_spawn_panel_content("Monsters")
	_populate_monster_spawn_buttons()


func _show_items_spawn_category() -> void:
	_clear_spawn_panel_content("Items")
	_populate_items_spawn_buttons()


func _show_resource_spawn_category(category: String) -> void:
	match category:
		"wood":
			_clear_spawn_panel_content("Trees / Wood")
		"ore":
			_clear_spawn_panel_content("Ores / Rocks")
		_:
			_clear_spawn_panel_content("Other Resources")
	_populate_resource_spawn_buttons(category)


func _populate_monster_spawn_buttons() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_all_monsters"):
		return

	var monsters: Dictionary = content_db.get_all_monsters()
	var monster_ids: Array = monsters.keys()
	monster_ids.sort()
	for monster_id in monster_ids:
		var monster_data: Variant = monsters[monster_id]
		if not monster_data is Dictionary:
			continue

		var button := Button.new()
		button.text = str(monster_data.get("display_name", str(monster_id).capitalize()))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_debug_spawn_monster_pressed.bind(str(monster_id)))
		monster_spawn_list.add_child(button)


func _populate_resource_spawn_buttons(category: String) -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_all_resources"):
		return

	var resources: Dictionary = content_db.get_all_resources()
	var resource_ids: Array = resources.keys()
	resource_ids.sort()
	for resource_id in resource_ids:
		var resource_data: Variant = resources[resource_id]
		if not resource_data is Dictionary:
			continue
		if _get_resource_spawn_category(str(resource_id), resource_data) != category:
			continue

		var button := Button.new()
		button.text = "%s  [T%d]" % [
			str(resource_data.get("display_name", str(resource_id).capitalize())),
			int(resource_data.get("resource_tier", 1)),
		]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_debug_spawn_resource_pressed.bind(str(resource_id)))
		monster_spawn_list.add_child(button)


func _populate_items_spawn_buttons(search_text := "") -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("get_all_items"):
		return

	var items: Dictionary = content_db.get_all_items()
	var item_ids: Array = items.keys()
	item_ids.sort()

	var search_line := LineEdit.new()
	search_line.placeholder_text = "Search items..."
	search_line.focus_mode = Control.FOCUS_ALL
	search_line.text = search_text
	search_line.text_changed.connect(_on_items_search_text_changed)
	monster_spawn_list.add_child(search_line)

	for item_id in item_ids:
		var item_data: Variant = items[item_id]
		if not item_data is Dictionary:
			continue
		var display_name := str(item_data.get("display_name", str(item_id).capitalize()))
		var item_type := str(item_data.get("item_type", ""))

		if not search_text.is_empty():
			var search_lower := search_text.to_lower()
			var match_name := display_name.to_lower().contains(search_lower)
			var match_id := str(item_id).to_lower().contains(search_lower)
			var match_type := item_type.to_lower().contains(search_lower)
			if not match_name and not match_id and not match_type:
				continue

		var button := Button.new()
		button.text = "%s  [%s]" % [display_name, item_type]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_debug_spawn_item_pressed.bind(str(item_id)))
		monster_spawn_list.add_child(button)

	if search_text.is_empty():
		search_line.grab_focus()


func _on_items_search_text_changed(new_text: String) -> void:
	_clear_spawn_panel_content("Items", false)
	_populate_items_spawn_buttons(new_text)
	_add_spawn_back_button_for_items()


func _add_spawn_back_button_for_items() -> void:
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(_populate_spawn_debug_panel)
	var first_child: Node = monster_spawn_list.get_child(0)
	if first_child != null:
		monster_spawn_list.add_child(back_button)
		monster_spawn_list.move_child(back_button, 0)
	else:
		monster_spawn_list.add_child(back_button)


func _on_debug_spawn_item_pressed(item_id: String) -> void:
	var leftover := add_item_to_inventory(item_id, 1)
	if leftover == 0:
		print("Spawned item: %s" % item_id)
	else:
		print("Inventory full, could not spawn: %s" % item_id)


func _get_resource_spawn_category(resource_id: String, resource_data: Dictionary) -> String:
	var required_tool_type := str(resource_data.get("required_tool_type", ""))
	var skill_type := str(resource_data.get("skill_type", ""))
	if required_tool_type == "axe" or skill_type == "lumbering" or resource_id.contains("tree"):
		return "wood"
	if required_tool_type == "pickaxe" or skill_type == "mining" or resource_id.contains("ore") or resource_id.contains("rock") or resource_id.contains("node"):
		return "ore"
	return "other"


func _on_spawn_monster_button_pressed() -> void:
	_populate_spawn_debug_panel()
	monster_spawn_panel.visible = true


func _on_close_monster_spawn_pressed() -> void:
	monster_spawn_panel.visible = false


func _on_debug_spawn_monster_pressed(monster_id: String) -> void:
	var enemies_root := _get_current_enemies_root()
	if enemies_root == null:
		push_warning("Game could not find the current map enemy root for debug spawn.")
		return
	var monster := monster_spawner.spawn_monster(monster_id, player.global_position + Vector2(96, 0))
	if monster == null:
		return
	enemies_root.add_child(monster)
	print("Spawned monster: %s" % monster_id)


func _on_debug_spawn_resource_pressed(resource_type_id: String) -> void:
	var resources_root := _get_current_resources_root()
	if resources_root == null:
		push_warning("Game could not find the current map resource root for debug spawn.")
		return
	var resource_id := "debug_%s_%d" % [resource_type_id, Time.get_ticks_msec()]
	var resource_position := resources_root.to_local(player.global_position + Vector2(-96, 0))
	var resource := resource_scene_factory.instantiate_resource(resource_type_id, resource_id, resource_position)
	if resource == null:
		return
	resources_root.add_child(resource)
	resource.global_position = player.global_position + Vector2(-96, 0)
	if resource.has_signal("collected"):
		resource.connect("collected", _on_resource_collected)
	print("Spawned resource: %s" % resource_type_id)


func _on_natural_spawn_toggled(is_enabled: bool) -> void:
	if night_enemy_spawner != null:
		night_enemy_spawner.natural_spawn_enabled = is_enabled
	print("Natural monster spawn: %s" % ("ON" if is_enabled else "OFF"))


func _is_natural_spawn_enabled() -> bool:
	if night_enemy_spawner == null:
		return false
	return bool(night_enemy_spawner.get("natural_spawn_enabled"))


func _get_current_enemies_root() -> Node2D:
	if current_map is MapRoot:
		return (current_map as MapRoot).get_enemies_root()
	return null


func _get_current_resources_root() -> Node2D:
	if current_map is MapRoot:
		return (current_map as MapRoot).get_resources_root()
	return null
