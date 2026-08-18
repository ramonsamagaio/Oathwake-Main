class_name RomesteadProceduralGameWorld
extends "res://scripts/labs/romestead_systems/RomesteadBiomeWorld2D.gd"

const ResourceSceneFactoryScript := preload("res://scripts/resources/ResourceSceneFactory.gd")
const RomesteadWildlifeScene := preload("res://scenes/creatures/RomesteadWildlife.tscn")

const ROUND_TREES := ["tree2", "tree3", "tree4", "tree5", "tree6", "tree7", "tree8", "tree9"]
const OLIVE_TREES := ["tree10", "tree11"]
const CYPRESS_TREES := [
	"tree12", "tree13", "tree14", "tree15", "tree16", "tree17", "tree18", "tree19",
	"tree20", "tree21", "tree22", "tree23", "tree24", "tree25", "tree26", "tree27",
	"tree28", "tree29", "tree30", "tree31", "tree32", "tree33", "tree34", "tree35",
	"tree36", "tree37", "tree38", "tree39", "tree40",
]
const BIG_ROCKS := ["rock1", "rock2", "rock3", "rock4", "rock5", "rock6", "rock7", "rock8", "rock9", "rock10"]
const SMALL_STONES := ["stone1", "stone2", "stone3", "stone4", "stone5", "stone6", "stone7", "stone8"]
const BUSHES := [
	"bush1", "bush2", "bush3", "bush4", "bush5", "bush6", "bush7", "bush8",
	"bush9", "bush10", "bush11", "bush12", "bush13", "bush14", "bush15", "bush16",
	"bush17", "bush18", "bush19", "bush20", "bush21",
]
const WHEATS := [
	"wheat1", "wheat2", "wheat3", "wheat4", "wheat5", "wheat6", "wheat7", "wheat8",
	"wheat9", "wheat10", "wheat11", "wheat12", "wheat13", "wheat14", "wheat15", "wheat16",
	"wheat17", "wheat18", "wheat19", "wheat20", "wheat21", "wheat22", "wheat23", "wheat24",
]
const APPLE_TREES := ["tree41"]
const STONE_PINES := ["tree42"]
const FOREST_MUSHROOMS := ["mushroom_red", "mushroom_brown", "mushroom_yellow"]
const FOREST_FLOWERS := ["bellflower1", "lily1"]
const TREE_RESPAWN_MIN_DISTANCE := 64.0
const TREE_TO_OTHER_MIN_DISTANCE := 38.0
const DEFAULT_RESPAWN_MIN_DISTANCE := 28.0
const VISIBILITY_UPDATES_PER_FRAME := 48
const WILDLIFE_VISIBILITY_UPDATES_PER_FRAME := 8
const RESOURCE_STREAM_BUDGET_PER_FRAME := 10

@export_node_path("Node2D") var resources_path := NodePath("../Resources")
@export_node_path("Node2D") var wildlife_path := NodePath("../Enemies")

var _resources: Node2D
var _resource_factory := ResourceSceneFactoryScript.new()
var _wildlife_root: Node2D
var _respawn_nonce := 0
var _wind_resources: Array[Node] = []
var _occlusion_resources: Array[Node] = []
var _player: Node2D
var _occlusion_update_elapsed := 0.05
var _weather_wind_strength := 0.18
var _weather_wind_speed := 0.9
var _weather_wind_direction := Vector2(1.0, 0.12)
var _managed_resources: Array[Node] = []
var _visibility_scan_index := 0
var _wildlife_instances: Array[Node2D] = []
var _wildlife_scan_index := 0
var _initial_resource_spatial: Dictionary = {}
var _pending_resource_spawns: Dictionary = {}
var _generation_resource_bounds := Rect2()


func _ready() -> void:
	_resources = get_node_or_null(resources_path) as Node2D
	_wildlife_root = get_node_or_null(wildlife_path) as Node2D
	add_to_group("procedural_resource_world")
	var game_session := get_node_or_null("/root/GameSession")
	if game_session != null:
		var world_data: Variant = game_session.get("world_data")
		if world_data is Dictionary:
			world_seed = int((world_data as Dictionary).get("seed", world_seed))
	var should_generate := auto_generate
	auto_generate = false
	super._ready()
	if should_generate:
		generate_world(world_seed)


