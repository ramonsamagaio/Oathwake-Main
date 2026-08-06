extends Node2D

const STUN_FRAME_PATHS := [
	"res://assets/sprites/effects/FX/CONDITIONS/STUN/STUN_0001.png",
	"res://assets/sprites/effects/FX/CONDITIONS/STUN/STUN_0002.png",
	"res://assets/sprites/effects/FX/CONDITIONS/STUN/STUN_0003.png",
	"res://assets/sprites/effects/FX/CONDITIONS/STUN/STUN_0004.png",
	"res://assets/sprites/effects/FX/CONDITIONS/STUN/STUN_0005.png",
	"res://assets/sprites/effects/FX/CONDITIONS/STUN/STUN_0006.png",
	"res://assets/sprites/effects/FX/CONDITIONS/STUN/STUN_0007.png",
]

@export_range(1.0, 30.0, 0.5) var animation_fps := 10.0
@export var head_offset := Vector2(0.0, -42.0)
@export_range(0.1, 4.0, 0.05) var visual_scale := 0.55

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	position = head_offset
	_build_animation()


func _build_animation() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("stun")
	frames.set_animation_loop("stun", true)
	frames.set_animation_speed("stun", animation_fps)
	for frame_path in STUN_FRAME_PATHS:
		if not ResourceLoader.exists(frame_path):
			continue
		var texture := ResourceLoader.load(frame_path) as Texture2D
		if texture != null:
			frames.add_frame("stun", texture)
	sprite.sprite_frames = frames
	sprite.scale = Vector2.ONE * visual_scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if frames.get_frame_count("stun") > 0:
		sprite.play("stun")


func get_frame_count() -> int:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation("stun"):
		return 0
	return sprite.sprite_frames.get_frame_count("stun")
