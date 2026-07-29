class_name DynamicProjectedSpriteShadow
extends "res://scripts/effects/ProjectedSpriteShadow.gd"

const MASK_SHADER := preload("res://shaders/projected_shadow_mask.gdshader")
const WIND_SHADER := preload("res://shaders/foliage_wind_2d.gdshader")


func configure(target: Node2D, source: CanvasItem, config: Dictionary, foot_offset: Vector2) -> void:
	super.configure(target, source, config, foot_offset)
	if not is_in_group("projected_shadow_caster"):
		add_to_group("projected_shadow_caster")


func get_shadow_owner() -> Node2D:
	return _target


func get_shadow_source() -> CanvasItem:
	return _source


func is_shadow_caster_active() -> bool:
	return (
		is_inside_tree()
		and visible
		and _target != null
		and _source != null
		and is_instance_valid(_target)
		and is_instance_valid(_source)
		and _target.is_visible_in_tree()
		and _source.is_visible_in_tree()
		and texture != null
		and polygon.size() >= 4
	)


func populate_external_projection_proxy(
	proxy: Polygon2D,
	group: CanvasItem,
	direction: Vector2,
	stretch_amount: float
) -> bool:
	if proxy == null or group == null or not is_shadow_caster_active():
		return false
	var projected := _external_projection_polygon(direction, stretch_amount)
	if projected.is_empty():
		return false
	var group_inverse := group.global_transform.affine_inverse()
	var group_polygon := PackedVector2Array()
	for point in projected:
		group_polygon.append(group_inverse * (global_transform * point))
	proxy.polygon = group_polygon
	proxy.uv = uv
	proxy.texture = texture
	proxy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	proxy.color = Color.WHITE
	proxy.self_modulate = Color.WHITE
	proxy.visible = true
	proxy.set_meta("shadow_owner_id", _target.get_instance_id())
	proxy.set_meta("shadow_source_id", _source.get_instance_id())
	_sync_external_proxy_material(proxy)
	return true


func _external_projection_polygon(direction: Vector2, stretch_amount: float) -> PackedVector2Array:
	if polygon.size() < 4:
		return PackedVector2Array()
	var safe_direction := direction.normalized()
	if safe_direction.length_squared() < 0.0001:
		return PackedVector2Array()
	var safe_current_stretch := maxf(_projection_stretch, 0.001)
	var target_stretch := maxf(stretch_amount, 0.05)

	# Sprite silhouettes are represented by a four-corner projected quad. The
	# lower edge is the contact line, so rebuilding only the two upper vertices
	# preserves attachment while allowing one independent direction per emitter.
	if polygon.size() == 4:
		var bottom_left := polygon[3]
		var bottom_right := polygon[2]
		var left_height := (polygon[0] - bottom_left).length() / safe_current_stretch
		var right_height := (polygon[1] - bottom_right).length() / safe_current_stretch
		return PackedVector2Array([
			bottom_left + safe_direction * left_height * target_stretch,
			bottom_right + safe_direction * right_height * target_stretch,
			bottom_right,
			bottom_left,
		])

	# Polygon sources are uncommon for authored shadow casters. Preserve their
	# shape and rotate the existing projection around its lowest contact point.
	var contact := polygon[0]
	for point in polygon:
		if point.y > contact.y:
			contact = point
	var current_angle := _projection_direction.angle()
	var angle_delta := safe_direction.angle() - current_angle
	var scale_ratio := target_stretch / safe_current_stretch
	var transformed := PackedVector2Array()
	for point in polygon:
		var relative := point - contact
		transformed.append(contact + relative.rotated(angle_delta) * scale_ratio)
	return transformed


func _sync_external_proxy_material(proxy: Polygon2D) -> void:
	var material := proxy.material as ShaderMaterial
	if material == null or material.shader != MASK_SHADER:
		material = ShaderMaterial.new()
		material.resource_local_to_scene = true
		material.shader = MASK_SHADER
		proxy.material = material
	var source_material := _source.material as ShaderMaterial
	var uses_shared_wind := source_material != null and source_material.shader == WIND_SHADER
	material.set_shader_parameter("wind_enabled", uses_shared_wind and bool(_shader_parameter(source_material, "enabled", true)))
	if uses_shared_wind:
		material.set_shader_parameter("wind_amplitude", float(_shader_parameter(source_material, "amplitude", 0.08)))
		material.set_shader_parameter("wind_time_scale", float(_shader_parameter(source_material, "time_scale", 0.20)))
		material.set_shader_parameter("wind_noise_scale", float(_shader_parameter(source_material, "noise_scale", 0.004)))
		material.set_shader_parameter("wind_rotation_strength", float(_shader_parameter(source_material, "rotation_strength", 1.0)))
		material.set_shader_parameter("wind_rotation_pivot", _shader_parameter(source_material, "rotation_pivot", Vector2(0.5, 1.0)))
		material.set_shader_parameter("wind_direction", _shader_parameter(source_material, "wind_direction", Vector2(1.0, 0.16)))
		material.set_shader_parameter("wind_strength", float(_shader_parameter(source_material, "wind_strength", 0.85)))
		material.set_shader_parameter("wind_gust_strength", float(_shader_parameter(source_material, "gust_strength", 0.34)))
		material.set_shader_parameter("wind_gust_speed", float(_shader_parameter(source_material, "gust_speed", 0.42)))
		material.set_shader_parameter("wind_phase", float(_shader_parameter(source_material, "phase", 0.0)))
	var source_node := _source as Node2D
	var source_origin := source_node.global_position if source_node != null else Vector2.ZERO
	var source_scale := Vector2.ONE
	if source_node != null:
		source_scale = source_node.global_scale.abs()
	material.set_shader_parameter("source_world_origin", source_origin)
	material.set_shader_parameter("source_world_size", _visible_frame_size * source_scale)
	proxy.set_meta("shadow_wind_synced", uses_shared_wind)
