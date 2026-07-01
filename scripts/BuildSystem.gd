extends Node

const RecipeBookScript = preload("res://scripts/systems/RecipeBook.gd")
const SOURCE_ID := 0
const BUILD_TYPE_WALL := RecipeBookScript.WALL_ID
const BUILD_TYPE_CAMPFIRE := RecipeBookScript.CAMPFIRE_ID
const BUILD_TYPE_WORKBENCH := RecipeBookScript.WORKBENCH_ID
const BUILD_TYPE_BED := RecipeBookScript.BED_ID
const BUILD_TYPE_CHEST := RecipeBookScript.CHEST_ID
const ChestScene := preload("res://scenes/buildings/Chest.tscn")
const WALL_TILE := Vector2i(2, 0)
const CAMPFIRE_TILE := Vector2i(3, 0)
const WORKBENCH_TILE := Vector2i(4, 0)
const BED_TILE := Vector2i(5, 0)
const CHEST_TILE := Vector2i(2, 0)
const VALID_PREVIEW_COLOR := Color(0.50, 0.32, 0.18, 0.55)
const VALID_CAMPFIRE_PREVIEW_COLOR := Color(0.88, 0.34, 0.10, 0.55)
const VALID_WORKBENCH_PREVIEW_COLOR := Color(0.44, 0.28, 0.14, 0.55)
const VALID_BED_PREVIEW_COLOR := Color(0.42, 0.34, 0.62, 0.55)
const VALID_CHEST_PREVIEW_COLOR := Color(0.55, 0.34, 0.12, 0.55)
const INVALID_PREVIEW_COLOR := Color(0.90, 0.12, 0.10, 0.55)

@export var tile_size: Vector2i = Vector2i(32, 32)
@export var main_path: NodePath = ".."
@export var player_path: NodePath = "../World/Player"
@export var build_layer_path: NodePath = "../World/BuildLayer"
@export var ground_layer_path: NodePath = "../World/GroundLayer"
@export var obstacle_layer_path: NodePath = "../World/ObstacleLayer"
@export var resources_root_path: NodePath = "../World/Resources"
@export var build_label_path: NodePath = "../UI/BuildLabel"

var build_mode_enabled := false
var current_tile := Vector2i.ZERO
var selected_build_type := BUILD_TYPE_WALL
var preview: Polygon2D
var recipe_book := RecipeBookScript.new()
var building_metadata_by_cell := {}
var building_scene_by_cell := {}
var next_bed_id := 1
var next_chest_id := 1

@onready var main = get_node(main_path)
@onready var player: CharacterBody2D = get_node(player_path)
@onready var build_layer: TileMapLayer = get_node(build_layer_path)
@onready var ground_layer: TileMapLayer = get_node(ground_layer_path)
@onready var obstacle_layer: TileMapLayer = get_node(obstacle_layer_path)
@onready var resources_root: Node2D = get_node(resources_root_path)
@onready var build_label: Label = get_node(build_label_path)
var buildings_root: Node2D


func _ready() -> void:
	add_to_group("build_system")
	buildings_root = _get_or_create_buildings_root()

	if build_layer.tile_set != null:
		tile_size = build_layer.tile_set.tile_size

	_create_preview()
	_update_build_label()


func _process(_delta: float) -> void:
	current_tile = _get_mouse_tile()
	_update_preview()
	_update_build_label()


func _unhandled_input(event: InputEvent) -> void:
	if _is_crafting_open():
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_set_build_mode_enabled(not build_mode_enabled)
		get_viewport().set_input_as_handled()
		return

	if not build_mode_enabled:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var recipe_id := recipe_book.get_recipe_id_for_key(event.keycode)
		if not recipe_id.is_empty():
			selected_build_type = recipe_id
			get_viewport().set_input_as_handled()
			_update_preview()
			_update_build_label()
			return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_try_place_selected_building(current_tile)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		_try_remove_building(current_tile)


