extends Node

const PixelParticle2D := preload("res://scripts/effects/PixelParticle2D.gd")
const CONTACT_LIGHT_TEXTURE_SIZE := 64
const DEFAULT_CONTACT_LIGHT_COLOR := Color("#FFD78A")
const DEFAULT_CONTACT_LIGHT_ENERGY := 0.72
const DEFAULT_CONTACT_LIGHT_RADIUS := 34.0
const DEFAULT_CONTACT_LIGHT_DURATION := 0.055
const DEFAULT_CRITICAL_LIGHT_MULTIPLIER := 2.0

var _contact_light_texture: Texture2D


func spawn_world_hit_sparks(world_position: Vector2, is_critical := false) -> void:
	var profile := _get_profile("critical_hit_sparks" if is_critical else "hit_sparks")
	var count := int(profile.get("pixel_count", 14))
	var speed_min := float(profile.get("speed_min", 45.0))
	var speed_max := float(profile.get("speed_max", 105.0))
	var lifetime := float(profile.get("lifetime", 0.34))
	var fade_out_time := float(profile.get("fade_out_time", lifetime))
	var distance := float(profile.get("distance", speed_max * lifetime))
	var size_min := float(profile.get("size_min", 1.0))
	var size_max := float(profile.get("size_max", 2.0))
	var jitter_radius := float(profile.get("jitter_radius", 5.0))
	var color_switch_interval := float(profile.get("color_switch_interval", 0.035))
	var gravity := float(profile.get("gravity", 420.0))
	var horizontal_bias := float(profile.get("horizontal_bias", 0.9))
	var upward_bias := float(profile.get("upward_bias", 1.0))
	var colors := _parse_color_array(profile.get("colors", []), [Color("#BB2D45"), Color("#D87A3C"), Color("#DB9B42"), Color("#17191B"), Color("#26292D")])

	var parent := _get_world_parent()
	if parent == null:
		return

	var light_profile := _get_profile("hit_sparks").duplicate(true)
	if is_critical:
		light_profile["contact_light_critical_multiplier"] = float(profile.get("contact_light_critical_multiplier", DEFAULT_CRITICAL_LIGHT_MULTIPLIER))
	_spawn_contact_light(parent, world_position, light_profile, is_critical)

	for _i in range(count):
		var particle := PixelParticle2D.new()
		particle.top_level = true
		particle.z_as_relative = false
		particle.z_index = 4089
		parent.add_child(particle)
		particle.global_position = world_position + Vector2(randf_range(-jitter_radius, jitter_radius), randf_range(-jitter_radius, jitter_radius))
		var distance_scale := distance / maxf(speed_max * lifetime, 0.01)
		var x_speed := randf_range(-speed_max * horizontal_bias, speed_max * horizontal_bias) * distance_scale
		var y_speed := -randf_range(speed_min * upward_bias, speed_max * upward_bias) * distance_scale
		var velocity := Vector2(x_speed, y_speed)
		var particle_lifetime := lifetime * randf_range(0.78, 1.18)
		particle.setup(velocity, particle_lifetime, randf_range(size_min, size_max), colors, color_switch_interval, gravity, minf(fade_out_time, particle_lifetime))


func _spawn_contact_light(parent: Node, world_position: Vector2, profile: Dictionary, is_critical: bool) -> PointLight2D:
	if not bool(profile.get("contact_light_enabled", true)):
		return null
	var duration := maxf(float(profile.get("contact_light_duration", DEFAULT_CONTACT_LIGHT_DURATION)), 0.0)
	var radius := maxf(float(profile.get("contact_light_radius", DEFAULT_CONTACT_LIGHT_RADIUS)), 0.0)
	var peak_energy := _resolve_contact_light_peak_energy(profile, is_critical)
	if duration <= 0.0 or radius <= 0.0 or peak_energy <= 0.0:
		return null

	var light := PointLight2D.new()
	light.name = "CriticalHitContactLight" if is_critical else "HitContactLight"
	light.top_level = true
	light.z_as_relative = false
	light.z_index = 4087
	light.texture = _get_contact_light_texture()
	light.texture_scale = maxf(radius / (float(CONTACT_LIGHT_TEXTURE_SIZE) * 0.5), 0.01)
	light.color = _color_from_value(profile.get("contact_light_color", DEFAULT_CONTACT_LIGHT_COLOR), DEFAULT_CONTACT_LIGHT_COLOR)
	light.energy = peak_energy
	light.shadow_enabled = false
	light.set_meta("hit_contact_light", true)
	light.set_meta("critical", is_critical)
	light.set_meta("peak_energy", peak_energy)
	light.set_meta("duration", duration)
	light.set_meta("radius", radius)
	parent.add_child(light)
	light.global_position = world_position

	var tween := light.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(light, "energy", 0.0, duration)
	tween.tween_callback(light.queue_free)
	return light


