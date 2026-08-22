class_name RomesteadRuntimeSchedulerOptimized
extends "res://scripts/world/RomesteadRuntimeScheduler.gd"

# Keep streaming work small enough that creating several ResourceNode scenes
# cannot monopolize a render frame. The previous scheduler allowed 18 scene
# instantiations every 50 ms, which made average FPS look healthy while frame
# time still spiked visibly.
const SMOOTH_RESOURCE_SPAWNS_PER_PASS: int = 4


func _camera_refresh_needed() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false

	var camera: Camera2D = viewport.get_camera_2d()
	var focus_position: Vector2 = _world.global_position if _world != null else Vector2.ZERO
	var zoom_value: Vector2 = Vector2.ONE
	if camera != null:
		# With Camera2D smoothing enabled, global_position follows the target while
		# the rendered screen can still be catching up. Visibility must follow what
		# the player actually sees.
		focus_position = camera.get_screen_center_position()
		zoom_value = camera.zoom
	var viewport_size: Vector2 = viewport.get_visible_rect().size

	if not _last_focus_position.is_finite():
		_store_view_signature(focus_position, viewport_size, zoom_value)
		return true

	var moved_far: bool = (
		focus_position.distance_squared_to(_last_focus_position)
		>= CAMERA_REFRESH_DISTANCE * CAMERA_REFRESH_DISTANCE
	)
	var view_changed: bool = viewport_size != _last_viewport_size or zoom_value != _last_zoom
	if moved_far or view_changed:
		_store_view_signature(focus_position, viewport_size, zoom_value)
		return true
	return false


func _get_stream_focus_position() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player != null:
		return _player.global_position

	var viewport: Viewport = get_viewport()
	var camera: Camera2D = viewport.get_camera_2d() if viewport != null else null
	if camera != null:
		return camera.get_screen_center_position()
	return _world.global_position if _world != null else Vector2.ZERO


func _stream_nearby_resources(stream_bounds: Rect2) -> int:
	var pending: Dictionary = _pending_dictionary()
	if pending.is_empty() or _pending_by_chunk.is_empty():
		return 0

	var spawned: int = 0
	for chunk: Vector2i in _chunks_for_rect(stream_bounds):
		if spawned >= SMOOTH_RESOURCE_SPAWNS_PER_PASS:
			break
		var keys_value: Variant = _pending_by_chunk.get(chunk, null)
		if not (keys_value is Array):
			continue
		var keys: Array = keys_value as Array
		var index: int = keys.size() - 1
		while index >= 0 and spawned < SMOOTH_RESOURCE_SPAWNS_PER_PASS:
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


func _refresh_wildlife(active_bounds: Rect2) -> void:
	if _world == null:
		return
	var wildlife_value: Variant = _world.get("_wildlife_instances")
	if not (wildlife_value is Array):
		return

	var wildlife: Array = wildlife_value as Array
	var active_count: int = 0
	var index: int = wildlife.size() - 1
	while index >= 0:
		var animal_value: Variant = wildlife[index]

		# IMPORTANT: validate the Object before any `as Node2D` cast. Enemy death
		# queue_free() can leave a Freed Object variant in an Array until the owner
		# removes it. Casting that stale variant is the exact runtime error seen
		# when the squirrel died.
		if typeof(animal_value) != TYPE_OBJECT or not is_instance_valid(animal_value):
			wildlife.remove_at(index)
			index -= 1
			continue

		var animal := animal_value as Node2D
		if animal == null:
			wildlife.remove_at(index)
			index -= 1
			continue
		var active: bool = active_bounds.has_point(animal.global_position)
		if animal.has_method("set_runtime_active"):
			animal.call("set_runtime_active", active)
		if active:
			active_count += 1
		index -= 1

	_diagnostics["active_wildlife"] = active_count