func _get_mouse_tile() -> Vector2i:
	var mouse_position := build_layer.to_local(build_layer.get_global_mouse_position())
	return _local_position_to_grid_cell(mouse_position)


func _try_place_selected_building(tile_position: Vector2i) -> bool:
	return _try_place_building(tile_position, selected_build_type)


func _try_place_wall(tile_position: Vector2i) -> bool:
	return _try_place_building(tile_position, BUILD_TYPE_WALL)


func _try_place_campfire(tile_position: Vector2i) -> bool:
	return _try_place_building(tile_position, BUILD_TYPE_CAMPFIRE)


func _try_place_workbench(tile_position: Vector2i) -> bool:
	return _try_place_building(tile_position, BUILD_TYPE_WORKBENCH)


func _try_place_bed(tile_position: Vector2i) -> bool:
	return _try_place_building(tile_position, BUILD_TYPE_BED)


func _try_place_building(tile_position: Vector2i, building_type: String) -> bool:
	building_type = _normalize_building_type(building_type)
	if not _can_place_building(tile_position, building_type, true):
		return false

	_spend_building_cost(building_type)
	build_layer.set_cell(tile_position, SOURCE_ID, _get_building_tile(building_type))
	_create_building_metadata(tile_position, building_type)
	_spawn_building_scene(tile_position, building_type)
	print("Built %s at tile %s" % [_get_building_display_name(building_type), tile_position])
	_update_preview()
	return true


func _try_remove_wall(tile_position: Vector2i) -> bool:
	return _try_remove_building(tile_position)


func _try_remove_building(tile_position: Vector2i) -> bool:
	var building_type := _get_building_type_at_tile(tile_position)
	if building_type.is_empty():
		print("There is no player-built construction here.")
		return false

	_sync_building_metadata(tile_position)
	var building_position := build_layer.to_global(_grid_cell_to_local_center(tile_position))
	var metadata := _get_building_metadata(tile_position)
	if _is_storage_building_type(building_type) and _has_items_in_storage_slots(metadata.get("storage_slots", [])):
		print("Empty the %s before removing it." % _get_building_display_name(building_type))
		return false

	_remove_building_scene(tile_position)
	build_layer.erase_cell(tile_position)
	building_metadata_by_cell.erase(_cell_key(tile_position))
	_refund_building_cost(building_type)
	if main.has_method("on_building_removed"):
		main.on_building_removed(building_type, building_position, metadata)
	print("Removed %s at tile %s" % [_get_building_display_name(building_type), tile_position])
	_update_preview()
	return true


func get_built_buildings() -> Array:
	var buildings := []

	for cell in build_layer.get_used_cells():
		var building_type := _get_building_type_at_tile(cell)
		if building_type.is_empty():
			continue

		_sync_building_metadata(cell)
		buildings.append({
			"type": building_type,
			"x": cell.x,
			"y": cell.y,
		}.merged(_get_building_metadata(cell)))

	return buildings


func load_built_buildings(buildings: Array) -> void:
	_clear_built_buildings()
	building_metadata_by_cell.clear()
	next_bed_id = 1
	next_chest_id = 1

	for building in buildings:
		if not building is Dictionary:
			continue

		var building_type := _normalize_building_type(str(building.get("type", BUILD_TYPE_WALL)))
		if not _is_known_building_type(building_type):
			continue

		var tile_position := Vector2i(
			int(building.get("x", 0)),
			int(building.get("y", 0))
		)
		build_layer.set_cell(tile_position, SOURCE_ID, _get_building_tile(building_type))
		_load_building_metadata(tile_position, building_type, building)
		_spawn_building_scene(tile_position, building_type)

	_update_preview()


func get_built_wall_cells() -> Array:
	var wall_cells := []

	for cell in build_layer.get_used_cells():
		if _is_player_built_wall(cell):
			wall_cells.append({
				"x": cell.x,
				"y": cell.y,
			})

	return wall_cells


