extends "res://scripts/items/WorldItemShaderSuite.gd"

var _drop_shadow_base_scale := Vector2.ONE


func _process(delta: float) -> void:
	super._process(delta)
	if _shadow == null or collected or not hover_enabled:
		return
	var wave := sin(_hover_phase)
	var height_factor := (wave + 1.0) * 0.5
	_shadow.scale = _drop_shadow_base_scale * Vector2(
		1.0 - height_factor * 0.10,
		1.0 - height_factor * 0.06
	)
	_shadow.color.a = shadow_opacity * (1.0 - height_factor * 0.18)
	_shadow.modulate = Color.WHITE


func _sync_outline_visual() -> void:
	super._sync_outline_visual()
	_configure_drop_shadow()


func _configure_drop_shadow() -> void:
	if _shadow == null or sprite == null:
		return
	var texture := outline_sprite.texture if outline_sprite != null and outline_sprite.texture != null else sprite.texture
	if texture == null:
		_shadow.visible = false
		return
	var texture_size := texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		_shadow.visible = false
		return
	var visual_width := maxf(texture_size.x * absf(sprite.scale.x), 1.0)
	var visual_height := maxf(texture_size.y * absf(sprite.scale.y), 1.0)
	var target_width := clampf(visual_width * 0.34, 8.0, 18.0)
	var target_height := clampf(target_width * 0.26, 2.4, 4.8)
	_drop_shadow_base_scale = Vector2(target_width / 16.0, target_height / 6.0)
	_shadow.scale = _drop_shadow_base_scale
	_shadow.position = Vector2(
		_sprite_base_position.x,
		_sprite_base_position.y + clampf(visual_height * 0.20, 6.0, 11.0)
	)
	_shadow.show_behind_parent = true
	_shadow.z_index = -1
	_shadow.color = Color(0.012, 0.009, 0.016, shadow_opacity)
	_shadow.modulate = Color.WHITE
	_shadow.visible = not collected
