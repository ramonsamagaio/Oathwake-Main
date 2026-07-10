extends Node2D

const Inventory = preload("res://scripts/Inventory.gd")
const SaveSystem = preload("res://scripts/systems/SaveSystem.gd")
const SaveSlotManager = preload("res://scripts/systems/SaveSlotManager.gd")
const SettingsManager = preload("res://scripts/systems/SettingsManager.gd")
const WorldItemSpawner = preload("res://scripts/systems/WorldItemSpawner.gd")
const InventoryDebug = preload("res://scripts/systems/InventoryDebug.gd")
const EquipmentSystem = preload("res://scripts/systems/EquipmentSystem.gd")
const GameplayInventoryBridge = preload("res://scripts/game/GameplayInventoryBridge.gd")
const GameplayAudioController = preload("res://scripts/game/GameplayAudioController.gd")
const DebugPanelController = preload("res://scripts/game/DebugPanelController.gd")
const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")
const HUDStatusUIScene := preload("res://scenes/ui/HUDStatusUI.tscn")
const DebugTreeScene = preload("res://scenes/Tree.tscn")
const DebugRockScene = preload("res://scenes/Rock.tscn")
const MonsterSpawner = preload("res://scripts/systems/MonsterSpawner.gd")
const BUILD_TYPE_BED := "bed"

var inventory := Inventory.new()
var equipment_system := EquipmentSystem.new()
var collected_resource_ids := {}
var save_system := SaveSystem.new()
var save_slot_manager: Node
var settings_manager: Node
var player_stat_spin_boxes := {}
var monster_spawner := MonsterSpawner.new()
var hud_status_ui: Control
var inventory_bridge: GameplayInventoryBridge
var audio_controller: GameplayAudioController
var debug_panel_controller: DebugPanelController

@export var bed_respawn_range: float = 72.0

@onready var world = $World
@onready var resources_root: Node2D = $World/Resources
@onready var wood_label: Label = $UI/WoodLabel
@onready var stone_label: Label = $UI/StoneLabel
@onready var gel_label: Label = $UI/GelLabel
@onready var tool_label: Label = $UI/ToolLabel
@onready var health_label: Label = $UI/HealthLabel
@onready var xp_label: Label = $UI/XpLabel
@onready var villagers_label: Label = $UI/VillagersLabel
@onready var houses_label: Label = $UI/HousesLabel
@onready var housed_villagers_label: Label = $UI/HousedVillagersLabel
@onready var save_button: Button = $UI/SaveButton
@onready var load_button: Button = $UI/LoadButton
@onready var player_stats_button: Button = $UI/PlayerStatsButton
@onready var player_stats_panel: Panel = $UI/PlayerStatsPanel
@onready var close_player_stats_button: Button = $UI/PlayerStatsPanel/CloseButton
@onready var player_stats_list: VBoxContainer = $UI/PlayerStatsPanel/StatsList
@onready var apply_player_stats_button: Button = $UI/PlayerStatsPanel/ApplyButton
@onready var spawn_monster_button: Button = $UI/SpawnMonsterButton
@onready var monster_spawn_panel: Panel = $UI/MonsterSpawnPanel
@onready var close_monster_spawn_button: Button = $UI/MonsterSpawnPanel/CloseButton
@onready var monster_spawn_list: VBoxContainer = $UI/MonsterSpawnPanel/SpawnScroll/MonsterList
@onready var inventory_ui = $UI/InventoryUI
@onready var storage_ui = $UI/StorageUI
@onready var hotbar_ui = $UI/HotbarUI
@onready var character_status_ui = $UI/CharacterStatusUI
@onready var player = $World/Player
@onready var enemies_root: Node2D = $World/Enemies
@onready var build_system = $BuildSystem
@onready var housing_system = $HousingSystem
@onready var settlement_manager = $SettlementManager
@onready var night_enemy_spawner = $NightEnemySpawner


