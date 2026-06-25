extends RefCounted

var placeholder_texture: Texture2D


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
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		print("SpriteResolver: missing texture_path for sprite_id '%s'." % sprite_id)
		return get_placeholder_texture()

	var texture = load(texture_path)
	if texture is Texture2D:
		return texture

	print("SpriteResolver: texture_path is not a Texture2D for sprite_id '%s'." % sprite_id)
	return get_placeholder_texture()


func get_texture_for_item(item_id: String) -> Texture2D:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return get_placeholder_texture()

	var item_data: Dictionary = content_db.get_item(item_id)
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
	if placeholder_texture != null:
		return placeholder_texture

	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.16, 0.15, 0.18, 1.0))
	for y in range(16):
		for x in range(16):
			if x == y or x == 15 - y:
				image.set_pixel(x, y, Color(0.55, 0.52, 0.62, 1.0))

	placeholder_texture = ImageTexture.create_from_image(image)
	return placeholder_texture


func _get_content_db() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null

	return main_loop.root.get_node_or_null("ContentDB")
