extends AnimatedSprite2D

const FRAME_SIZE := Vector2i(16, 32)
const FRAME_COUNT := 8
const ANIMATION_NAME := "burn"
const FRAME_RATE := 10.0
const FLAME_SHEET_PATH := "res://assets/sprites/effects/fire/campfire_fire_sheet.png"


func _ready() -> void:
	configure_from_sheet()


func configure_from_sheet() -> bool:
	if not ResourceLoader.exists(FLAME_SHEET_PATH):
		visible = false
		return false
	var texture := ResourceLoader.load(FLAME_SHEET_PATH) as Texture2D
	if texture == null:
		visible = false
		return false
	var frames := SpriteFrames.new()
	frames.add_animation(ANIMATION_NAME)
	frames.set_animation_loop(ANIMATION_NAME, true)
	frames.set_animation_speed(ANIMATION_NAME, FRAME_RATE)
	for index in range(FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(Vector2(index * FRAME_SIZE.x, 0), Vector2(FRAME_SIZE))
		frames.add_frame(ANIMATION_NAME, atlas)
	sprite_frames = frames
	animation = ANIMATION_NAME
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true
	visible = true
	play(ANIMATION_NAME)
	return true


func get_authored_frame_count() -> int:
	if sprite_frames == null or not sprite_frames.has_animation(ANIMATION_NAME):
		return 0
	return sprite_frames.get_frame_count(ANIMATION_NAME)
