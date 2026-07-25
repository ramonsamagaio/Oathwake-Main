extends Node2D

var _config: Dictionary = {}
var _wind_source: Node
var _anchor: Node2D
var _particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _night_strength := 0.0
var _area_size := Vector2(900.0, 520.0)


func configure(config: Dictionary, wind_source: Node) -> void:
	_config = config.duplicate(true)
	_wind_source = wind_source
	_area_size = _vector_from_value(_config.get("area_size", {}), Vector2(900.0, 520.0))
	_area_size.x = maxf(_area_size.x, 64.0)
	_area_size.y = maxf(_area_size.y, 64.0)
	_reset_particles()


func _ready() -> void:
	_rng.randomize()
	z_as_relative = false
	z_index = int(_config.get("z_index", 3600))
	_anchor = get_tree().get_first_node_in_group("player") as Node2D
	if _particles.is_empty():
		_reset_particles()
	set_process(bool(_config.get("enabled", true)))


func _process(delta: float) -> void:
	_time += delta
	if _anchor == null or not is_instance_valid(_anchor):
		_anchor = get_tree().get_first_node_in_group("player") as Node2D
	if _anchor != null:
		global_position = _anchor.global_position.round()
	_update_night_strength()
	_update_particles(delta)
	queue_redraw()


func _draw() -> void:
	if not bool(_config.get("enabled", true)):
		return
	var day_alpha := clampf(float(_config.get("day_alpha", 0.52)), 0.0, 1.0)
	var night_alpha := clampf(float(_config.get("night_alpha", 0.86)), 0.0, 1.0)
	for particle in _particles:
		var kind := str(particle.get("kind", "pollen"))
		var position_value: Vector2 = particle.get("position", Vector2.ZERO)
		var size_value := float(particle.get("size", 1.0))
		var phase := float(particle.get("phase", 0.0))
		var alpha := 0.0
		var color := Color.WHITE
		match kind:
			"firefly":
				alpha = night_alpha * _night_strength * (0.52 + sin((_time * 2.1) + phase) * 0.30)
				color = _color_from_value(_config.get("firefly_color", "#FFE286FF"), Color(1.0, 0.89, 0.52, 1.0))
				if alpha > 0.01:
					_draw_soft_pixel(position_value, size_value, Color(color.r, color.g, color.b, alpha))
			"leaf":
				alpha = lerpf(day_alpha, night_alpha * 0.42, _night_strength) * 0.52
				color = _color_from_value(_config.get("leaf_color", "#758B4DFF"), Color(0.46, 0.55, 0.30, 1.0))
				var leaf_size := Vector2(maxf(size_value * 2.0, 2.0), maxf(size_value, 1.0))
				draw_rect(Rect2(position_value - leaf_size * 0.5, leaf_size), Color(color.r, color.g, color.b, alpha), true)
			_:
				alpha = lerpf(day_alpha, night_alpha * 0.26, _night_strength) * (0.55 + sin((_time * 0.8) + phase) * 0.20)
				color = _color_from_value(_config.get("pollen_color", "#D8D19AFF"), Color(0.85, 0.82, 0.60, 1.0))
				var half := Vector2.ONE * maxf(size_value, 1.0) * 0.5
				draw_rect(Rect2(position_value - half, half * 2.0), Color(color.r, color.g, color.b, alpha), true)


func _draw_soft_pixel(position_value: Vector2, size_value: float, color: Color) -> void:
	var glow_radius := maxf(size_value * 3.2, 3.0)
	for step in range(4, 0, -1):
		var ratio := float(step) / 4.0
		var glow_alpha := color.a * 0.055 * ratio
		draw_circle(position_value, glow_radius * ratio, Color(color.r, color.g, color.b, glow_alpha))
	var pixel_size := maxf(size_value, 1.0)
	var half := Vector2.ONE * pixel_size * 0.5
	draw_rect(Rect2(position_value - half, half * 2.0), color, true)


func _reset_particles() -> void:
	_particles.clear()
	_add_particles("pollen", maxi(int(_config.get("pollen_count", 22)), 0), 1.0, 1.5)
	_add_particles("firefly", maxi(int(_config.get("firefly_count", 8)), 0), 1.0, 2.0)
	_add_particles("leaf", maxi(int(_config.get("leaf_count", 5)), 0), 1.0, 2.0)


func _add_particles(kind: String, count: int, min_size: float, max_size: float) -> void:
	for _index in range(count):
		_particles.append({
			"kind": kind,
			"position": Vector2(
				_rng.randf_range(-_area_size.x * 0.5, _area_size.x * 0.5),
				_rng.randf_range(-_area_size.y * 0.5, _area_size.y * 0.5)
			),
			"size": _rng.randf_range(min_size, max_size),
			"phase": _rng.randf_range(0.0, TAU),
			"seed": _rng.randf_range(0.65, 1.35),
		})


func _update_particles(delta: float) -> void:
	var wind := Vector2(10.0, 1.0)
	if _wind_source != null and is_instance_valid(_wind_source) and _wind_source.has_method("get_wind_vector"):
		wind = _wind_source.call("get_wind_vector")
	for index in range(_particles.size()):
		var particle := _particles[index]
		var kind := str(particle.get("kind", "pollen"))
		var seed := float(particle.get("seed", 1.0))
		var phase := float(particle.get("phase", 0.0))
		var position_value: Vector2 = particle.get("position", Vector2.ZERO)
		var drift := Vector2(sin((_time * 0.75 * seed) + phase), cos((_time * 0.52 * seed) + phase))
		match kind:
			"firefly":
				position_value += (drift * 7.5 + wind * 0.05) * delta
			"leaf":
				position_value += (wind * (0.55 + seed * 0.18) + Vector2(0.0, 5.0) + drift * 2.0) * delta
			_:
				position_value += (wind * 0.12 + drift * 3.2 + Vector2(0.0, -0.8)) * delta
		particle["position"] = _wrap_position(position_value)
		_particles[index] = particle


func _wrap_position(value: Vector2) -> Vector2:
	var half := _area_size * 0.5
	if value.x < -half.x:
		value.x += _area_size.x
	elif value.x > half.x:
		value.x -= _area_size.x
	if value.y < -half.y:
		value.y += _area_size.y
	elif value.y > half.y:
		value.y -= _area_size.y
	return value


func _update_night_strength() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if cycle != null and cycle.has_method("get_night_strength"):
		_night_strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	else:
		_night_strength = 0.0


func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)
