extends SceneTree

const DynamicShadowScript := preload("res://scripts/effects/PinnedActiveFrameProjectedShadow.gd")
const DayNightCycleScript := preload("res://scripts/world/DayNightCycle.gd")
const LocalLightShadowDirectorScript := preload("res://scripts/effects/LocalLightShadowDirector.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_pinned_oblique_geometry()
	await _validate_southern_caster_limit()
	await _validate_continuous_solar_cycle()
	await _validate_night_local_light_shadow()
	if failures.is_empty():
		print("DYNAMIC_SHADOW_CYCLE_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("DYNAMIC_SHADOW_CYCLE_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_pinned_oblique_geometry() -> void:
	var image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(4, 44):
		for x in range(8, 24):
			image.set_pixel(x, y, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var target := Node2D.new()
	root.add_child(target)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	target.add_child(sprite)
	var shadow := DynamicShadowScript.new() as Polygon2D
	target.add_child(shadow)

	var expected_bottom_left := Vector2(-8.0, 20.0)
	var expected_bottom_right := Vector2(8.0, 20.0)
	var expected_length := (40.0 - 6.0) * 1.25
	for direction_degrees in [-135.0, -112.5, -90.0, -67.5, -45.0]:
		var direction := Vector2.RIGHT.rotated(deg_to_rad(direction_degrees)).normalized()
		shadow.set("_config", {"local_light_shadow": false})
		shadow.set("_projection_direction", direction)
		shadow.set("_projection_stretch", 1.25)
		shadow.set("_projection_width_scale", 1.0)
		shadow.set("_projection_root_overlap", 6.0)
		shadow.call(
			"_apply_texture_rect",
			texture,
			texture.get_size(),
			true,
			Vector2.ZERO,
			false,
			false,
			Transform2D.IDENTITY
		)
		if shadow.polygon.size() != 4:
			failures.append("Pinned projection did not produce a four-corner silhouette at %s degrees." % direction_degrees)
			continue
		var bottom_right := shadow.polygon[2]
		var bottom_left := shadow.polygon[3]
		if bottom_left.distance_to(expected_bottom_left) > 0.001 or bottom_right.distance_to(expected_bottom_right) > 0.001:
			failures.append("Sun movement displaced the pinned south edge at %s degrees: %s / %s." % [direction_degrees, bottom_left, bottom_right])
		var left_projection := shadow.polygon[0] - bottom_left
		var right_projection := shadow.polygon[1] - bottom_right
		var expected_projection := direction * expected_length
		if left_projection.distance_to(expected_projection) > 0.01 or right_projection.distance_to(expected_projection) > 0.01:
			failures.append("Shadow was rotated as a card instead of obliquely stretched at %s degrees." % direction_degrees)
		if absf(shadow.polygon[0].distance_to(shadow.polygon[1]) - 16.0) > 0.01:
			failures.append("Pinned projection changed the silhouette width at %s degrees." % direction_degrees)
		if _polygon_area(shadow.polygon) <= 100.0:
			failures.append("Pinned projection collapsed into a line inside the solar angle range at %s degrees." % direction_degrees)
		for point in shadow.polygon:
			if point.y > expected_bottom_left.y + 0.001:
				failures.append("Pinned projection crossed south of the caster at %s degrees." % direction_degrees)
				break
		var contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2.ZERO)
		var anchor: Vector2 = shadow.get_meta("shadow_projection_anchor", Vector2(INF, INF))
		if contact.distance_to(anchor) > 0.001:
			failures.append("Pinned shadow contact and projection origin diverged at %s degrees." % direction_degrees)
		if not bool(shadow.get_meta("shadow_projection_pinned_base", false)):
			failures.append("Directional shadow did not publish its pinned-base projection contract.")
		if bool(shadow.get_meta("shadow_projection_rigid_basis", true)):
			failures.append("Directional shadow still reports the obsolete rigid rotating basis.")
		if str(shadow.get_meta("shadow_projection_mode", "")) != "pinned_oblique_shear":
			failures.append("Directional shadow did not use pinned oblique shear mode.")

	target.queue_free()
	await process_frame


func _validate_southern_caster_limit() -> void:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(8, 57):
		var width := 16 + int(float(y - 8) * 0.65)
		var left := maxi(2, 32 - width / 2)
		var right := mini(62, 32 + width / 2)
		for x in range(left, right):
			image.set_pixel(x, y, Color.WHITE)
	var target := Node2D.new()
	root.add_child(target)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	target.add_child(sprite)
	var shadow := DynamicShadowScript.new() as Polygon2D
	target.add_child(shadow)
	shadow.call("configure", target, sprite, {
		"enabled": true,
		"direction_degrees": -135.0,
		"stretch": 1.25,
		"width_scale": 1.0,
		"root_overlap": 6.0,
		"mask_weight": 1.0,
	}, Vector2(0.0, 28.0))
	await process_frame
	var southern_limit_y := float(shadow.get_meta("shadow_southern_limit_y", INF))
	var maximum_shadow_y := -INF
	for point in shadow.polygon:
		maximum_shadow_y = maxf(maximum_shadow_y, point.y)
	if maximum_shadow_y > southern_limit_y + 0.01:
		failures.append("Solar shadow crossed the pinned lower boundary: %s > %s." % [maximum_shadow_y, southern_limit_y])
	if not bool(shadow.get_meta("shadow_projection_pinned_base", false)):
		failures.append("Wide caster did not use the pinned south-edge projection.")
	if _polygon_area(shadow.polygon) <= 100.0:
		failures.append("Pinned southern projection distorted or collapsed the shadow.")
	target.queue_free()
	await process_frame


func _validate_continuous_solar_cycle() -> void:
	var cycle := DayNightCycleScript.new()
	root.add_child(cycle)
	cycle.set_process(false)
	await process_frame

	cycle.call("set_time_of_day", 0.0)
	var morning := cycle.call("get_sun_shadow_direction") as Vector2
	if morning.x >= 0.0 or morning.y >= 0.0:
		failures.append("Morning solar shadow does not begin upper-left of the caster.")
	if float(cycle.call("get_solar_shadow_strength")) < 0.99:
		failures.append("Morning solar shadow is not fully visible after the invisible reset.")

	cycle.call("set_time_of_day", 0.46)
	var dusk_start_direction := cycle.call("get_sun_shadow_direction") as Vector2
	var dusk_start_strength := float(cycle.call("get_solar_shadow_strength"))
	cycle.call("set_time_of_day", 0.58)
	var moving_fade_direction := cycle.call("get_sun_shadow_direction") as Vector2
	var moving_fade_strength := float(cycle.call("get_solar_shadow_strength"))
	if dusk_start_strength <= moving_fade_strength or moving_fade_strength <= 0.0:
		failures.append("Solar shadow is not fading progressively during dusk.")
	if absf(dusk_start_direction.angle_to(moving_fade_direction)) < deg_to_rad(4.0):
		failures.append("Solar shadow parked before becoming invisible instead of moving through its fade-out.")
	if moving_fade_direction.x <= 0.0 or moving_fade_direction.y >= 0.0:
		failures.append("Evening solar shadow is not finishing upper-right of the caster.")

	cycle.call("set_time_of_day", 0.70)
	var hidden_direction := cycle.call("get_sun_shadow_direction") as Vector2
	if float(cycle.call("get_solar_shadow_strength")) > 0.001:
		failures.append("Solar shadow is still visible during the hidden night reset window.")
	if hidden_direction.distance_to(morning) > 0.001:
		failures.append("Solar shadow did not reset to the morning angle while invisible.")

	cycle.call("set_time_of_day", 0.90)
	var dawn_strength := float(cycle.call("get_solar_shadow_strength"))
	var dawn_direction := cycle.call("get_sun_shadow_direction") as Vector2
	if dawn_strength <= 0.0 or dawn_strength >= 1.0:
		failures.append("Solar shadow is not fading in during the late-night brightening phase.")
	if dawn_direction.distance_to(morning) > 0.001:
		failures.append("Dawn fade-in does not begin at the morning angle.")

	cycle.call("set_time_of_day", 0.999)
	var before_rollover := cycle.call("get_sun_shadow_direction") as Vector2
	cycle.call("set_time_of_day", 0.001)
	var after_rollover := cycle.call("get_sun_shadow_direction") as Vector2
	if absf(before_rollover.angle_to(after_rollover)) > deg_to_rad(2.0):
		failures.append("Solar shadow still jumps visibly at the night-to-day rollover.")

	cycle.queue_free()
	await process_frame


func _validate_night_local_light_shadow() -> void:
	var cycle := DayNightCycleScript.new()
	root.add_child(cycle)
	cycle.set_process(false)
	cycle.call("set_time_of_day", 0.75)
	await process_frame

	var emitter := Node2D.new()
	emitter.position = Vector2.ZERO
	emitter.add_to_group("world_light_emitter")
	root.add_child(emitter)
	var light := PointLight2D.new()
	var light_image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	light_image.fill(Color.WHITE)
	light.texture = ImageTexture.create_from_image(light_image)
	light.texture_scale = 2.0
	light.energy = 0.25
	light.enabled = true
	emitter.add_child(light)

	var target := Node2D.new()
	target.position = Vector2(72.0, 0.0)
	root.add_child(target)
	var sprite_image := Image.create(24, 36, false, Image.FORMAT_RGBA8)
	sprite_image.fill(Color.TRANSPARENT)
	for y in range(3, 34):
		for x in range(6, 18):
			sprite_image.set_pixel(x, y, Color.WHITE)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(sprite_image)
	target.add_child(sprite)
	var solar_caster := DynamicShadowScript.new() as Polygon2D
	target.add_child(solar_caster)
	solar_caster.call("configure", target, sprite, {"enabled": true}, Vector2(0.0, 18.0))

	var director := LocalLightShadowDirectorScript.new()
	root.add_child(director)
	director.set_process(false)
	await process_frame
	director.call("_refresh_emitter_cache")
	director.call("_update_local_light_shadows")
	await process_frame

	if int(director.call("get_active_local_shadow_count")) < 1:
		failures.append("Night PointLight2D did not create a local projected shadow.")
	else:
		var local_shadows: Variant = director.get("_local_shadows")
		if local_shadows is Dictionary:
			for shadow_value in (local_shadows as Dictionary).values():
				if shadow_value == null or not is_instance_valid(shadow_value):
					continue
				var shadow := shadow_value as Polygon2D
				if shadow == null:
					continue
				if not shadow.visible or float(shadow.get_meta("shadow_mask_weight", 0.0)) <= 0.05:
					failures.append("Night local shadow exists but is effectively invisible.")
				var expected_direction := (target.global_position - light.global_position).normalized()
				var actual_direction: Vector2 = shadow.get_meta("shadow_projection_direction", Vector2.ZERO)
				if actual_direction.length_squared() < 0.9 or expected_direction.dot(actual_direction.normalized()) < 0.99:
					failures.append("Night local shadow is not projected away from its PointLight2D.")
				if _polygon_area(shadow.polygon) <= 50.0:
					failures.append("Night local shadow geometry collapsed or was not generated.")
				break

	target.queue_free()
	await process_frame
	director.call("_remove_stale_shadows", {})
	if int(director.call("get_active_local_shadow_count")) != 0:
		failures.append("Freed caster left a stale local shadow entry behind.")

	director.queue_free()
	emitter.queue_free()
	cycle.queue_free()
	await process_frame


func _polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var signed_area := 0.0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		signed_area += (current.x * next.y) - (next.x * current.y)
	return absf(signed_area) * 0.5
