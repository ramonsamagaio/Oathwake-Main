## Fixed runtime contract shared by every gameplay map scene.
class_name MapRoot
extends Node2D

const FUNCTIONAL_GROUND_TEXTURE := preload("res://assets/generated/functional_ground_tile.svg")
const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")
const DirectionalShadowRuntime := preload("res://scripts/effects/DirectionalShadowRuntime.gd")
const WorldVisualDirectorScript := preload("res://scripts/world/WorldVisualDirector.gd")

@export var map_id: String = ""
@export var display_name: String = ""
@export var default_spawn_point_name: String = "PlayerSpawn"

var _loaded_save_data: Dictionary = {}
var _world_visual_director: Node2D

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
	_ensure_world_visual_director()
	_ensure_functional_ground()
	call_deferred("_configure_authored_prop_presentation")
	call_deferred("_configure_authored_environment_layers")


func _ensure_world_visual_director() -> void:
	_world_visual_director = get_node_or_null("WorldVisualDirector") as Node2D
	if _world_visual_director == null:
		_world_visual_director = WorldVisualDirectorScript.new()
		_world_visual_director.name = "WorldVisualDirector"
		add_child(_world_visual_director)
		move_child(_world_visual_director, 0)
	if _world_visual_director.has_method("configure_map"):
		_world_visual_director.call("configure_map", map_id)


func _configure_authored_prop_presentation() -> void:
	if _props_root == null:
		return
	var prop_sprites: Array[Sprite2D] = []
	_collect_authored_prop_sprites(_props_root, prop_sprites)
	for sprite in prop_sprites:
		if _world_visual_director != null and _world_visual_director.has_method("register_authored_sprite"):
			_world_visual_director.call("register_authored_sprite", sprite)
		if not _is_depth_sorted_authored_prop(sprite):
			continue
		var line_ratio := _get_authored_prop_depth_ratio(sprite)
		WorldDepthRuntime.apply_sprite_depth(sprite, line_ratio)
		sprite.set_meta("authored_depth_line_ratio", line_ratio)
		var shadow_config := {
			"enabled": _authored_prop_casts_shadow(sprite),
			"opacity": 0.28,
			"z_index": -1,
		}
		DirectionalShadowRuntime.apply_to_sprite(sprite, shadow_config)


func _configure_authored_environment_layers() -> void:
	if _props_root == null or _world_visual_director == null:
		return
	var layers: Array[CanvasItem] = []
	_collect_authored_environment_layers(_props_root, layers)
	for layer in layers:
		if _world_visual_director.has_method("register_authored_environment_layer"):
			_world_visual_director.call("register_authored_environment_layer", layer)
		elif _world_visual_director.has_method("register_authored_foliage_layer"):
			_world_visual_director.call("register_authored_foliage_layer", layer)


func _collect_authored_prop_sprites(node: Node, output: Array[Sprite2D]) -> void:
	for child in node.get_children():
		if child is Sprite2D:
			output.append(child as Sprite2D)
		if child is Node and not (child as Node).is_in_group("persistent_content_visual"):
			_collect_authored_prop_sprites(child, output)


func _collect_authored_environment_layers(node: Node, output: Array[CanvasItem]) -> void:
	for child in node.get_children():
		if child is TileMapLayer:
			var name_text := str(child.name).to_lower()
			for token in ["grass", "foliage", "vegetation", "water", "river", "lake", "pond", "stream", "agua", "água"]:
				if name_text.contains(token):
					output.append(child as CanvasItem)
					break
		if child is Node and not (child as Node).is_in_group("persistent_content_visual"):
			_collect_authored_environment_layers(child, output)


func _is_depth_sorted_authored_prop(sprite: Sprite2D) -> bool:
	if sprite == null or sprite.texture == null or not sprite.visible:
		return false
	var name_text := str(sprite.name).to_lower()
	for token in ["tree", "arbusto", "shrub", "log", "stone", "casa", "house", "crate", "sign", "lamp", "curral", "fence", "post", "barrel", "campfire", "stump", "sapling"]:
		if name_text.contains(token):
			return true
	return false


func _authored_prop_casts_shadow(sprite: Sprite2D) -> bool:
	var name_text := str(sprite.name).to_lower()
	for token in ["tree", "arbusto", "shrub", "log", "stone", "casa", "house", "crate", "sign", "lamp", "curral", "fence", "post", "barrel", "campfire", "stump", "sapling"]:
		if name_text.contains(token):
			return true
	return false


func _get_authored_prop_depth_ratio(sprite: Sprite2D) -> float:
	var name_text := str(sprite.name).to_lower()
	if name_text.contains("tree") or name_text.contains("sapling"):
		return 0.58
	if name_text.contains("casa") or name_text.contains("house") or name_text.contains("lamp") or name_text.contains("sign"):
		return 0.68
	return 0.62


func _ensure_functional_ground() -> void:
	# Authored visuals can remain independent while this layer supplies buildable cells.
	# The texture is a committed resource rather than an ImageTexture created during
	# scene startup, preventing zero-sized image construction on threaded map loads.
	if _ground_layer.tile_set == null:
		var source := TileSetAtlasSource.new()
		source.texture = FUNCTIONAL_GROUND_TEXTURE
		source.texture_region_size = Vector2i(32, 32)
		source.create_tile(Vector2i.ZERO)
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