func _ready() -> void:
	add_to_group("main")
	save_slot_manager = get_node_or_null("/root/SaveSlotManager")
	if save_slot_manager == null:
		save_slot_manager = SaveSlotManager.new()
	settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager == null:
		settings_manager = SettingsManager.new()
		settings_manager.load_settings()
		settings_manager.apply_settings()
	add_child(monster_spawner)
	audio_controller = GameplayAudioController.new()
	add_child(audio_controller)
	audio_controller.setup(world, player)
	_configure_save_buttons()
	_configure_player_stats_debug_ui()
	_configure_monster_spawn_debug_ui()
	_apply_oathwake_ui_font()
	_ensure_hud_status_ui()
	debug_panel_controller = DebugPanelController.new()
	add_child(debug_panel_controller)
	debug_panel_controller.setup({
		"hud_status_ui": hud_status_ui,
		"labels": {
			"wood": wood_label, "stone": stone_label, "gel": gel_label, "tool": tool_label,
			"health": health_label, "xp": xp_label, "villagers": villagers_label,
			"houses": houses_label, "housed_villagers": housed_villagers_label,
			"player_stats_panel": player_stats_panel, "monster_spawn_panel": monster_spawn_panel,
		},
		"panels": [wood_label, stone_label, gel_label, tool_label, health_label, xp_label,
			villagers_label, houses_label, housed_villagers_label, save_button, load_button,
			player_stats_button, spawn_monster_button],
	})
	_set_debug_ui_visible(false)
	inventory_bridge = GameplayInventoryBridge.new()
	add_child(inventory_bridge)
	inventory_bridge.setup({
		"controller": self, "inventory": inventory, "equipment_system": equipment_system,
		"player": player, "inventory_ui": inventory_ui, "storage_ui": storage_ui,
		"hotbar_ui": hotbar_ui, "character_status_ui": character_status_ui,
		"workbench_ui": $UI/WorkbenchUI,
	})
	inventory.changed.connect(_update_resource_labels)
	player.health_changed.connect(_update_health_label)
	player.tool_changed.connect(_update_tool_label)
	housing_system.changed.connect(_on_housing_changed)
	settlement_manager.changed.connect(_update_settlement_labels)
	equipment_system.changed.connect(inventory_ui.refresh)
	equipment_system.changed.connect(_update_tool_label)
	if player.has_signal("xp_changed"):
		player.xp_changed.connect(_update_xp_label)
	if player.has_signal("level_changed"):
		player.level_changed.connect(_update_xp_label_from_player)
	save_button.pressed.connect(save_game)
	load_button.pressed.connect(load_game)
	_connect_resource_nodes()
	_update_resource_labels()
	_update_tool_label(player.get_current_tool())
	_update_health_label(player.health, player.max_health)
	_update_xp_label_from_player()
	_update_settlement_labels()
	load_game()


func _process(delta: float) -> void:
	if audio_controller != null:
		audio_controller.update_ambience(delta)


func _apply_oathwake_ui_font() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	_apply_oathwake_ui_font_recursive(ui)


func _apply_oathwake_ui_font_recursive(node: Node) -> void:
	if node is Label:
		if node.name == "XpLabel":
			OathwakeTextStyle.apply_profile_to_label(node as Label, "xp_number")
		else:
			OathwakeTextStyle.apply_profile_to_label(node as Label, "base_ui")
	elif node is Button:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "ui_button")
	elif node is LineEdit:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "base_ui")
	elif node is OptionButton:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "base_ui")
	elif node is SpinBox:
		OathwakeTextStyle.apply_profile_to_control(node as Control, "base_ui")

	for child in node.get_children():
		_apply_oathwake_ui_font_recursive(child)


func _ensure_hud_status_ui() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	var existing := ui.get_node_or_null("HUDStatusUI") as Control
	if existing != null:
		hud_status_ui = existing
		return
	hud_status_ui = HUDStatusUIScene.instantiate() as Control
	hud_status_ui.name = "HUDStatusUI"
	ui.add_child(hud_status_ui)
	ui.move_child(hud_status_ui, 0)


