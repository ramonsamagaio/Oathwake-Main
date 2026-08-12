class_name ProceduralCreature
extends Node2D

signal parameter_changed(key: StringName, value: Variant)
signal preset_applied
signal simulation_state_changed(active: bool)

const PIXEL_UNIT := 1.0

@export_group("Identity")
@export var creature_id: StringName = &"procedural_creature"
@export var random_seed: int = 1337

@export_group("Simulation")
@export_range(5.0, 120.0, 1.0) var simulation_hz: float = 60.0
@export var simulation_enabled := true
@export var quantize_motion := true
@export_range(0.1, 4.0, 0.05) var global_scale_factor := 1.0
@export_range(0.0, 4.0, 0.05) var motion_intensity := 1.0

@export_group("LOD / Budget")
@export var lod_enabled := true
@export_range(64.0, 4096.0, 16.0) var full_rate_distance := 640.0
@export_range(64.0, 8192.0, 16.0) var reduced_rate_distance := 1200.0
@export_range(1.0, 60.0, 1.0) var reduced_simulation_hz := 20.0

@export_group("Palette")
@export var primary_color := Color("6f9f57")
@export var secondary_color := Color("45653d")
@export var accent_color := Color("c6d98b")
@export var shadow_color := Color("25352d")

# Kept as a read-only compatibility value because older presets and creature
# scripts may still ask for pixel_size. Rendering is now always one real pixel.
var pixel_size: int = 1
var velocity := Vector2.ZERO
var external_force := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _sim_accumulator := 0.0
var _manual_lod_anchor: Node2D
var _world_movement_bounds := Rect2()
var _has_world_movement_bounds := false
var _simulation_position := Vector2.ZERO
var _presented_position := Vector2.ZERO


func _ready() -> void:
	pixel_size = 1
	_rng.seed = random_seed
	_simulation_position = position
	_presented_position = position
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not simulation_enabled:
		return
	var effective_hz := _effective_hz()
	if effective_hz <= 0.0:
		return
	var step := 1.0 / effective_hz
	_sim_accumulator += minf(delta, 0.1)
	var guard := 0
	while _sim_accumulator >= step and guard < 5:
		_sim_accumulator -= step
		_simulate(step)
		guard += 1
	queue_redraw()


func _simulate(delta: float) -> void:
	# Physics accumulates subpixel motion, while presentation snaps to the fixed
	# one-pixel grid. This preserves slow movement without ever changing pixel size.
	if position.distance_squared_to(_presented_position) > 0.0001:
		_simulation_position = position

	velocity += external_force * delta
	external_force = Vector2.ZERO
	_simulation_position += velocity * delta
	_simulation_position = _clamp_point_to_movement_bounds(_simulation_position)
	position = _snap_vec(_simulation_position) if quantize_motion else _simulation_position
	_presented_position = position
	velocity *= pow(0.88, delta * 60.0)

	_simulate_creature(delta)

	# Specialized solvers may author position directly. Fold that displacement
	# back into the continuous accumulator so the next tick cannot snap backwards.
	if position.distance_squared_to(_presented_position) > 0.0001:
		_simulation_position = _clamp_point_to_movement_bounds(position)
		position = _snap_vec(_simulation_position) if quantize_motion else _simulation_position
		_presented_position = position


func _simulate_creature(_delta: float) -> void:
	pass


func apply_impulse(impulse: Vector2) -> void:
	velocity += impulse * motion_intensity


func add_force(force: Vector2) -> void:
	external_force += force * motion_intensity


func set_movement_bounds(bounds: Rect2) -> void:
	_world_movement_bounds = bounds
	_has_world_movement_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0
	if _has_world_movement_bounds:
		_simulation_position = _clamp_point_to_movement_bounds(_simulation_position)
		position = _snap_vec(_simulation_position) if quantize_motion else _simulation_position
		_presented_position = position


func clear_movement_bounds() -> void:
	_has_world_movement_bounds = false
	_world_movement_bounds = Rect2()


