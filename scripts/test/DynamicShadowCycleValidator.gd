extends SceneTree

const SolarShadowScript := preload("res://scripts/effects/PinnedActiveFrameProjectedShadow.gd")
const DayNightCycleScript := preload("res://scripts/world/DayNightCycle.gd")
const LocalLightShadowDirectorScript := preload("res://scripts/effects/LocalLightShadowDirector.gd")
const DirectionalShadowRuntimeScript := preload("res://scripts/effects/DirectionalShadowRuntime.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_footprint_extrusion_and_animation_stability()
	await _validate_pinned_contact_transform()
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


func _validate_footprint_extrusion_and_animation_stability() -> void:
	var target := Node2D.new()
	target.name = "PlayerActiveFrameTest"
	target.add_to_group("player")
	root.add_child(target)

	var cycle := DayNightCycleScript.new()
	root.add_child(cycle)
	cycle.set_process(false)
	cycle.call("set_time_of_day", 0.0)
	await process_frame

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

	# A gameplay collider is present deliberately. Solar shadows must ignore it
	# and project only the alpha silhouette of the currently displayed frame.
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = 7.0
	collision.shape = circle
	target.add_child(collision)

	var shadow := SolarShadowScript.new() as Polygon2D
	target.add_child(shadow)
	var contact_hint := Vector2(0.0, 24.0)
	var config := {
		"enabled": true,
		"direction_degrees": -135.0,
		"stretch": 1.25,
		"mask_weight": 1.0,
	}
	shadow.call("configure", target, animated, config, contact_hint)
	await process_frame

	if shadow.polygon.size() != 4:
		failures.append("Active-frame solar projection did not create its four-point silhouette warp.")
	if str(shadow.get_meta("shadow_projection_mode", "")) != "ground_contact_silhouette":
		failures.append("Solar shadow did not use ground-contact active-frame projection.")
	if bool(shadow.get_meta("shadow_profile_uses_collision_footprint", true)):
		failures.append("Solar shadow incorrectly used the gameplay CollisionShape2D footprint.")
	if not bool(shadow.get_meta("shadow_profile_uses_active_frame_alpha", false)):
		failures.append("Solar shadow ignored the active animation frame alpha silhouette.")
	if not bool(shadow.get_meta("shadow_source_frame_isolated", false)):
		failures.append("Solar shadow sampled more than the current animation frame.")
	if str(shadow.get_meta("shadow_profile_id", "")) != "humanoid":
		failures.append("Player caster was not classified with the humanoid profile.")
	if _polygon_area(shadow.polygon) <= 50.0:
		failures.append("Active-frame solar projection collapsed into a line or tiny polygon.")

	var first_polygon := shadow.polygon.duplicate()
	var first_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2(INF, INF))
	var first_proxy := _shadow_proxy(shadow)
	var first_texture := first_proxy.texture if first_proxy != null else null
	if first_proxy == null or first_texture != frames.get_frame_texture("walk", 0):
		failures.append("Frame 0 was not isolated in the shared shadow compositor.")
	if not first_contact.is_finite():
		failures.append("Frame 0 did not publish a valid ground-contact point.")

	animated.frame = 1
	shadow.call("_refresh_silhouette")
	await process_frame
	var second_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2(INF, INF))
	var second_proxy := _shadow_proxy(shadow)
	if _polygons_match(first_polygon, shadow.polygon, 0.01):
		failures.append("Changing animation frames did not update the projected silhouette.")
	if first_contact.distance_to(second_contact) <= 0.01:
		failures.append("Changing animation frames did not update the alpha-derived contact point.")
	if first_texture == null or second_proxy == null or second_proxy.texture != frames.get_frame_texture("walk", 1):
		failures.append("Animation frame change did not replace the compositor with frame 1.")
	if int(shadow.get_meta("shadow_source_frame", -1)) != 1:
		failures.append("Canonical diagnostics did not advance to animation frame 1.")

	var frame_one_polygon := shadow.polygon.duplicate()
	var frame_one_contact := second_contact
	cycle.call("set_time_of_day", 0.58)
	shadow.call("configure", target, animated, config, contact_hint)
	await process_frame
	var rotated_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2(INF, INF))
	if rotated_contact.distance_to(frame_one_contact) > 0.01:
		failures.append("Rotating the sun detached the shadow from the active-frame ground contact.")
	if _polygons_match(frame_one_polygon, shadow.polygon, 0.01):
		failures.append("Rotating the sun did not rotate the active-frame projection.")
	var direction: Vector2 = shadow.get_meta("shadow_projection_direction", Vector2.ZERO)
	if direction.x <= 0.0 or direction.y >= 0.0:
		failures.append("Evening active-frame projection did not point upper-right.")

	target.queue_free()
	cycle.queue_free()
	await process_frame


