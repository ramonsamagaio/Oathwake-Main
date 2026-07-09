@tool
extends Node2D

const TRAIL_STYLE_PIXEL := 0
const TRAIL_STYLE_SOFT_GLOW := 1
const TRAIL_STYLE_PIXEL_AND_SOFT_GLOW := 2

@export_group("Area")
@export var area_size: Vector2 = Vector2(256, 256)
@export_range(0, 128, 1) var firefly_count: int = 8
@export var debug_draw_area: bool = false

@export_group("Pixel Shape")
@export_range(1.0, 8.0, 0.5) var pixel_size_min: float = 1.0
@export_range(1.0, 8.0, 0.5) var pixel_size_max: float = 2.0

@export_group("Motion")
@export_range(0.0, 120.0, 1.0) var speed_min: float = 8.0
@export_range(0.0, 160.0, 1.0) var speed_max: float = 24.0
@export_range(0.0, 80.0, 1.0) var drift_strength: float = 18.0
@export_range(0.0, 8.0, 0.05) var direction_smoothness: float = 2.5

@export_group("Glow")
@export var glow_enabled: bool = true
@export_range(1.0, 48.0, 0.5) var glow_size: float = 7.0
@export_range(0.0, 1.0, 0.01) var glow_alpha: float = 0.18
@export var soft_glow_enabled: bool = true
@export_range(1, 12, 1) var soft_glow_steps: int = 5
@export_range(0.1, 4.0, 0.1) var soft_glow_falloff: float = 1.7
@export_range(0.0, 3.0, 0.01) var glow_intensity: float = 1.0

@export_group("Trail")
@export var trail_enabled: bool = true
@export_range(0, 96, 1) var trail_length: int = 18
@export_range(0.0, 1.0, 0.01) var trail_fade: float = 0.62
@export_enum("Pixel", "Soft Glow", "Pixel + Soft Glow") var trail_style: int = TRAIL_STYLE_PIXEL_AND_SOFT_GLOW
@export_range(0.2, 8.0, 0.1) var trail_pixel_scale: float = 1.0
@export_range(0.2, 24.0, 0.1) var trail_glow_size: float = 5.5
@export_range(0.0, 1.0, 0.01) var trail_glow_alpha: float = 0.16
@export_range(1, 12, 1) var trail_soft_steps: int = 4
@export_range(0.1, 4.0, 0.1) var trail_soft_falloff: float = 1.35

@export_group("Flicker")
@export_range(0.0, 1.0, 0.01) var alpha_min: float = 0.35
@export_range(0.0, 1.0, 0.01) var alpha_max: float = 0.9
@export_range(0.05, 24.0, 0.05) var flicker_speed: float = 2.0
@export_range(0.0, 1.0, 0.01) var flicker_randomness: float = 0.35

@export_group("Color Cycle")
@export var color_cycle_enabled: bool = true
@export_range(0.0, 48.0, 0.05) var color_cycle_speed: float = 5.0
@export_range(0.0, 1.0, 0.01) var color_cycle_randomness: float = 0.65
@export_range(0.0, 1.0, 0.01) var color_blend: float = 0.35

@export_group("Editable Palette")
@export var use_color_pickers: bool = true
@export_range(1, 6, 1) var active_palette_colors: int = 4
@export var palette_color_1: Color = Color(1.0, 0.95, 0.58, 1.0)
@export var palette_color_2: Color = Color(1.0, 0.78, 0.25, 1.0)
@export var palette_color_3: Color = Color(1.0, 0.58, 0.22, 1.0)
@export var palette_color_4: Color = Color(0.95, 0.68, 0.32, 1.0)
@export var palette_color_5: Color = Color(0.55, 0.78, 1.0, 1.0)
@export var palette_color_6: Color = Color(0.68, 0.46, 1.0, 1.0)

@export_group("Legacy / Advanced")
@export var color_palette: PackedColorArray = PackedColorArray([
	Color(1.0, 0.95, 0.58, 1.0),
	Color(1.0, 0.78, 0.25, 1.0),
	Color(1.0, 0.58, 0.22, 1.0),
	Color(0.95, 0.68, 0.32, 1.0),
])
@export var additive_blend: bool = true
@export var z_index_value: int = 0

