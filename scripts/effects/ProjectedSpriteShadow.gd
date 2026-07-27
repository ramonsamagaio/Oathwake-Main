class_name ProjectedSpriteShadow
extends Polygon2D

var _target: Node2D
var _source: CanvasItem
var _config: Dictionary = {}
var _foot_offset := Vector2.ZERO


func configure(target: Node2D, source: CanvasItem, config: Dictionary, foot_offset: Vector2) -> void:
	_target = target
	_source = source
	_config = config.duplicate(true)
	_foot_offset = foot_offset
	name = "GroundShadow"
	show_behind_parent = true
	z_as_relative = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_meta("directional_shadow", true)
	if not is_in_group("persistent_content_visual"):
		add_to_group("persistent_content_visual")
	_apply_projection_settings()
	_refresh_silhouette()
	set_process(true)


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _source == null or not is_instance_valid(_source):
		visible = false
		return
	_refresh_silhouette()


func _apply_projection_settings() -> void:
	var live_global := _get_live_global_config()
	var direction_degrees := float(live_global.get("direction_degrees", _config.get("direction_degrees", -45.0)))
	var stretch_amount := maxf(float(live_global.get("stretch", _config.get("stretch", 1.15))), 0.05)
	var opacity := clampf(float(live_global.get("opacity", _config.get("opacity", 0.30))), 0.0, 1.0)
	var shadow_color := _color_from_value(live_global.get("color", _config.get("color", "#050609FF")), Color(0.02, 0.024, 0.035, 1.0))
	var offset := _vector_from_value(_config.get("offset", {}), Vector2.ZERO)

	# The source silhouette points upward from its feet. Rotating that local UP
	# vector toward the requested screen-space angle lays the sprite on the ground.
	rotation = deg_to_rad(direction_degrees) - Vector2.UP.angle()
	scale = Vector2(1.0, stretch_amount)
	position = _foot_offset + offset
	color = Color(shadow_color.r, shadow_color.g, shadow_color.b, opacity * shadow_color.a)
	self_modulate = Color.WHITE
	z_index = int(_config.get("z_index", -1))
	visible = bool(_config.get("enabled", true)) and bool(live_global.get("enabled", true)) and opacity > 0.001
	set_meta("shadow_direction_degrees", direction_degrees)
	set_meta("shadow_stretch", stretch_amount)
	set_meta("shadow_opacity", opacity)


func _refresh_silhouette() -> void:
	_apply_projection_settings()
	if not visible:
		return
	if _source is AnimatedSprite2D:
		_apply_animated_sprite(_source as AnimatedSprite2D)
	elif _source is Sprite2D:
		_apply_sprite(_source as Sprite2D)
	elif _source is Polygon2D:
		_apply_polygon(_source as Polygon2D)
	else:
		texture = null
		uv = PackedVector2Array()
		polygon = PackedVector2Array()


func _apply_animated_sprite(source: AnimatedSprite2D) -> void:
	if source.sprite_frames == null or not source.sprite_frames.has_animation(source.animation):
		_clear_visual()
		return
	var frame_count := source.sprite_frames.get_frame_count(source.animation)
	if frame_count <= 0:
		_clear_visual()
		return
	var frame_index := clampi(source.frame, 0, frame_count - 1)
	var frame_texture := source.sprite_frames.get_frame_texture(source.animation, frame_index)
	if frame_texture == null:
		_clear_visual()
		return
	_apply_texture_rect(
		frame_texture,
		frame_texture.get_size(),
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)


func _apply_sprite(source: Sprite2D) -> void:
	var frame_texture := _resolve_sprite_texture(source)
	if frame_texture == null:
		_clear_visual()
		return
	_apply_texture_rect(
		frame_texture,
		frame_texture.get_size(),
		source.centered,
		source.offset,
		source.flip_h,
		source.flip_v,
		_source_to_target_transform(source)
	)


func _apply_texture_rect(
	frame_texture: Texture2D,
	frame_size: Vector2,
	centered: bool,
	offset: Vector2,
	flip_h: bool,
	flip_v: bool,
	relative_transform: Transform2D
) -> void:
	texture = frame_texture
	var top_left := offset
	if centered:
		top_left -= frame_size * 0.5
	var local_corners := PackedVector2Array([
		top_left,
		top_left + Vector2(frame_size.x, 0.0),
		top_left + frame_size,
		top_left + Vector2(0.0, frame_size.y),
	])
	var projected := PackedVector2Array()
	for point in local_corners:
		projected.append((relative_transform * point) - _foot_offset)
	polygon = projected

	var left_u := frame_size.x if flip_h else 0.0
	var right_u := 0.0 if flip_h else frame_size.x
	var top_v := frame_size.y if flip_v else 0.0
	var bottom_v := 0.0 if flip_v else frame_size.y
	uv = PackedVector2Array([
		Vector2(left_u, top_v),
		Vector2(right_u, top_v),
		Vector2(right_u, bottom_v),
		Vector2(left_u, bottom_v),
	])


func _apply_polygon(source: Polygon2D) -> void:
	texture = source.texture
	var relative_transform := _source_to_target_transform(source)
	var projected := PackedVector2Array()
	for point in source.polygon:
		projected.append((relative_transform * point) - _foot_offset)
	polygon = projected
	uv = source.uv


func _source_to_target_transform(source: Node2D) -> Transform2D:
	if _target == null or source == null:
		return Transform2D.IDENTITY
	if source == _target:
		return Transform2D.IDENTITY
	return _target.global_transform.affine_inverse() * source.global_transform


func _resolve_sprite_texture(source: Sprite2D) -> Texture2D:
	if source.texture == null:
		return null
	var needs_atlas := source.region_enabled or source.hframes > 1 or source.vframes > 1
	if not needs_atlas:
		return source.texture
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = source.texture
	if source.region_enabled and source.region_rect.size.x > 0.0 and source.region_rect.size.y > 0.0:
		atlas_texture.region = source.region_rect
		return atlas_texture
	var frame_size := source.texture.get_size() / Vector2(maxi(source.hframes, 1), maxi(source.vframes, 1))
	var frame_index := maxi(source.frame, 0)
	var column := frame_index % maxi(source.hframes, 1)
	var row := frame_index / maxi(source.hframes, 1)
	atlas_texture.region = Rect2(Vector2(column, row) * frame_size, frame_size)
	return atlas_texture


func _clear_visual() -> void:
	texture = null
	uv = PackedVector2Array()
	polygon = PackedVector2Array()


func _get_live_global_config() -> Dictionary:
	if _target == null:
		return {}
	var content_db := _target.get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		return {}
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var value: Variant = profile.get("directional_shadow", {})
	return value as Dictionary if value is Dictionary else {}


func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges()
	return Color.from_string(text, fallback) if not text.is_empty() else fallback
