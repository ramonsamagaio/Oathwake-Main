class_name HitFlashOverlay
extends RefCounted

static var _white_shader: Shader


static func flash_node(target: Node, duration := 0.08) -> void:
	if target == null or duration <= 0.0:
		return
	_flash_recursive(target, duration)


static func _flash_recursive(node: Node, duration: float) -> void:
	for child in node.get_children():
		if child is AnimatedSprite2D:
			_flash_animated_sprite(child as AnimatedSprite2D, duration)
		elif child is Sprite2D:
			_flash_sprite(child as Sprite2D, duration)
		elif child is Polygon2D:
			_flash_polygon(child as Polygon2D, duration)
		_flash_recursive(child, duration)


static func _flash_animated_sprite(source: AnimatedSprite2D, duration: float) -> void:
	if not source.visible or source.sprite_frames == null:
		return
	if _should_skip(source):
		return
	var texture := source.sprite_frames.get_frame_texture(source.animation, source.frame)
	if texture == null:
		return
	var overlay := Sprite2D.new()
	overlay.name = "HitFlashOverlay"
	overlay.texture = texture
	overlay.centered = source.centered
	overlay.offset = source.offset
	overlay.position = source.position
	overlay.rotation = source.rotation
	overlay.scale = source.scale
	overlay.skew = source.skew
	overlay.flip_h = source.flip_h
	overlay.flip_v = source.flip_v
	overlay.z_index = source.z_index + 100
	overlay.texture_filter = source.texture_filter
	_add_and_fade(source, overlay, duration)


static func _flash_sprite(source: Sprite2D, duration: float) -> void:
	if not source.visible or source.texture == null:
		return
	if _should_skip(source):
		return
	var overlay := Sprite2D.new()
	overlay.name = "HitFlashOverlay"
	overlay.texture = source.texture
	overlay.centered = source.centered
	overlay.offset = source.offset
	overlay.position = source.position
	overlay.rotation = source.rotation
	overlay.scale = source.scale
	overlay.skew = source.skew
	overlay.flip_h = source.flip_h
	overlay.flip_v = source.flip_v
	overlay.region_enabled = source.region_enabled
	overlay.region_rect = source.region_rect
	overlay.z_index = source.z_index + 100
	overlay.texture_filter = source.texture_filter
	_add_and_fade(source, overlay, duration)


static func _flash_polygon(source: Polygon2D, duration: float) -> void:
	if not source.visible or source.polygon.is_empty():
		return
	if _should_skip(source):
		return
	var overlay := Polygon2D.new()
	overlay.name = "HitFlashOverlay"
	overlay.polygon = source.polygon
	overlay.uv = source.uv
	overlay.texture = source.texture
	overlay.position = source.position
	overlay.rotation = source.rotation
	overlay.scale = source.scale
	overlay.skew = source.skew
	overlay.z_index = source.z_index + 100
	overlay.color = Color.WHITE
	_add_and_fade(source, overlay, duration, false)


static func _add_and_fade(source: CanvasItem, overlay: CanvasItem, duration: float, use_shader := true) -> void:
	var parent := source.get_parent()
	if parent == null:
		return
	parent.add_child(overlay)
	if use_shader:
		var material := ShaderMaterial.new()
		material.shader = _get_white_shader()
		overlay.material = material
	overlay.modulate = Color.WHITE
	var tween := overlay.create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(overlay.queue_free)


static func _get_white_shader() -> Shader:
	if _white_shader == null:
		_white_shader = Shader.new()
		_white_shader.code = "shader_type canvas_item;\nvoid fragment(){ vec4 tex = texture(TEXTURE, UV); COLOR = vec4(vec3(1.0), tex.a * COLOR.a); }"
	return _white_shader


static func _should_skip(item: CanvasItem) -> bool:
	var clean_name := str(item.name).to_lower()
	return clean_name.contains("shadow") or clean_name.contains("glow") or clean_name.contains("flashoverlay")