func has_movement_bounds() -> bool:
	return _has_world_movement_bounds


func get_movement_bounds() -> Rect2:
	return _world_movement_bounds


func _clamp_point_to_movement_bounds(point: Vector2, margin: float = 0.0) -> Vector2:
	if not _has_world_movement_bounds:
		return point
	var inner := _world_movement_bounds.grow(-maxf(0.0, margin))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return _world_movement_bounds.get_center()
	return Vector2(
		clampf(point.x, inner.position.x, inner.end.x),
		clampf(point.y, inner.position.y, inner.end.y)
	)


func _pick_roam_target(home: Vector2, radius: float, margin: float = 0.0) -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * maxf(0.0, radius)
	var target := home + Vector2(cos(angle), sin(angle)) * distance
	return _clamp_point_to_movement_bounds(target, margin)


func _pick_roam_target_far(
	current: Vector2,
	home: Vector2,
	radius: float,
	margin: float,
	minimum_travel: float
) -> Vector2:
	# Prefer destinations that produce a meaningful journey. The old random
	# target picker could repeatedly choose nearby points, making roaming read as
	# nervous shuffling rather than exploration.
	var best := _clamp_point_to_movement_bounds(home, margin)
	var best_distance := current.distance_to(best)
	for _attempt in range(10):
		var angle := _rng.randf_range(0.0, TAU)
		# Bias away from the center of the roam disc so routes cover more ground.
		var distance := lerpf(radius * 0.48, radius, sqrt(_rng.randf()))
		var candidate := home + Vector2(cos(angle), sin(angle)) * distance
		candidate = _clamp_point_to_movement_bounds(candidate, margin)
		var travel := current.distance_to(candidate)
		if travel > best_distance:
			best = candidate
			best_distance = travel
		if travel >= minimum_travel:
			return candidate
	return best


func _roam_watchdog_time(distance: float, speed: float, minimum_time: float, extra_time: float = 2.0) -> float:
	# A roam target must live long enough to be reachable. The timer is a stuck
	# watchdog only, never the normal reason to abandon a valid destination.
	var travel_time := distance / maxf(1.0, speed)
	return maxf(minimum_time, travel_time * 1.65 + extra_time)


func reseed(new_seed: int = -1) -> void:
	if new_seed < 0:
		new_seed = int(Time.get_ticks_usec() & 0x7fffffff)
	random_seed = new_seed
	_rng.seed = random_seed
	_reset_simulation()
	queue_redraw()


func _reset_simulation() -> void:
	velocity = Vector2.ZERO
	external_force = Vector2.ZERO
	_simulation_position = position
	_presented_position = position


func set_lod_anchor(anchor: Node2D) -> void:
	_manual_lod_anchor = anchor


func set_parameter(key: StringName, value: Variant) -> bool:
	if key == &"pixel_size":
		# Compatibility with old presets: accept the key but never allow the
		# procedural renderer to leave the one-pixel grid.
		pixel_size = 1
	elif key == &"simulation_hz":
		simulation_hz = clampf(float(value), 5.0, 120.0)
	elif key == &"global_scale_factor":
		global_scale_factor = clampf(float(value), 0.1, 4.0)
	elif key == &"motion_intensity":
		motion_intensity = clampf(float(value), 0.0, 4.0)
	elif key == &"quantize_motion":
		quantize_motion = bool(value)
	elif key == &"lod_enabled":
		lod_enabled = bool(value)
	else:
		return _set_creature_parameter(key, value)
	parameter_changed.emit(key, get_parameter(key))
	queue_redraw()
	return true


func _set_creature_parameter(_key: StringName, _value: Variant) -> bool:
	return false


func get_parameter(key: StringName) -> Variant:
	if key == &"pixel_size":
		return 1
	if key == &"simulation_hz":
		return simulation_hz
	if key == &"global_scale_factor":
		return global_scale_factor
	if key == &"motion_intensity":
		return motion_intensity
	if key == &"quantize_motion":
		return quantize_motion
	if key == &"lod_enabled":
		return lod_enabled
	return _get_creature_parameter(key)