func generate_world(new_seed: int = world_seed) -> void:
	_generation_resource_bounds = _compute_active_bounds().grow(64.0)
	super.generate_world(new_seed)
	_generation_resource_bounds = Rect2()
	_spawn_procedural_wildlife()
	_apply_initial_runtime_culling(_compute_active_bounds())


func _process(delta: float) -> void:
	var active_bounds := _compute_active_bounds()
	_stream_pending_resources(active_bounds.grow(96.0))
	_update_resource_visibility_slice(active_bounds)
	_update_wildlife_visibility_slice(active_bounds)
	for resource in _wind_resources:
		if not is_instance_valid(resource) or not resource.visible:
			continue
		var resource_2d := resource as Node2D
		if resource_2d != null and active_bounds.has_point(resource_2d.global_position):
			resource.call("set_romestead_environment", 0.0, 0.0, _weather_wind_strength, _weather_wind_speed, _weather_wind_direction)
			resource.call("tick_romestead_motion", delta)
	_occlusion_update_elapsed += delta
	if _occlusion_update_elapsed >= 0.05:
		var occlusion_delta := _occlusion_update_elapsed
		_occlusion_update_elapsed = 0.0
		if _player == null or not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player != null:
			for resource in _occlusion_resources:
				if not is_instance_valid(resource) or not resource.visible:
					continue
				var resource_2d := resource as Node2D
				if resource_2d != null and active_bounds.has_point(resource_2d.global_position):
					resource.call("tick_player_occlusion", _player.global_position, occlusion_delta)


func _compute_active_bounds() -> Rect2:
	var focus := get_viewport().get_camera_2d()
	var focus_position := focus.global_position if focus != null else global_position
	var half_view := get_viewport_rect().size * 0.5
	if focus != null:
		half_view /= Vector2(maxf(absf(focus.zoom.x), 0.01), maxf(absf(focus.zoom.y), 0.01))
	# Keep a small horizontal margin and extra room below the viewport because a
	# tree's grounded anchor can sit below the screen while its canopy is visible.
	return Rect2(
		focus_position - half_view - Vector2(48.0, 32.0),
		half_view * 2.0 + Vector2(96.0, 144.0)
	)


func _apply_initial_runtime_culling(active_bounds: Rect2) -> void:
	# The incremental scanner is ideal while the camera moves, but a five-times
	# larger world must not leave thousands of fresh canvas/collision nodes active
	# until that scanner completes its first lap.
	for resource in _managed_resources:
		if not is_instance_valid(resource) or not resource.has_method("set_runtime_culled"):
			continue
		var resource_2d := resource as Node2D
		if resource_2d != null:
			resource.call("set_runtime_culled", not active_bounds.has_point(resource_2d.global_position))
	for animal in _wildlife_instances:
		if animal != null and is_instance_valid(animal) and animal.has_method("set_runtime_active"):
			animal.call("set_runtime_active", active_bounds.has_point(animal.global_position))


func _update_resource_visibility_slice(active_bounds: Rect2) -> void:
	if _managed_resources.is_empty():
		return
	var update_count := mini(VISIBILITY_UPDATES_PER_FRAME, _managed_resources.size())
	for _index in range(update_count):
		if _visibility_scan_index >= _managed_resources.size():
			_visibility_scan_index = 0
		var resource := _managed_resources[_visibility_scan_index]
		_visibility_scan_index += 1
		if not is_instance_valid(resource):
			continue
		var resource_2d := resource as Node2D
		if resource_2d == null or not resource.has_method("set_runtime_culled"):
			continue
		resource.call("set_runtime_culled", not active_bounds.has_point(resource_2d.global_position))


func _update_wildlife_visibility_slice(active_bounds: Rect2) -> void:
	if _wildlife_instances.is_empty():
		return
	var count := mini(WILDLIFE_VISIBILITY_UPDATES_PER_FRAME, _wildlife_instances.size())
	for _index in range(count):
		if _wildlife_scan_index >= _wildlife_instances.size():
			_wildlife_scan_index = 0
		var animal := _wildlife_instances[_wildlife_scan_index]
		_wildlife_scan_index += 1
		if animal != null and is_instance_valid(animal) and animal.has_method("set_runtime_active"):
			animal.call("set_runtime_active", active_bounds.has_point(animal.global_position))


