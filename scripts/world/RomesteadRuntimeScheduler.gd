class_name RomesteadRuntimeScheduler
extends Node

# Runtime scheduler adapted from the architectural patterns observed in the
# shipped Romestead binary: visible-area/chunk updates, bounded streaming and
# phased simulation instead of scanning the complete world every frame.
#
# This script deliberately does not own generation. The authored procedural
# world remains the source of truth for terrain/resources; this node only
# decides what needs CPU work around the current camera.

const STREAM_CHUNK_PIXELS := 384.0
const ACTIVE_MARGIN_PIXELS := 176.0
const STREAM_MARGIN_PIXELS := 288.0
const CAMERA_REFRESH_DISTANCE := 96.0
const MAX_RESOURCE_SPAWNS_PER_TICK := 18

const STREAM_INTERVAL := 0.05
const VISIBILITY_INTERVAL := 0.10
const WIND_INTERVAL := 1.0 / 30.0
const OCCLUSION_INTERVAL := 0.10
const WILDLIFE_INTERVAL := 0.20
const PENDING_INDEX_CHECK_INTERVAL := 0.75

var _world: Node2D
var _enabled := false

var _pending_by_chunk: Dictionary = {}
var _known_pending_count := -1
var _last_world_seed := -2147483648

var _active_resources: Array[Node] = []
var _active_wind_resources: Array[Node] = []
var _active_occlusion_resources: Array[Node] = []
var _active_resource_ids: Dictionary = {}

var _player: Node2D
var _last_focus_position := Vector2(INF, INF)
var _last_viewport_size := Vector2.ZERO
var _last_zoom := Vector2.ZERO
var _force_visibility_refresh := true

var _stream_accumulator := 0.0
var _visibility_accumulator := 0.0
var _wind_accumulator := 0.0
var _occlusion_accumulator := 0.0
var _wildlife_accumulator := 0.0
var _index_check_accumulator := 0.0

var _last_wind_strength := INF
var _last_wind_speed := INF
var _last_wind_direction := Vector2(INF, INF)

var _diagnostics := {
	"stream_ticks": 0,
	"streamed_resources": 0,
	"visibility_refreshes": 0,
	"pending_chunks": 0,
	"pending_resources": 0,
	"active_resources": 0,
	"active_wind": 0,
	"active_occlusion": 0,
	"active_wildlife": 0,
}


func setup(world: Node) -> void:
	_detach_world()
	if not (world is Node2D):
		set_process(false)
		return
	_world = world as Node2D
	if not _supports_managed_world(_world):
		_world = null
		set_process(false)
		return

	# The original RomesteadProceduralGameWorld._process() is intentionally
	# replaced by this scheduler. ResourceNode already disables individual idle
	# callbacks, so this leaves one bounded world scheduler instead of N actors.
	_world.set_process(false)
	_enabled = true
	set_process(true)
	_rebuild_pending_chunk_index()
	_force_visibility_refresh = true
	_refresh_visibility(true)
	_refresh_wildlife(_get_active_bounds())


func _exit_tree() -> void:
	_detach_world()


func _detach_world() -> void:
	if _world != null and is_instance_valid(_world) and _enabled:
		_world.set_process(true)
	_world = null
	_enabled = false
	_pending_by_chunk.clear()
	_active_resources.clear()
	_active_wind_resources.clear()
	_active_occlusion_resources.clear()
	_active_resource_ids.clear()
	set_process(false)


func _supports_managed_world(world: Node) -> bool:
	return (
		world.has_method("_compute_active_bounds")
		and world.has_method("_instantiate_functional_resource")
		and world.has_method("set_environment")
	)