func _set_debug_ui_visible(is_visible: bool) -> void:
	if debug_panel_controller != null:
		debug_panel_controller.set_debug_visible(is_visible)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_set_debug_ui_visible(not debug_panel_controller.is_visible)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if _try_recruit_nearby_npc():
			get_viewport().set_input_as_handled()
			return

		if _try_interact_with_nearby_npc():
			get_viewport().set_input_as_handled()
			return

		_try_set_respawn_point()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		housing_system.validate_houses(true)
		settlement_manager.validate_assignments()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		InventoryDebug.validate_full_item_state(self)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		InventoryDebug.print_all(self)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		InventoryDebug.print_full_item_snapshot(self)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		settlement_manager.assign_nearby_npc_to_house()
		_update_settlement_labels()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		character_status_ui.toggle()
		get_viewport().set_input_as_handled()


func _connect_resource_nodes() -> void:
	for resource_node in resources_root.get_children():
		if resource_node.has_signal("collected"):
			resource_node.connect("collected", _on_resource_collected)


func _on_resource_collected(resource_id: String, _item_id: String, _amount: int) -> void:
	if not resource_id.is_empty():
		collected_resource_ids[resource_id] = true

	# Resource nodes spawn world items for pickup, so do not grant inventory here.
	# This keeps collected state tracking separate from the actual item pickup flow.


func add_resource(resource_name: String, amount: int) -> void:
	var leftover := add_item_to_inventory(resource_name, amount)
	if leftover > 0:
		print("Inventory full. Could not add %d %s" % [leftover, resource_name])


func add_item_to_inventory(item_id: String, amount: int, metadata: Dictionary = {}) -> int:
	return inventory_bridge.add_item(item_id, amount, metadata)


func drop_item_near_player(item_id: String, amount: int, metadata: Dictionary = {}) -> void:
	if item_id.is_empty() or amount <= 0:
		return

	WorldItemSpawner.spawn_item_near_position(item_id, amount, player.global_position, metadata)


func open_storage(storage_node) -> void:
	if build_system != null and build_system.has_method("set_build_mode_enabled"):
		build_system.set_build_mode_enabled(false)
	inventory_bridge.open_storage(storage_node)


func can_spend_resource(resource_name: String, amount: int) -> bool:
	return inventory_bridge.can_spend(resource_name, amount)


func spend_resource(resource_name: String, amount: int) -> bool:
	return inventory_bridge.spend(resource_name, amount)


func save_game() -> void:
	var save_data := {
		"inventory": inventory.get_all_items(),
		"inventory_slots": inventory.get_slots(),
		"equipment_slots": equipment_system.get_slots_for_save(),
		"walls": build_system.get_built_wall_cells(),
		"buildings": build_system.get_built_buildings(),
		"respawning_resources": _get_respawning_resources(),
		"world_items": _get_world_items_save_data(),
		"unlocked_tools": player.get_unlocked_tools(),
		"current_tool": player.get_current_tool(),
		"selected_hotbar_slot": int(hotbar_ui.get("selected_slot")) if hotbar_ui != null else 0,
		"hotbar_shortcuts": hotbar_ui.get_hotbar_shortcuts() if hotbar_ui != null and hotbar_ui.has_method("get_hotbar_shortcuts") else [],
		"player_progression": _get_player_progression_save_data(),
		"respawn_point": _get_respawn_point_save_data(),
		"settlement": settlement_manager.get_save_data(),
	}

	var save_path: String = save_slot_manager.get_active_save_path()
	var save_error := save_system.save_json(save_path, save_data)
	if not save_error.is_empty():
		print(save_error)
		return

	print("Game saved to %s" % save_path)