func set_environment(wetness: float, lightning: float, wind_strength: float, wind_speed: float, wind_direction: Vector2, hour: float = 15.0, daylight: float = 1.0) -> void:
	_weather_wind_strength = wind_strength
	_weather_wind_speed = wind_speed
	_weather_wind_direction = wind_direction
	super.set_environment(wetness, lightning, wind_strength, wind_speed, wind_direction, hour, daylight)


func get_wind_vector() -> Vector2:
	var direction := _weather_wind_direction.normalized() if _weather_wind_direction.length_squared() > 0.0001 else Vector2.RIGHT
	var gust := 1.0 + sin(Time.get_ticks_msec() * 0.001 * maxf(_weather_wind_speed, 0.1) * TAU * 0.22) * 0.18
	return direction * _weather_wind_strength * gust * 18.0


func get_wind_strength() -> float:
	return get_wind_vector().length() / 18.0


func _spawn_prop(prop_position: Vector2, kind: PropKind, variation_seed: int = 0) -> void:
	# DrawFlowersNew's 32x32 ground plants are decorative pixels, not harvestable
	# entities. Keep them in the native wind layer instead of turning each rare
	# plant into a ResourceNode in the integrated game.
	if kind in [PropKind.FLOOR_DETAIL, PropKind.GROUND_PLANT]:
		super._spawn_prop(prop_position, kind, variation_seed)
		return
	if _resources == null:
		return
	var resource_type := _resource_type_for_prop(kind, variation_seed)
	if resource_type.is_empty():
		return
	if not _reserve_initial_resource_position(prop_position, kind):
		return
	var cell := Vector2i(roundi(prop_position.x / float(tile_size)), roundi(prop_position.y / float(tile_size)))
	var spawn_key := "%d,%d,%s" % [cell.x, cell.y, resource_type]
	if not _generation_resource_bounds.has_point(to_global(prop_position)):
		_pending_resource_spawns[spawn_key] = {
			"position": prop_position,
			"kind": int(kind),
			"variation_seed": variation_seed,
			"resource_type": resource_type,
		}
		return
	_instantiate_functional_resource(prop_position, kind, variation_seed, resource_type)


func _instantiate_functional_resource(prop_position: Vector2, kind: PropKind, variation_seed: int, resource_type: String) -> void:
	if _resources == null or resource_type.is_empty():
		return
	var cell := Vector2i(roundi(prop_position.x / float(tile_size)), roundi(prop_position.y / float(tile_size)))
	# The stable id identifies a placed instance for save/respawn. The Content
	# Editor model remains resource_type (tree2, rock1, etc.), one per sprite.
	var resource_id := "romestead_resource_%d_%d_%s" % [cell.x, cell.y, resource_type]
	var local_position := _resources.to_local(to_global(prop_position.round()))
	var resource_node := _resource_factory.instantiate_resource(resource_type, resource_id, local_position)
	if resource_node == null:
		return
	resource_node.name = ("Resource_%d_%d" % [cell.x, cell.y]).validate_node_name()
	resource_node.set_meta("procedural_biome", int(_biomes.get(cell, BIOME_DRY)))
	_resources.add_child(resource_node)
	_managed_resources.append(resource_node)
	if resource_node.has_method("uses_romestead_wind") and bool(resource_node.call("uses_romestead_wind")):
		_wind_resources.append(resource_node)
	if resource_node.has_method("uses_player_occlusion") and bool(resource_node.call("uses_player_occlusion")):
		_occlusion_resources.append(resource_node)


func _stream_pending_resources(active_bounds: Rect2) -> void:
	if _pending_resource_spawns.is_empty():
		return
	var instantiated := 0
	for key_value in _pending_resource_spawns.keys():
		if instantiated >= RESOURCE_STREAM_BUDGET_PER_FRAME:
			break
		var key := str(key_value)
		var spawn := _pending_resource_spawns[key] as Dictionary
		var local_position := Vector2(spawn.get("position", Vector2.ZERO))
		if not active_bounds.has_point(to_global(local_position)):
			continue
		_pending_resource_spawns.erase(key)
		var kind: PropKind = int(spawn.get("kind", int(PropKind.BUSH)))
		_instantiate_functional_resource(local_position, kind, int(spawn.get("variation_seed", 0)), str(spawn.get("resource_type", "")))
		instantiated += 1


func _spawn_light_landmarks() -> void:
	# Gameplay light landmarks are authored/buildable. The lab-only braziers are
	# deliberately not injected into the real map.
	pass