var _rng := RandomNumberGenerator.new()
var _fireflies: Array = []
var _time: float = 0.0
var _additive_material: CanvasItemMaterial
var _last_palette_signature := ""


func _ready() -> void:
	_rng.randomize()
	_migrate_legacy_palette_to_color_pickers()
	_last_palette_signature = _palette_signature()
	_ensure_material()
	_reset_fireflies()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	z_index = z_index_value
	_apply_material()
	_ensure_firefly_count()
	_refresh_fireflies_if_palette_changed()
	_update_fireflies(delta)
	queue_redraw()


func apply_warm_fireflies_preset() -> void:
	area_size = Vector2(256, 256)
	firefly_count = 8
	speed_min = 6.0
	speed_max = 18.0
	drift_strength = 15.0
	glow_enabled = true
	soft_glow_enabled = true
	glow_size = 7.0
	glow_alpha = 0.18
	trail_enabled = true
	trail_length = 18
	trail_fade = 0.62
	trail_style = TRAIL_STYLE_PIXEL_AND_SOFT_GLOW
	active_palette_colors = 3
	palette_color_1 = Color(1.0, 0.95, 0.58, 1.0)
	palette_color_2 = Color(1.0, 0.76, 0.26, 1.0)
	palette_color_3 = Color(1.0, 0.55, 0.20, 1.0)
	alpha_min = 0.35
	alpha_max = 0.85
	flicker_speed = 1.8
	color_cycle_enabled = true
	color_cycle_speed = 4.0
	_mark_palette_dirty()
	_reset_fireflies()


func apply_magic_wisps_preset() -> void:
	area_size = Vector2(256, 256)
	firefly_count = 6
	speed_min = 4.0
	speed_max = 13.0
	drift_strength = 22.0
	glow_enabled = true
	soft_glow_enabled = true
	glow_size = 10.0
	glow_alpha = 0.2
	trail_enabled = true
	trail_length = 28
	trail_fade = 0.7
	trail_style = TRAIL_STYLE_SOFT_GLOW
	trail_glow_size = 8.0
	trail_glow_alpha = 0.2
	active_palette_colors = 3
	palette_color_1 = Color(0.55, 0.78, 1.0, 1.0)
	palette_color_2 = Color(0.68, 0.46, 1.0, 1.0)
	palette_color_3 = Color(1.0, 0.9, 0.55, 1.0)
	alpha_min = 0.28
	alpha_max = 0.78
	flicker_speed = 0.9
	color_cycle_enabled = true
	color_cycle_speed = 2.2
	_mark_palette_dirty()
	_reset_fireflies()


func apply_low_density_preset() -> void:
	firefly_count = 4
	speed_min = 4.0
	speed_max = 12.0
	trail_length = 12
	glow_size = 6.0
	_reset_fireflies()


func apply_dense_forest_preset() -> void:
	firefly_count = 16
	speed_min = 6.0
	speed_max = 20.0
	trail_length = 24
	glow_size = 8.0
	_reset_fireflies()


func apply_temple_dust_preset() -> void:
	area_size = Vector2(1120, 560)
	firefly_count = 28
	pixel_size_min = 1.0
	pixel_size_max = 1.5
	speed_min = 2.0
	speed_max = 7.0
	drift_strength = 10.0
	glow_enabled = true
	soft_glow_enabled = true
	glow_size = 5.0
	glow_alpha = 0.08
	trail_enabled = false
	trail_length = 8
	trail_fade = 0.25
	alpha_min = 0.08
	alpha_max = 0.32
	flicker_speed = 0.65
	color_cycle_enabled = false
	active_palette_colors = 4
	palette_color_1 = Color(0.55, 0.45, 0.75, 1.0)
	palette_color_2 = Color(0.38, 0.32, 0.52, 1.0)
	palette_color_3 = Color(0.80, 0.70, 0.52, 1.0)
	palette_color_4 = Color(0.22, 0.22, 0.28, 1.0)
	_mark_palette_dirty()
	_reset_fireflies()


