## Fixed runtime contract shared by every gameplay map scene.
class_name MapRoot
extends Node2D

@export var map_id: String = ""
@export var display_name: String = ""
@export var default_spawn_point_name: String = "PlayerSpawn"

var _loaded_save_data: Dictionary = {}

@onready var _ground_layer: TileMapLayer = $GroundLayer
@onready var _obstacle_layer: TileMapLayer = $ObstacleLayer
@onready var _build_layer: TileMapLayer = $BuildLayer
@onready var _props_root: Node2D = $Props
@onready var _resources_root: Node2D = $Resources
@onready var _enemies_root: Node2D = $Enemies
@onready var _npcs_root: Node2D = $NPCs
@onready var _world_items_root: Node2D = $WorldItems
@onready var _spawn_points_root: Node2D = $SpawnPoints


func get_ground_layer() -> TileMapLayer:
	return _ground_layer


func get_obstacle_layer() -> TileMapLayer:
	return _obstacle_layer


func get_build_layer() -> TileMapLayer:
	return _build_layer


func get_resources_root() -> Node2D:
	return _resources_root


func get_enemies_root() -> Node2D:
	return _enemies_root


func get_npcs_root() -> Node2D:
	return _npcs_root


func get_world_items_root() -> Node2D:
	return _world_items_root


func get_props_root() -> Node2D:
	return _props_root


func get_spawn_point(name := "PlayerSpawn") -> Node2D:
	var spawn_name := name if not name.is_empty() else default_spawn_point_name
	return _spawn_points_root.get_node_or_null(NodePath(spawn_name)) as Node2D


func get_default_spawn_position() -> Vector2:
	var spawn_point := get_spawn_point(default_spawn_point_name)
	return spawn_point.global_position if spawn_point != null else global_position


func get_tile_type_at_position(_global_position: Vector2) -> String:
	return "grass"


func _ready() -> void:
	_ensure_functional_ground()


func _ensure_functional_ground() -> void:
	# Authored visuals can remain independent while this layer supplies buildable cells.
	if _ground_layer.tile_set == null:
		var image := Image.create(192, 32, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.16, 0.30, 0.18, 0.20))
		var source := TileSetAtlasSource.new()
		source.texture = ImageTexture.create_from_image(image)
		source.texture_region_size = Vector2i(32, 32)
		for atlas_x in range(6):
			source.create_tile(Vector2i(atlas_x, 0))
		var tile_set := TileSet.new()
		tile_set.tile_size = Vector2i(32, 32)
		tile_set.add_source(source, 0)
		_ground_layer.tile_set = tile_set
	if _ground_layer.get_used_cells().is_empty():
		for x in range(-8, 60):
			for y in range(-8, 40):
				_ground_layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	if _build_layer.tile_set == null:
		_build_layer.tile_set = _ground_layer.tile_set
	if _obstacle_layer.tile_set == null:
		_obstacle_layer.tile_set = _ground_layer.tile_set


func get_map_save_data() -> Dictionary:
	var data := _loaded_save_data.duplicate(true)
	data["map_id"] = map_id
	var respawning_resources := _get_resource_save_data()
	data["respawning_resources"] = respawning_resources
	# Temporary alias while map-save consumers migrate to the explicit field name.
	data["resources"] = respawning_resources
	return data


func load_map_save_data(data: Dictionary) -> void:
	_loaded_save_data = data.duplicate(true) if data != null else {}
	var saved_map_id := str(_loaded_save_data.get("map_id", ""))
	if not saved_map_id.is_empty() and saved_map_id != map_id:
		push_warning("MapRoot ignored save data for a different map: %s" % saved_map_id)
		return
	_apply_resource_save_data(_loaded_save_data.get("respawning_resources", _loaded_save_data.get("resources", [])))


func _get_resource_save_data() -> Array:
	var saved_resources := []
	for resource_node in _resources_root.get_children():
		if not resource_node.has_method("is_collected") or not resource_node.is_collected():
			continue
		if not resource_node.has_method("get_resource_id"):
			continue
		var resource_id := str(resource_node.get_resource_id())
		if resource_id.is_empty():
			continue
		var respawn_time_left := 0.0
		if resource_node.has_method("get_respawn_time_left"):
			respawn_time_left = float(resource_node.get_respawn_time_left())
		saved_resources.append({
			"id": resource_id,
			"respawn_time_left": respawn_time_left,
		})
	return saved_resources


func _apply_resource_save_data(saved_resources: Variant) -> void:
	var respawn_by_id := {}
	if saved_resources is Array:
		for resource_data in saved_resources:
			if resource_data is Dictionary:
				var resource_id := str(resource_data.get("id", ""))
				if not resource_id.is_empty():
					respawn_by_id[resource_id] = float(resource_data.get("respawn_time_left", 0.0))
	for resource_node in _resources_root.get_children():
		if not resource_node.has_method("get_resource_id") or not resource_node.has_method("set_collected"):
			continue
		var resource_id := str(resource_node.get_resource_id())
		if respawn_by_id.has(resource_id):
			resource_node.set_collected(true, float(respawn_by_id[resource_id]))
		else:
			resource_node.set_collected(false)


# TODO(migration): restore world items, buildings, NPCs and persistent enemies from
# WorldSave.maps once their spawners accept explicit map roots instead of Main paths.
