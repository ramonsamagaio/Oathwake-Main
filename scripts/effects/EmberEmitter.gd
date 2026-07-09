@tool
extends Node2D

@export_group("Emission")
@export var emission_area: Vector2 = Vector2(32, 16)
@export_range(0, 160, 1) var ember_count: int = 16
@export_range(0.1, 80.0, 0.1) var spawn_rate: float = 16.0

@export_group("Pixel Shape")
@export_range(1.0, 8.0, 0.5) var pixel_size_min: float = 1.0
@export_range(1.0, 8.0, 0.5) var pixel_size_max: float = 2.0

@export_group("Motion")
@export_range(0.0, 160.0, 1.0) var rise_speed_min: float = 22.0
@export_range(0.0, 220.0, 1.0) var rise_speed_max: float = 54.0
@export_range(0.0, 80.0, 1.0) var horizontal_drift: float = 16.0
@export_range(0.05, 8.0, 0.05) var lifetime_min: float = 0.55
@export_range(0.05, 8.0, 0.05) var lifetime_max: float = 1.45

@export_group("Glow / Trail")
@export var glow_enabled: bool = true
@export_range(1.0, 24.0, 0.5) var glow_size: float = 5.0
@export_range(0.0, 1.0, 0.01) var glow_alpha: float = 0.16
@export var trail_enabled: bool = true
@export_range(0, 24, 1) var trail_length: int = 6
@export_range(0.0, 1.0, 0.01) var trail_alpha: float = 0.55

@export_group("Editable Palette")
@export var use_color_pickers: bool = true
@export_range(1, 6, 1) var active_palette_colors: int = 4
@export var palette_color_1: Color = Color(1.0, 0.9, 0.38, 1.0)
@export var palette_color_2: Color = Color(1.0, 0.48, 0.12, 1.0)
@export var palette_color_3: Color = Color(0.9, 0.28, 0.08, 1.0)
@export var palette_color_4: Color = Color(0.45, 0.08, 0.04, 1.0)
@export var palette_color_5: Color = Color(0.85, 0.2, 1.0, 1.0)
@export var palette_color_6: Color = Color(0.35, 0.08, 0.75, 1.0)

@export_group("Legacy / Advanced")
@export var color_palette: PackedColorArray = PackedColorArray([
	Color(1.0, 0.9, 0.38, 1.0),
	Color(1.0, 0.48, 0.12, 1.0),
	Color(0.9, 0.28, 0.08, 1.0),
	Color(0.45, 0.08, 0.04, 1.0),
])
@export var additive_blend: bool = true
@export var z_index_value: int = 0
@export var debug_draw_emission_area: bool = false

var _rng := RandomNumberGenerator.new()
var _embers: Array = []
var _time: float = 0.0
var _additive_material: CanvasItemMaterial
var _last_palette_signature := ""