func load_game() -> void:
	var save_path: String = save_slot_manager.get_active_save_path()
	var save_result := save_system.load_json(save_path)
	if not bool(save_result.get("ok", false)):
		print(str(save_result.get("error", "Could not load save file.")))
		return

	var save_data: Dictionary = save_result.get("data", {})
	var inventory_slots = save_data.get("inventory_slots", [])
	if inventory_slots is Array:
		inventory.set_slots(inventory_slots)
	else:
		var inventory_data = save_data.get("inventory", {})
		if not inventory_data is Dictionary:
			inventory_data = {}
		_load_inventory(inventory_data)
	equipment_system.set_slots_from_save(save_data.get("equipment_slots", {}))
	inventory_ui.refresh()

	var buildings = save_data.get("buildings", [])
	if save_data.has("buildings") and buildings is Array:
		build_system.load_built_buildings(buildings)
	else:
		var wall_cells = save_data.get("walls", [])
		if not wall_cells is Array:
			wall_cells = []

		build_system.load_built_wall_cells(wall_cells)

	var respawning_resources = save_data.get("respawning_resources", [])
	if not respawning_resources is Array:
		respawning_resources = []

	_load_respawning_resources(respawning_resources)

	var world_items: Variant = save_data.get("world_items", [])
	if not world_items is Array:
		world_items = []
	_load_world_items(world_items)

	var unlocked_tools = save_data.get("unlocked_tools", [])
	if not unlocked_tools is Array:
		unlocked_tools = []

	player.set_unlocked_tools(unlocked_tools)
	player.set_current_tool(str(save_data.get("current_tool", player.get_current_tool())))
	_load_player_progression(save_data.get("player_progression", {}))
	_load_respawn_point(save_data.get("respawn_point", {}))
	if hotbar_ui != null:
		if hotbar_ui.has_method("set_hotbar_shortcuts"):
			hotbar_ui.set_hotbar_shortcuts(save_data.get("hotbar_shortcuts", []))
		hotbar_ui.refresh()
		if hotbar_ui.has_method("select_slot"):
			hotbar_ui.select_slot(int(save_data.get("selected_hotbar_slot", hotbar_ui.get("selected_slot"))))
	housing_system.validate_houses(false)
	settlement_manager.load_save_data(save_data.get("settlement", {}))
	_update_settlement_labels()
	_update_health_label(player.health, player.max_health)
	_update_xp_label_from_player()
	_update_tool_label(player.get_current_tool())
	print("Game loaded from %s" % save_path)


func _update_resource_labels() -> void:
	debug_panel_controller.set_resource_counts(
		_get_item_display_name("wood"), inventory.get_count("wood"),
		_get_item_display_name("stone"), inventory.get_count("stone"),
		_get_item_display_name("gel"), inventory.get_count("gel")
	)


func _update_health_label(current_health: int, max_health: int) -> void:
	debug_panel_controller.set_health(current_health, max_health)


func _update_xp_label(current_xp: Variant = null, xp_to_next_level: Variant = null, level: Variant = null) -> void:
	if xp_label == null:
		return

	var xp_value := int(current_xp if current_xp != null else player.current_xp)
	var xp_next := int(xp_to_next_level if xp_to_next_level != null else player.xp_to_next_level)
	var level_value := int(level if level != null else player.level)
	debug_panel_controller.set_xp(xp_value, xp_next, level_value)


func _update_xp_label_from_player(_level = null) -> void:
	_update_xp_label()


func _update_tool_label(current_tool := "") -> void:
	var display_tool := str(current_tool)
	debug_panel_controller.set_current_tool(display_tool)


func _update_settlement_labels() -> void:
	debug_panel_controller.set_settlement(
		settlement_manager.get_recruited_count(),
		housing_system.get_valid_house_count(),
		settlement_manager.get_housed_count()
	)


func _on_housing_changed(_valid_house_count: int) -> void:
	_update_settlement_labels()


