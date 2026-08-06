extends RefCounted

const PLACEHOLDER_TEXTURE: Texture2D = preload("res://assets/generated/sprite_placeholder.svg")


func get_texture_for_sprite(sprite_id: String) -> Texture2D:
	if sprite_id.is_empty():
		return get_placeholder_texture()

	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_sprite"):
		return get_placeholder_texture()

	if not content_db.has_sprite(sprite_id):
		print("SpriteResolver: missing sprite_id '%s'." % sprite_id)
		return get_placeholder_texture()

	var sprite_data: Dictionary = content_db.get_sprite(sprite_id)
	var texture_path := str(sprite_data.get("texture_path", ""))
	return _load_texture_path(texture_path, "sprite_id '%s'" % sprite_id)


func get_texture_for_item(item_id: String) -> Texture2D:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return get_placeholder_texture()

	var item_data: Dictionary = content_db.get_item(item_id)
	var direct_texture_path := str(item_data.get("sprite_path", ""))
	if not direct_texture_path.is_empty():
		var direct_texture := _load_texture_path(direct_texture_path, "item_id '%s'" % item_id)
		return _apply_optional_region(direct_texture, item_data.get("sprite_region", {}))
	return get_texture_for_sprite(str(item_data.get("sprite_id", "")))


func get_texture_for_monster(monster_id: String) -> Texture2D:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_monster") or not content_db.has_monster(monster_id):
		return get_placeholder_texture()

	var monster_data: Dictionary = content_db.get_monster(monster_id)
	return get_texture_for_sprite(str(monster_data.get("sprite_id", "")))


func get_texture_for_resource(resource_id: String) -> Texture2D:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_resource") or not content_db.has_resource(resource_id):
		return get_placeholder_texture()

	var resource_data: Dictionary = content_db.get_resource(resource_id)
	return get_texture_for_sprite(str(resource_data.get("sprite_id", "")))


func get_texture_for_terrain_type(terrain_type_id: String) -> Texture2D:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_terrain_type") or not content_db.has_terrain_type(terrain_type_id):
		return get_placeholder_texture()

	var terrain_data: Dictionary = content_db.get_terrain_type(terrain_type_id)
	return get_texture_for_sprite(str(terrain_data.get("sprite_id", "")))


func get_texture_for_tileset(tileset_id: String) -> Texture2D:
	return get_texture_for_terrain_type(tileset_id)


func get_placeholder_texture() -> Texture2D:
	return PLACEHOLDER_TEXTURE if _is_usable_texture(PLACEHOLDER_TEXTURE) else null


func _load_texture_path(texture_path: String, context: String) -> Texture2D:
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		print("SpriteResolver: missing texture_path for %s." % context)
		return get_placeholder_texture()

	var loaded_resource = ResourceLoader.load(texture_path)
	if loaded_resource is Texture2D:
		var texture := loaded_resource as Texture2D
		if _is_usable_texture(texture):
			return texture
		print("SpriteResolver: zero-sized texture for %s at '%s'." % [context, texture_path])
		return get_placeholder_texture()

	print("SpriteResolver: texture_path is not a Texture2D for %s." % context)
	return get_placeholder_texture()


func _apply_optional_region(texture: Texture2D, region_value: Variant) -> Texture2D:
	if texture == null or not region_value is Dictionary:
		return texture
	var region := region_value as Dictionary
	var width := float(region.get("w", 0.0))
	var height := float(region.get("h", 0.0))
	if width <= 0.0 or height <= 0.0:
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(
		float(region.get("x", 0.0)),
		float(region.get("y", 0.0)),
		width,
		height
	)
	return atlas


func _is_usable_texture(texture: Texture2D) -> bool:
	return texture != null and texture.get_width() > 0 and texture.get_height() > 0


func _get_content_db() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null

	return main_loop.root.get_node_or_null("ContentDB")
