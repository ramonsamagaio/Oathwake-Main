extends Node

var _owner: Node2D
var _sprite: AnimatedSprite2D
var _sprite_frames: SpriteFrames
var _direction_mode := "single"
var _visual_offset := Vector2.ZERO
var _fallback_nodes: Array = []
var _current_animation_name := ""
var _current_flip_h := false
var _current_flip_v := false
var _uses_scene_sprite := false


func configure(owner: Node2D, monster_data: Dictionary, animations_data: Dictionary, direction_mode: String, fallback_nodes: Array) -> void:
	_owner = owner
	_direction_mode = direction_mode if not direction_mode.is_empty() else "single"
	_fallback_nodes = fallback_nodes.duplicate()
	_ensure_sprite()
	if _sprite != null and _sprite.sprite_frames != null and not _sprite.sprite_frames.get_animation_names().is_empty():
		_sprite_frames = _sprite.sprite_frames
		_uses_scene_sprite = true
	else:
			_build_sprite_frames(animations_data)
		_uses_scene_sprite = false
	_apply_visual_config(monster_data)
	_set_fallback_visible(_sprite_frames == null or _sprite_frames.get_animation_names().is_empty())


func set_visual_offset(offset: Vector2) -> void:
	_visual_offset = offset
	if _sprite != null:
		_sprite.position = _visual_offset


func play_state(state: String, facing_direction: String) -> void:
	if _sprite == null or _sprite_frames == null:
		_set_fallback_visible(true)
		return

	var resolved := _resolve_animation_name(state, facing_direction)
	if str(resolved.get("name", "")).is_empty():
		if _sprite_frames.has_animation("idle"):
			resolved = {"name": "idle", "flip_h": false, "flip_v": false}
		else:
			_sprite.visible = true
			_set_fallback_visible(false)
			return

	_set_fallback_visible(false)
	_sprite.visible = true
	_sprite.position = _visual_offset
	_sprite.flip_h = bool(resolved.get("flip_h", false))
	_sprite.flip_v = bool(resolved.get("flip_v", false))

	var animation_name := str(resolved.get("name", ""))
	if animation_name != _current_animation_name or _sprite.animation != animation_name:
		_current_animation_name = animation_name
		_current_flip_h = _sprite.flip_h
		_current_flip_v = _sprite.flip_v
		_sprite.play(animation_name)
	elif _sprite.flip_h != _current_flip_h or _sprite.flip_v != _current_flip_v:
		_current_flip_h = _sprite.flip_h
		_current_flip_v = _sprite.flip_v


func _ensure_sprite() -> void:
	if _sprite != null:
		return
	if _owner != null:
		var existing := _owner.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if existing != null:
			_sprite = existing
			_sprite.centered = true
			_sprite.position = _visual_offset
			_sprite.z_index = 2
			return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "MonsterSprite"
	_sprite.centered = true
	_sprite.position = _visual_offset
	_sprite.z_index = 2
	_sprite.visible = false
	add_child(_sprite)


func _build_sprite_frames(animations_data: Dictionary) -> void:
	_sprite_frames = SpriteFrames.new()
	if animations_data.is_empty():
		_sprite.sprite_frames = _sprite_frames
		return

	for animation_name in animations_data.keys():
		var animation_def: Variant = animations_data[animation_name]
		if not animation_def is Dictionary:
			continue
		var frames := _build_animation_frames(animation_def)
		if frames.is_empty():
			continue
		_sprite_frames.add_animation(str(animation_name))
		_sprite_frames.set_animation_speed(str(animation_name), float(animation_def.get("fps", 6.0)))
		_sprite_frames.set_animation_loop(str(animation_name), bool(animation_def.get("loop", true)))
		for frame in frames:
			_sprite_frames.add_frame(str(animation_name), frame)

	_sprite.sprite_frames = _sprite_frames


func _build_animation_frames(animation_def: Dictionary) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var texture_path := str(animation_def.get("texture_path", ""))
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return frames

	var texture := ResourceLoader.load(texture_path) as Texture2D
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return frames

	var frame_width := int(animation_def.get("frame_width", 0))
	var frame_height := int(animation_def.get("frame_height", 0))
	if frame_width <= 0 or frame_height <= 0:
		frames.append(texture)
		return frames

	var texture_width := texture.get_width()
	var texture_height := texture.get_height()
	if frame_width > texture_width or frame_height > texture_height:
		frames.append(texture)
		return frames

	var total_frames := int(animation_def.get("frames", 0))
	if total_frames <= 0:
		total_frames = maxi(1, texture_width / frame_width)

	var frame_start := maxi(int(animation_def.get("frame_start", 0)), 0)
	var row := maxi(int(animation_def.get("row", 0)), 0)
	var y := row * frame_height
	if y + frame_height > texture_height:
		return frames
	for index in range(total_frames):
		var x := (frame_start + index) * frame_width
		if x + frame_width > texture_width:
			break
		var frame_texture := AtlasTexture.new()
		frame_texture.atlas = texture
		frame_texture.region = Rect2(x, y, frame_width, frame_height)
		frames.append(frame_texture)

	if frames.is_empty():
		frames.append(texture)
	return frames


func _resolve_animation_name(state: String, facing_direction: String) -> Dictionary:
	if _sprite_frames == null:
		return {}
	var candidates: Array = []
	candidates.append({"name": state, "flip_h": false, "flip_v": false})

	if _direction_mode == "4dir" and not facing_direction.is_empty() and facing_direction != "single":
		candidates.append({"name": "%s_%s" % [state, facing_direction], "flip_h": false, "flip_v": false})
		if facing_direction == "left":
			candidates.append({"name": "%s_right" % state, "flip_h": true, "flip_v": false})
		elif facing_direction == "right":
			candidates.append({"name": "%s_left" % state, "flip_h": true, "flip_v": false})
		elif facing_direction == "up":
			candidates.append({"name": "%s_up" % state, "flip_h": false, "flip_v": false})
		elif facing_direction == "down":
			candidates.append({"name": "%s_down" % state, "flip_h": false, "flip_v": false})

	for candidate in candidates:
		var animation_name := str(candidate.get("name", ""))
		if not animation_name.is_empty() and _sprite_frames.has_animation(animation_name):
			return candidate
	return {}


func _set_fallback_visible(visible_state: bool) -> void:
	for node in _fallback_nodes:
		if node is CanvasItem and is_instance_valid(node):
			(node as CanvasItem).visible = visible_state

func _apply_visual_config(monster_data: Dictionary) -> void:
	if _sprite == null:
		return
	var scale_value := maxf(float(monster_data.get("visual_scale", 1.0)), 0.01)
	_sprite.scale = Vector2.ONE * scale_value
	var offset_value: Variant = monster_data.get("visual_offset", {})
	if offset_value is Dictionary:
		_visual_offset = Vector2(float(offset_value.get("x", 0.0)), float(offset_value.get("y", 0.0)))
	_sprite.position = _visual_offset

func has_animation(animation_name: String) -> bool:
	return _sprite_frames != null and _sprite_frames.has_animation(animation_name)

func get_animation_duration(animation_name: String) -> float:
	if not has_animation(animation_name):
		return 0.0
	var fps := _sprite_frames.get_animation_speed(animation_name)
	return float(_sprite_frames.get_frame_count(animation_name)) / maxf(fps, 0.01)