func _draw() -> void:
	var bounds := _get_bounds()
	if debug_draw_area:
		draw_rect(bounds, Color(0.35, 0.75, 1.0, 0.35), false, 1.0)

	for firefly in _fireflies:
		var position_value: Vector2 = firefly.get("position", Vector2.ZERO)
		var pixel_size: float = float(firefly.get("size", 1.0))
		var phase: float = float(firefly.get("phase", 0.0))
		var local_flicker_speed := flicker_speed * (1.0 + float(firefly.get("seed", 0.0)) * flicker_randomness)
		var flicker := lerpf(alpha_min, alpha_max, (sin((_time * local_flicker_speed) + phase) + 1.0) * 0.5)
		var color_value := _get_firefly_color(firefly)
		var draw_color := Color(color_value.r, color_value.g, color_value.b, flicker * color_value.a)

		if trail_enabled:
			_draw_trail(firefly, pixel_size, draw_color)

		if glow_enabled and glow_size > 0.0 and glow_alpha > 0.0:
			var glow_color := Color(draw_color.r, draw_color.g, draw_color.b, draw_color.a * glow_alpha * glow_intensity)
			if soft_glow_enabled:
				_draw_soft_circle(position_value, glow_size, glow_color, soft_glow_steps, soft_glow_falloff)
			else:
				draw_circle(position_value, glow_size, glow_color)

		var half_size := Vector2(pixel_size, pixel_size) * 0.5
		draw_rect(Rect2(position_value - half_size, Vector2(pixel_size, pixel_size)), draw_color, true)


func _draw_trail(firefly: Dictionary, pixel_size: float, color_value: Color) -> void:
	var trail: Array = firefly.get("trail", [])
	if trail.is_empty():
		return
	for index in range(trail.size()):
		var trail_position: Vector2 = trail[index]
		var fade := 1.0 - (float(index + 1) / float(maxi(trail.size(), 1)))
		var trail_alpha := color_value.a * trail_fade * fade
		var trail_color := Color(color_value.r, color_value.g, color_value.b, trail_alpha)
		if trail_style == TRAIL_STYLE_PIXEL or trail_style == TRAIL_STYLE_PIXEL_AND_SOFT_GLOW:
			var trail_size := maxf(1.0, pixel_size * trail_pixel_scale * fade)
			draw_rect(Rect2(trail_position - Vector2(trail_size, trail_size) * 0.5, Vector2(trail_size, trail_size)), trail_color, true)
		if trail_style == TRAIL_STYLE_SOFT_GLOW or trail_style == TRAIL_STYLE_PIXEL_AND_SOFT_GLOW:
			var glow_radius := maxf(0.5, trail_glow_size * fade)
			var glow_color := Color(color_value.r, color_value.g, color_value.b, color_value.a * trail_glow_alpha * fade)
			_draw_soft_circle(trail_position, glow_radius, glow_color, trail_soft_steps, trail_soft_falloff)


func _draw_soft_circle(center: Vector2, radius: float, color_value: Color, steps: int, falloff: float) -> void:
	var safe_steps := maxi(1, steps)
	for step in range(safe_steps, 0, -1):
		var ratio := float(step) / float(safe_steps)
		var alpha_weight := pow(1.0 - ratio * 0.82, falloff)
		var ring_color := Color(color_value.r, color_value.g, color_value.b, color_value.a * alpha_weight)
		draw_circle(center, radius * ratio, ring_color)


func _update_fireflies(delta: float) -> void:
	var bounds := _get_bounds()
	for firefly in _fireflies:
		var position_value: Vector2 = firefly.get("position", Vector2.ZERO)
		var velocity: Vector2 = firefly.get("velocity", Vector2.RIGHT)
		var phase: float = float(firefly.get("phase", 0.0))
		var speed: float = float(firefly.get("speed", 10.0))

		var drift := Vector2(
			sin((_time * 0.9) + phase),
			cos((_time * 0.73) + (phase * 1.31))
		) * drift_strength
		var desired_velocity := (velocity + (drift * delta)).normalized() * speed
		velocity = velocity.lerp(desired_velocity, clampf(delta * direction_smoothness, 0.0, 1.0))
		position_value += velocity * delta

		if position_value.x < bounds.position.x or position_value.x > bounds.end.x:
			velocity.x *= -1.0
			position_value.x = clampf(position_value.x, bounds.position.x, bounds.end.x)
		if position_value.y < bounds.position.y or position_value.y > bounds.end.y:
			velocity.y *= -1.0
			position_value.y = clampf(position_value.y, bounds.position.y, bounds.end.y)

		var trail: Array = firefly.get("trail", [])
		trail.push_front(position_value)
		while trail.size() > trail_length:
			trail.pop_back()

		firefly["position"] = position_value
		firefly["velocity"] = velocity
		firefly["trail"] = trail