func load_built_wall_cells(wall_cells: Array) -> void:
	var buildings := []

	for wall_cell in wall_cells:
		if not wall_cell is Dictionary:
			continue

		buildings.append({
			"type": BUILD_TYPE_WALL,
			"x": int(wall_cell.get("x", 0)),
			"y": int(wall_cell.get("y", 0)),
		})

	load_built_buildings(buildings)


func _can_place_wall(tile_position: Vector2i, show_message := false) -> bool:
	return _can_place_building(tile_position, BUILD_TYPE_WALL, show_message)


func _can_place_building(tile_position: Vector2i, building_type: String, show_message := false) -> bool:
	building_type = _normalize_building_type(building_type)

	if not _is_known_building_type(building_type):
		if show_message:
			print("Unknown building type: %s" % building_type)
		return false

	if ground_layer.get_cell_source_id(tile_position) == -1:
		if show_message:
			print("Cannot build outside the map.")
		return false

	if obstacle_layer.get_cell_source_id(tile_position) != -1:
		if show_message:
			print("Cannot build on an obstacle.")
		return false

	if _is_resource_at_tile(tile_position):
		if show_message:
			print("Cannot build on a resource.")
		return false

	if build_layer.get_cell_source_id(tile_position) != -1:
		if show_message:
			print("There is already a construction here.")
		return false

	if tile_position == _global_position_to_grid_cell(player.global_position):
		if show_message:
			print("Cannot build on the player.")
		return false

	if not _can_spend_building_cost(building_type):
		if show_message:
			print("Not enough resources to build %s." % _get_building_display_name(building_type))
		return false

	return true


func _is_player_built_wall(tile_position: Vector2i) -> bool:
	return _get_building_type_at_tile(tile_position) == BUILD_TYPE_WALL


func _clear_built_walls() -> void:
	for cell in build_layer.get_used_cells():
		if _is_player_built_wall(cell):
			build_layer.erase_cell(cell)


func _clear_built_buildings() -> void:
	for cell in build_layer.get_used_cells():
		if not _get_building_type_at_tile(cell).is_empty():
			build_layer.erase_cell(cell)
	for cell_key in building_scene_by_cell.keys():
		var building_scene = building_scene_by_cell[cell_key]
		if building_scene is Node:
			building_scene.queue_free()
	building_scene_by_cell.clear()
	building_metadata_by_cell.clear()


func _get_building_type_at_tile(tile_position: Vector2i) -> String:
	if build_layer.get_cell_source_id(tile_position) != SOURCE_ID:
		return ""

	var metadata := _get_building_metadata(tile_position)
	var metadata_type := str(metadata.get("type", ""))
	if not metadata_type.is_empty():
		return metadata_type

	var atlas_coords := build_layer.get_cell_atlas_coords(tile_position)
	if atlas_coords == WALL_TILE:
		return BUILD_TYPE_WALL
	if atlas_coords == CAMPFIRE_TILE:
		return BUILD_TYPE_CAMPFIRE
	if atlas_coords == WORKBENCH_TILE:
		return BUILD_TYPE_WORKBENCH
	if atlas_coords == BED_TILE:
		return BUILD_TYPE_BED

	return ""


func _get_building_tile(building_type: String) -> Vector2i:
	building_type = _normalize_building_type(building_type)

	if building_type == BUILD_TYPE_CAMPFIRE:
		return CAMPFIRE_TILE
	if building_type == BUILD_TYPE_WORKBENCH:
		return WORKBENCH_TILE
	if building_type == BUILD_TYPE_BED:
		return BED_TILE
	if _is_storage_building_type(building_type):
		return CHEST_TILE

	return WALL_TILE


func _is_known_building_type(building_type: String) -> bool:
	building_type = _normalize_building_type(building_type)
	return recipe_book.has_recipe(building_type)


