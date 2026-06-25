extends RefCounted

var animated_sprite: AnimatedSprite2D
var last_valid_animation := ""
var last_requested_animation := ""
var warned_requests := {}


func setup(sprite: AnimatedSprite2D) -> void:
	animated_sprite = sprite


func play_if_available(animation_name: String) -> bool:
	last_requested_animation = animation_name
	if animated_sprite == null:
		_warn_once(animation_name, "Missing AnimatedSprite2D. Holding last valid frame.")
		return false

	var sprite_frames := animated_sprite.sprite_frames
	if sprite_frames == null:
		_warn_once(animation_name, "Missing SpriteFrames. Holding last valid frame.")
		return false

	if not sprite_frames.has_animation(animation_name):
		_warn_once(animation_name, "Missing animation: %s. Holding last valid frame." % animation_name)
		return false

	if sprite_frames.get_frame_count(animation_name) < 1:
		_warn_once(animation_name, "Animation has no frames: %s. Holding last valid frame." % animation_name)
		return false

	if animated_sprite.animation == animation_name and animated_sprite.is_playing():
		last_valid_animation = animation_name
		return true

	animated_sprite.play(animation_name)
	last_valid_animation = animation_name
	return true


func has_any_valid_animation() -> bool:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false

	for animation_name in animated_sprite.sprite_frames.get_animation_names():
		if animated_sprite.sprite_frames.get_frame_count(animation_name) > 0:
			return true

	return false


func _warn_once(key: String, message: String) -> void:
	if warned_requests.has(key):
		return

	warned_requests[key] = true
	print(message)