func _configure_save_buttons() -> void:
	save_button.focus_mode = Control.FOCUS_NONE
	load_button.focus_mode = Control.FOCUS_NONE


func _configure_player_stats_debug_ui() -> void:
	player_stats_button.focus_mode = Control.FOCUS_NONE
	close_player_stats_button.focus_mode = Control.FOCUS_NONE
	apply_player_stats_button.focus_mode = Control.FOCUS_NONE
	player_stats_panel.visible = false
	player_stats_button.pressed.connect(_on_player_stats_button_pressed)
	close_player_stats_button.pressed.connect(_on_close_player_stats_pressed)
	apply_player_stats_button.pressed.connect(_on_apply_player_stats_pressed)
	_populate_player_stats_controls()


func _populate_player_stats_controls() -> void:
	player_stat_spin_boxes.clear()
	for child in player_stats_list.get_children():
		child.queue_free()

	var stats := _get_player_stats_for_debug()
	for stat_name in ["str", "dex", "agi", "vit", "wis", "int", "luk"]:
		var row := HBoxContainer.new()
		player_stats_list.add_child(row)

		var label := Label.new()
		label.text = stat_name.to_upper()
		label.custom_minimum_size = Vector2(52, 0)
		row.add_child(label)

		var spin_box := SpinBox.new()
		spin_box.min_value = 0
		spin_box.max_value = 999
		spin_box.step = 1
		spin_box.value = int(stats.get(stat_name, 5))
		spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spin_box)
		player_stat_spin_boxes[stat_name] = spin_box


func _get_player_stats_for_debug() -> Dictionary:
	if player.has_method("get_debug_base_stats"):
		return player.get_debug_base_stats()

	return {}


func _on_player_stats_button_pressed() -> void:
	_populate_player_stats_controls()
	player_stats_panel.visible = true
	monster_spawn_panel.visible = false


func _on_close_player_stats_pressed() -> void:
	player_stats_panel.visible = false


func _on_apply_player_stats_pressed() -> void:
	for stat_name in player_stat_spin_boxes.keys():
		var spin_box: SpinBox = player_stat_spin_boxes[stat_name]
		if player.has_method("set_debug_base_stat"):
			player.set_debug_base_stat(str(stat_name), int(spin_box.value))

	print("Applied debug player stats.")


func _configure_monster_spawn_debug_ui() -> void:
	spawn_monster_button.focus_mode = Control.FOCUS_NONE
	spawn_monster_button.text = "SPAWN"
	close_monster_spawn_button.focus_mode = Control.FOCUS_NONE
	monster_spawn_panel.visible = false
	spawn_monster_button.pressed.connect(_on_spawn_monster_button_pressed)
	close_monster_spawn_button.pressed.connect(_on_close_monster_spawn_pressed)
	_populate_spawn_debug_panel()


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
		var monster_data = monsters[monster_id]
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
		var resource_data = resources[resource_id]
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
		var item_data = items[item_id]
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
	var first_child = monster_spawn_list.get_child(0)
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
	player_stats_panel.visible = false


func _on_close_monster_spawn_pressed() -> void:
	monster_spawn_panel.visible = false


func _on_debug_spawn_monster_pressed(monster_id: String) -> void:
	var monster = monster_spawner.spawn_monster(monster_id, player.global_position + Vector2(96, 0))
	if monster == null:
		return
	enemies_root.add_child(monster)
	print("Spawned monster: %s" % monster_id)


func _on_debug_spawn_resource_pressed(resource_type_id: String) -> void:
	var resource_data := _get_resource_data(resource_type_id)
	var scene := DebugRockScene if str(resource_data.get("required_tool_type", "")) == "pickaxe" else DebugTreeScene
	var resource = scene.instantiate()
	resource.resource_type_id = resource_type_id
	resource.resource_id = "debug_%s_%d" % [resource_type_id, Time.get_ticks_msec()]
	resource.resource_name = str(resource_data.get("display_name", resource_type_id.capitalize()))
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
		return true
	return bool(night_enemy_spawner.natural_spawn_enabled)


