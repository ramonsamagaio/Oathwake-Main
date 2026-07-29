class_name ProjectedSpriteShadow
extends Polygon2D

const ALPHA_THRESHOLD := 0.01
const DEFAULT_DIRECTION_DEGREES := -45.0
const ProjectedShadowGroupScript := preload("res://scripts/effects/ProjectedShadowGroup.gd")
const ProjectedShadowMaskShader := preload("res://shaders/projected_shadow_mask.gdshader")
const FoliageWindShader := preload("res://shaders/foliage_wind_2d.gdshader")

static var _alpha_bounds_cache: Dictionary = {}

var _target: Node2D
var _source: CanvasItem
var _config: Dictionary = {}
var _foot_offset := Vector2.ZERO
var _projection_direction := Vector2.RIGHT.rotated(deg_to_rad(DEFAULT_DIRECTION_DEGREES))
var _projection_stretch := 1.15
var _visible_frame_size := Vector2(32.0, 32.0)
var _shadow_group: CanvasGroup
var _render_proxy: Polygon2D
var _proxy_material: ShaderMaterial


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


func _exit_tree() -> void:
	if _render_proxy != null and is_instance_valid(_render_proxy):
		_render_proxy.queue_free()
	_render_proxy = null
	_shadow_group = null


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _source == null or not is_instance_valid(_source):
		visible = false
		_hide_render_proxy()
		return
	_refresh_silhouette()


func _apply_projection_settings() -> void:
	var live_global := _get_live_global_config()
	var direction_degrees := float(live_global.get("direction_degrees", _config.get("direction_degrees", DEFAULT_DIRECTION_DEGREES)))
	var stretch_amount := maxf(float(live_global.get("stretch", _config.get("stretch", 1.15))), 0.05)
	var opacity := clampf(float(live_global.get("opacity", _config.get("opacity", 0.30))), 0.0, 1.0)
	var offset := _vector_from_value(_config.get("offset", {}), Vector2.ZERO)

	# The projected geometry itself performs the shear. Keeping this node
	# unrotated preserves the entire contact line at the source sprite's feet.
	_projection_direction = Vector2.RIGHT.rotated(deg_to_rad(direction_degrees)).normalized()
	_projection_stretch = stretch_amount
	rotation = 0.0
	scale = Vector2.ONE
	position = offset
	# This child remains the canonical geometry and metadata owner, while the
	# shared CanvasGroup draws one combined mask for every shadow. Making this
	# polygon transparent prevents ordinary alpha blending from darkening overlaps.
	color = Color(1.0, 1.0, 1.0, 0.0)
	self_modulate = Color.WHITE
	z_index = int(_config.get("z_index", -1))
	visible = bool(_config.get("enabled", true)) and bool(live_global.get("enabled", true)) and opacity > 0.001
	set_meta("shadow_direction_degrees", direction_degrees)
	set_meta("shadow_stretch", stretch_amount)
	set_meta("shadow_opacity", opacity)


func _refresh_silhouette() -> void:
	_apply_projection_settings()
	if not visible:
		_hide_render_proxy()
		return
	if _source is AnimatedSprite2D:
		_apply_animated_sprite(_source as AnimatedSprite2D)
	elif _source is Sprite2D:
		_apply_sprite(_source as Sprite2D)
	elif _source is Polygon2D:
		_apply_polygon(_source as Polygon2D)
	else:
		_clear_visual()
	_sync_render_proxy()


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
	set_meta("shadow_source_kind", "AnimatedSprite2D")
	set_meta("shadow_source_animation", source.animation)
	set_meta("shadow_source_frame", frame_index)


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
	set_meta("shadow_source_kind", "Sprite2D")
	set_meta("shadow_source_frame", source.frame)


