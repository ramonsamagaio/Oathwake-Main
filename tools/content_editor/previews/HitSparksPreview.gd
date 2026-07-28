class_name HitSparksPreview
extends Control

var _profile: Dictionary = {}
var _particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _replay_elapsed := 0.0
var _replay_delay := 0.25


func _ready() -> void:
	custom_minimum_size = Vector2(360.0, 220.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	set_process(true)
	restart()


func set_profile(profile: Dictionary) -> void:
	_profile = profile.duplicate(true)
	restart()


func restart() -> void:
	_particles.clear()
	_replay_elapsed = 0.0
	var count := maxi(int(_profile.get("pixel_count", 18)), 0)
	var lifetime := maxf(float(_profile.get("lifetime", 0.38)), 0.01)
	var speed_min := float(_profile.get("speed_min", 42.0))
	var speed_max := maxf(float(_profile.get("speed_max", 98.0)), speed_min)
	var distance := maxf(float(_profile.get("distance", 26.0)), 0.0)
	var jitter_radius := maxf(float(_profile.get("jitter_radius", 5.0)), 0.0)
	var horizontal_bias := float(_profile.get("horizontal_bias", 0.85))
	var upward_bias := float(_profile.get("upward_bias", 1.0))
	var gravity := float(_profile.get("gravity", 430.0))
	var size_min := maxf(float(_profile.get("size_min", 1.0)), 0.5)
	var size_max := maxf(float(_profile.get("size_max", 2.0)), size_min)
	var fade_out_time := clampf(float(_profile.get("fade_out_time", 0.26)), 0.0, lifetime)
	var colors := _parse_colors(_profile.get("colors", []))
	var distance_scale := distance / maxf(speed_max * lifetime, 0.01)
	var origin := Vector2(size.x * 0.5, size.y * 0.58)
	for _index in range(count):
		var particle_lifetime := lifetime * _rng.randf_range(0.78, 1.18)
		_particles.append({
			"position": origin + Vector2(_rng.randf_range(-jitter_radius, jitter_radius), _rng.randf_range(-jitter_radius, jitter_radius)),
			"velocity": Vector2(
				_rng.randf_range(-speed_max * horizontal_bias, speed_max * horizontal_bias) * distance_scale,
				-_rng.randf_range(speed_min * upward_bias, speed_max * upward_bias) * distance_scale
			),
			"age": 0.0,
			"lifetime": particle_lifetime,
			"fade_out_time": minf(fade_out_time, particle_lifetime),
			"gravity": gravity,
			"size": _rng.randf_range(size_min, size_max),
			"color": colors[_rng.randi_range(0, colors.size() - 1)],
		})
	queue_redraw()


func _process(delta: float) -> void:
	var alive := false
	for index in range(_particles.size()):
		var particle := _particles[index]
		var age := float(particle.get("age", 0.0)) + delta
		particle["age"] = age
		var lifetime := float(particle.get("lifetime", 0.01))
		if age < lifetime:
			alive = true
			var velocity: Vector2 = particle.get("velocity", Vector2.ZERO)
			velocity.y += float(particle.get("gravity", 0.0)) * delta
			particle["velocity"] = velocity
			var current_position: Vector2 = particle.get("position", Vector2.ZERO)
			particle["position"] = current_position + velocity * delta
		_particles[index] = particle
	if not alive:
		_replay_elapsed += delta
		if _replay_elapsed >= _replay_delay:
			restart()
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.055, 0.06, 0.07, 1.0), true)
	var ground_y := size.y * 0.72
	draw_rect(Rect2(0.0, ground_y, size.x, size.y - ground_y), Color(0.085, 0.095, 0.075, 1.0), true)
	draw_line(Vector2(0.0, ground_y), Vector2(size.x, ground_y), Color(0.18, 0.20, 0.16, 1.0), 1.0)
	var origin := Vector2(size.x * 0.5, size.y * 0.58)
	draw_circle(origin, 18.0, Color(0.16, 0.18, 0.20, 1.0))
	draw_circle(origin, 11.0, Color(0.26, 0.29, 0.31, 1.0))
	for particle in _particles:
		var age := float(particle.get("age", 0.0))
		var lifetime := float(particle.get("lifetime", 0.01))
		if age >= lifetime:
			continue
		var color: Color = particle.get("color", Color.WHITE)
		var fade_out_time := maxf(float(particle.get("fade_out_time", 0.0)), 0.001)
		var fade_start := maxf(lifetime - fade_out_time, 0.0)
		if age > fade_start:
			color.a *= 1.0 - clampf((age - fade_start) / fade_out_time, 0.0, 1.0)
		var pixel_size := maxf(float(particle.get("size", 1.0)), 1.0)
		var position: Vector2 = particle.get("position", Vector2.ZERO)
		draw_rect(Rect2(position - Vector2.ONE * pixel_size * 0.5, Vector2.ONE * pixel_size), color, true)


func _parse_colors(raw_colors: Variant) -> Array[Color]:
	var parsed: Array[Color] = []
	if raw_colors is Array:
		for value in raw_colors as Array:
			if value is Color:
				parsed.append(value)
			else:
				var text := str(value)
				if not text.is_empty():
					parsed.append(Color.from_string(text, Color.WHITE))
	if parsed.is_empty():
		parsed = [Color("#BB2D45"), Color("#D87A3C"), Color("#DB9B42"), Color("#17191B"), Color("#26292D")]
	return parsed
