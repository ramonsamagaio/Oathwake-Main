class_name RomesteadRuntimeScheduler
extends Node

# Runtime scheduler adapted from the architectural patterns observed in the
# shipped Romestead binary: visible-area/chunk updates, bounded streaming and
# phased simulation instead of scanning the complete world every frame.
#
# This script deliberately does not own generation. The authored procedural
# world remains the source of truth for terrain/resources; this node only
# decides what needs CPU work around the current camera.

const STREAM_CHUNK_PIXELS: float = 384.0
const ACTIVE_MARGIN_PIXELS: float = 176.0
const STREAM_MARGIN_PIXELS: float = 288.0
const CAMERA_REFRESH_DISTANCE: float = 96.0
const MAX_RESOURCE_SPAWNS_PER_TICK: int = 18

const STREAM_INTERVAL: float = 0.05
const VISIBILITY_INTERVAL: float = 0.10
const WIND_INTERVAL: float = 1.0 / 30.0
const OCCLUSION_INTERVAL: float = 0.10
const WILDLIFE_INTERVAL: float = 0.20
const PENDING_INDEX_CHECK_INTERVAL: float = 0.75

var _world: Node2D
var _enabled: bool = false

var _pending_by_chunk: Dictionary = {}
var _known_pending_count: int = -1
var _last_world_seed: int = -2147483648

var _active_resources: Array[Node] = []
var _active_wind_resources: Array[Node] = []
var _active_occlusion_resources: Array[Node] = []
var _active_resource_ids: Dictionary = {}

var _player: Node2D
var _last_focus_position: Vector2 = Vector2(INF, INF)
var _last_viewport_size: Vector2 = Vector2.ZERO
var _last_zoom: Vector2 = Vector2.ZERO
var _force_visibility_refresh: bool = true

var _stream_accumulator: float = 0.0
var _visibility_accumulator: float = 0.0
var _wind_accumulator: float = 0.0
var _occlusion_accumulator: float = 0.0
var _wildlife_accumulator: float = 0.0
var _index_check_accumulator: float = 0.0

var _last_wind_strength: float = INF
var _last_wind_speed: float = INF
var _last_wind_direction: Vector2 = Vector2(INF, INF)

