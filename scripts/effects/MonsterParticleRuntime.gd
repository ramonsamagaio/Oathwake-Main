extends RefCounted

const PARTICLE_NODE_NAME := "ContentParticles"
const MODE_ATTACHED := "attached"
const MODE_TRAIL := "trail"
const DEFAULT_COLOR := Color(0.82, 0.90, 1.0, 0.70)
const DEFAULT_VISUAL_SCALE_REFERENCE := 2.0
const BUTTERFLY_COLORS := {
	"blue": "#8FC7FFE6",
	"grey": "#C8CCD6CC",
	"pink": "#FF9ED8E6",
	"red": "#FF836FE6",
	"white": "#FFF5DDE6",
	"yellow": "#FFE68AE6",
}


static func apply(host: Node2D, actor_data: Dictionary) -> void:
	if host == null:
		return
	var is_butterfly := (
		str(actor_data.get("content_group", "")) == "butterflies"
		or str(actor_data.get("pet_family", "")) == "butterfly"
	)
	var config_value: Variant = actor_data.get("particles", {})
	var config := config_value as Dictionary if config_value is Dictionary else {}
	var enabled := bool(config.get("enabled", is_butterfly))
	var particles := host.get_node_or_null(PARTICLE_NODE_NAME) as CPUParticles2D
	if not enabled:
		if particles != null:
			particles.emitting = false
			particles.queue_free()
		return
	if particles == null:
		particles = CPUParticles2D.new()
		particles.name = PARTICLE_NODE_NAME
		particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		particles.one_shot = false
		particles.texture = _make_pixel_texture()
		host.add_child(particles)

	var mode := _normalize_mode(str(config.get("mode", MODE_TRAIL if is_butterfly else MODE_ATTACHED)))
	var is_trail := mode == MODE_TRAIL
	var default_color := _resolve_default_color(actor_data, is_butterfly)
	var particle_color := Color.from_string(str(config.get("color", default_color)), DEFAULT_COLOR)
	var visual_scale := maxf(float(actor_data.get("visual_scale", DEFAULT_VISUAL_SCALE_REFERENCE)), 0.01)
	var scale_with_visual := bool(config.get("scale_with_visual", is_butterfly))
	var visual_scale_ratio := visual_scale / DEFAULT_VISUAL_SCALE_REFERENCE if scale_with_visual else 1.0
	var size_multiplier := maxf(float(config.get("size_multiplier", 1.0)), 0.01)
	var resolved_size_multiplier := visual_scale_ratio * size_multiplier

	particles.emitting = false
	particles.local_coords = not is_trail
	particles.amount = maxi(int(config.get("amount", 8 if is_trail else 5)), 1)
	particles.lifetime = maxf(float(config.get("lifetime", 0.90 if is_trail else 0.70)), 0.05)
	particles.preprocess = 0.0 if is_trail else particles.lifetime
	particles.randomness = clampf(float(config.get("randomness", 0.80 if is_trail else 0.65)), 0.0, 1.0)
	particles.explosiveness = clampf(float(config.get("explosiveness", 0.0)), 0.0, 1.0)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = maxf(float(config.get("emission_radius", 2.0 if is_trail else 5.0)), 0.0)

	var direction := Vector2(
		float(config.get("direction_x", 0.0)),
		float(config.get("direction_y", -1.0))
	)
	particles.direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
	particles.spread = clampf(float(config.get("spread", 180.0)), 0.0, 180.0)
	particles.gravity = Vector2(
		float(config.get("gravity_x", 0.0)),
		float(config.get("gravity_y", 0.0 if is_trail else 5.0))
	)
	particles.initial_velocity_min = maxf(float(config.get("speed_min", 0.8 if is_trail else 3.0)), 0.0)
	particles.initial_velocity_max = maxf(
		float(config.get("speed_max", 2.5 if is_trail else 9.0)),
		particles.initial_velocity_min
	)
	var default_scale_min := 0.45 if is_trail else 0.8
	var default_scale_max := 0.80 if is_trail else 1.3
	particles.scale_amount_min = maxf(float(config.get("scale_min", default_scale_min)) * resolved_size_multiplier, 0.01)
	particles.scale_amount_max = maxf(
		float(config.get("scale_max", default_scale_max)) * resolved_size_multiplier,
		particles.scale_amount_min
	)
	particles.color = particle_color
	particles.color_ramp = _make_fade_ramp() if bool(config.get("fade_out", is_trail)) else null
	particles.position = Vector2(
		float(config.get("offset_x", 0.0)),
		float(config.get("offset_y", -18.0))
	)
	particles.z_index = int(config.get("z_index", 3))
	particles.restart()
	particles.emitting = true
	particles.set_meta("content_particle_config", config.duplicate(true))
	particles.set_meta("content_particle_mode", mode)
	particles.set_meta("content_particle_world_trail", is_trail)
	particles.set_meta("content_particle_visual_scale_ratio", visual_scale_ratio)
	particles.set_meta("content_particle_size_multiplier", size_multiplier)
	particles.set_meta("content_particle_resolved_size_multiplier", resolved_size_multiplier)
	particles.set_meta("butterfly_default_particles", is_butterfly and config.is_empty())


static func _normalize_mode(value: String) -> String:
	return MODE_ATTACHED if value.strip_edges().to_lower() == MODE_ATTACHED else MODE_TRAIL


static func _resolve_default_color(actor_data: Dictionary, is_butterfly: bool) -> String:
	var color_name := str(actor_data.get("pet_color", "")).strip_edges().to_lower()
	if BUTTERFLY_COLORS.has(color_name):
		return str(BUTTERFLY_COLORS[color_name])
	if is_butterfly:
		var display_name := str(actor_data.get("display_name", "")).to_lower()
		for candidate in BUTTERFLY_COLORS.keys():
			if display_name.contains(str(candidate)):
				return str(BUTTERFLY_COLORS[candidate])
	return "#DDEEFFB3"


static func _make_fade_ramp() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	return gradient


static func _make_pixel_texture() -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
