@tool
extends Node2D

@export var emission_area: Vector2 = Vector2(32, 16)
@export_range(0, 160, 1) var ember_count: int = 16
@export_range(0.1, 80.0, 0.1) var spawn_rate: float = 16.0
@export_range(1.0, 8.0, 0.5) var pixel_size_min: float = 1.0
@export_range(1.0, 8.0, 0.5) var pixel_size_max: float = 2.0
@export_range(0.0, 160.0, 1.0) var rise_speed_min: float = 22.0
@export_range(0.0, 220.0, 1.0) var rise_speed_max: float = 54.0
@export_range(0.0, 80.0, 1.0) var horizontal_drift: float = 16.0
@export_range(0.05, 8.0, 0.05) var lifetime_min: float = 0.55
@export_range(0.05, 8.0, 0.05) var lifetime_max: float = 1.45
@export var glow_enabled: bool = true
@export_range(1.0, 24.0, 0.5) var glow_size: float = 5.0
@export var trail_enabled: bool = true
@export_range(0, 24, 1) var trail_length: int = 6
@export var color_palette: PackedColorArray = PackedColorArray([
	Color(1.0, 0.9, 0.38, 1.0),
	Color(1.0, 0.48, 0.12, 1.0),
	Color(0.9, 0.28, 0.08, 1.0),
	Color(0.45, 0.08, 0.04, 1.0),
])
@export var additive_blend: bool = true
@export var z_index_value: int = 0

var _rng := RandomNumberGenerator.new()
var _embers: Array = []
var _time: float = 0.0
var _additive_material: CanvasItemMaterial


func _ready() -> void:
	_rng.randomize()
	_ensure_material()
	_reset_embers()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	z_index = z_index_value
	_apply_material()
	_ensure_ember_count()
	_update_embers(delta)
	queue_redraw()


func apply_small_campfire_preset() -> void:
	emission_area = Vector2(34, 16)
	ember_count = 16
	spawn_rate = 18.0
	rise_speed_min = 24.0
	rise_speed_max = 58.0
	horizontal_drift = 18.0
	lifetime_min = 0.55
	lifetime_max = 1.35
	glow_enabled = true
	glow_size = 5.0
	trail_enabled = true
	trail_length = 6
	_reset_embers()


func apply_torch_preset() -> void:
	emission_area = Vector2(12, 8)
	ember_count = 7
	spawn_rate = 10.0
	rise_speed_min = 26.0
	rise_speed_max = 62.0
	horizontal_drift = 8.0
	lifetime_min = 0.35
	lifetime_max = 0.85
	glow_enabled = true
	glow_size = 4.0
	trail_enabled = true
	trail_length = 4
	_reset_embers()


func apply_forge_preset() -> void:
	emission_area = Vector2(52, 18)
	ember_count = 34
	spawn_rate = 38.0
	rise_speed_min = 38.0
	rise_speed_max = 110.0
	horizontal_drift = 30.0
	lifetime_min = 0.45
	lifetime_max = 1.6
	glow_enabled = true
	glow_size = 6.5
	trail_enabled = true
	trail_length = 8
	_reset_embers()


func apply_dying_embers_preset() -> void:
	emission_area = Vector2(38, 12)
	ember_count = 6
	spawn_rate = 3.0
	rise_speed_min = 10.0
	rise_speed_max = 28.0
	horizontal_drift = 10.0
	lifetime_min = 0.65
	lifetime_max = 1.7
	glow_enabled = true
	glow_size = 4.0
	trail_enabled = true
	trail_length = 4
	color_palette = PackedColorArray([
		Color(0.95, 0.32, 0.1, 1.0),
		Color(0.55, 0.11, 0.05, 1.0),
		Color(0.32, 0.04, 0.03, 1.0),
	])
	_reset_embers()


func _draw() -> void:
	for ember in _embers:
		if not bool(ember.get("alive", false)):
			continue
		var position_value: Vector2 = ember.get("position", Vector2.ZERO)
		var color_value: Color = ember.get("color", Color.WHITE)
		var age: float = float(ember.get("age", 0.0))
		var lifetime: float = maxf(float(ember.get("lifetime", 1.0)), 0.001)
		var life_ratio := clampf(age / lifetime, 0.0, 1.0)
		var alpha := 1.0 - life_ratio
		var pulse := (sin((_time * 10.0) + float(ember.get("phase", 0.0))) + 1.0) * 0.5
		var warm_color := color_value.lerp(_get_palette_color(0), pulse * 0.35)
		var draw_color := Color(warm_color.r, warm_color.g, warm_color.b, alpha)
		var pixel_size: float = float(ember.get("size", 1.0))

		if trail_enabled:
			_draw_trail(ember, pixel_size, draw_color)

		if glow_enabled:
			draw_circle(position_value, glow_size, Color(draw_color.r, draw_color.g, draw_color.b, draw_color.a * 0.16))

		var half_size := Vector2(pixel_size, pixel_size) * 0.5
		draw_rect(Rect2(position_value - half_size, Vector2(pixel_size, pixel_size)), draw_color, true)