func _get_building_cost(building_type: String) -> Array:
	building_type = _normalize_building_type(building_type)
	if recipe_book.has_method("get_build_cost"):
		return recipe_book.get_build_cost(building_type)
	return recipe_book.get_cost(building_type)


func _get_building_display_name(building_type: String) -> String:
	building_type = _normalize_building_type(building_type)
	return recipe_book.get_display_name(building_type)


func _is_storage_building_type(building_type: String) -> bool:
	building_type = _normalize_building_type(building_type)
	var item_data := _get_storage_item_data(building_type)
	if item_data.is_empty():
		return false

	if str(item_data.get("building_type", "")) == "storage":
		return true

	var tags: Variant = item_data.get("tags", [])
	return tags is Array and tags.has("storage")


func _get_storage_item_data(building_type: String) -> Dictionary:
	var recipe := recipe_book.get_recipe(building_type)
	var item_id := str(recipe.get("output_item_id", building_type))
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}

	return content_db.get_item(item_id)


func _get_storage_display_name(building_type: String) -> String:
	var item_data := _get_storage_item_data(building_type)
	return str(item_data.get("display_name", _get_building_display_name(building_type)))


func _get_storage_slot_count(building_type: String) -> int:
	var item_data := _get_storage_item_data(building_type)
	return max(int(item_data.get("storage_slots", 20)), 1)


func _get_loaded_storage_slot_count(building_type: String, building: Dictionary) -> int:
	var default_slot_count := _get_storage_slot_count(building_type)
	var saved_slot_count := int(building.get("storage_slot_count", building.get("slot_count", default_slot_count)))
	var storage_slots: Variant = building.get("storage_slots", [])
	if storage_slots is Array:
		saved_slot_count = max(saved_slot_count, storage_slots.size())
	if saved_slot_count > default_slot_count:
		print("Storage %s loaded with %d slots to preserve saved items." % [str(building.get("storage_id", building_type)), saved_slot_count])
	return max(saved_slot_count, default_slot_count)


func _normalize_building_type(building_type: String) -> String:
	return recipe_book.normalize_recipe_id(building_type)


func _can_spend_building_cost(building_type: String) -> bool:
	for cost in _get_building_cost(building_type):
		var resource_name := str(cost.get("resource", ""))
		var amount := int(cost.get("amount", 0))
		if not main.can_spend_resource(resource_name, amount):
			return false

	return true


func _spend_building_cost(building_type: String) -> void:
	for cost in _get_building_cost(building_type):
		var resource_name := str(cost.get("resource", ""))
		var amount := int(cost.get("amount", 0))
		main.spend_resource(resource_name, amount)


func _refund_building_cost(building_type: String) -> void:
	for cost in _get_building_cost(building_type):
		var resource_name := str(cost.get("resource", ""))
		var amount := int(cost.get("amount", 0))
		main.add_resource(resource_name, amount)


func get_campfire_positions() -> Array:
	var campfire_positions := []

	for cell in build_layer.get_used_cells():
		if _get_building_type_at_tile(cell) == BUILD_TYPE_CAMPFIRE:
			campfire_positions.append(build_layer.to_global(_grid_cell_to_local_center(cell)))

	return campfire_positions


func get_workbench_positions() -> Array:
	var workbench_positions := []

	for cell in build_layer.get_used_cells():
		if _get_building_type_at_tile(cell) == BUILD_TYPE_WORKBENCH:
			workbench_positions.append(build_layer.to_global(_grid_cell_to_local_center(cell)))

	return workbench_positions


func get_bed_positions() -> Array:
	var bed_positions := []

	for cell in build_layer.get_used_cells():
		if _get_building_type_at_tile(cell) == BUILD_TYPE_BED:
			bed_positions.append(build_layer.to_global(_grid_cell_to_local_center(cell)))

	return bed_positions