func _process(delta: float) -> void:
	if not _enabled or _world == null or not is_instance_valid(_world):
		set_process(false)
		return

	_stream_accumulator += delta
	_visibility_accumulator += delta
	_wind_accumulator += delta
	_occlusion_accumulator += delta
	_wildlife_accumulator += delta
	_index_check_accumulator += delta

	if _index_check_accumulator >= PENDING_INDEX_CHECK_INTERVAL:
		_index_check_accumulator = fmod(_index_check_accumulator, PENDING_INDEX_CHECK_INTERVAL)
		_check_pending_index_integrity()

	if _camera_refresh_needed():
		_force_visibility_refresh = true

	if _stream_accumulator >= STREAM_INTERVAL:
		var elapsed := _stream_accumulator
		_stream_accumulator = fmod(_stream_accumulator, STREAM_INTERVAL)
		var streamed := _stream_nearby_resources(_get_active_bounds().grow(STREAM_MARGIN_PIXELS))
		if streamed > 0:
			_force_visibility_refresh = true
		_diagnostics["stream_ticks"] = int(_diagnostics["stream_ticks"]) + 1
		# Keep elapsed consumed so a long hitch cannot cause an immediate burst of
		# multiple spawn passes on the next frame.
		if elapsed > STREAM_INTERVAL * 4.0:
			_stream_accumulator = 0.0

	if _force_visibility_refresh or _visibility_accumulator >= VISIBILITY_INTERVAL:
		_visibility_accumulator = fmod(_visibility_accumulator, VISIBILITY_INTERVAL)
		_refresh_visibility(_force_visibility_refresh)
		_force_visibility_refresh = false

	if _wind_accumulator >= WIND_INTERVAL:
		var wind_delta := _wind_accumulator
		_wind_accumulator = fmod(_wind_accumulator, WIND_INTERVAL)
		_tick_wind(minf(wind_delta, WIND_INTERVAL * 3.0))

	if _occlusion_accumulator >= OCCLUSION_INTERVAL:
		var occlusion_delta := _occlusion_accumulator
		_occlusion_accumulator = fmod(_occlusion_accumulator, OCCLUSION_INTERVAL)
		_tick_occlusion(minf(occlusion_delta, OCCLUSION_INTERVAL * 3.0))

	if _wildlife_accumulator >= WILDLIFE_INTERVAL:
		_wildlife_accumulator = fmod(_wildlife_accumulator, WILDLIFE_INTERVAL)
		_refresh_wildlife(_get_active_bounds())


func _camera_refresh_needed() -> bool:
	var camera := get_viewport().get_camera_2d()
	var focus_position := camera.global_position if camera != null else _world.global_position
	var viewport_size := get_viewport_rect().size
	var zoom := camera.zoom if camera != null else Vector2.ONE
	if not _last_focus_position.is_finite():
		_store_view_signature(focus_position, viewport_size, zoom)
		return true
	var moved_far := focus_position.distance_squared_to(_last_focus_position) >= CAMERA_REFRESH_DISTANCE * CAMERA_REFRESH_DISTANCE
	var view_changed := viewport_size != _last_viewport_size or zoom != _last_zoom
	if moved_far or view_changed:
		_store_view_signature(focus_position, viewport_size, zoom)
		return true
	return false


func _store_view_signature(focus_position: Vector2, viewport_size: Vector2, zoom: Vector2) -> void:
	_last_focus_position = focus_position
	_last_viewport_size = viewport_size
	_last_zoom = zoom


func _get_active_bounds() -> Rect2:
	if _world != null and _world.has_method("_compute_active_bounds"):
		var value: Variant = _world.call("_compute_active_bounds")
		if value is Rect2:
			return (value as Rect2).grow(ACTIVE_MARGIN_PIXELS)
	var camera := get_viewport().get_camera_2d()
	var focus_position := camera.global_position if camera != null else Vector2.ZERO
	return Rect2(focus_position - Vector2(640.0, 360.0), Vector2(1280.0, 720.0)).grow(ACTIVE_MARGIN_PIXELS)


func _chunk_key(global_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(global_position.x / STREAM_CHUNK_PIXELS),
		floori(global_position.y / STREAM_CHUNK_PIXELS)
	)