func _clear_generated_content() -> void:
	_wind_resources.clear()
	_occlusion_resources.clear()
	_managed_resources.clear()
	_wildlife_instances.clear()
	_initial_resource_spatial.clear()
	_pending_resource_spawns.clear()
	_wildlife_scan_index = 0
	_visibility_scan_index = 0
	if _resources != null:
		for child in _resources.get_children():
			_resources.remove_child(child)
			child.queue_free()
	if _wildlife_root != null:
		for child in _wildlife_root.get_children():
			if child.is_in_group("romestead_wildlife"):
				_wildlife_root.remove_child(child)
				child.queue_free()
	super._clear_generated_content()


func _spawn_procedural_wildlife() -> void:
	if _wildlife_root == null or _biomes.is_empty():
		return
	var profiles := [
		{"id": "squirrel", "count": 12, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT, BIOME_FOREST]},
		{"id": "rabbit", "count": 9, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT]},
		{"id": "deer_female", "count": 5, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT, BIOME_FOREST]},
		{"id": "bird", "count": 10, "biomes": [BIOME_MEADOW, BIOME_FOREST_LIGHT, BIOME_FOREST]},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x6A91F4
	for profile_value in profiles:
		var profile := profile_value as Dictionary
		var candidates: Array[Vector2i] = []
		var allowed := profile.get("biomes", []) as Array
		for cell_value in _biomes.keys():
			var cell := cell_value as Vector2i
			if allowed.has(int(_biomes[cell])) and Vector2(cell).length() > 10.0 and _is_spawn_cell_clear(cell, true):
				candidates.append(cell)
		for _index in range(int(profile.get("count", 0))):
			if candidates.is_empty():
				break
			var candidate_index := rng.randi_range(0, candidates.size() - 1)
			var cell := candidates[candidate_index]
			candidates.remove_at(candidate_index)
			var local_world_position := Vector2(cell * tile_size) + Vector2(tile_size, tile_size) * 0.5
			var creature := RomesteadWildlifeScene.instantiate() as Node2D
			if creature != null:
				creature.set("monster_id", str(profile.get("id", "")))
				creature.position = _wildlife_root.to_local(to_global(local_world_position))
				_wildlife_root.add_child(creature)
				_wildlife_instances.append(creature)
				creature.call("set_runtime_active", false)


func get_random_respawn_position(resource_type_id: String, previous_position: Vector2) -> Vector2:
	if _resources == null or _biomes.is_empty():
		return previous_position
	var content_db := get_node_or_null("/root/ContentDB")
	var allowed_biomes: Array = []
	if content_db != null and content_db.has_method("get_resource"):
		var data: Dictionary = content_db.get_resource(resource_type_id)
		var biome_value: Variant = data.get("biomes", [])
		if biome_value is Array:
			allowed_biomes = biome_value
	var candidates: Array[Vector2i] = []
	for cell_value in _biomes.keys():
		var cell := cell_value as Vector2i
		if _biome_is_allowed(int(_biomes[cell]), allowed_biomes):
			candidates.append(cell)
	if candidates.is_empty():
		return previous_position

	_respawn_nonce += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 8191 + resource_type_id.hash() * 131 + _respawn_nonce * 524287
	for _attempt in range(mini(candidates.size(), 96)):
		var cell := candidates[rng.randi_range(0, candidates.size() - 1)]
		var world_position := to_global(Vector2(cell * tile_size) + Vector2(tile_size, tile_size) * 0.5)
		var candidate := _resources.to_local(world_position)
		if _is_respawn_position_clear(candidate, resource_type_id):
			return _resources.to_global(candidate)
	return previous_position


func get_terrain_name_at_world(world_position: Vector2) -> String:
	if _ground == null:
		return "grass"
	var cell := _ground.local_to_map(_ground.to_local(world_position))
	match int(_terrain_types.get(cell, TERRAIN_BASE)):
		TERRAIN_DIRT:
			return "dirt"
		TERRAIN_GREEN:
			return "short_grass"
		TERRAIN_FOREST_LIGHT:
			return "forest_light"
		TERRAIN_FOREST_DEEP:
			return "forest"
		_:
			return "grass"


