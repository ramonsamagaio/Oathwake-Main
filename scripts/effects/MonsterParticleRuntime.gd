extends RefCounted

const PARTICLE_NODE_NAME := "ContentParticles"
const DEFAULT_COLOR := Color(0.82, 0.90, 1.0, 0.70)
const BUTTERFLY_COLORS := {
	"blue": "#8FC7FFE6",
	"grey": "#C8CCD6CC",
	"pink": "#FF9ED8E6",
	"red": "#FF836FE6",
	"white": "#FFF5DDE6",
	"yellow": "#FFE68AE6",
}


static func apply(host: Node2D, monster_data: Dictionary) -> void:
	if host == null:
		return
	var is_butterfly := str(monster_data.get("content_group", "")) == "butterflies"
	var config_value: Variant = monster_data.get("particles", {})
	var config := config_value as Dictionary if config_value is Dictionary else {}
	var enabled := bool(config.get("enabled", is_butterfly))
	var particles := host.get_node_or_null(PARTICLE_NODE_NAME) as CPUParticles2D
	if not enabled:
		if particles != null:
			particles.queue_free()
		return
	if particles == null:
		particles = CPUParticles2D.new()
		particles.name = PARTICLE_NODE_NAME
		particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		particles.local_coords = true
		particles.one_shot = false
		particles.texture = _make_pixel_texture()
		host.add_child(particles)

	var default_color := str(BUTTERFLY_COLORS.get(str(monster_data.get("pet_color", "")), "#DDEEFFB3"))
	if is_butterfly and str(monster_data.get("pet_color", "")).is_empty():
		for color_name in BUTTERFLY_COLORS.keys():
			if str(monster_data.get("display_name", "")).to_lower().contains(str(color_name)):
				default_color = str(BUTTERFLY_COLORS[color_name])
				break

	particles.amount = maxi(int(config.get("amount", 5)), 1)
	particles.lifetime = maxf(float(config.get("lifetime", 0.70)), 0.05)
	particles.preprocess = particles.lifetime
	particles.randomness = clampf(float(config.get("randomness", 0.65)), 0.0, 1.0)
	particles.explosiveness = clampf(float(config.get("explosiveness", 0.0)), 0.0, 1.0)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = maxf(float(config.get("emission_radius", 5.0)), 0.0)
	var direction := Vector2(float(config.get("direction_x", 0.0)), float(config.get("direction_y", -1.0)))
	particles.direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
	particles.spread = clampf(float(config.get("spread", 180.0)), 0.0, 180.0)
	particles.gravity = Vector2(float(config.get("gravity_x", 0.0)), float(config.get("gravity_y", 5.0)))
	particles.initial_velocity_min = maxf(float(config.get("speed_min", 3.0)), 0.0)
	particles.initial_velocity_max = maxf(float(config.get("speed_max", 9.0)), particles.initial_velocity_min)
	particles.scale_amount_min = maxf(float(config.get("scale_min", 0.8)), 0.05)
	particles.scale_amount_max = maxf(float(config.get("scale_max", 1.3)), particles.scale_amount_min)
	particles.color = Color.from_string(str(config.get("color", default_color)), DEFAULT_COLOR)
	particles.position = Vector2(float(config.get("offset_x", 0.0)), float(config.get("offset_y", -18.0)))
	particles.z_index = int(config.get("z_index", 3))
	particles.emitting = true
	particles.set_meta("content_particle_config", config.duplicate(true))
	particles.set_meta("butterfly_default_particles", is_butterfly and config.is_empty())


static func _make_pixel_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
	var texture := GradientTexture1D.new()
	texture.width = 2
	texture.gradient = gradient
	return texture