func get_beds() -> Array:
	var beds := []

	for cell in build_layer.get_used_cells():
		if _get_building_type_at_tile(cell) != BUILD_TYPE_BED:
			continue

		var metadata := _get_building_metadata(cell)
		beds.append({
			"bed_id": str(metadata.get("bed_id", "")),
			"occupied_by_npc_id": str(metadata.get("occupied_by_npc_id", "")),
			"x": cell.x,
			"y": cell.y,
			"position": build_layer.to_global(_grid_cell_to_local_center(cell)),
		})

	return beds


func set_bed_occupied_by_npc_id(bed_id: String, npc_instance_id: String) -> bool:
	for cell in build_layer.get_used_cells():
		if _get_building_type_at_tile(cell) != BUILD_TYPE_BED:
			continue

		var metadata := _get_building_metadata(cell)
		if str(metadata.get("bed_id", "")) != bed_id:
			continue

		metadata["occupied_by_npc_id"] = npc_instance_id
		building_metadata_by_cell[_cell_key(cell)] = metadata
		return true

	return false


func clear_bed_occupancy_for_npc(npc_instance_id: String) -> void:
	for cell_key in building_metadata_by_cell.keys():
		var metadata: Dictionary = building_metadata_by_cell[cell_key]
		if str(metadata.get("occupied_by_npc_id", "")) == npc_instance_id:
			metadata["occupied_by_npc_id"] = ""
			building_metadata_by_cell[cell_key] = metadata


func clear_all_bed_occupancy() -> void:
	for cell_key in building_metadata_by_cell.keys():
		var metadata: Dictionary = building_metadata_by_cell[cell_key]
		if metadata.has("occupied_by_npc_id"):
			metadata["occupied_by_npc_id"] = ""
			building_metadata_by_cell[cell_key] = metadata


func has_bed_id(bed_id: String) -> bool:
	for bed in get_beds():
		if str(bed.get("bed_id", "")) == bed_id:
			return true

	return false


func get_wall_count_near_cell(center_cell: Vector2i, radius: int) -> int:
	var wall_count := 0

	for cell in build_layer.get_used_cells():
		if _get_building_type_at_tile(cell) != BUILD_TYPE_WALL:
			continue

		if abs(cell.x - center_cell.x) <= radius and abs(cell.y - center_cell.y) <= radius:
			wall_count += 1

	return wall_count


func is_workbench_near_position(global_position: Vector2, max_distance: float) -> bool:
	for workbench_position in get_workbench_positions():
		if global_position.distance_to(workbench_position) <= max_distance:
			return true

	return false


func get_nearest_bed_position(global_position: Vector2, max_distance: float) -> Vector2:
	var nearest_position := Vector2.INF
	var nearest_distance := max_distance

	for bed_position in get_bed_positions():
		var distance := global_position.distance_to(bed_position)
		if distance <= nearest_distance:
			nearest_position = bed_position
			nearest_distance = distance

	return nearest_position


func is_bed_near_position(global_position: Vector2, max_distance: float) -> bool:
	return get_nearest_bed_position(global_position, max_distance) != Vector2.INF


func _is_resource_at_tile(tile_position: Vector2i) -> bool:
	for resource_node in resources_root.get_children():
		if resource_node is Node2D and not resource_node.is_queued_for_deletion():
			if resource_node.has_method("is_collected") and resource_node.is_collected():
				continue

			var resource_tile := _global_position_to_grid_cell(resource_node.global_position)
			if resource_tile == tile_position:
				return true

	return false


func _global_position_to_grid_cell(global_position: Vector2) -> Vector2i:
	return _local_position_to_grid_cell(build_layer.to_local(global_position))


func _local_position_to_grid_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(local_position.x / tile_size.x),
		floori(local_position.y / tile_size.y)
	)


func _grid_cell_to_local_center(tile_position: Vector2i) -> Vector2:
	return Vector2(
		(tile_position.x * tile_size.x) + (tile_size.x * 0.5),
		(tile_position.y * tile_size.y) + (tile_size.y * 0.5)
	)


