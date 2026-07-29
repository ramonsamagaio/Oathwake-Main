extends SceneTree

const SHADOW_SCRIPT := preload("res://scripts/effects/ProjectedSpriteShadow.gd")
const SHADOW_RUNTIME := preload("res://scripts/effects/DirectionalShadowRuntime.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_sprite_frame_crop()
	await _validate_animated_frame_switch()
	await _validate_runtime_source_choice()
	if failures.is_empty():
		print("PROJECTED_SHADOW_FRAME_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PROJECTED_SHADOW_FRAME_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_sprite_frame_crop() -> void:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(4, 13):
		for x in range(6, 15):
			image.set_pixel(x, y, Color.WHITE)
	for y in range(2, 11):
		for x in range(20, 29):
			image.set_pixel(x, y, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var target := Node2D.new()
	root.add_child(target)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = 2
	sprite.frame = 0
	target.add_child(sprite)
	var shadow := SHADOW_SCRIPT.new()
	target.add_child(shadow)
	shadow.configure(target, sprite, {"enabled": true}, Vector2(0, 8))
	await process_frame
	var opaque_rect: Rect2i = shadow.get_meta("shadow_opaque_rect", Rect2i())
	if opaque_rect != Rect2i(Vector2i(6, 4), Vector2i(9, 9)):
		failures.append("Frame 0 alpha bounds are incorrect: %s" % opaque_rect)
	if shadow.texture == texture:
		failures.append("Frame 0 still uses the complete texture.")
	if shadow.polygon.size() == 4:
		var bottom_right := shadow.transform * shadow.polygon[2]
		var bottom_left := shadow.transform * shadow.polygon[3]
		if bottom_left.distance_to(Vector2(-2.0, 5.0)) > 0.001 or bottom_right.distance_to(Vector2(7.0, 5.0)) > 0.001:
			failures.append("Projected contact edge is detached: %s / %s" % [bottom_left, bottom_right])
	else:
		failures.append("Projected shadow polygon is invalid.")
	if not is_zero_approx(shadow.rotation) or shadow.scale != Vector2.ONE:
		failures.append("Projected shadow still rotates the complete quad.")
	sprite.frame = 1
	await process_frame
	var second_rect: Rect2i = shadow.get_meta("shadow_opaque_rect", Rect2i())
	if second_rect != Rect2i(Vector2i(4, 2), Vector2i(9, 9)):
		failures.append("Frame 1 alpha bounds are incorrect: %s" % second_rect)
	if int(shadow.get_meta("shadow_source_frame", -1)) != 1:
		failures.append("Sprite frame metadata did not advance.")
	target.queue_free()
	await process_frame


func _validate_animated_frame_switch() -> void:
	var first_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	first_image.fill(Color.TRANSPARENT)
	for y in range(8, 15):
		for x in range(2, 7):
			first_image.set_pixel(x, y, Color.WHITE)
	var second_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	second_image.fill(Color.TRANSPARENT)
	for y in range(4, 15):
		for x in range(9, 15):
			second_image.set_pixel(x, y, Color.WHITE)
	var first_texture := ImageTexture.create_from_image(first_image)
	var second_texture := ImageTexture.create_from_image(second_image)
	var frames := SpriteFrames.new()
	frames.add_animation("walk")
	frames.add_frame("walk", first_texture)
	frames.add_frame("walk", second_texture)
	var target := Node2D.new()
	root.add_child(target)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = "walk"
	sprite.frame = 0
	target.add_child(sprite)
	var shadow := SHADOW_SCRIPT.new()
	target.add_child(shadow)
	shadow.configure(target, sprite, {"enabled": true}, Vector2(0, 8))
	await process_frame
	var first_rect: Rect2i = shadow.get_meta("shadow_opaque_rect", Rect2i())
	if shadow.texture != first_texture:
		failures.append("Animated frame 0 texture was not selected.")
	sprite.frame = 1
	await process_frame
	var second_rect: Rect2i = shadow.get_meta("shadow_opaque_rect", Rect2i())
	if first_rect == second_rect or shadow.texture != second_texture:
		failures.append("Animated frame 1 was not reflected by the shadow.")
	if int(shadow.get_meta("shadow_source_frame", -1)) != 1:
		failures.append("Animated frame metadata did not advance.")
	target.queue_free()
	await process_frame


func _validate_runtime_source_choice() -> void:
	var sheet_image := Image.create(128, 16, false, Image.FORMAT_RGBA8)
	sheet_image.fill(Color.WHITE)
	var sheet_texture := ImageTexture.create_from_image(sheet_image)
	var frame_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	frame_image.fill(Color.TRANSPARENT)
	for y in range(5, 15):
		for x in range(5, 11):
			frame_image.set_pixel(x, y, Color.WHITE)
	var frame_texture := ImageTexture.create_from_image(frame_image)
	var frames := SpriteFrames.new()
	frames.add_animation("walk")
	frames.add_frame("walk", frame_texture)
	var target := Node2D.new()
	root.add_child(target)
	var sheet_sprite := Sprite2D.new()
	sheet_sprite.texture = sheet_texture
	target.add_child(sheet_sprite)
	var animated := AnimatedSprite2D.new()
	animated.sprite_frames = frames
	animated.animation = "walk"
	target.add_child(animated)
	var shadow := SHADOW_RUNTIME.apply_to_target(target, {"enabled": true})
	await process_frame
	if shadow == null or shadow.texture != frame_texture:
		failures.append("Runtime selected a sprite sheet instead of the active animation frame.")
	elif str(shadow.get_meta("shadow_source_kind", "")) != "AnimatedSprite2D":
		failures.append("Runtime source kind is not AnimatedSprite2D.")
	target.queue_free()
	await process_frame
