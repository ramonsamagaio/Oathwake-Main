extends Node2D

const PARRY_SHEET_PATH := "res://assets/sprites/effects/FX/IMPACTS/parry.png"
const FRAME_SIZE := Vector2i(64, 64)
const FRAME_COUNT := 9
const SHEET_ROW_INDEX := 4

@export_range(1.0, 60.0, 0.5) var animation_fps := 24.0
@export_range(0.1, 4.0, 0.05) var visual_scale := 0.85

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_build_animation()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("parry"):
		sprite.play("parry")
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 1.08, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_animation() -> void:
	if sprite == null or not ResourceLoader.exists(PARRY_SHEET_PATH):
		return
	var texture := ResourceLoader.load(PARRY_SHEET_PATH) as Texture2D
	if texture == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("parry")
	frames.set_animation_loop("parry", false)
	frames.set_animation_speed("parry", animation_fps)
	var y := SHEET_ROW_INDEX * FRAME_SIZE.y
	for frame_index in range(FRAME_COUNT):
		var x := frame_index * FRAME_SIZE.x
		if x + FRAME_SIZE.x > texture.get_width() or y + FRAME_SIZE.y > texture.get_height():
			break
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(x, y, FRAME_SIZE.x, FRAME_SIZE.y)
		frames.add_frame("parry", atlas)
	sprite.sprite_frames = frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * visual_scale
	var callback := Callable(self, "_on_animation_finished")
	if not sprite.animation_finished.is_connected(callback):
		sprite.animation_finished.connect(callback)


func _on_animation_finished() -> void:
	queue_free()


func get_frame_count() -> int:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation("parry"):
		return 0
	return sprite.sprite_frames.get_frame_count("parry")


func get_sheet_row_index() -> int:
	return SHEET_ROW_INDEX