func _resolve_contact_light_peak_energy(profile: Dictionary, is_critical: bool) -> float:
	var energy := maxf(float(profile.get("contact_light_energy", DEFAULT_CONTACT_LIGHT_ENERGY)), 0.0)
	if is_critical:
		var critical_multiplier := maxf(float(profile.get("contact_light_critical_multiplier", DEFAULT_CRITICAL_LIGHT_MULTIPLIER)), 0.0)
		energy *= critical_multiplier
	return energy


func _get_contact_light_texture() -> Texture2D:
	if _contact_light_texture != null and is_instance_valid(_contact_light_texture):
		return _contact_light_texture
	var image := Image.create(CONTACT_LIGHT_TEXTURE_SIZE, CONTACT_LIGHT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2.ONE * (float(CONTACT_LIGHT_TEXTURE_SIZE - 1) * 0.5)
	var maximum_distance := maxf(center.x, 0.001)
	for y in range(CONTACT_LIGHT_TEXTURE_SIZE):
		for x in range(CONTACT_LIGHT_TEXTURE_SIZE):
			var normalized_distance := Vector2(float(x), float(y)).distance_to(center) / maximum_distance
			var intensity := pow(1.0 - clampf(normalized_distance, 0.0, 1.0), 2.35)
			image.set_pixel(x, y, Color(intensity, intensity, intensity, 1.0))
	_contact_light_texture = ImageTexture.create_from_image(image)
	return _contact_light_texture


func spawn_ui_bar_pixels(parent: Control, local_position: Vector2, profile_id := "hud_life_damage") -> void:
	if parent == null:
		return
	var profile := _get_profile(profile_id)
	var count := int(profile.get("pixel_count", 8))
	var lifetime := float(profile.get("lifetime", 0.62))
	var distance_min := float(profile.get("distance_min", 8.0))
	var distance_max := float(profile.get("distance_max", 24.0))
	var drift_x := float(profile.get("drift_x", 10.0))
	var size_min := float(profile.get("size_min", 2.0))
	var size_max := float(profile.get("size_max", 3.0))
	var color_switch_interval := float(profile.get("color_switch_interval", 0.055))
	var colors := _parse_color_array(profile.get("colors", []), [Color(0.85, 0.0, 0.05, 1.0), Color(1.0, 0.12, 0.10, 1.0), Color(0.45, 0.0, 0.02, 1.0)])

	for _i in range(count):
		var pixel := ColorRect.new()
		pixel.name = "LifeDamagePixel"
		pixel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pixel.size = Vector2.ONE * randf_range(size_min, size_max)
		pixel.position = local_position + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		pixel.color = colors[randi() % colors.size()]
		pixel.z_index = 998
		parent.add_child(pixel)

		var target_position := pixel.position + Vector2(randf_range(-drift_x, drift_x), randf_range(distance_min, distance_max))
		var tween := pixel.create_tween()
		tween.set_parallel(true)
		tween.tween_property(pixel, "position", target_position, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(pixel, "modulate:a", 0.0, lifetime)
		tween.set_parallel(false)
		if colors.size() > 1:
			var steps := maxi(1, int(lifetime / maxf(color_switch_interval, 0.01)))
			for step in range(steps):
				var next_color := colors[step % colors.size()]
				tween.tween_property(pixel, "color", next_color, color_switch_interval)
		tween.tween_callback(pixel.queue_free)


func _get_world_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


func _get_profile(profile_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile(profile_id):
		return content_db.get_vfx_profile(profile_id)
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}


func _parse_color_array(raw_colors: Variant, fallback: Array[Color]) -> Array[Color]:
	var parsed: Array[Color] = []
	if raw_colors is Array:
		for raw_color in raw_colors:
			if raw_color is Color:
				parsed.append(raw_color)
			else:
				var color_text := str(raw_color)
				if not color_text.is_empty():
					parsed.append(Color(color_text))
	return parsed if not parsed.is_empty() else fallback


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)