func _get_resource_data(resource_type_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_resource") or not content_db.has_resource(resource_type_id):
		return {}
	return content_db.get_resource(resource_type_id)


func _load_inventory(inventory_data: Dictionary) -> void:
	var normalized_inventory := {}

	for item_id in inventory_data.keys():
		normalized_inventory[str(item_id).to_lower()] = int(inventory_data[item_id])

	if inventory_data.has("Wood"):
		normalized_inventory["wood"] = int(inventory_data.get("Wood", 0))
	if inventory_data.has("Stone"):
		normalized_inventory["stone"] = int(inventory_data.get("Stone", 0))
	if inventory_data.has("Gel"):
		normalized_inventory["gel"] = int(inventory_data.get("Gel", 0))

	inventory.set_items(normalized_inventory)


func _get_item_display_name(item_id: String) -> String:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return item_id.capitalize()

	var item_data: Dictionary = content_db.get_item(item_id)
	return str(item_data.get("display_name", item_id.capitalize()))


func _get_respawning_resources() -> Array:
	var respawning_resources := []

	for resource_node in resources_root.get_children():
		if not resource_node.has_method("is_collected"):
			continue

		if not resource_node.is_collected():
			continue

		if not resource_node.has_method("get_resource_id"):
			continue

		var resource_id := str(resource_node.get_resource_id())
		if resource_id.is_empty():
			continue

		var respawn_time_left := 0.0
		if resource_node.has_method("get_respawn_time_left"):
			respawn_time_left = float(resource_node.get_respawn_time_left())
		if respawn_time_left <= 0.0:
			continue

		respawning_resources.append({
			"id": resource_id,
			"respawn_time_left": respawn_time_left,
		})

	return respawning_resources


func _get_world_items_save_data() -> Array:
	var world_items := []

	for node in get_tree().get_nodes_in_group("world_item"):
		if not node is Node2D:
			continue
		if node.has_method("is_collected") and node.is_collected():
			continue

		var item_id := str(node.get("item_id"))
		var amount := int(node.get("amount"))
		if item_id.is_empty() or amount <= 0:
			continue

		if node.has_method("get_save_data"):
			world_items.append(node.get_save_data())
		else:
			var item_position: Vector2 = node.global_position
			world_items.append({
				"item_id": item_id,
				"amount": amount,
				"position": {
					"x": item_position.x,
					"y": item_position.y,
				},
			})

	return world_items


func _load_world_items(world_items: Array) -> void:
	WorldItemSpawner.clear_world_items()

	for raw_data in world_items:
		if not raw_data is Dictionary:
			continue
		var world_item_data: Dictionary = raw_data

		var item_id := str(world_item_data.get("item_id", ""))
		var amount := int(world_item_data.get("amount", 0))
		var raw_position: Variant = world_item_data.get("position", {})
		if not raw_position is Dictionary:
			continue
		if item_id.is_empty() or amount <= 0:
			continue

		var position_data: Dictionary = raw_position
		var world_position := Vector2(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.0))
		)
		var raw_metadata: Variant = world_item_data.get("metadata", {})
		var load_meta_dict := {}
		if raw_metadata is Dictionary:
			load_meta_dict = raw_metadata
		WorldItemSpawner.spawn_loaded_item(item_id, amount, world_position, load_meta_dict)


func _load_respawning_resources(respawning_resources: Array) -> void:
	collected_resource_ids.clear()
	var respawn_time_by_id := {}

	for respawning_resource in respawning_resources:
		if not respawning_resource is Dictionary:
			continue

		var resource_id := str(respawning_resource.get("id", ""))
		var respawn_time_left := float(respawning_resource.get("respawn_time_left", 0.0))
		if resource_id.is_empty() or respawn_time_left <= 0.0:
			continue

		respawn_time_by_id[resource_id] = respawn_time_left

	for resource_node in resources_root.get_children():
		if not resource_node.has_method("get_resource_id"):
			continue

		var resource_id := str(resource_node.get_resource_id())
		if respawn_time_by_id.has(resource_id):
			resource_node.set_collected(true, float(respawn_time_by_id[resource_id]))
			collected_resource_ids[resource_id] = true
		else:
			resource_node.set_collected(false)