func _ensure_firefly_count() -> void:
	while _fireflies.size() < firefly_count:
		_fireflies.append(_make_firefly())
	while _fireflies.size() > firefly_count:
		_fireflies.pop_back()


func _reset_fireflies() -> void:
	_fireflies.clear()
	_ensure_firefly_count()


func _refresh_fireflies_if_palette_changed() -> void:
	var signature := _palette_signature()
	if signature == _last_palette_signature:
		return
	_last_palette_signature = signature
	for firefly in _fireflies:
		firefly["color"] = _get_palette_color(_rng.randi_range(0, max(_get_active_palette().size() - 1, 0)))
		firefly["palette_index"] = _rng.randi_range(0, max(_get_active_palette().size() - 1, 0))


func _make_firefly() -> Dictionary:
	var bounds := _get_bounds()
	var angle := _rng.randf_range(0.0, TAU)
	var palette := _get_active_palette()
	var palette_index := _rng.randi_range(0, max(palette.size() - 1, 0))
	var seed := _rng.randf()
	return {
		"position": Vector2(
			_rng.randf_range(bounds.position.x, bounds.end.x),
			_rng.randf_range(bounds.position.y, bounds.end.y)
		),
		"velocity": Vector2(cos(angle), sin(angle)) * _rng.randf_range(speed_min, speed_max),
		"speed": _rng.randf_range(speed_min, speed_max),
		"phase": _rng.randf_range(0.0, TAU),
		"color": _get_palette_color(palette_index),
		"palette_index": palette_index,
		"color_phase": _rng.randf_range(0.0, TAU),
		"seed": seed,
		"size": _rng.randf_range(pixel_size_min, pixel_size_max),
		"trail": [],
	}


func _get_bounds() -> Rect2:
	return Rect2(area_size * -0.5, area_size)


func _get_firefly_color(firefly: Dictionary) -> Color:
	var palette := _get_active_palette()
	if palette.is_empty():
		return Color(1.0, 0.86, 0.35, 1.0)
	if not color_cycle_enabled or is_zero_approx(color_cycle_speed):
		return firefly.get("color", palette[0])
	var base_index := float(int(firefly.get("palette_index", 0)))
	var seed := float(firefly.get("seed", 0.0))
	var local_speed := color_cycle_speed * (1.0 + seed * color_cycle_randomness)
	var phase := float(firefly.get("color_phase", 0.0))
	var animated_index := base_index + (_time * local_speed) + phase
	return _sample_palette(animated_index, color_blend)


func _sample_palette(animated_index: float, blend_amount: float) -> Color:
	var palette := _get_active_palette()
	if palette.is_empty():
		return Color(1.0, 0.86, 0.35, 1.0)
	var count := palette.size()
	var wrapped := fposmod(animated_index, float(count))
	var index_a := int(floor(wrapped)) % count
	var index_b := (index_a + 1) % count
	var t := fract(wrapped) * clampf(blend_amount, 0.0, 1.0)
	return palette[index_a].lerp(palette[index_b], t)


func _get_palette_color(index: int) -> Color:
	var palette := _get_active_palette()
	if palette.is_empty():
		return Color(1.0, 0.86, 0.35, 1.0)
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
		_color_close(palette[0], Color(1.0, 0.95, 0.58, 1.0))
		and _color_close(palette[1], Color(1.0, 0.78, 0.25, 1.0))
		and _color_close(palette[2], Color(1.0, 0.58, 0.22, 1.0))
		and _color_close(palette[3], Color(0.95, 0.68, 0.32, 1.0))
	)


func _picker_palette_matches_default() -> bool:
	return (
		active_palette_colors == 4
		and _color_close(palette_color_1, Color(1.0, 0.95, 0.58, 1.0))
		and _color_close(palette_color_2, Color(1.0, 0.78, 0.25, 1.0))
		and _color_close(palette_color_3, Color(1.0, 0.58, 0.22, 1.0))
		and _color_close(palette_color_4, Color(0.95, 0.68, 0.32, 1.0))
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