func _apply_texture_rect(
	frame_texture: Texture2D,
	frame_size: Vector2,
	centered: bool,
	offset: Vector2,
	flip_h: bool,
	flip_v: bool,
	relative_transform: Transform2D
) -> void:
	var opaque_rect := _get_opaque_pixel_rect(frame_texture)
	if opaque_rect.size.x <= 0 or opaque_rect.size.y <= 0:
		_clear_visual()
		return

	texture = frame_texture
	_visible_frame_size = frame_size
	var base_top_left := offset
	if centered:
		base_top_left -= frame_size * 0.5

	# Flips affect where the cropped opaque rectangle is drawn, not only its UVs.
	var drawn_position := Vector2(opaque_rect.position)
	var opaque_size := Vector2(opaque_rect.size)
	if flip_h:
		drawn_position.x = frame_size.x - float(opaque_rect.end.x)
	if flip_v:
		drawn_position.y = frame_size.y - float(opaque_rect.end.y)
	var visible_top_left := base_top_left + drawn_position
	var visible_bottom_right := visible_top_left + opaque_size

	var local_corners := PackedVector2Array([
		visible_top_left,
		Vector2(visible_bottom_right.x, visible_top_left.y),
		visible_bottom_right,
		Vector2(visible_top_left.x, visible_bottom_right.y),
	])

	# Project every column away from its own point on the lowest opaque row.
	# Unlike rotating a rectangular quad, this shear leaves the full bottom edge
	# attached to the sprite while the alpha texture preserves the exact silhouette.
	var contact_y := visible_bottom_right.y
	var transformed_origin := relative_transform * Vector2.ZERO
	var transformed_up := relative_transform * Vector2.UP
	var vertical_scale := maxf((transformed_up - transformed_origin).length(), 0.0001)
	var projected := PackedVector2Array()
	for point in local_corners:
		var base_point := relative_transform * Vector2(point.x, contact_y)
		var projection_height := maxf(contact_y - point.y, 0.0) * vertical_scale
		projected.append(base_point + _projection_direction * projection_height * _projection_stretch)
	polygon = projected

	var left_u := float(opaque_rect.end.x) if flip_h else float(opaque_rect.position.x)
	var right_u := float(opaque_rect.position.x) if flip_h else float(opaque_rect.end.x)
	var top_v := float(opaque_rect.end.y) if flip_v else float(opaque_rect.position.y)
	var bottom_v := float(opaque_rect.position.y) if flip_v else float(opaque_rect.end.y)
	uv = PackedVector2Array([
		Vector2(left_u, top_v),
		Vector2(right_u, top_v),
		Vector2(right_u, bottom_v),
		Vector2(left_u, bottom_v),
	])
	set_meta("shadow_opaque_rect", opaque_rect)


func _apply_polygon(source: Polygon2D) -> void:
	texture = source.texture
	var relative_transform := _source_to_target_transform(source)
	if source.polygon.is_empty():
		_clear_visual()
		return
	var lowest_y := source.polygon[0].y
	for point in source.polygon:
		lowest_y = maxf(lowest_y, point.y)
	var transformed_origin := relative_transform * Vector2.ZERO
	var transformed_up := relative_transform * Vector2.UP
	var vertical_scale := maxf((transformed_up - transformed_origin).length(), 0.0001)
	var projected := PackedVector2Array()
	for point in source.polygon:
		var base_point := relative_transform * Vector2(point.x, lowest_y)
		var projection_height := maxf(lowest_y - point.y, 0.0) * vertical_scale
		projected.append(base_point + _projection_direction * projection_height * _projection_stretch)
	polygon = projected
	uv = source.uv
	_visible_frame_size = _polygon_size(source.polygon)
	set_meta("shadow_source_kind", "Polygon2D")


func _sync_render_proxy() -> void:
	if polygon.is_empty() or texture == null or not visible or not _is_source_near_viewport():
		_hide_render_proxy()
		return
	_ensure_render_proxy()
	if _render_proxy == null or _shadow_group == null:
		return
	var group_inverse := _shadow_group.global_transform.affine_inverse()
	var shadow_transform := global_transform
	var group_polygon := PackedVector2Array()
	for point in polygon:
		group_polygon.append(group_inverse * (shadow_transform * point))
	_render_proxy.polygon = group_polygon
	_render_proxy.uv = uv
	_render_proxy.texture = texture
	_render_proxy.visible = true
	_render_proxy.set_meta("shadow_source_id", _source.get_instance_id())
	_render_proxy.set_meta("shadow_owner_id", _target.get_instance_id())
	_sync_proxy_material()
	set_meta("shadow_render_proxy_id", _render_proxy.get_instance_id())


func _ensure_render_proxy() -> void:
	_ensure_shadow_group()
	if _shadow_group == null:
		return
	if _render_proxy != null and is_instance_valid(_render_proxy) and _render_proxy.get_parent() == _shadow_group:
		return
	if _render_proxy != null and is_instance_valid(_render_proxy):
		_render_proxy.queue_free()
	_render_proxy = Polygon2D.new()
	_render_proxy.name = "ShadowMask_%s" % str(get_instance_id())
	_render_proxy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_render_proxy.color = Color.WHITE
	_render_proxy.self_modulate = Color.WHITE
	_render_proxy.z_index = 0
	_render_proxy.z_as_relative = true
	_proxy_material = ShaderMaterial.new()
	_proxy_material.resource_local_to_scene = true
	_proxy_material.shader = ProjectedShadowMaskShader
	_render_proxy.material = _proxy_material
	_shadow_group.add_child(_render_proxy)


func _ensure_shadow_group() -> void:
	if _shadow_group != null and is_instance_valid(_shadow_group):
		return
	var existing := get_tree().get_first_node_in_group("projected_shadow_group") as CanvasGroup
	if existing != null:
		_shadow_group = existing
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	_shadow_group = ProjectedShadowGroupScript.new() as CanvasGroup
	host.add_child(_shadow_group)