var _diagnostics: Dictionary = {
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

	# Replace the old world-wide idle scan with one bounded scheduler.
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

	# A large camera/focus jump is a streaming event, not only a visibility event.
	# Run one bounded pass immediately so teleports, loads and uncapped headless
	# validation do not have to wait for STREAM_INTERVAL wall-clock time to elapse.
	var focus_changed: bool = _camera_refresh_needed()
	if focus_changed:
		_force_visibility_refresh = true
		_run_stream_pass()
		_stream_accumulator = 0.0
	elif _stream_accumulator >= STREAM_INTERVAL:
		var elapsed: float = _stream_accumulator
		_stream_accumulator = fmod(_stream_accumulator, STREAM_INTERVAL)
		_run_stream_pass()
		# A long hitch must not cause a burst of catch-up spawn passes.
		if elapsed > STREAM_INTERVAL * 4.0:
			_stream_accumulator = 0.0

	if _force_visibility_refresh or _visibility_accumulator >= VISIBILITY_INTERVAL:
		_visibility_accumulator = fmod(_visibility_accumulator, VISIBILITY_INTERVAL)
		_refresh_visibility(_force_visibility_refresh)
		_force_visibility_refresh = false

	if _wind_accumulator >= WIND_INTERVAL:
		var wind_delta: float = _wind_accumulator
		_wind_accumulator = fmod(_wind_accumulator, WIND_INTERVAL)
		_tick_wind(minf(wind_delta, WIND_INTERVAL * 3.0))

	if _occlusion_accumulator >= OCCLUSION_INTERVAL:
		var occlusion_delta: float = _occlusion_accumulator
		_occlusion_accumulator = fmod(_occlusion_accumulator, OCCLUSION_INTERVAL)
		_tick_occlusion(minf(occlusion_delta, OCCLUSION_INTERVAL * 3.0))

	if _wildlife_accumulator >= WILDLIFE_INTERVAL:
		_wildlife_accumulator = fmod(_wildlife_accumulator, WILDLIFE_INTERVAL)
		_refresh_wildlife(_get_active_bounds())


func _run_stream_pass() -> void:
	var streamed: int = _stream_nearby_resources(_get_active_bounds().grow(STREAM_MARGIN_PIXELS))
	if streamed > 0:
		_force_visibility_refresh = true
	_diagnostics["stream_ticks"] = int(_diagnostics["stream_ticks"]) + 1


func _camera_refresh_needed() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false

	var camera: Camera2D = viewport.get_camera_2d()
	var focus_position: Vector2 = _world.global_position if _world != null else Vector2.ZERO
	var zoom: Vector2 = Vector2.ONE
	if camera != null:
		focus_position = camera.global_position
		zoom = camera.zoom

	# Node does not expose CanvasItem.get_viewport_rect(). Query the Viewport
	# explicitly so this scheduler works as a plain Node in Godot 4.6.x.
	var viewport_size: Vector2 = viewport.get_visible_rect().size

	if not _last_focus_position.is_finite():
		_store_view_signature(focus_position, viewport_size, zoom)
		return true

	var moved_far: bool = (
		focus_position.distance_squared_to(_last_focus_position)
		>= CAMERA_REFRESH_DISTANCE * CAMERA_REFRESH_DISTANCE
	)
	var view_changed: bool = viewport_size != _last_viewport_size or zoom != _last_zoom
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

	var viewport: Viewport = get_viewport()
	var camera: Camera2D = viewport.get_camera_2d() if viewport != null else null
	var focus_position: Vector2 = Vector2.ZERO
	var visible_size: Vector2 = Vector2(1280.0, 720.0)
	var zoom: Vector2 = Vector2.ONE
	if viewport != null:
		visible_size = viewport.get_visible_rect().size
	if camera != null:
		focus_position = camera.global_position
		zoom = camera.zoom
	var safe_zoom: Vector2 = Vector2(maxf(absf(zoom.x), 0.001), maxf(absf(zoom.y), 0.001))
	var world_visible_size: Vector2 = visible_size / safe_zoom
	return Rect2(focus_position - world_visible_size * 0.5, world_visible_size).grow(ACTIVE_MARGIN_PIXELS)


func _chunk_key(global_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(global_position.x / STREAM_CHUNK_PIXELS),
		floori(global_position.y / STREAM_CHUNK_PIXELS)
	)


func _chunks_for_rect(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start: Vector2i = _chunk_key(rect.position)
	var safe_end: Vector2 = rect.end - Vector2(0.001, 0.001)
	var finish: Vector2i = _chunk_key(safe_end)
	for y: int in range(start.y, finish.y + 1):
		for x: int in range(start.x, finish.x + 1):
			result.append(Vector2i(x, y))
	return result


func _pending_dictionary() -> Dictionary:
	if _world == null:
		return {}
	var value: Variant = _world.get("_pending_resource_spawns")
	return value as Dictionary if value is Dictionary else {}


func _rebuild_pending_chunk_index() -> void:
	_pending_by_chunk.clear()
	var pending: Dictionary = _pending_dictionary()
	for key_value: Variant in pending.keys():
		var key: String = str(key_value)
		var spawn_value: Variant = pending.get(key, null)
		if not (spawn_value is Dictionary):
			continue
		var spawn: Dictionary = spawn_value as Dictionary
		var position_value: Variant = spawn.get("position", Vector2.ZERO)
		var local_position: Vector2 = position_value as Vector2 if position_value is Vector2 else Vector2.ZERO
		var global_position: Vector2 = _world.to_global(local_position)
		var chunk: Vector2i = _chunk_key(global_position)
		if not _pending_by_chunk.has(chunk):
			_pending_by_chunk[chunk] = []
		var chunk_keys: Array = _pending_by_chunk[chunk] as Array
		chunk_keys.append(key)
	_known_pending_count = pending.size()
	_last_world_seed = int(_world.get("world_seed"))
	_diagnostics["pending_chunks"] = _pending_by_chunk.size()
	_diagnostics["pending_resources"] = pending.size()


func _check_pending_index_integrity() -> void:
	if _world == null:
		return
	var pending: Dictionary = _pending_dictionary()
	var world_seed: int = int(_world.get("world_seed"))
	if world_seed != _last_world_seed or pending.size() > _known_pending_count:
		_rebuild_pending_chunk_index()
		return
	_known_pending_count = pending.size()
	_diagnostics["pending_resources"] = pending.size()


func _stream_nearby_resources(stream_bounds: Rect2) -> int:
	var pending: Dictionary = _pending_dictionary()
	if pending.is_empty() or _pending_by_chunk.is_empty():
		return 0

	var spawned: int = 0
	for chunk: Vector2i in _chunks_for_rect(stream_bounds):
		if spawned >= MAX_RESOURCE_SPAWNS_PER_TICK:
			break
		var keys_value: Variant = _pending_by_chunk.get(chunk, null)
		if not (keys_value is Array):
			continue
		var keys: Array = keys_value as Array
		var index: int = keys.size() - 1
		while index >= 0 and spawned < MAX_RESOURCE_SPAWNS_PER_TICK:
			var key: String = str(keys[index])
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

			var spawn: Dictionary = spawn_value as Dictionary
			var position_value: Variant = spawn.get("position", Vector2.ZERO)
			var local_position: Vector2 = position_value as Vector2 if position_value is Vector2 else Vector2.ZERO
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

	var active_bounds: Rect2 = _get_active_bounds()
	var resources: Array = _managed_resources()
	var next_active_resources: Array[Node] = []
	var next_active_wind: Array[Node] = []
	var next_active_occlusion: Array[Node] = []
	var next_ids: Dictionary = {}
	var wind_strength: float = float(_world.get("_weather_wind_strength"))
	var wind_speed: float = float(_world.get("_weather_wind_speed"))
	var wind_direction_value: Variant = _world.get("_weather_wind_direction")
	var wind_direction: Vector2 = wind_direction_value as Vector2 if wind_direction_value is Vector2 else Vector2.RIGHT

	for resource_value: Variant in resources:
		var resource: Node = resource_value as Node
		if resource == null or not is_instance_valid(resource):
			continue
		var resource_2d: Node2D = resource as Node2D
		if resource_2d == null:
			continue

		var is_active: bool = active_bounds.has_point(resource_2d.global_position)
		var instance_id: int = resource.get_instance_id()
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
	var wind_strength: float = float(_world.get("_weather_wind_strength"))
	var wind_speed: float = float(_world.get("_weather_wind_speed"))
	var direction_value: Variant = _world.get("_weather_wind_direction")
	var wind_direction: Vector2 = direction_value as Vector2 if direction_value is Vector2 else Vector2.RIGHT
	var environment_changed: bool = (
		not is_equal_approx(wind_strength, _last_wind_strength)
		or not is_equal_approx(wind_speed, _last_wind_speed)
		or not wind_direction.is_equal_approx(_last_wind_direction)
	)

	for resource: Node in _active_wind_resources:
		if resource == null or not is_instance_valid(resource):
			continue
		if resource is CanvasItem and not (resource as CanvasItem).visible:
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

	var player_position: Vector2 = _player.global_position
	for resource: Node in _active_occlusion_resources:
		if resource == null or not is_instance_valid(resource):
			continue
		if resource is CanvasItem and not (resource as CanvasItem).visible:
			continue
		if resource.has_method("tick_player_occlusion"):
			resource.call("tick_player_occlusion", player_position, delta)


func _refresh_wildlife(active_bounds: Rect2) -> void:
	if _world == null:
		return
	var wildlife_value: Variant = _world.get("_wildlife_instances")
	if not (wildlife_value is Array):
		return

	var wildlife: Array = wildlife_value as Array
	var active_count: int = 0
	for animal_value: Variant in wildlife:
		var animal: Node2D = animal_value as Node2D
		if animal == null or not is_instance_valid(animal):
			continue
		var active: bool = active_bounds.has_point(animal.global_position)
		if animal.has_method("set_runtime_active"):
			animal.call("set_runtime_active", active)
		if active:
			active_count += 1
	_diagnostics["active_wildlife"] = active_count


func get_diagnostics() -> Dictionary:
	var result: Dictionary = _diagnostics.duplicate(true)
	result["scheduler_enabled"] = _enabled
	result["world_process_disabled"] = _world != null and not _world.is_processing()
	return result