func _load_collected_resources(resource_ids: Array) -> void:
	collected_resource_ids.clear()

	for resource_id in resource_ids:
		collected_resource_ids[str(resource_id)] = true

	for resource_node in resources_root.get_children():
		if not resource_node.has_method("get_resource_id"):
			continue

		resource_node.set_collected(collected_resource_ids.has(resource_node.get_resource_id()))


func _try_set_respawn_point() -> void:
	if not build_system.has_method("get_nearest_bed_position"):
		return

	var bed_position: Vector2 = build_system.get_nearest_bed_position(player.global_position, bed_respawn_range)
	if bed_position == Vector2.INF:
		print("Need a Bed nearby.")
		return

	player.set_respawn_point(bed_position)
	print("Respawn point set")


func _try_interact_with_nearby_npc() -> bool:
	for npc in get_tree().get_nodes_in_group("npc"):
		if not npc.has_method("try_interact_with_player"):
			continue

		if npc.call("try_interact_with_player", player):
			return true

	return false


func _try_recruit_nearby_npc() -> bool:
	for npc in get_tree().get_nodes_in_group("npc"):
		if not npc.has_method("try_recruit_with_player"):
			continue

		if npc.call("try_recruit_with_player", player):
			_update_settlement_labels()
			return true

	return false


func _get_respawn_point_save_data() -> Dictionary:
	if not player.has_method("has_custom_respawn_point") or not player.has_custom_respawn_point():
		return {
			"enabled": false,
		}

	var respawn_position: Vector2 = player.get_respawn_point()
	return {
		"enabled": true,
		"x": respawn_position.x,
		"y": respawn_position.y,
	}


func _load_respawn_point(respawn_point_data) -> void:
	if not respawn_point_data is Dictionary:
		player.clear_respawn_point()
		return

	if not bool(respawn_point_data.get("enabled", false)):
		player.clear_respawn_point()
		return

	var respawn_position := Vector2(
		float(respawn_point_data.get("x", 0.0)),
		float(respawn_point_data.get("y", 0.0))
	)

	if _is_bed_position_valid(respawn_position):
		player.set_respawn_point(respawn_position)
	else:
		player.clear_respawn_point()


func _get_player_progression_save_data() -> Dictionary:
	if not player.has_method("get_progression_data"):
		return {}

	return player.get_progression_data()


func _load_player_progression(player_progression_data) -> void:
	if not player.has_method("load_progression_data"):
		return

	player.load_progression_data(player_progression_data)


func _is_bed_position_valid(respawn_position: Vector2) -> bool:
	if not build_system.has_method("get_bed_positions"):
		return false

	for bed_position in build_system.get_bed_positions():
		if respawn_position.distance_to(bed_position) <= 2.0:
			return true

	return false


func on_building_removed(building_type: String, building_position: Vector2, metadata := {}) -> void:
	if building_type != BUILD_TYPE_BED:
		housing_system.validate_houses(false)
		settlement_manager.validate_assignments()
		return

	if settlement_manager.has_method("on_bed_removed"):
		settlement_manager.on_bed_removed(str(metadata.get("bed_id", "")))

	if not player.has_method("has_custom_respawn_point") or not player.has_custom_respawn_point():
		housing_system.validate_houses(false)
		settlement_manager.validate_assignments()
		return

	if player.get_respawn_point().distance_to(building_position) <= 2.0:
		player.clear_respawn_point()
		print("Respawn point cleared")

	housing_system.validate_houses(false)
	settlement_manager.validate_assignments()
