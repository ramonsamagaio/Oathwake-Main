## Data-driven visual fallback used when a monster has no custom scene_path.
extends "res://scripts/enemies/EnemyBase.gd"

const AnimationSetLoaderScript := preload("res://scripts/systems/AnimationSetLoader.gd")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _load_monster_data() -> void:
	super._load_monster_data()
	_apply_content_visual()


func _apply_content_visual() -> void:
	if animated_sprite == null or monster_data.is_empty():
		return
	var animation_set_id := str(monster_data.get("animation_set_id", ""))
	if not animation_set_id.is_empty():
		var frames := AnimationSetLoaderScript.new().load_from_animation_set_id(animation_set_id)
		if not frames.get_animation_names().is_empty():
			animated_sprite.sprite_frames = frames
			return

	var sprite_id := str(monster_data.get("sprite_id", ""))
	if sprite_id.is_empty():
		return
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_sprite") or not content_db.has_sprite(sprite_id):
		push_warning("GenericMonster could not find sprite_id: %s" % sprite_id)
		return
	var sprite_data: Dictionary = content_db.get_sprite(sprite_id)
	var texture_path := str(sprite_data.get("texture_path", ""))
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		push_warning("GenericMonster has an invalid sprite texture: %s" % texture_path)
		return
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _get_sprite_texture(texture, sprite_data))
	animated_sprite.sprite_frames = frames


func _get_sprite_texture(texture: Texture2D, sprite_data: Dictionary) -> Texture2D:
	if not bool(sprite_data.get("region_enabled", false)):
		return texture
	var region_data: Variant = sprite_data.get("region", {})
	if not region_data is Dictionary:
		return texture
	var region := Rect2(
		float(region_data.get("x", 0.0)),
		float(region_data.get("y", 0.0)),
		float(region_data.get("w", texture.get_width())),
		float(region_data.get("h", texture.get_height()))
	)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	return atlas