func _set_build_mode_enabled(is_enabled: bool) -> void:
	build_mode_enabled = is_enabled
	_update_preview()
	_update_build_label()


func set_build_mode_enabled(is_enabled: bool) -> void:
	_set_build_mode_enabled(is_enabled)


func is_build_mode_enabled() -> bool:
	return build_mode_enabled


func _is_crafting_open() -> bool:
	var crafting_system = get_tree().get_first_node_in_group("crafting_system")
	if crafting_system == null:
		return false

	if not crafting_system.has_method("is_crafting_open"):
		return false

	return crafting_system.is_crafting_open()


func _create_preview() -> void:
	preview = Polygon2D.new()
	preview.name = "BuildPreview"
	preview.polygon = PackedVector2Array([
		Vector2(-tile_size.x * 0.5, -tile_size.y * 0.5),
		Vector2(tile_size.x * 0.5, -tile_size.y * 0.5),
		Vector2(tile_size.x * 0.5, tile_size.y * 0.5),
		Vector2(-tile_size.x * 0.5, tile_size.y * 0.5),
	])
	preview.color = VALID_PREVIEW_COLOR
	preview.z_index = 3
	preview.visible = false
	build_layer.add_child(preview)


func _update_preview() -> void:
	if preview == null:
		return

	preview.visible = build_mode_enabled
	if not build_mode_enabled:
		return

	preview.position = _grid_cell_to_local_center(current_tile)
	preview.color = _get_preview_color()


func _get_preview_color() -> Color:
	if not _can_place_building(current_tile, selected_build_type):
		return INVALID_PREVIEW_COLOR

	if selected_build_type == BUILD_TYPE_CAMPFIRE:
		return VALID_CAMPFIRE_PREVIEW_COLOR
	if selected_build_type == BUILD_TYPE_WORKBENCH:
		return VALID_WORKBENCH_PREVIEW_COLOR
	if selected_build_type == BUILD_TYPE_BED:
		return VALID_BED_PREVIEW_COLOR
	if _is_storage_building_type(selected_build_type):
		return VALID_CHEST_PREVIEW_COLOR

	return VALID_PREVIEW_COLOR


func _update_build_label() -> void:
	var mode_text := "On" if build_mode_enabled else "Off"
	var lines := [
		"B: Build Mode %s" % mode_text,
	]

	for building_type in _get_building_ui_order():
		lines.append("%s %s" % [
			_get_building_key_text(building_type),
			_get_building_display_name(building_type),
		])

	lines.append("Selected: %s" % _get_building_display_name(selected_build_type))
	lines.append("Cost: %s" % _get_building_cost_text(selected_build_type))

	if not _can_spend_building_cost(selected_build_type):
		lines.append("Not enough resources")

	lines.append("Tile: %d, %d" % [current_tile.x, current_tile.y])
	build_label.text = _join_lines(lines)


func _get_building_ui_order() -> Array:
	var building_ids := [
		BUILD_TYPE_WALL,
		BUILD_TYPE_CAMPFIRE,
		BUILD_TYPE_WORKBENCH,
		BUILD_TYPE_BED,
	]
	var storage_building_ids: Array[String] = []

	for recipe in recipe_book.get_recipes_by_type("building"):
		var recipe_id := str(recipe.get("id", ""))
		if recipe_id.is_empty() or building_ids.has(recipe_id):
			continue
		if _is_storage_building_type(recipe_id):
			storage_building_ids.append(recipe_id)

	storage_building_ids.sort_custom(_compare_building_ids_by_tier)
	for storage_building_id in storage_building_ids:
		building_ids.append(storage_building_id)

	return building_ids


func _compare_building_ids_by_tier(a: String, b: String) -> bool:
	var a_recipe := recipe_book.get_recipe(a)
	var b_recipe := recipe_book.get_recipe(b)
	var a_tier := int(a_recipe.get("tier", 999))
	var b_tier := int(b_recipe.get("tier", 999))
	if a_tier == b_tier:
		return a < b

	return a_tier < b_tier


