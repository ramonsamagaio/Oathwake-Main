extends SceneTree

const SHADOW_SCRIPT := preload("res://scripts/effects/ProjectedSpriteShadow.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_sprite_frame_crop()
	await _validate_animated_frame_switch()
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
	if opaque_rect.size != Vector2i(9, 9):
		failures.append("Sprite frame alpha crop did not isolate the first frame silhouette: %s" % opaque_rect)
	if shadow.texture == texture:
		failures.append("Sprite shadow did not resolve the active hframes region.")
	target.queue_free()
	await process_frame


func _validate_animated_frame_switch() -> void:
	var frame_a_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	frame_a_image.fill(Color.TRANSPARENT)
	for y in range(8, 15):
		for x in range(2, 7):
			frame_a_image.set_pixel(x, y, Color.WHITE)
	var frame_b_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	frame_b_image.fill(Color.TRANSPARENT)
	for y in range(4, 15):
		for x in range(9, 15):
			frame_b_image.set_pixel(x, y, Color.WHITE)
	var frames := SpriteFrames.new()
	frames.add_animation("walk")
	frames.add_frame("walk", ImageTexture.create_from_image(frame_a_image))
	frames.add_frame("walk", ImageTexture.create_from_image(frame_b_image))
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
	sprite.frame = 1
	await process_frame
	var second_rect: Rect2i = shadow.get_meta("shadow_opaque_rect", Rect2i())
	if first_rect == second_rect:
		failures.append("Animated shadow did not change with the active frame.")
	if int(shadow.get_meta("shadow_source_frame", -1)) != 1:
		failures.append("Animated shadow metadata does not track the active frame.")
	target.queue_free()
	await process_frame