func _validate_pinned_contact_transform() -> void:
	var target := Node2D.new()
	target.name = "NestedPinnedContactTest"
	target.position = Vector2(41.0, -23.0)
	target.rotation = deg_to_rad(9.0)
	target.scale = Vector2(1.08, 0.94)
	target.add_to_group("player")
	root.add_child(target)

	var cycle := DayNightCycleScript.new()
	root.add_child(cycle)
	cycle.set_process(false)
	cycle.call("set_time_of_day", 0.0)
	await process_frame

	var visual_rig := Node2D.new()
	visual_rig.position = Vector2(7.0, -9.0)
	visual_rig.rotation = deg_to_rad(17.0)
	visual_rig.scale = Vector2(1.35, 0.75)
	target.add_child(visual_rig)

	var sprite := Sprite2D.new()
	var image := Image.create(20, 30, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.centered = true
	sprite.offset = Vector2(3.0, -4.0)
	sprite.position = Vector2(-5.0, 6.0)
	sprite.rotation = deg_to_rad(-11.0)
	sprite.scale = Vector2(1.2, 0.8)
	visual_rig.add_child(sprite)

	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10.0, 6.0)
	collision.shape = rectangle
	target.add_child(collision)
	await process_frame

	var sprite_rect := sprite.get_rect()
	var local_bottom_center := Vector2(sprite_rect.get_center().x, sprite_rect.end.y)
	var expected_contact := target.to_local(sprite.to_global(local_bottom_center))
	var resolved_contact := DirectionalShadowRuntimeScript.estimate_target_foot_offset(target)
	if expected_contact.distance_to(resolved_contact) > 0.001:
		failures.append("Nested sprite contact ignored centered, offset or transform hierarchy.")

	var config := {
		"enabled": true,
		"direction_degrees": -135.0,
		"stretch": 1.0,
		"mask_weight": 1.0,
	}
	var visual_size := DirectionalShadowRuntimeScript.estimate_target_visual_size(target)
	var shadow := DirectionalShadowRuntimeScript.apply_to_target(target, config, visual_size, resolved_contact, sprite)
	await process_frame
	if shadow == null:
		failures.append("Pinned-contact transform test did not create a shadow.")
	else:
		var initial_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2(INF, INF))
		if initial_contact.distance_to(expected_contact) > 0.01:
			failures.append("Nested active-frame shadow was not aligned to the transformed sprite base.")
		if bool(shadow.get_meta("shadow_profile_uses_collision_footprint", true)):
			failures.append("Nested active-frame shadow incorrectly used the collision footprint.")
		var initial_polygon := shadow.polygon.duplicate()
		cycle.call("set_time_of_day", 0.58)
		shadow.call("configure", target, sprite, config, resolved_contact)
		await process_frame
		var rotated_contact: Vector2 = shadow.get_meta("shadow_projection_contact", Vector2(INF, INF))
		if rotated_contact.distance_to(expected_contact) > 0.01:
			failures.append("Rotating the sun moved the nested active-frame contact.")
		if _polygons_match(initial_polygon, shadow.polygon, 0.01):
			failures.append("Rotating the sun did not rotate the nested active-frame projection.")

	target.queue_free()
	cycle.queue_free()
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
		failures.append("Morning solar shadow is not fully visible after reset.")

	cycle.call("set_time_of_day", 0.46)
	var dusk_start_direction := cycle.call("get_sun_shadow_direction") as Vector2
	var dusk_start_strength := float(cycle.call("get_solar_shadow_strength"))
	cycle.call("set_time_of_day", 0.58)
	var moving_direction := cycle.call("get_sun_shadow_direction") as Vector2
	var moving_strength := float(cycle.call("get_solar_shadow_strength"))
	if dusk_start_strength <= moving_strength or moving_strength <= 0.0:
		failures.append("Solar shadow is not fading progressively during dusk.")
	if absf(dusk_start_direction.angle_to(moving_direction)) < deg_to_rad(4.0):
		failures.append("Solar shadow stopped moving before its fade completed.")

	cycle.call("set_time_of_day", 0.70)
	if float(cycle.call("get_solar_shadow_strength")) > 0.001:
		failures.append("Solar shadow remains visible in the hidden night reset window.")

	cycle.call("set_time_of_day", 0.90)
	var dawn_strength := float(cycle.call("get_solar_shadow_strength"))
	if dawn_strength <= 0.0 or dawn_strength >= 1.0:
		failures.append("Solar shadow is not fading in during dawn.")

	cycle.queue_free()
	await process_frame


func _validate_night_local_light_shadow() -> void:
	var cycle := DayNightCycleScript.new()
	root.add_child(cycle)
	cycle.set_process(false)
	cycle.call("set_time_of_day", 0.75)
	await process_frame

	var emitter := Node2D.new()
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
	sprite_image.fill(Color.WHITE)
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
				if bool(shadow.get_meta("shadow_projection_profiled", false)):
					failures.append("Night local shadow incorrectly switched to daylight footprint extrusion.")
				if _polygon_area(shadow.polygon) <= 50.0:
					failures.append("Night local shadow geometry collapsed.")
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