func _chunks_for_rect(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start := _chunk_key(rect.position)
	var safe_end := rect.end - Vector2(0.001, 0.001)
	var finish := _chunk_key(safe_end)
	for y in range(start.y, finish.y + 1):
		for x in range(start.x, finish.x + 1):
			result.append(Vector2i(x, y))
	return result


func _pending_dictionary() -> Dictionary:
	if _world == null:
		return {}
	var value: Variant = _world.get("_pending_resource_spawns")
	return value as Dictionary if value is Dictionary else {}


func _rebuild_pending_chunk_index() -> void:
	_pending_by_chunk.clear()
	var pending := _pending_dictionary()
	for key_value in pending.keys():
		var key := str(key_value)
		var spawn_value: Variant = pending.get(key, null)
		if not (spawn_value is Dictionary):
			continue
		var spawn := spawn_value as Dictionary
		var local_position := Vector2(spawn.get("position", Vector2.ZERO))
		var global_position := _world.to_global(local_position)
		var chunk := _chunk_key(global_position)
		if not _pending_by_chunk.has(chunk):
			_pending_by_chunk[chunk] = []
		(_pending_by_chunk[chunk] as Array).append(key)
	_known_pending_count = pending.size()
	_last_world_seed = int(_world.get("world_seed"))
	_diagnostics["pending_chunks"] = _pending_by_chunk.size()
	_diagnostics["pending_resources"] = pending.size()


func _check_pending_index_integrity() -> void:
	if _world == null:
		return
	var pending := _pending_dictionary()
	var world_seed := int(_world.get("world_seed"))
	# Normal streaming changes _known_pending_count itself. A seed/regeneration
	# change or an unexpected increase means another system rewrote reservations,
	# in which case rebuilding once is much cheaper than scanning them every frame.
	if world_seed != _last_world_seed or pending.size() > _known_pending_count:
		_rebuild_pending_chunk_index()
		return
	_known_pending_count = pending.size()
	_diagnostics["pending_resources"] = pending.size()


func _stream_nearby_resources(stream_bounds: Rect2) -> int:
	var pending := _pending_dictionary()
	if pending.is_empty() or _pending_by_chunk.is_empty():
		return 0
	var spawned := 0
	for chunk in _chunks_for_rect(stream_bounds):
		if spawned >= MAX_RESOURCE_SPAWNS_PER_TICK:
			break
		var keys_value: Variant = _pending_by_chunk.get(chunk, null)
		if not (keys_value is Array):
			continue
		var keys := keys_value as Array
		var index := keys.size() - 1
		while index >= 0 and spawned < MAX_RESOURCE_SPAWNS_PER_TICK:
			var key := str(keys[index])
			if not pending.has(key):
				keys.remove_at(index)
				index -= 1
				continue
			var spawn_value: Variant = pending.get(key, null)
			if not (spawn_value is Dictionary):
				pending.erase(key)
				keys.remove_at(index)
				index -= 1
				continue
			var spawn := spawn_value as Dictionary
			var local_position := Vector2(spawn.get("position", Vector2.ZERO))
			if not stream_bounds.has_point(_world.to_global(local_position)):
				index -= 1
				continue
			pending.erase(key)
			keys.remove_at(index)
			_world.call(
				"_instantiate_functional_resource",
				local_position,
				int(spawn.get("kind", 0)),
				int(spawn.get("variation_seed", 0)),
				str(spawn.get("resource_type", ""))
			)
			spawned += 1
			index -= 1
		if keys.is_empty():
			_pending_by_chunk.erase(chunk)
	_known_pending_count = pending.size()
	_diagnostics["pending_chunks"] = _pending_by_chunk.size()
	_diagnostics["pending_resources"] = pending.size()
	_diagnostics["streamed_resources"] = int(_diagnostics["streamed_resources"]) + spawned
	return spawned


func _managed_resources() -> Array:
	if _world == null:
		return []
	var value: Variant = _world.get("_managed_resources")
	return value as Array if value is Array else []


func _refresh_visibility(force_all: bool) -> void:
	if _world == null:
		return
	var active_bounds := _get_active_bounds()
	var resources := _managed_resources()
	var next_active_resources: Array[Node] = []
	var next_active_wind: Array[Node] = []
	var next_active_occlusion: Array[Node] = []
	var next_ids: Dictionary = {}
	var wind_strength := float(_world.get("_weather_wind_strength"))
	var wind_speed := float(_world.get("_weather_wind_speed"))
	var wind_direction_value: Variant = _world.get("_weather_wind_direction")
	var wind_direction := wind_direction_value as Vector2 if wind_direction_value is Vector2 else Vector2.RIGHT

	for resource_value in resources:
		var resource := resource_value as Node
		if resource == null or not is_instance_valid(resource):
			continue
		var resource_2d := resource as Node2D
		if resource_2d == null:
			continue
		var is_active := active_bounds.has_point(resource_2d.global_position)
		var instance_id := resource.get_instance_id()
		if force_all or is_active != _active_resource_ids.has(instance_id):
			if resource.has_method("set_runtime_culled"):
				resource.call("set_runtime_culled", not is_active)
		if not is_active:
			continue
		next_ids[instance_id] = true
		next_active_resources.append(resource)
		if resource.has_method("uses_romestead_wind") and bool(resource.call("uses_romestead_wind")):
			next_active_wind.append(resource)
			if not _active_resource_ids.has(instance_id) and resource.has_method("set_romestead_environment"):
				resource.call("set_romestead_environment", 0.0, 0.0, wind_strength, wind_speed, wind_direction)
		if resource.has_method("uses_player_occlusion") and bool(resource.call("uses_player_occlusion")):
			next_active_occlusion.append(resource)

	_active_resources = next_active_resources
	_active_wind_resources = next_active_wind
	_active_occlusion_resources = next_active_occlusion
	_active_resource_ids = next_ids
	_diagnostics["visibility_refreshes"] = int(_diagnostics["visibility_refreshes"]) + 1
	_diagnostics["active_resources"] = _active_resources.size()
	_diagnostics["active_wind"] = _active_wind_resources.size()
	_diagnostics["active_occlusion"] = _active_occlusion_resources.size()


func _tick_wind(delta: float) -> void:
	if _world == null or _active_wind_resources.is_empty():
		return
	var wind_strength := float(_world.get("_weather_wind_strength"))
	var wind_speed := float(_world.get("_weather_wind_speed"))
	var direction_value: Variant = _world.get("_weather_wind_direction")
	var wind_direction := direction_value as Vector2 if direction_value is Vector2 else Vector2.RIGHT
	var environment_changed := (
		not is_equal_approx(wind_strength, _last_wind_strength)
		or not is_equal_approx(wind_speed, _last_wind_speed)
		or not wind_direction.is_equal_approx(_last_wind_direction)
	)
	for resource in _active_wind_resources:
		if resource == null or not is_instance_valid(resource) or not resource.visible:
			continue
		if environment_changed and resource.has_method("set_romestead_environment"):
			resource.call("set_romestead_environment", 0.0, 0.0, wind_strength, wind_speed, wind_direction)
		if resource.has_method("tick_romestead_motion"):
			resource.call("tick_romestead_motion", delta)
	_last_wind_strength = wind_strength
	_last_wind_speed = wind_speed
	_last_wind_direction = wind_direction


func _tick_occlusion(delta: float) -> void:
	if _active_occlusion_resources.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return
	var player_position := _player.global_position
	for resource in _active_occlusion_resources:
		if resource == null or not is_instance_valid(resource) or not resource.visible:
			continue
		if resource.has_method("tick_player_occlusion"):
			resource.call("tick_player_occlusion", player_position, delta)


func _refresh_wildlife(active_bounds: Rect2) -> void:
	if _world == null:
		return
	var wildlife_value: Variant = _world.get("_wildlife_instances")
	if not (wildlife_value is Array):
		return
	var active_count := 0
	for animal_value in wildlife_value as Array:
		var animal := animal_value as Node2D
		if animal == null or not is_instance_valid(animal):
			continue
		var active := active_bounds.has_point(animal.global_position)
		if animal.has_method("set_runtime_active"):
			animal.call("set_runtime_active", active)
		if active:
			active_count += 1
	_diagnostics["active_wildlife"] = active_count


func get_diagnostics() -> Dictionary:
	var result := _diagnostics.duplicate(true)
	result["scheduler_enabled"] = _enabled
	result["world_process_disabled"] = _world != null and not _world.is_processing()
	return result