func _get_building_key_text(building_type: String) -> String:
	var build_key := recipe_book.get_build_key(building_type)
	match build_key:
		KEY_1:
			return "1"
		KEY_2:
			return "2"
		KEY_3:
			return "3"
		KEY_4:
			return "4"
		KEY_5:
			return "5"
		KEY_6:
			return "6"
		KEY_7:
			return "7"
		KEY_8:
			return "8"
		KEY_9:
			return "9"
		KEY_0:
			return "0"
		KEY_MINUS:
			return "-"
		_:
			return "?"


func _get_building_cost_text(building_type: String) -> String:
	var parts := []

	for cost in _get_building_cost(building_type):
		var resource_name := str(cost.get("resource", ""))
		var amount := int(cost.get("amount", 0))
		if resource_name.is_empty() or amount <= 0:
			continue

		parts.append("%d %s" % [amount, resource_name])

	if parts.is_empty():
		return "Free"

	return _join_lines_with_separator(parts, ", ")


func _join_lines(lines: Array) -> String:
	return _join_lines_with_separator(lines, "\n")


func _join_lines_with_separator(lines: Array, separator: String) -> String:
	var text := ""

	for line in lines:
		if not text.is_empty():
			text += separator

		text += str(line)

	return text


func _create_building_metadata(tile_position: Vector2i, building_type: String) -> void:
	var metadata := {
		"type": building_type,
	}

	if building_type == BUILD_TYPE_BED:
		var bed_id := "bed_%03d" % next_bed_id
		next_bed_id += 1
		metadata["bed_id"] = bed_id
		metadata["occupied_by_npc_id"] = ""

	if _is_storage_building_type(building_type):
		var chest_id := "chest_%03d" % next_chest_id
		next_chest_id += 1
		metadata["building_id"] = building_type
		metadata["storage_id"] = chest_id
		metadata["display_name"] = _get_storage_display_name(building_type)
		metadata["storage_slot_count"] = _get_storage_slot_count(building_type)
		metadata["storage_slots"] = []

	building_metadata_by_cell[_cell_key(tile_position)] = metadata


func _load_building_metadata(tile_position: Vector2i, building_type: String, building: Dictionary) -> void:
	var metadata := {
		"type": building_type,
	}

	if building_type == BUILD_TYPE_BED:
		var bed_id := str(building.get("bed_id", ""))
		if bed_id.is_empty():
			bed_id = "bed_%03d" % next_bed_id

		var occupied_by_npc_id := str(building.get("occupied_by_npc_id", ""))
		metadata["bed_id"] = bed_id
		metadata["occupied_by_npc_id"] = occupied_by_npc_id
		next_bed_id = max(next_bed_id, _get_bed_id_number(bed_id) + 1)

	if _is_storage_building_type(building_type):
		var storage_id := str(building.get("storage_id", ""))
		if storage_id.is_empty():
			storage_id = "chest_%03d" % next_chest_id
		metadata["building_id"] = str(building.get("building_id", building_type))
		metadata["storage_id"] = storage_id
		metadata["display_name"] = str(building.get("display_name", _get_storage_display_name(building_type)))
		metadata["storage_slot_count"] = _get_loaded_storage_slot_count(building_type, building)
		var storage_slots: Variant = building.get("storage_slots", [])
		metadata["storage_slots"] = storage_slots if storage_slots is Array else []
		next_chest_id = max(next_chest_id, _get_chest_id_number(storage_id) + 1)

	building_metadata_by_cell[_cell_key(tile_position)] = metadata


func _get_building_metadata(tile_position: Vector2i) -> Dictionary:
	var metadata = building_metadata_by_cell.get(_cell_key(tile_position), {})
	if not metadata is Dictionary:
		return {}

	return metadata.duplicate(true)