func get_biome_id_at_world(world_position: Vector2) -> String:
	if _ground == null:
		return "dry"
	var cell := _ground.local_to_map(_ground.to_local(world_position))
	var biome := int(_biomes.get(cell, BIOME_DRY))
	for biome_id in ["water", "dirt", "meadow", "forest_light", "forest", "forest_deep", "swamp", "dry"]:
		if _biome_is_allowed(biome, [biome_id]):
			return biome_id
	return "dry"


func _resource_type_for_prop(kind: PropKind, variation_seed: int) -> String:
	match kind:
		PropKind.TREE_ROUND:
			return _pick_variant(ROUND_TREES, variation_seed)
		PropKind.TREE_OLIVE:
			return _pick_variant(OLIVE_TREES, variation_seed)
		PropKind.TREE_CYPRESS:
			return _pick_variant(CYPRESS_TREES, variation_seed)
		PropKind.ROCK_BIG:
			return _pick_variant(BIG_ROCKS, variation_seed)
		PropKind.ROCK_SMALL:
			return _pick_variant(SMALL_STONES, variation_seed)
		PropKind.BUSH, PropKind.GROUND_PLANT:
			return _pick_variant(BUSHES, variation_seed)
		PropKind.WHEAT:
			return _pick_variant(WHEATS, variation_seed)
		PropKind.APPLE_TREE:
			return _pick_variant(APPLE_TREES, variation_seed)
		PropKind.STONE_PINE:
			return _pick_variant(STONE_PINES, variation_seed)
		PropKind.MOSSY_ROCK:
			return "mossy_rock1"
		PropKind.COPPER_ORE:
			return "copper_ore_node"
		PropKind.MUSHROOM:
			return _pick_variant(FOREST_MUSHROOMS, variation_seed)
		PropKind.FLOWER:
			return _pick_variant(FOREST_FLOWERS, variation_seed)
		PropKind.PURPLE_BUSH:
			return "purple_bush1"
		PropKind.SMALL_BUSH:
			return "forest_bush1"
		_:
			return ""


func _pick_variant(options: Array, variation_seed: int) -> String:
	return str(options[posmod(variation_seed, options.size())]) if not options.is_empty() else ""


func _reserve_initial_resource_position(candidate: Vector2, kind: PropKind) -> bool:
	# EntitySizeSpotsGenerator in the base world already reserved every accepted
	# spot, including spots whose entity roll produced nothing. Do not run a
	# second resource-only spacing pass here; only reject authored blockers.
	var radius := 6.0
	if kind in [PropKind.TREE_ROUND, PropKind.TREE_OLIVE, PropKind.TREE_CYPRESS, PropKind.APPLE_TREE, PropKind.STONE_PINE]:
		radius = 10.0
	elif kind in [PropKind.ROCK_BIG, PropKind.MOSSY_ROCK]:
		radius = 9.0
	elif kind in [PropKind.ROCK_SMALL, PropKind.COPPER_ORE]:
		radius = 6.0
	return not _is_world_position_blocked(to_global(candidate), radius, false)


func _biome_is_allowed(biome: int, allowed: Array) -> bool:
	if allowed.is_empty():
		return true
	var biome_id := "dry"
	match biome:
		BIOME_DIRT:
			biome_id = "dirt"
		BIOME_MEADOW:
			biome_id = "meadow"
		BIOME_FOREST:
			biome_id = "forest"
		BIOME_FOREST_LIGHT:
			biome_id = "forest_light"
		BIOME_FOREST_DEEP:
			biome_id = "forest_deep"
		BIOME_SWAMP:
			biome_id = "swamp"
		BIOME_WATER:
			biome_id = "water"
	return allowed.has(biome_id)


func _is_respawn_position_clear(candidate: Vector2, respawning_type_id := "") -> bool:
	if _is_world_position_blocked(_resources.to_global(candidate), 8.0, true):
		return false
	var respawning_is_tree := _is_tree_type(respawning_type_id)
	for node in _resources.get_children():
		if not node is Node2D or not node.visible:
			continue
		var other_type := str(node.call("get_resource_type_id")) if node.has_method("get_resource_type_id") else ""
		var other_is_tree := _is_tree_type(other_type)
		var minimum_distance := DEFAULT_RESPAWN_MIN_DISTANCE
		if respawning_is_tree and other_is_tree:
			minimum_distance = TREE_RESPAWN_MIN_DISTANCE
		elif respawning_is_tree or other_is_tree:
			minimum_distance = TREE_TO_OTHER_MIN_DISTANCE
		if (node as Node2D).position.distance_squared_to(candidate) < minimum_distance * minimum_distance:
			return false
	return true


