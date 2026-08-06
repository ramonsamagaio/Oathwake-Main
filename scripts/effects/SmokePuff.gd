@tool
extends Node2D

const SMOKE_SHEET_PATH := "res://assets/sprites/effects/FX/PUFFS/Free Smoke Fx  Pixel 07.png"
const FRAME_SIZE := Vector2i(64, 64)
const FRAME_COUNT := 16
const SHEET_ROW_INDEX := 10
const FACING_OPTIONS := ["left", "right"]

@export_group("Profile")
@export var use_content_db_profile: bool = true
@export var vfx_profile_id: String = "default"
@export var auto_play: bool = true
@export var auto_free_on_finish: bool = true

@export_group("Animation")
@export_range(1.0, 60.0, 0.5) var animation_fps := 28.0
@export_range(0.05, 4.0, 0.05) var puff_scale := 0.55
@export_range(-0.25, 0.25, 0.01) var horizontal_variation := 0.08
@export_enum("left", "right") var facing := "right"

@onready var puff_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_apply_profile()
	_build_animation()
	if Engine.is_editor_hint():
		return
	facing = _normalize_facing(facing)
	puff_sprite.flip_h = facing == "left"
	rotation = randf_range(-horizontal_variation, horizontal_variation)
	set_meta("dash_smoke_facing", facing)
	if auto_play and puff_sprite.sprite_frames != null and puff_sprite.sprite_frames.has_animation("dash_smoke"):
		puff_sprite.play("dash_smoke")


func setup_profile(profile_id: String) -> void:
	vfx_profile_id = profile_id if not profile_id.is_empty() else "default"
	_apply_profile()


func _apply_profile() -> void:
	if not use_content_db_profile:
		return
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile"):
		return
	var profile_id := vfx_profile_id if content_db.has_vfx_profile(vfx_profile_id) else "default"
	if not content_db.has_vfx_profile(profile_id):
		return
	var profile: Dictionary = content_db.get_vfx_profile(profile_id)
	puff_scale = float(profile.get("smoke_puff_scale", puff_scale)) * 0.46


func _build_animation() -> void:
	if puff_sprite == null or not ResourceLoader.exists(SMOKE_SHEET_PATH):
		return
	var texture := ResourceLoader.load(SMOKE_SHEET_PATH) as Texture2D
	if texture == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("dash_smoke")
	frames.set_animation_loop("dash_smoke", false)
	frames.set_animation_speed("dash_smoke", animation_fps)
	var y := SHEET_ROW_INDEX * FRAME_SIZE.y
	for frame_index in range(FRAME_COUNT):
		var x := frame_index * FRAME_SIZE.x
		if x + FRAME_SIZE.x > texture.get_width() or y + FRAME_SIZE.y > texture.get_height():
			break
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(x, y, FRAME_SIZE.x, FRAME_SIZE.y)
		frames.add_frame("dash_smoke", atlas)
	puff_sprite.sprite_frames = frames
	puff_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	puff_sprite.scale = Vector2.ONE * puff_scale
	var callback := Callable(self, "_on_animation_finished")
	if not puff_sprite.animation_finished.is_connected(callback):
		puff_sprite.animation_finished.connect(callback)


func _on_animation_finished() -> void:
	if auto_free_on_finish:
		queue_free()


func _normalize_facing(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	return normalized if normalized in FACING_OPTIONS else "right"


func get_frame_count() -> int:
	if puff_sprite == null or puff_sprite.sprite_frames == null or not puff_sprite.sprite_frames.has_animation("dash_smoke"):
		return 0
	return puff_sprite.sprite_frames.get_frame_count("dash_smoke")


func get_sheet_row_index() -> int:
	return SHEET_ROW_INDEX


func get_facing() -> String:
	return _normalize_facing(facing)