func _cell_key(tile_position: Vector2i) -> String:
	return "%d,%d" % [tile_position.x, tile_position.y]


func _get_bed_id_number(bed_id: String) -> int:
	if not bed_id.begins_with("bed_"):
		return 0

	return int(bed_id.trim_prefix("bed_"))


func _get_chest_id_number(chest_id: String) -> int:
	if not chest_id.begins_with("chest_"):
		return 0

	return int(chest_id.trim_prefix("chest_"))


func _spawn_building_scene(tile_position: Vector2i, building_type: String) -> void:
	if not _is_storage_building_type(building_type):
		return

	if buildings_root == null:
		buildings_root = _get_or_create_buildings_root()
	if buildings_root == null:
		return

	var cell_key := _cell_key(tile_position)
	_remove_building_scene(tile_position)
	var chest: Node = ChestScene.instantiate()
	buildings_root.add_child(chest)
	chest.global_position = build_layer.to_global(_grid_cell_to_local_center(tile_position))

	var metadata := _get_building_metadata(tile_position)
	if chest.has_method("set_building_id"):
		chest.set_building_id(str(metadata.get("building_id", building_type)))
	if chest.has_method("set_display_name"):
		chest.set_display_name(str(metadata.get("display_name", _get_storage_display_name(building_type))))
	if chest.has_method("set_slot_count"):
		chest.set_slot_count(int(metadata.get("storage_slot_count", _get_storage_slot_count(building_type))))
	if chest.has_method("set_storage_id"):
		chest.set_storage_id(str(metadata.get("storage_id", "")))
	var storage_slots: Variant = metadata.get("storage_slots", [])
	if storage_slots is Array and chest.has_method("set_storage_slots"):
		chest.set_storage_slots(storage_slots)

	building_scene_by_cell[cell_key] = chest


func _remove_building_scene(tile_position: Vector2i) -> void:
	var cell_key := _cell_key(tile_position)
	if not building_scene_by_cell.has(cell_key):
		return

	var building_scene = building_scene_by_cell[cell_key]
	if building_scene is Node:
		building_scene.queue_free()
	building_scene_by_cell.erase(cell_key)


func _sync_building_metadata(tile_position: Vector2i) -> void:
	var cell_key := _cell_key(tile_position)
	if not building_scene_by_cell.has(cell_key):
		return

	var building_scene = building_scene_by_cell[cell_key]
	if building_scene == null:
		return

	var metadata := _get_building_metadata(tile_position)
	if building_scene.has_method("get_building_id"):
		metadata["building_id"] = str(building_scene.get_building_id())
	if building_scene.has_method("get_display_name"):
		metadata["display_name"] = str(building_scene.get_display_name())
	if building_scene.has_method("get_slot_count"):
		metadata["storage_slot_count"] = int(building_scene.get_slot_count())
	if building_scene.has_method("get_storage_id"):
		metadata["storage_id"] = str(building_scene.get_storage_id())
	if building_scene.has_method("get_storage_slots"):
		metadata["storage_slots"] = building_scene.get_storage_slots()
	building_metadata_by_cell[cell_key] = metadata


func _has_items_in_storage_slots(storage_slots: Variant) -> bool:
	if not storage_slots is Array:
		return false

	for slot in storage_slots:
		if not slot is Dictionary:
			continue

		var item_id := str(slot.get("item_id", ""))
		var amount := int(slot.get("amount", 0))
		if not item_id.is_empty() and amount > 0:
			return true

	return false


func _get_or_create_buildings_root() -> Node2D:
	var world := get_node_or_null("../World") as Node2D
	if world == null:
		return null

	var existing := world.get_node_or_null("Buildings") as Node2D
	if existing != null:
		return existing

	var new_root := Node2D.new()
	new_root.name = "Buildings"
	new_root.y_sort_enabled = true
	world.add_child(new_root)
	return new_root