func _ready() -> void:
	_rng.randomize()
	_migrate_legacy_palette_to_color_pickers()
	_last_palette_signature = _palette_signature()
	_ensure_material()
	_reset_embers()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	z_index = z_index_value
	_apply_material()
	_ensure_ember_count()
	_refresh_embers_if_palette_changed()
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
	glow_alpha = 0.16
	trail_enabled = true
	trail_length = 6
	trail_alpha = 0.55
	active_palette_colors = 4
	palette_color_1 = Color(1.0, 0.9, 0.38, 1.0)
	palette_color_2 = Color(1.0, 0.48, 0.12, 1.0)
	palette_color_3 = Color(0.9, 0.28, 0.08, 1.0)
	palette_color_4 = Color(0.45, 0.08, 0.04, 1.0)
	_mark_palette_dirty()
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
	glow_alpha = 0.14
	trail_enabled = true
	trail_length = 4
	trail_alpha = 0.45
	active_palette_colors = 3
	palette_color_1 = Color(1.0, 0.85, 0.32, 1.0)
	palette_color_2 = Color(1.0, 0.46, 0.12, 1.0)
	palette_color_3 = Color(0.74, 0.15, 0.06, 1.0)
	_mark_palette_dirty()
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
	glow_alpha = 0.18
	trail_enabled = true
	trail_length = 8
	trail_alpha = 0.62
	active_palette_colors = 4
	palette_color_1 = Color(1.0, 0.95, 0.44, 1.0)
	palette_color_2 = Color(1.0, 0.32, 0.08, 1.0)
	palette_color_3 = Color(0.85, 0.08, 0.03, 1.0)
	palette_color_4 = Color(0.25, 0.03, 0.02, 1.0)
	_mark_palette_dirty()
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
	glow_alpha = 0.12
	trail_enabled = true
	trail_length = 4
	trail_alpha = 0.35
	active_palette_colors = 3
	palette_color_1 = Color(0.95, 0.32, 0.1, 1.0)
	palette_color_2 = Color(0.55, 0.11, 0.05, 1.0)
	palette_color_3 = Color(0.32, 0.04, 0.03, 1.0)
	color_palette = PackedColorArray([
		palette_color_1,
		palette_color_2,
		palette_color_3,
	])
	_mark_palette_dirty()
	_reset_embers()


func apply_purple_fire_preset() -> void:
	emission_area = Vector2(32, 16)
	ember_count = 18
	spawn_rate = 17.0
	rise_speed_min = 18.0
	rise_speed_max = 48.0
	horizontal_drift = 14.0
	lifetime_min = 0.55
	lifetime_max = 1.35
	glow_enabled = true
	glow_size = 5.5
	glow_alpha = 0.18
	trail_enabled = true
	trail_length = 6
	trail_alpha = 0.52
	active_palette_colors = 4
	palette_color_1 = Color(1.0, 0.52, 0.95, 1.0)
	palette_color_2 = Color(0.83, 0.22, 0.92, 1.0)
	palette_color_3 = Color(0.52, 0.15, 0.84, 1.0)
	palette_color_4 = Color(1.0, 0.76, 0.35, 1.0)
	color_palette = PackedColorArray([
		palette_color_1,
		palette_color_2,
		palette_color_3,
		palette_color_4,
	])
	_mark_palette_dirty()
	_reset_embers()


func _draw() -> void:
	if debug_draw_emission_area:
		draw_rect(Rect2(emission_area * -0.5, emission_area), Color(0.55, 0.25, 1.0, 0.35), false, 1.0)

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

		if glow_enabled and glow_size > 0.0 and glow_alpha > 0.0:
			draw_circle(position_value, glow_size, Color(draw_color.r, draw_color.g, draw_color.b, draw_color.a * glow_alpha))

		var half_size := Vector2(pixel_size, pixel_size) * 0.5
		draw_rect(Rect2(position_value - half_size, Vector2(pixel_size, pixel_size)), draw_color, true)


