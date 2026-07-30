extends SceneTree

const SolarShadowScript := preload("res://scripts/effects/PinnedActiveFrameProjectedShadow.gd")
const DayNightCycleScript := preload("res://scripts/world/DayNightCycle.gd")
const LocalLightShadowDirectorScript := preload("res://scripts/effects/LocalLightShadowDirector.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_profile_geometry_and_animation_stability()
	await _validate_profile_auto_classification()
	await _validate_continuous_solar_cycle()
	await _validate_night_local_light_shadow()
	if failures.is_empty():
		print("DYNAMIC_SHADOW_CYCLE_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("DYNAMIC_SHADOW_CYCLE_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_profile_geometry_and_animation_stability() -> void:
	var target := Node2D.new()
	target.name = "PlayerProfileTest"
	target.add_to_group("player")
	root.add_child(target)

	var animated := AnimatedSprite2D.new()
	animated.name = "AnimatedSprite2D"
	var frames := SpriteFrames.new()
	frames.add_animation("walk")
	var narrow_image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	narrow_image.fill(Color.TRANSPARENT)
	for y in range(4, 45):
		for x in range(12, 20):
			narrow_image.set_pixel(x, y, Color.WHITE)
	var wide_image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	wide_image.fill(Color.TRANSPARENT)
	for y in range(10, 42):
		for x in range(3, 29):
			wide_image.set_pixel(x, y, Color.WHITE)
	frames.add_frame("walk", ImageTexture.create_from_image(narrow_image))
	frames.add_frame("walk", ImageTexture.create_from_image(wide_image))
	animated.sprite_frames = frames
	animated.animation = "walk"
	animated.frame = 0
	target.add_child(animated)

	var shadow := SolarShadowScript.new() as Polygon2D
	target.add_child(shadow)
	var config := {
		"enabled": true,
		"direction_degrees": -135.0,
		"stretch": 1.25,
		"width_scale": 1.0,
		"root_overlap": 6.0,
		"mask_weight": 1.0,
	}
	shadow.call("configure", target, animated, config, Vector2(0.0, 24.0))
	await process_frame

	if shadow.polygon.size() != 4:
		failures.append("Universal profile shadow did not produce one stable four-corner card.")
	if str(shadow.get_meta("shadow_projection_mode", "")) != "universal_shadow_profile":
		failures.append("Solar shadow did not switch to universal profile projection.")
	if not bool(shadow.get_meta("shadow_projection_profiled", false)):
		failures.append("Solar shadow did not publish the profiled projection contract.")
	if str(shadow.get_meta("shadow_profile_id", "")) != "humanoid":
		failures.append("Player caster was not classified with the humanoid shadow profile.")
	if not bool(shadow.get_meta("shadow_profile_ignores_frame_silhouette", false)):
		failures.append("Profile shadow still depends on the active animation-frame silhouette.")
	if _polygon_area(shadow.polygon) <= 100.0:
		failures.append("Universal profile shadow collapsed into a line or tiny card.")

	var first_polygon := shadow.polygon.duplicate()
	var first_proxy := _shadow_proxy(shadow)
	var first_profile_texture := first_proxy.texture if first_proxy != null else null
	var first_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2(INF, INF))
	animated.frame = 1
	shadow.call("_refresh_silhouette")
	await process_frame
	if not _polygons_match(first_polygon, shadow.polygon, 0.01):
		failures.append("Changing to a radically different animation frame changed the solar shadow geometry.")
	var second_proxy := _shadow_proxy(shadow)
	if first_profile_texture == null or second_proxy == null or second_proxy.texture != first_profile_texture:
		failures.append("Animated frame change replaced the compositor's universal profile mask texture.")
	if shadow.texture != frames.get_frame_texture("walk", 1):
		failures.append("Canonical shadow diagnostics did not advance to the authored animation frame.")
	var second_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2.ZERO)
	if first_contact.distance_to(second_contact) > 0.001:
		failures.append("Animated frame change moved the universal shadow foot pivot.")

	config["direction_degrees"] = -45.0
	shadow.call("configure", target, animated, config, Vector2(0.0, 24.0))
	await process_frame
	var rotated_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2.ZERO)
	if first_contact.distance_to(rotated_contact) > 0.001:
		failures.append("Sun rotation moved the caster pivot instead of rotating the profile around it.")
	if absf(_polygon_area(first_polygon) - _polygon_area(shadow.polygon)) > 0.1:
		failures.append("Universal shadow profile changed area while rotating through the solar arc.")
	var direction: Vector2 = shadow.get_meta("shadow_projection_direction", Vector2.ZERO)
	if direction.x <= 0.0 or direction.y >= 0.0:
		failures.append("Evening profile shadow did not rotate to the upper-right direction.")

	target.queue_free()
	await process_frame


func _validate_profile_auto_classification() -> void:
	var cases := [
		{"name": "AncientTreeStump", "size": Vector2i(96, 128), "expected": "trunk_wide"},
		{"name": "IronOreRock", "size": Vector2i(48, 36), "expected": "rock_compact"},
		{"name": "VillageHouseRoof", "size": Vector2i(180, 128), "expected": "building_wide"},
		{"name": "WoodFencePost", "size": Vector2i(20, 72), "expected": "thin_segment"},
	]
	for case_value in cases:
		var case := case_value as Dictionary
		var target := Node2D.new()
		target.name = str(case["name"])
		root.add_child(target)
		var sprite := Sprite2D.new()
		var size := case["size"] as Vector2i
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		sprite.texture = ImageTexture.create_from_image(image)
		target.add_child(sprite)
		var shadow := SolarShadowScript.new() as Polygon2D
		target.add_child(shadow)
		shadow.set_meta("shadow_visual_size_hint", Vector2(size))
		shadow.call("configure", target, sprite, {"enabled": true}, Vector2(0.0, float(size.y) * 0.5))
		await process_frame
		if str(shadow.get_meta("shadow_profile_id", "")) != str(case["expected"]):
			failures.append("%s was not auto-classified as %s." % [case["name"], case["expected"]])
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
	var solar_caster := SolarShadowScript.new() as Polygon2D
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
				if bool(shadow.get_meta("shadow_projection_profiled", false)):
					failures.append("Night local shadow incorrectly switched to the solar-only universal profile mask.")
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


func _shadow_proxy(shadow: Polygon2D) -> Polygon2D:
	if shadow == null:
		return null
	var proxy_id := int(shadow.get_meta("shadow_render_proxy_id", 0))
	if proxy_id <= 0:
		return null
	var proxy_value: Variant = instance_from_id(proxy_id)
	if proxy_value == null or not is_instance_valid(proxy_value):
		return null
	return proxy_value as Polygon2D


func _polygons_match(a: PackedVector2Array, b: PackedVector2Array, tolerance: float) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if a[index].distance_to(b[index]) > tolerance:
			return false
	return true


func _polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var signed_area := 0.0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		signed_area += (current.x * next.y) - (next.x * current.y)
	return absf(signed_area) * 0.5