func _is_tree_type(resource_type_id: String) -> bool:
	return resource_type_id.to_lower().begins_with("tree")


func _is_spawn_cell_clear(cell: Vector2i, include_resources: bool) -> bool:
	if _is_forest_structure(cell) or _plains_cliffs.has(cell):
		return false
	var local_position := Vector2(cell * tile_size) + Vector2(tile_size, tile_size) * 0.5
	return not _is_world_position_blocked(to_global(local_position), 7.0, include_resources)


func _is_world_position_blocked(world_position: Vector2, radius: float, include_resources: bool) -> bool:
	var local_position := to_local(world_position)
	var cell := Vector2i(roundi(local_position.x / float(tile_size)), roundi(local_position.y / float(tile_size)))
	if _is_forest_structure(cell) or _plains_cliffs.has(cell):
		return true
	for building_value in get_tree().get_nodes_in_group("building"):
		var building := building_value as Node2D
		if building != null and _node_collision_overlaps_circle(building, world_position, radius):
			return true
	if include_resources:
		for resource_value in _managed_resources:
			var resource := resource_value as Node2D
			if resource == null or not is_instance_valid(resource) or not resource.visible:
				continue
			var resource_data_value: Variant = resource.get("resource_data")
			var collision_value: Variant = (resource_data_value as Dictionary).get("collision", {}) if resource_data_value is Dictionary else {}
			var collision := collision_value as Dictionary if collision_value is Dictionary else {}
			var other_radius := float(collision.get("body_radius", 6.0))
			if resource.global_position.distance_squared_to(world_position) <= pow(radius + other_radius, 2.0):
				return true
		for pending_value in _pending_resource_spawns.values():
			var pending := pending_value as Dictionary
			var pending_world := to_global(Vector2(pending.get("position", Vector2.ZERO)))
			if pending_world.distance_squared_to(world_position) <= pow(radius + 6.0, 2.0):
				return true
	return false


func _node_collision_overlaps_circle(node: Node, world_position: Vector2, radius: float) -> bool:
	var probe := CircleShape2D.new()
	probe.radius = radius
	var probe_transform := Transform2D(0.0, world_position)
	for descendant_value in node.find_children("*", "CollisionShape2D", true, false):
		var collision := descendant_value as CollisionShape2D
		if collision == null or collision.disabled or collision.shape == null:
			continue
		if collision.shape.collide(collision.global_transform, probe, probe_transform):
			return true
	return false


func clear_spawnables_in_building(building: Node2D) -> void:
	if building == null:
		return
	for resource_value in _managed_resources:
		var resource := resource_value as Node2D
		if resource == null or not is_instance_valid(resource):
			continue
		if _node_collision_overlaps_circle(building, resource.global_position, 6.0):
			var resource_type := str(resource.call("get_resource_type_id")) if resource.has_method("get_resource_type_id") else ""
			resource.global_position = get_random_respawn_position(resource_type, resource.global_position)
	for animal in _wildlife_instances:
		if animal == null or not is_instance_valid(animal):
			continue
		if _node_collision_overlaps_circle(building, animal.global_position, 7.0):
			var replacement := _find_clear_wildlife_position(animal.global_position)
			if replacement != Vector2.INF:
				animal.global_position = replacement
	for key_value in _pending_resource_spawns.keys():
		var key := str(key_value)
		var pending := _pending_resource_spawns[key] as Dictionary
		var pending_world := to_global(Vector2(pending.get("position", Vector2.ZERO)))
		if _node_collision_overlaps_circle(building, pending_world, 6.0):
			_pending_resource_spawns.erase(key)


func _find_clear_wildlife_position(fallback: Vector2) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ int(fallback.x * 919.0) ^ int(fallback.y * 613.0) ^ _respawn_nonce
	var cells := _biomes.keys()
	if cells.is_empty():
		return Vector2.INF
	for _attempt in range(192):
		var cell := cells[rng.randi_range(0, cells.size() - 1)] as Vector2i
		if _is_spawn_cell_clear(cell, true):
			return to_global(Vector2(cell * tile_size) + Vector2(tile_size, tile_size) * 0.5)
	return Vector2.INF
