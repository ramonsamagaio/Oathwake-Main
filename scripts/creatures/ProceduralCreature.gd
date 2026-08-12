class_name ProceduralCreature
extends Node2D

signal parameter_changed(key: StringName, value: Variant)
signal preset_applied
signal simulation_state_changed(active: bool)

@export_group("Identity")
@export var creature_id: StringName = &"procedural_creature"
@export var random_seed: int = 1337

@export_group("Simulation")
@export_range(5.0, 120.0, 1.0) var simulation_hz: float = 60.0
@export_range(1, 8, 1) var pixel_size: int = 2
@export var simulation_enabled := true
@export var quantize_motion := true
@export_range(0.1, 4.0, 0.05) var global_scale_factor := 1.0
@export_range(0.0, 4.0, 0.05) var motion_intensity := 1.0

@export_group("LOD / Budget")
@export var lod_enabled := true
@export_range(64.0, 4096.0, 16.0) var full_rate_distance := 640.0
@export_range(64.0, 8192.0, 16.0) var reduced_rate_distance := 1200.0
@export_range(1.0, 60.0, 1.0) var reduced_simulation_hz := 20.0
@export var pause_when_offscreen := true
@export_range(0.1, 5.0, 0.1) var offscreen_grace_seconds := 0.5

@export_group("Palette")
@export var primary_color := Color("6f9f57")
@export var secondary_color := Color("45653d")
@export var accent_color := Color("c6d98b")
@export var shadow_color := Color("25352d")

var velocity := Vector2.ZERO
var external_force := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _sim_accumulator := 0.0
var _offscreen_time := 0.0
var _manual_lod_anchor: Node2D


func _ready() -> void:
	_rng.seed = random_seed
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
	velocity += external_force * delta
	external_force = Vector2.ZERO
	position += velocity * delta
	velocity *= pow(0.88, delta * 60.0)
	if quantize_motion:
		position = _snap_vec(position)
	_simulate_creature(delta)


func _simulate_creature(_delta: float) -> void:
	pass


func apply_impulse(impulse: Vector2) -> void:
	velocity += impulse * motion_intensity


func add_force(force: Vector2) -> void:
	external_force += force * motion_intensity


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


func set_lod_anchor(anchor: Node2D) -> void:
	_manual_lod_anchor = anchor


func set_parameter(key: StringName, value: Variant) -> bool:
	if key == &"pixel_size":
		pixel_size = clampi(int(value), 1, 8)
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
	parameter_changed.emit(key, value)
	queue_redraw()
	return true


func _set_creature_parameter(_key: StringName, _value: Variant) -> bool:
	return false


func get_parameter(key: StringName) -> Variant:
	if key == &"pixel_size":
		return pixel_size
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
	return [
		{"key": &"global_scale_factor", "label": "Scale", "type": "float", "min": 0.35, "max": 2.5, "step": 0.05},
		{"key": &"motion_intensity", "label": "Motion", "type": "float", "min": 0.0, "max": 3.0, "step": 0.05},
		{"key": &"pixel_size", "label": "Pixel Size", "type": "int", "min": 1, "max": 6, "step": 1},
	] + _get_creature_editor_schema()


func _get_creature_editor_schema() -> Array[Dictionary]:
	return []


func make_preset() -> Dictionary:
	var params := {}
	for descriptor in get_editor_schema():
		var key: StringName = descriptor.get("key", &"")
		if key != &"":
			params[String(key)] = get_parameter(key)
	return {
		"version": 1,
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
	var camera := get_viewport().get_camera_2d()
	return camera


func _snap(value: float) -> float:
	var step := maxf(1.0, float(pixel_size))
	return round(value / step) * step


func _snap_vec(value: Vector2) -> Vector2:
	return Vector2(_snap(value.x), _snap(value.y))


func _px_rect(center: Vector2, size: Vector2, color: Color) -> void:
	var snapped_center := _snap_vec(center)
	var snapped_size := Vector2(maxf(pixel_size, _snap(size.x)), maxf(pixel_size, _snap(size.y)))
	draw_rect(Rect2(snapped_center - snapped_size * 0.5, snapped_size), color, true)


func _draw_pixel_disc(center: Vector2, radius: float, color: Color) -> void:
	var r := maxf(float(pixel_size), radius)
	var step := maxf(1.0, float(pixel_size))
	var y := -r
	while y <= r:
		var half_width := sqrt(maxf(0.0, r * r - y * y))
		var x := -half_width
		while x <= half_width:
			_px_rect(center + Vector2(x, y), Vector2(step, step), color)
			x += step
		y += step