func _sync_proxy_material() -> void:
	if _proxy_material == null or _source == null:
		return
	var source_material := _source.material as ShaderMaterial
	var uses_shared_wind := source_material != null and source_material.shader == FoliageWindShader
	_proxy_material.set_shader_parameter("wind_enabled", uses_shared_wind and bool(_shader_parameter(source_material, "enabled", true)))
	if uses_shared_wind:
		_proxy_material.set_shader_parameter("wind_amplitude", float(_shader_parameter(source_material, "amplitude", 0.08)))
		_proxy_material.set_shader_parameter("wind_time_scale", float(_shader_parameter(source_material, "time_scale", 0.20)))
		_proxy_material.set_shader_parameter("wind_noise_scale", float(_shader_parameter(source_material, "noise_scale", 0.004)))
		_proxy_material.set_shader_parameter("wind_rotation_strength", float(_shader_parameter(source_material, "rotation_strength", 1.0)))
		_proxy_material.set_shader_parameter("wind_rotation_pivot", _shader_parameter(source_material, "rotation_pivot", Vector2(0.5, 1.0)))
		_proxy_material.set_shader_parameter("wind_direction", _shader_parameter(source_material, "wind_direction", Vector2(1.0, 0.16)))
		_proxy_material.set_shader_parameter("wind_strength", float(_shader_parameter(source_material, "wind_strength", 0.85)))
		_proxy_material.set_shader_parameter("wind_gust_strength", float(_shader_parameter(source_material, "gust_strength", 0.34)))
		_proxy_material.set_shader_parameter("wind_gust_speed", float(_shader_parameter(source_material, "gust_speed", 0.42)))
		_proxy_material.set_shader_parameter("wind_phase_offset", float(_shader_parameter(source_material, "phase_offset", 0.0)))
	var source_node := _source as Node2D
	var source_origin := source_node.global_position if source_node != null else Vector2.ZERO
	var source_scale := Vector2.ONE
	if source_node != null:
		source_scale = Vector2(absf(source_node.global_scale.x), absf(source_node.global_scale.y))
	_proxy_material.set_shader_parameter("source_world_origin", source_origin)
	_proxy_material.set_shader_parameter("source_world_size", _visible_frame_size * source_scale)
	_render_proxy.set_meta("shadow_wind_synced", uses_shared_wind)


func _shader_parameter(shader_material: ShaderMaterial, parameter_name: String, fallback: Variant) -> Variant:
	if shader_material == null:
		return fallback
	var value: Variant = shader_material.get_shader_parameter(parameter_name)
	return fallback if value == null else value


func _is_source_near_viewport() -> bool:
	if _source == null or not (_source is Node2D):
		return true
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return true
	var zoom := camera.zoom
	var safe_zoom := Vector2(maxf(absf(zoom.x), 0.01), maxf(absf(zoom.y), 0.01))
	var half_view := get_viewport_rect().size * 0.5 / safe_zoom
	var margin := Vector2(768.0, 768.0)
	var bounds := Rect2(camera.get_screen_center_position() - half_view - margin, (half_view + margin) * 2.0)
	return bounds.has_point((_source as Node2D).global_position)


func _hide_render_proxy() -> void:
	if _render_proxy != null and is_instance_valid(_render_proxy):
		_render_proxy.visible = false


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
	var horizontal_frames := maxi(source.hframes, 1)
	var vertical_frames := maxi(source.vframes, 1)
	var frame_size := source.texture.get_size() / Vector2(horizontal_frames, vertical_frames)
	var maximum_frame := horizontal_frames * vertical_frames - 1
	var frame_index := clampi(source.frame, 0, maximum_frame)
	var column := frame_index % horizontal_frames
	var row := frame_index / horizontal_frames
	atlas_texture.region = Rect2(Vector2(column, row) * frame_size, frame_size)
	return atlas_texture


func _get_opaque_pixel_rect(frame_texture: Texture2D) -> Rect2i:
	if frame_texture == null:
		return Rect2i()
	var texture_size := Vector2i(frame_texture.get_size())
	var cache_key := _alpha_cache_key(frame_texture, texture_size)
	if _alpha_bounds_cache.has(cache_key):
		return _alpha_bounds_cache[cache_key] as Rect2i
	var image := frame_texture.get_image()
	if image == null or image.is_empty():
		var fallback := Rect2i(Vector2i.ZERO, texture_size)
		_alpha_bounds_cache[cache_key] = fallback
		return fallback

	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= ALPHA_THRESHOLD:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
	var result := Rect2i()
	if maximum.x >= minimum.x and maximum.y >= minimum.y:
		result = Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	_alpha_bounds_cache[cache_key] = result
	return result


func _alpha_cache_key(frame_texture: Texture2D, texture_size: Vector2i) -> String:
	if frame_texture is AtlasTexture:
		var atlas_texture := frame_texture as AtlasTexture
		var atlas_id := "none"
		if atlas_texture.atlas != null:
			atlas_id = str(atlas_texture.atlas.get_instance_id())
		return "atlas:%s:%s:%dx%d" % [atlas_id, str(atlas_texture.region), texture_size.x, texture_size.y]
	return "texture:%s:%dx%d" % [str(frame_texture.get_instance_id()), texture_size.x, texture_size.y]


func _polygon_size(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2(32.0, 32.0)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds.size


func _clear_visual() -> void:
	texture = null
	uv = PackedVector2Array()
	polygon = PackedVector2Array()
	_hide_render_proxy()


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
