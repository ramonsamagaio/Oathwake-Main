class_name RomesteadWeatherVisuals2D
extends Node2D

const CLOUD_TEXTURE_PATH := "res://assets/world_lab/romestead_editable/cloud_layer.svg"
const PARTICLE_POOL_SIZE := 520

var weather_state := {
	"rain": 0.0,
	"snow": 0.0,
	"embers": 0.0,
	"clouds": 0.0,
	"wind_strength": 0.15,
	"wind_direction": Vector2(1.0, 0.15),
	"lightning": 0.0,
}
var _particles: Array[Dictionary] = []
var _cloud_sprites: Array[Sprite2D] = []
var _rng := RandomNumberGenerator.new()
var _cloud_texture: Texture2D


func _ready() -> void:
	_cloud_texture = _load_svg_texture(CLOUD_TEXTURE_PATH)
	_rng.seed = 819271
	for index in range(PARTICLE_POOL_SIZE):
		_particles.append({
			"position": Vector2(_rng.randf_range(0.0, 1600.0), _rng.randf_range(0.0, 900.0)),
			"speed": _rng.randf_range(0.72, 1.35),
			"phase": _rng.randf(),
			"size": _rng.randf_range(0.75, 1.4),
		})
	_create_clouds()
	_refresh_processing_state()


func apply_weather_state(state: Dictionary) -> void:
	for key in weather_state.keys():
		if state.has(key):
			weather_state[key] = state[key]
	_refresh_processing_state()


func _process(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var rain: float = float(weather_state["rain"])
	var snow: float = float(weather_state["snow"])
	var embers: float = float(weather_state["embers"])
	var active_count := mini(PARTICLE_POOL_SIZE, ceili(maxf(rain, maxf(snow, embers)) * PARTICLE_POOL_SIZE))
	var wind_direction: Vector2 = weather_state["wind_direction"]
	var wind_strength: float = float(weather_state["wind_strength"])

	for index in range(active_count):
		var particle: Dictionary = _particles[index]
		var position: Vector2 = particle["position"]
		var speed: float = particle["speed"]
		if rain >= snow and rain >= embers:
			position += Vector2(130.0 + wind_direction.x * wind_strength * 190.0, 690.0) * speed * delta
		elif snow >= embers:
			var phase: float = float(particle["phase"]) * TAU
			position += Vector2(wind_direction.x * wind_strength * 90.0 + sin(Time.get_ticks_msec() * 0.0015 + phase) * 24.0, 72.0) * speed * delta
		else:
			position += Vector2(wind_direction.x * wind_strength * 55.0 + sin(Time.get_ticks_msec() * 0.002 + index) * 18.0, -82.0) * speed * delta

		if position.x > viewport_size.x + 30.0:
			position.x = -30.0
		elif position.x < -30.0:
			position.x = viewport_size.x + 30.0
		if position.y > viewport_size.y + 30.0:
			position.y = -30.0
		elif position.y < -30.0:
			position.y = viewport_size.y + 30.0
		particle["position"] = position
		_particles[index] = particle

	_update_clouds(delta, viewport_size)
	queue_redraw()


func _refresh_processing_state() -> void:
	var precipitation := maxf(float(weather_state["rain"]), maxf(float(weather_state["snow"]), float(weather_state["embers"])))
	var active := precipitation > 0.001 or float(weather_state["clouds"]) > 0.10 or float(weather_state["lightning"]) > 0.001
	set_process(active)
	if not active:
		_update_clouds(0.0, get_viewport_rect().size)
		queue_redraw()


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	var rain: float = float(weather_state["rain"])
	var snow: float = float(weather_state["snow"])
	var embers: float = float(weather_state["embers"])
	var lightning: float = float(weather_state["lightning"])
	var active_count := mini(PARTICLE_POOL_SIZE, ceili(maxf(rain, maxf(snow, embers)) * PARTICLE_POOL_SIZE))
	for index in range(active_count):
		var particle: Dictionary = _particles[index]
		var position: Vector2 = particle["position"]
		var size: float = particle["size"]
		if rain >= snow and rain >= embers:
			draw_line(position, position + Vector2(-5.0, -18.0) * size, Color(0.63, 0.79, 0.90, 0.72 * rain), maxf(1.0, size))
		elif snow >= embers:
			draw_circle(position, 1.8 * size, Color(0.91, 0.96, 0.98, 0.88 * snow))
		else:
			draw_rect(Rect2(position - Vector2.ONE * size, Vector2.ONE * 2.0 * size), Color(1.0, 0.49, 0.18, 0.80 * embers))
	if lightning > 0.001:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.78, 0.87, 1.0, lightning * 0.52))


func _create_clouds() -> void:
	for index in range(5):
		var cloud := Sprite2D.new()
		cloud.texture = _cloud_texture
		cloud.centered = true
		cloud.position = Vector2(float(index) * 390.0 - 100.0, 100.0 + float(index % 2) * 155.0)
		cloud.scale = Vector2.ONE * (1.25 + float(index % 3) * 0.25)
		cloud.show_behind_parent = true
		cloud.modulate = Color(0.33, 0.38, 0.42, 0.0)
		add_child(cloud)
		_cloud_sprites.append(cloud)


func _update_clouds(delta: float, viewport_size: Vector2) -> void:
	var cloud_amount: float = float(weather_state["clouds"])
	var wind_direction: Vector2 = weather_state["wind_direction"]
	var wind_strength: float = float(weather_state["wind_strength"])
	for index in range(_cloud_sprites.size()):
		var cloud := _cloud_sprites[index]
		cloud.position.x += (12.0 + wind_direction.x * wind_strength * 34.0) * delta
		if cloud.position.x > viewport_size.x + 260.0:
			cloud.position.x = -260.0
		cloud.modulate = Color(0.28, 0.32, 0.36, cloud_amount * (0.13 + float(index % 2) * 0.035))


func _load_svg_texture(resource_path: String) -> Texture2D:
	var svg_text := FileAccess.get_file_as_string(resource_path)
	if svg_text.is_empty():
		push_error("Could not read editable lab asset: %s" % resource_path)
		return ImageTexture.new()
	var image := Image.new()
	var error := image.load_svg_from_string(svg_text, 1.0)
	if error != OK:
		push_error("Could not rasterize editable lab asset: %s" % resource_path)
		return ImageTexture.new()
	return ImageTexture.create_from_image(image)
