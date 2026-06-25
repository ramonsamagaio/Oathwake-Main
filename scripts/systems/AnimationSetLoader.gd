extends RefCounted


func load_for_character(character_id: String) -> SpriteFrames:
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("get_character"):
		push_warning("AnimationSetLoader could not find ContentDB.")
		return SpriteFrames.new()

	if content_db.has_method("has_character") and not content_db.has_character(character_id):
		push_warning("AnimationSetLoader could not find character: %s" % character_id)
		return SpriteFrames.new()

	var character_data: Dictionary = content_db.get_character(character_id)
	if character_data.is_empty():
		push_warning("AnimationSetLoader could not find character: %s" % character_id)
		return SpriteFrames.new()

	return load_from_animation_set_id(str(character_data.get("animation_set_id", "")))


func load_from_animation_set_id(animation_set_id: String) -> SpriteFrames:
	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	if animation_set_id.is_empty():
		push_warning("AnimationSetLoader received empty animation_set_id.")
		return sprite_frames

	var content_db := _get_content_db()
	if content_db == null:
		push_warning("AnimationSetLoader could not find ContentDB.")
		return sprite_frames

	if content_db.has_method("has_animation_set") and not content_db.has_animation_set(animation_set_id):
		push_warning("AnimationSetLoader could not find animation_set_id: %s" % animation_set_id)
		return sprite_frames

	var animation_set_data: Dictionary = content_db.get_animation_set(animation_set_id)
	if animation_set_data.is_empty():
		push_warning("AnimationSetLoader could not find animation_set_id: %s" % animation_set_id)
		return sprite_frames

	var sprite_sheet_id := str(animation_set_data.get("sprite_sheet_id", ""))
	if content_db.has_method("has_sprite") and not content_db.has_sprite(sprite_sheet_id):
		push_warning("AnimationSetLoader could not find sprite_sheet_id: %s" % sprite_sheet_id)
		return sprite_frames

	var sprite_sheet_data: Dictionary = content_db.get_sprite(sprite_sheet_id)
	if sprite_sheet_data.is_empty():
		push_warning("AnimationSetLoader could not find sprite_sheet_id: %s" % sprite_sheet_id)
		return sprite_frames

	var texture := _load_sheet_texture(sprite_sheet_data)
	if texture == null:
		return sprite_frames

	var animations = animation_set_data.get("animations", {})
	if not animations is Dictionary:
		return sprite_frames

	for animation_name in animations.keys():
		var animation_data = animations[animation_name]
		if not animation_data is Dictionary:
			continue

		_add_animation_if_valid(sprite_frames, str(animation_name), animation_data, sprite_sheet_data, texture)

	return sprite_frames


func _add_animation_if_valid(sprite_frames: SpriteFrames, animation_name: String, animation_data: Dictionary, sprite_sheet_data: Dictionary, texture: Texture2D) -> void:
	var valid_frames := _get_valid_frame_indices(animation_data, sprite_sheet_data)
	if valid_frames.is_empty():
		return

	sprite_frames.add_animation(animation_name)
	sprite_frames.set_animation_speed(animation_name, max(float(animation_data.get("fps", 1.0)), 0.01))
	sprite_frames.set_animation_loop(animation_name, bool(animation_data.get("loop", true)))

	for frame_index in valid_frames:
		sprite_frames.add_frame(animation_name, _make_frame_texture(frame_index, sprite_sheet_data, texture))


func _get_valid_frame_indices(animation_data: Dictionary, sprite_sheet_data: Dictionary) -> Array:
	var frames = animation_data.get("frames", [])
	if not frames is Array:
		return []

	var total_frames := int(sprite_sheet_data.get("total_frames", 0))
	if total_frames < 1:
		total_frames = int(sprite_sheet_data.get("columns", 0)) * int(sprite_sheet_data.get("rows", 0))

	var valid_frames := []
	for frame in frames:
		var frame_index := int(frame)
		if frame_index < 0 or frame_index >= total_frames:
			continue

		valid_frames.append(frame_index)

	return valid_frames


func _make_frame_texture(frame_index: int, sprite_sheet_data: Dictionary, texture: Texture2D) -> Texture2D:
	var columns := int(sprite_sheet_data.get("columns", 0))
	var frame_width := int(sprite_sheet_data.get("frame_width", 0))
	var frame_height := int(sprite_sheet_data.get("frame_height", 0))
	if columns < 1 or frame_width < 1 or frame_height < 1:
		return texture

	var column := frame_index % columns
	var row := int(frame_index / columns)
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = Rect2(column * frame_width, row * frame_height, frame_width, frame_height)
	return atlas_texture


func _load_sheet_texture(sprite_sheet_data: Dictionary) -> Texture2D:
	var texture_path := str(sprite_sheet_data.get("texture_path", ""))
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		push_warning("AnimationSetLoader found invalid texture_path: %s" % texture_path)
		return null

	var texture = load(texture_path)
	if texture is Texture2D:
		return texture

	push_warning("AnimationSetLoader texture_path is not a Texture2D: %s" % texture_path)
	return null


func _get_content_db() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null

	return main_loop.root.get_node_or_null("ContentDB")