func _draw_trail(ember: Dictionary, pixel_size: float, color_value: Color) -> void:
	var trail: Array = ember.get("trail", [])
	if trail.is_empty():
		return
	for index in range(trail.size()):
		var trail_position: Vector2 = trail[index]
		var fade := 1.0 - (float(index + 1) / float(maxi(trail.size(), 1)))
		var current_alpha := color_value.a * trail_alpha * fade
		var trail_size := maxf(1.0, pixel_size * fade)
		draw_rect(
			Rect2(trail_position - Vector2(trail_size, trail_size) * 0.5, Vector2(trail_size, trail_size)),
			Color(color_value.r, color_value.g, color_value.b, current_alpha),
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


func _refresh_embers_if_palette_changed() -> void:
	var signature := _palette_signature()
	if signature == _last_palette_signature:
		return
	_last_palette_signature = signature
	for ember in _embers:
		ember["color"] = _get_palette_color(_rng.randi_range(0, max(_get_active_palette().size() - 1, 0)))


func _make_ember() -> Dictionary:
	return {
		"alive": false,
		"wait_time": _rng.randf_range(0.0, maxf(_next_spawn_delay(), 0.02)),
		"position": Vector2.ZERO,
		"velocity": Vector2.UP,
		"age": 0.0,
		"lifetime": 1.0,
		"phase": _rng.randf_range(0.0, TAU),
		"color": _get_palette_color(_rng.randi_range(0, max(_get_active_palette().size() - 1, 0))),
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
	ember["color"] = _get_palette_color(_rng.randi_range(0, max(_get_active_palette().size() - 1, 0)))
	ember["size"] = _rng.randf_range(pixel_size_min, pixel_size_max)
	ember["trail"] = []


func _next_spawn_delay() -> float:
	return 1.0 / maxf(spawn_rate, 0.001)


func _get_palette_color(index: int) -> Color:
	var palette := _get_active_palette()
	if palette.is_empty():
		return Color(1.0, 0.5, 0.1, 1.0)
	return palette[clampi(index, 0, palette.size() - 1)]


func _get_active_palette() -> Array[Color]:
	var palette: Array[Color] = []
	if use_color_pickers:
		var colors := [
			palette_color_1,
			palette_color_2,
			palette_color_3,
			palette_color_4,
			palette_color_5,
			palette_color_6,
		]
		for index in range(clampi(active_palette_colors, 1, colors.size())):
			palette.append(colors[index])
	else:
		for color in color_palette:
			palette.append(color)
	return palette


func _migrate_legacy_palette_to_color_pickers() -> void:
	if not use_color_pickers:
		return
	if color_palette.is_empty():
		return
	if _palette_matches_default(color_palette):
		return
	if not _picker_palette_matches_default():
		return
	_copy_legacy_palette_to_pickers()


func _copy_legacy_palette_to_pickers() -> void:
	active_palette_colors = clampi(color_palette.size(), 1, 6)
	if color_palette.size() > 0:
		palette_color_1 = color_palette[0]
	if color_palette.size() > 1:
		palette_color_2 = color_palette[1]
	if color_palette.size() > 2:
		palette_color_3 = color_palette[2]
	if color_palette.size() > 3:
		palette_color_4 = color_palette[3]
	if color_palette.size() > 4:
		palette_color_5 = color_palette[4]
	if color_palette.size() > 5:
		palette_color_6 = color_palette[5]


func _palette_matches_default(palette: PackedColorArray) -> bool:
	if palette.size() != 4:
		return false
	return (
		_color_close(palette[0], Color(1.0, 0.9, 0.38, 1.0))
		and _color_close(palette[1], Color(1.0, 0.48, 0.12, 1.0))
		and _color_close(palette[2], Color(0.9, 0.28, 0.08, 1.0))
		and _color_close(palette[3], Color(0.45, 0.08, 0.04, 1.0))
	)


func _picker_palette_matches_default() -> bool:
	return (
		active_palette_colors == 4
		and _color_close(palette_color_1, Color(1.0, 0.9, 0.38, 1.0))
		and _color_close(palette_color_2, Color(1.0, 0.48, 0.12, 1.0))
		and _color_close(palette_color_3, Color(0.9, 0.28, 0.08, 1.0))
		and _color_close(palette_color_4, Color(0.45, 0.08, 0.04, 1.0))
	)


func _color_close(a: Color, b: Color) -> bool:
	return (
		is_equal_approx(a.r, b.r)
		and is_equal_approx(a.g, b.g)
		and is_equal_approx(a.b, b.b)
		and is_equal_approx(a.a, b.a)
	)


func _palette_signature() -> String:
	var parts: Array[String] = []
	for color in _get_active_palette():
		parts.append("%0.3f,%0.3f,%0.3f,%0.3f" % [color.r, color.g, color.b, color.a])
	return "|".join(parts)


func _mark_palette_dirty() -> void:
	_last_palette_signature = ""


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
