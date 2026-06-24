extends Node

const SOURCE_ID := 0
const WALL_TILE := Vector2i(2, 0)
const WALL_COST_RESOURCE := "Wood"
const WALL_COST_AMOUNT := 1

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

	_update_build_label()


func _process(_delta: float) -> void:
	current_tile = _get_mouse_tile()
	_update_build_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		build_mode_enabled = not build_mode_enabled
		get_viewport().set_input_as_handled()
		_update_build_label()
		return

	if not build_mode_enabled:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_try_place_wall(current_tile)


func _get_mouse_tile() -> Vector2i:
	var mouse_position := build_layer.to_local(build_layer.get_global_mouse_position())
	return _local_position_to_grid_cell(mouse_position)


func _try_place_wall(tile_position: Vector2i) -> bool:
	if ground_layer.get_cell_source_id(tile_position) == -1:
		print("Cannot build outside the map.")
		return false

	if obstacle_layer.get_cell_source_id(tile_position) != -1:
		print("Cannot build on an obstacle.")
		return false

	if _is_resource_at_tile(tile_position):
		print("Cannot build on a resource.")
		return false

	if build_layer.get_cell_source_id(tile_position) != -1:
		print("There is already a wall here.")
		return false

	if tile_position == _global_position_to_grid_cell(player.global_position):
		print("Cannot build on the player.")
		return false

	if not main.spend_resource(WALL_COST_RESOURCE, WALL_COST_AMOUNT):
		print("Not enough Wood to build a wall.")
		return false

	build_layer.set_cell(tile_position, SOURCE_ID, WALL_TILE)
	print("Built wall at tile %s" % tile_position)
	return true


func _is_resource_at_tile(tile_position: Vector2i) -> bool:
	for resource_node in resources_root.get_children():
		if resource_node is Node2D and not resource_node.is_queued_for_deletion():
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


func _update_build_label() -> void:
	var mode_text := "On" if build_mode_enabled else "Off"
	build_label.text = "Build: %s | Tile: %d, %d" % [mode_text, current_tile.x, current_tile.y]
