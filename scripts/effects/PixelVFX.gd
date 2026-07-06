extends Node

const PixelParticle2D := preload("res://scripts/effects/PixelParticle2D.gd")


func spawn_world_hit_sparks(world_position: Vector2, is_critical := false) -> void:
	var profile := _get_profile("critical_hit_sparks" if is_critical else "hit_sparks")
	var count := int(profile.get("pixel_count", 14))
	var speed_min := float(profile.get("speed_min", 70.0))
	var speed_max := float(profile.get("speed_max", 155.0))
	var lifetime := float(profile.get("lifetime", 0.36))
	var size_min := float(profile.get("size_min", 2.0))
	var size_max := float(profile.get("size_max", 4.0))
	var jitter_radius := float(profile.get("jitter_radius", 6.0))
	var color_switch_interval := float(profile.get("color_switch_interval", 0.035))
	var gravity := float(profile.get("gravity", 0.0))
	var colors := _parse_color_array(profile.get("colors", []), [Color(1.0, 0.92, 0.45, 1.0), Color(1.0, 0.38, 0.16, 1.0), Color.WHITE])

	var parent := _get_world_parent()
	if parent == null:
		return

	for _i in range(count):
		var particle := PixelParticle2D.new()
		parent.add_child(particle)
		particle.global_position = world_position + Vector2(randf_range(-jitter_radius, jitter_radius), randf_range(-jitter_radius, jitter_radius))
		particle.z_index = 999
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(speed_min, speed_max)
		var velocity := Vector2.RIGHT.rotated(angle) * speed
		particle.setup(velocity, lifetime * randf_range(0.75, 1.2), randf_range(size_min, size_max), colors, color_switch_interval, gravity)


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
