extends "res://scripts/items/WorldItemShaderSuite.gd"

const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")

@export_category("Dropped Item Shadow")
@export var drop_shadow_enabled := true
@export_range(0.20, 0.80, 0.01) var drop_shadow_width_factor := 0.46
@export_range(0.15, 0.60, 0.01) var drop_shadow_height_ratio := 0.30

var _drop_shadow_base_scale := Vector2.ONE


func _process(delta: float) -> void:
	super._process(delta)
	WorldDepthRuntime.apply_node_depth(self)
	if _shadow == null or collected:
		return
	_shadow.visible = drop_shadow_enabled
	if not drop_shadow_enabled or not hover_enabled:
		return
	var wave := sin(_hover_phase)
	var height_factor := (wave + 1.0) * 0.5
	_shadow.scale = _drop_shadow_base_scale * Vector2(
		1.0 - height_factor * 0.10,
		1.0 - height_factor * 0.06
	)
	_shadow.color.a = shadow_opacity * (1.0 - height_factor * 0.14)
	_shadow.modulate = Color.WHITE


func _try_collect() -> void:
	var was_collected := collected
	super._try_collect()
	if not was_collected and collected:
		var sfx_manager := get_node_or_null("/root/SFXManager")
		if sfx_manager != null and sfx_manager.has_method("play_profile"):
			sfx_manager.play_profile("item_pickup", global_position)


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
	var target_width := clampf(visual_width * drop_shadow_width_factor, 10.0, 22.0)
	var target_height := clampf(target_width * drop_shadow_height_ratio, 3.0, 6.2)
	_drop_shadow_base_scale = Vector2(target_width / 16.0, target_height / 6.0)
	_shadow.scale = _drop_shadow_base_scale
	_shadow.position = Vector2(
		_sprite_base_position.x,
		_sprite_base_position.y + clampf(visual_height * 0.24, 6.0, 12.0)
	)
	_shadow.show_behind_parent = true
	# The WorldItem root is z=1. Keeping the child at z=0 makes the shadow
	# render above the map ground while the item sprites remain above it.
	_shadow.z_index = 0
	_shadow.color = Color(0.01, 0.007, 0.014, shadow_opacity)
	_shadow.modulate = Color.WHITE
	_shadow.visible = drop_shadow_enabled and not collected