func _get_creature_parameter(_key: StringName) -> Variant:
	return null


func get_editor_schema() -> Array[Dictionary]:
	var schema: Array[Dictionary] = [
		{"key": &"global_scale_factor", "label": "Geometry Scale", "type": "float", "min": 0.35, "max": 2.5, "step": 0.05},
		{"key": &"motion_intensity", "label": "Motion", "type": "float", "min": 0.0, "max": 3.0, "step": 0.05},
	]
	schema.append_array(_get_creature_editor_schema())
	return schema


func _get_creature_editor_schema() -> Array[Dictionary]:
	return []


func make_preset() -> Dictionary:
	var params: Dictionary = {}
	for descriptor in get_editor_schema():
		var key: StringName = descriptor.get("key", &"")
		if key != &"":
			params[String(key)] = get_parameter(key)
	return {
		"version": 2,
		"creature_id": String(creature_id),
		"seed": random_seed,
		"params": params,
		"palette": {
			"primary": primary_color.to_html(),
			"secondary": secondary_color.to_html(),
			"accent": accent_color.to_html(),
			"shadow": shadow_color.to_html(),
		},
	}


func apply_preset(data: Dictionary) -> void:
	if data.has("seed"):
		random_seed = int(data["seed"])
		_rng.seed = random_seed
	var palette: Dictionary = data.get("palette", {})
	if palette.has("primary"):
		primary_color = Color.from_string(String(palette["primary"]), primary_color)
	if palette.has("secondary"):
		secondary_color = Color.from_string(String(palette["secondary"]), secondary_color)
	if palette.has("accent"):
		accent_color = Color.from_string(String(palette["accent"]), accent_color)
	if palette.has("shadow"):
		shadow_color = Color.from_string(String(palette["shadow"]), shadow_color)
	var params: Dictionary = data.get("params", {})
	for key in params.keys():
		set_parameter(StringName(key), params[key])
	pixel_size = 1
	_reset_simulation()
	preset_applied.emit()
	queue_redraw()


func set_simulation_active(active: bool) -> void:
	simulation_enabled = active
	simulation_state_changed.emit(active)


func _effective_hz() -> float:
	if not lod_enabled:
		return simulation_hz
	var anchor := _resolve_lod_anchor()
	if anchor == null:
		return simulation_hz
	var distance := global_position.distance_to(anchor.global_position)
	if distance <= full_rate_distance:
		return simulation_hz
	if distance <= reduced_rate_distance:
		return reduced_simulation_hz
	return maxf(4.0, reduced_simulation_hz * 0.25)


func _resolve_lod_anchor() -> Node2D:
	if _manual_lod_anchor != null and is_instance_valid(_manual_lod_anchor):
		return _manual_lod_anchor
	return get_viewport().get_camera_2d()


func _snap(value: float) -> float:
	return round(value)


func _snap_vec(value: Vector2) -> Vector2:
	return Vector2(round(value.x), round(value.y))


func _px_rect(center: Vector2, size: Vector2, color: Color) -> void:
	# Every primitive is made from the one-pixel grid. Larger visual masses are
	# integer clusters, never enlarged source pixels.
	var snapped_center := _snap_vec(center)
	var snapped_size := Vector2(maxf(1.0, round(size.x)), maxf(1.0, round(size.y)))
	draw_rect(Rect2(snapped_center - snapped_size * 0.5, snapped_size), color, true)


func _draw_pixel_disc(center: Vector2, radius: float, color: Color) -> void:
	var r := maxf(1.0, round(radius))
	var snapped_center := _snap_vec(center)
	var y := -r
	while y <= r:
		var half_width := floor(sqrt(maxf(0.0, r * r - y * y)))
		var x := -half_width
		while x <= half_width:
			_px_rect(snapped_center + Vector2(x, y), Vector2.ONE, color)
			x += 1.0
		y += 1.0