func _draw_trail(ember: Dictionary, pixel_size: float, color_value: Color) -> void:
	var trail: Array = ember.get("trail", [])
	if trail.is_empty():
		return
	for index in range(trail.size()):
		var trail_position: Vector2 = trail[index]
		var fade := 1.0 - (float(index + 1) / float(maxi(trail.size(), 1)))
		var trail_alpha := color_value.a * 0.55 * fade
		var trail_size := maxf(1.0, pixel_size * fade)
		draw_rect(
			Rect2(trail_position - Vector2(trail_size, trail_size) * 0.5, Vector2(trail_size, trail_size)),
			Color(color_value.r, color_value.g, color_value.b, trail_alpha),
			true
		)


func _update_embers(delta: float) -> void:
	for ember in _embers:
		if not bool(ember.get("alive", false)):
			var wait_time: float = float(ember.get("wait_time", 0.0)) - delta
			if wait_time <= 0.0:
				_respawn_ember(ember)
			else:
				ember["wait_time"] = wait_time
			continue

		var age: float = float(ember.get("age", 0.0)) + delta
		var lifetime: float = float(ember.get("lifetime", 1.0))
		if age >= lifetime:
			ember["alive"] = false
			ember["wait_time"] = _next_spawn_delay()
			continue

		var position_value: Vector2 = ember.get("position", Vector2.ZERO)
		var velocity: Vector2 = ember.get("velocity", Vector2.UP)
		var phase: float = float(ember.get("phase", 0.0))
		velocity.x += sin((_time * 2.4) + phase) * horizontal_drift * delta
		position_value += velocity * delta

		var trail: Array = ember.get("trail", [])
		trail.push_front(position_value)
		while trail.size() > trail_length:
			trail.pop_back()

		ember["age"] = age
		ember["position"] = position_value
		ember["velocity"] = velocity
		ember["trail"] = trail


func _ensure_ember_count() -> void:
	while _embers.size() < ember_count:
		_embers.append(_make_ember())
	while _embers.size() > ember_count:
		_embers.pop_back()


func _reset_embers() -> void:
	_embers.clear()
	_ensure_ember_count()


func _make_ember() -> Dictionary:
	return {
		"alive": false,
		"wait_time": _rng.randf_range(0.0, maxf(_next_spawn_delay(), 0.02)),
		"position": Vector2.ZERO,
		"velocity": Vector2.UP,
		"age": 0.0,
		"lifetime": 1.0,
		"phase": _rng.randf_range(0.0, TAU),
		"color": _get_palette_color(_rng.randi_range(0, maxi(color_palette.size() - 1, 0))),
		"size": _rng.randf_range(pixel_size_min, pixel_size_max),
		"trail": [],
	}


func _respawn_ember(ember: Dictionary) -> void:
	var half_area := emission_area * 0.5
	var x := _rng.randf_range(-half_area.x, half_area.x)
	var y := _rng.randf_range(-half_area.y, half_area.y)
	ember["alive"] = true
	ember["wait_time"] = 0.0
	ember["position"] = Vector2(x, y)
	ember["velocity"] = Vector2(
		_rng.randf_range(-horizontal_drift * 0.35, horizontal_drift * 0.35),
		-_rng.randf_range(rise_speed_min, rise_speed_max)
	)
	ember["age"] = 0.0
	ember["lifetime"] = _rng.randf_range(lifetime_min, lifetime_max)
	ember["phase"] = _rng.randf_range(0.0, TAU)
	ember["color"] = _get_palette_color(_rng.randi_range(0, maxi(color_palette.size() - 1, 0)))
	ember["size"] = _rng.randf_range(pixel_size_min, pixel_size_max)
	ember["trail"] = []


func _next_spawn_delay() -> float:
	return 1.0 / maxf(spawn_rate, 0.001)


func _get_palette_color(index: int) -> Color:
	if color_palette.is_empty():
		return Color(1.0, 0.5, 0.1, 1.0)
	return color_palette[clampi(index, 0, color_palette.size() - 1)]


func _ensure_material() -> void:
	if _additive_material == null:
		_additive_material = CanvasItemMaterial.new()
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_apply_material()


func _apply_material() -> void:
	if additive_blend:
		material = _additive_material
	else:
		material = null
