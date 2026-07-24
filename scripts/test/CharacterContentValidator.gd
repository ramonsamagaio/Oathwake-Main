extends SceneTree

const SPRITES_PATH := "res://data/sprites.json"
const ANIMATION_SETS_PATH := "res://data/animation_sets.json"
const CHARACTERS_PATH := "res://data/characters.json"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sprites := _load_dictionary(SPRITES_PATH)
	var animation_sets := _load_dictionary(ANIMATION_SETS_PATH)
	var characters := _load_dictionary(CHARACTERS_PATH)

	if failures.is_empty():
		_validate_sprite_records(sprites)
		_validate_animation_sets(sprites, animation_sets)
		_validate_characters(sprites, animation_sets, characters)

	if failures.is_empty():
		print("CHARACTER_CONTENT_VALIDATION_PASS")
		quit(0)
		return

	for failure in failures:
		push_error("CHARACTER_CONTENT_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _load_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		failures.append("Content file is missing: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		failures.append("Content file is not a valid JSON object: %s" % path)
		return {}
	return parsed as Dictionary


func _validate_sprite_records(sprites: Dictionary) -> void:
	for key in sprites.keys():
		var sprite_id := str(key)
		var value: Variant = sprites[key]
		if not (value is Dictionary):
			failures.append("Sprite %s is not a dictionary record." % sprite_id)
			continue
		var sprite := value as Dictionary
		var texture_path := str(sprite.get("texture_path", ""))
		if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
			failures.append("Sprite %s has no loadable texture: %s" % [sprite_id, texture_path])
			continue

		if str(sprite.get("type", "single_sprite")) != "sprite_sheet":
			continue
		var columns := int(sprite.get("columns", 0))
		var rows := int(sprite.get("rows", 0))
		var frame_width := int(sprite.get("frame_width", _frame_size_value(sprite, "w")))
		var frame_height := int(sprite.get("frame_height", _frame_size_value(sprite, "h")))
		var total_frames := int(sprite.get("total_frames", 0))
		if columns <= 0 or rows <= 0 or frame_width <= 0 or frame_height <= 0:
			failures.append("Sprite sheet %s has invalid grid or frame dimensions." % sprite_id)
			continue
		if total_frames <= 0 or total_frames > columns * rows:
			failures.append("Sprite sheet %s has invalid total_frames %d for a %dx%d grid." % [sprite_id, total_frames, columns, rows])

		var texture := load(texture_path) as Texture2D
		if texture == null:
			failures.append("Sprite sheet %s texture could not be loaded." % sprite_id)
			continue
		var required_width := columns * frame_width
		var required_height := rows * frame_height
		if texture.get_width() < required_width or texture.get_height() < required_height:
			failures.append(
				"Sprite sheet %s grid requires %dx%d pixels but texture is %dx%d." % [
					sprite_id,
					required_width,
					required_height,
					texture.get_width(),
					texture.get_height(),
				]
			)


func _validate_animation_sets(sprites: Dictionary, animation_sets: Dictionary) -> void:
	for key in animation_sets.keys():
		var animation_set_id := str(key)
		var value: Variant = animation_sets[key]
		if not (value is Dictionary):
			failures.append("Animation set %s is not a dictionary record." % animation_set_id)
			continue
		var animation_set := value as Dictionary
		var sprite_id := str(animation_set.get("sprite_sheet_id", ""))
		if not sprites.has(sprite_id) or not (sprites[sprite_id] is Dictionary):
			failures.append("Animation set %s references missing sprite %s." % [animation_set_id, sprite_id])
			continue
		var sprite := sprites[sprite_id] as Dictionary
		var total_frames := int(sprite.get("total_frames", 0))
		if total_frames <= 0:
			total_frames = int(sprite.get("columns", 1)) * int(sprite.get("rows", 1))
		var animations_value: Variant = animation_set.get("animations", {})
		if not (animations_value is Dictionary):
			failures.append("Animation set %s has no animation dictionary." % animation_set_id)
			continue
		var animations := animations_value as Dictionary
		for animation_key in animations.keys():
			var animation_name := str(animation_key)
			var animation_value: Variant = animations[animation_key]
			if not (animation_value is Dictionary):
				failures.append("Animation %s/%s is not a dictionary record." % [animation_set_id, animation_name])
				continue
			var frames_value: Variant = (animation_value as Dictionary).get("frames", [])
			if not (frames_value is Array):
				failures.append("Animation %s/%s has no frame array." % [animation_set_id, animation_name])
				continue
			for frame_value in frames_value as Array:
				var frame_index := int(frame_value)
				if frame_index < 0 or frame_index >= total_frames:
					failures.append(
						"Animation %s/%s uses frame %d outside 0..%d for sprite %s." % [
							animation_set_id,
							animation_name,
							frame_index,
							total_frames - 1,
							sprite_id,
						]
					)


func _validate_characters(sprites: Dictionary, animation_sets: Dictionary, characters: Dictionary) -> void:
	for key in characters.keys():
		var character_id := str(key)
		var value: Variant = characters[key]
		if not (value is Dictionary):
			failures.append("Character %s is not a dictionary record." % character_id)
			continue
		var character := value as Dictionary
		var sprite_id := str(character.get("sprite_sheet_id", ""))
		var animation_set_id := str(character.get("animation_set_id", ""))
		if not sprites.has(sprite_id):
			failures.append("Character %s references missing sprite %s." % [character_id, sprite_id])
		if not animation_sets.has(animation_set_id) or not (animation_sets[animation_set_id] is Dictionary):
			failures.append("Character %s references missing animation set %s." % [character_id, animation_set_id])
			continue
		var animation_sprite_id := str((animation_sets[animation_set_id] as Dictionary).get("sprite_sheet_id", ""))
		if animation_sprite_id != sprite_id:
			failures.append(
				"Character %s uses sprite %s but animation set %s uses %s." % [
					character_id,
					sprite_id,
					animation_set_id,
					animation_sprite_id,
				]
			)


func _frame_size_value(sprite: Dictionary, axis: String) -> int:
	var value: Variant = sprite.get("frame_size", {})
	if not (value is Dictionary):
		return 0
	return int((value as Dictionary).get(axis, 0))
