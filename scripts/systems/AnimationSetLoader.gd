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

	_publish_animation_anchor(sprite_frames, animation_set_data)
	var fallback_sprite_sheet_id := str(animation_set_data.get("sprite_sheet_id", ""))
	var animations_value: Variant = animation_set_data.get("animations", {})
	if not (animations_value is Dictionary):
		return sprite_frames

	var sheet_cache: Dictionary = {}
	for animation_key in (animations_value as Dictionary).keys():
		var animation_name := str(animation_key)
		var animation_value: Variant = (animations_value as Dictionary)[animation_key]
		if not (animation_value is Dictionary):
			continue

		var animation_data := animation_value as Dictionary
		var sprite_sheet_id := str(animation_data.get("sprite_sheet_id", fallback_sprite_sheet_id))
		var sheet_bundle := _get_sheet_bundle(content_db, sprite_sheet_id, sheet_cache)
		if sheet_bundle.is_empty():
			push_warning("AnimationSetLoader skipped %s because sprite sheet %s is invalid." % [animation_name, sprite_sheet_id])
			continue

		_add_animation_if_valid(
			sprite_frames,
			animation_name,
			animation_data,
			sheet_bundle.get("data", {}) as Dictionary,
			sheet_bundle.get("texture") as Texture2D
		)

	return sprite_frames


func _publish_animation_anchor(sprite_frames: SpriteFrames, animation_set_data: Dictionary) -> void:
	var anchor_value: Variant = animation_set_data.get("anchor", {})
	if not anchor_value is Dictionary:
		return
	var anchor_data := anchor_value as Dictionary
	var anchor := Vector2(
		float(anchor_data.get("x", 0.0)),
		float(anchor_data.get("y", 0.0))
	)
	if not anchor.is_finite():
		return
	# The Content Editor stores anchors in frame-pixel space from the top-left.
	# Publishing it on SpriteFrames lets every AnimatedSprite2D use the exact same
	# feet/base pivot without inspecting transparent padding at runtime.
	sprite_frames.set_meta("shadow_ground_anchor", anchor)
	sprite_frames.set_meta("animation_anchor", anchor)


func _get_sheet_bundle(content_db: Node, sprite_sheet_id: String, cache: Dictionary) -> Dictionary:
	if sprite_sheet_id.is_empty():
		return {}
	if cache.has(sprite_sheet_id):
		var cached: Variant = cache[sprite_sheet_id]
		return cached as Dictionary if cached is Dictionary else {}
	if content_db.has_method("has_sprite") and not content_db.has_sprite(sprite_sheet_id):
		cache[sprite_sheet_id] = {}
		return {}

	var sprite_sheet_data: Dictionary = content_db.get_sprite(sprite_sheet_id)
	if sprite_sheet_data.is_empty():
		cache[sprite_sheet_id] = {}
		return {}
	var texture := _load_sheet_texture(sprite_sheet_data)
	if texture == null:
		cache[sprite_sheet_id] = {}
		return {}

	var bundle := {
		"data": sprite_sheet_data,
		"texture": texture,
	}
	cache[sprite_sheet_id] = bundle
	return bundle


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
	var frames_value: Variant = animation_data.get("frames", [])
	if not (frames_value is Array):
		return []

	var total_frames := int(sprite_sheet_data.get("total_frames", 0))
	if total_frames < 1:
		total_frames = int(sprite_sheet_data.get("columns", 0)) * int(sprite_sheet_data.get("rows", 0))

	var valid_frames := []
	for frame_value in frames_value as Array:
		var frame_index := int(frame_value)
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
