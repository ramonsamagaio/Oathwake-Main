extends Node

const SOURCE_ID := 0
const WALL_TILE := Vector2i(2, 0)
const WALL_COST_RESOURCE := "Wood"
const WALL_COST_AMOUNT := 1
const VALID_PREVIEW_COLOR := Color(0.50, 0.32, 0.18, 0.55)
const INVALID_PREVIEW_COLOR := Color(0.90, 0.12, 0.10, 0.55)

@export var tile_size: Vector2i = Vector2i(32, 32)
@export var main_path: NodePath = ".."
@export var player_path: NodePath = "../Player"
@export var build_layer_path: NodePath = "../World/BuildLayer"
@export var ground_layer_path: NodePath = "../World/GroundLayer"
@export var obstacle_layer_path: NodePath = "../World/ObstacleLayer"
@export var resources_root_path: NodePath = "../World/Resources"
@export var build_label_path: NodePath = "../UI/BuildLabel"

var build_mode_enabled := false
var current_tile := Vector2i.ZERO
var preview: Polygon2D

@onready var main = get_node(main_path)
@onready var player: CharacterBody2D = get_node(player_path)
@onready var build_layer: TileMapLayer = get_node(build_layer_path)
@onready var ground_layer: TileMapLayer = get_node(ground_layer_path)
@onready var obstacle_layer: TileMapLayer = get_node(obstacle_layer_path)
@onready var resources_root: Node2D = get_node(resources_root_path)
@onready var build_label: Label = get_node(build_label_path)


func _ready() -> void:
	if build_layer.tile_set != null:
		tile_size = build_layer.tile_set.tile_size

	_create_preview()
	_update_build_label()


func _process(_delta: float) -> void:
	current_tile = _get_mouse_tile()
	_update_preview()
	_update_build_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_set_build_mode_enabled(not build_mode_enabled)
		get_viewport().set_input_as_handled()
		return

	if not build_mode_enabled:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_try_place_wall(current_tile)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		_try_remove_wall(current_tile)


func _get_mouse_tile() -> Vector2i:
	var mouse_position := build_layer.to_local(build_layer.get_global_mouse_position())
	return _local_position_to_grid_cell(mouse_position)


func _try_place_wall(tile_position: Vector2i) -> bool:
	if not _can_place_wall(tile_position, true):
		return false

	if not main.spend_resource(WALL_COST_RESOURCE, WALL_COST_AMOUNT):
		print("Not enough Wood to build a wall.")
		return false

	build_layer.set_cell(tile_position, SOURCE_ID, WALL_TILE)
	print("Built wall at tile %s" % tile_position)
	_update_preview()
	return true


func _try_remove_wall(tile_position: Vector2i) -> bool:
	if not _is_player_built_wall(tile_position):
		print("There is no player-built wall here.")
		return false

	build_layer.erase_cell(tile_position)
	main.add_resource(WALL_COST_RESOURCE, WALL_COST_AMOUNT)
	print("Removed wall at tile %s" % tile_position)
	_update_preview()
	return true


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
	_clear_built_walls()

	for wall_cell in wall_cells:
		if not wall_cell is Dictionary:
			continue

		var tile_position := Vector2i(
			int(wall_cell.get("x", 0)),
			int(wall_cell.get("y", 0))
		)
		build_layer.set_cell(tile_position, SOURCE_ID, WALL_TILE)

	_update_preview()


func _can_place_wall(tile_position: Vector2i, show_message := false) -> bool:
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
			print("There is already a wall here.")
		return false

	if tile_position == _global_position_to_grid_cell(player.global_position):
		if show_message:
			print("Cannot build on the player.")
		return false

	if not main.can_spend_resource(WALL_COST_RESOURCE, WALL_COST_AMOUNT):
		if show_message:
			print("Not enough Wood to build a wall.")
		return false

	return true


func _is_player_built_wall(tile_position: Vector2i) -> bool:
	return (
		build_layer.get_cell_source_id(tile_position) == SOURCE_ID
		and build_layer.get_cell_atlas_coords(tile_position) == WALL_TILE
	)


func _clear_built_walls() -> void:
	for cell in build_layer.get_used_cells():
		if _is_player_built_wall(cell):
			build_layer.erase_cell(cell)


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
	preview.color = VALID_PREVIEW_COLOR if _can_place_wall(current_tile) else INVALID_PREVIEW_COLOR


func _update_build_label() -> void:
	var mode_text := "On" if build_mode_enabled else "Off"
	build_label.text = "Build: %s | Tile: %d, %d" % [mode_text, current_tile.x, current_tile.y]
