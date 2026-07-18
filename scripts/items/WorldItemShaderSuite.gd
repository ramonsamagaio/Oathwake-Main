extends "res://scripts/items/WorldItemEnhanced.gd"

@onready var outline_sprite: Sprite2D = $OutlineSprite
@onready var outline_settings: Node = $OutlineSettings

var _outline_visual_signature := ""
var _outline_frame_texture: Texture2D


func _ready() -> void:
	super._ready()
	_sync_outline_visual()


func _process(delta: float) -> void:
	super._process(delta)
	_sync_outline_transform()


func _apply_visual() -> void:
	super._apply_visual()
	if is_node_ready():
		_sync_outline_visual()


func _sync_outline_visual() -> void:
	if outline_sprite == null or sprite == null or outline_settings == null:
		return

	_outline_visual_signature = _get_outline_visual_signature()
	_outline_frame_texture = _build_exact_frame_texture()
	outline_sprite.texture = _outline_frame_texture
	outline_sprite.centered = sprite.centered
	outline_sprite.offset = sprite.offset
	outline_sprite.region_enabled = false
	outline_sprite.hframes = 1
	outline_sprite.vframes = 1
	outline_sprite.frame = 0
	outline_sprite.flip_h = sprite.flip_h
	outline_sprite.flip_v = sprite.flip_v
	outline_sprite.position = sprite.position
	outline_sprite.rotation = sprite.rotation
	outline_sprite.scale = sprite.scale
	outline_sprite.modulate.a = sprite.modulate.a
	_sync_outline_material()

	var texture_is_valid := outline_sprite.texture != null
	if texture_is_valid:
		var texture_size := outline_sprite.texture.get_size()
		texture_is_valid = texture_size.x > 0.0 and texture_size.y > 0.0
	outline_sprite.visible = bool(outline_settings.get("effect_enabled")) and texture_is_valid


func _sync_outline_transform() -> void:
	if outline_sprite == null or sprite == null:
		return
	var current_signature := _get_outline_visual_signature()
	if current_signature != _outline_visual_signature:
		_sync_outline_visual()
		return
	outline_sprite.position = sprite.position
	outline_sprite.rotation = sprite.rotation
	outline_sprite.scale = sprite.scale
	outline_sprite.flip_h = sprite.flip_h
	outline_sprite.flip_v = sprite.flip_v
	outline_sprite.modulate.a = sprite.modulate.a
	_sync_outline_material()


func _sync_outline_material() -> void:
	if outline_sprite == null or outline_settings == null:
		return
	var shader_material := outline_sprite.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		outline_sprite.visible = false
		return
	var scale_factor := maxf(maxf(absf(sprite.scale.x), absf(sprite.scale.y)), 0.001)
	var requested_world_size := float(outline_settings.get("outline_size"))
	var source_adjusted_size := requested_world_size / scale_factor
	shader_material.set_shader_parameter("enabled", bool(outline_settings.get("effect_enabled")))
	shader_material.set_shader_parameter("outline_color", outline_settings.get("outline_color"))
	shader_material.set_shader_parameter("outline_size", source_adjusted_size)
	shader_material.set_shader_parameter("alpha_threshold", float(outline_settings.get("alpha_threshold")))
	shader_material.set_shader_parameter("samples", int(outline_settings.get("samples")))


func _build_exact_frame_texture() -> Texture2D:
	if sprite == null or sprite.texture == null:
		return null
	var source_texture := sprite.texture
	var source_size := source_texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return null

	var visible_region := Rect2(Vector2.ZERO, source_size)
	var needs_region := false
	if sprite.region_enabled and sprite.region_rect.size.x > 0.0 and sprite.region_rect.size.y > 0.0:
		visible_region = sprite.region_rect
		needs_region = true
	elif sprite.hframes > 1 or sprite.vframes > 1:
		var column_count := maxi(sprite.hframes, 1)
		var row_count := maxi(sprite.vframes, 1)
		var frame_count := column_count * row_count
		var frame_index := clampi(sprite.frame, 0, frame_count - 1)
		var frame_size := source_size / Vector2(column_count, row_count)
		var frame_x := frame_index % column_count
		var frame_y := int(frame_index / column_count)
		visible_region = Rect2(Vector2(frame_x, frame_y) * frame_size, frame_size)
		needs_region = true

	if not needs_region:
		return source_texture
	if visible_region.size.x <= 0.0 or visible_region.size.y <= 0.0:
		return null

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = source_texture
	atlas_texture.region = visible_region
	return atlas_texture


func _get_outline_visual_signature() -> String:
	if sprite == null or sprite.texture == null:
		return "none"
	return "%d|%d|%d|%d|%s|%s" % [
		sprite.texture.get_instance_id(),
		sprite.frame,
		sprite.hframes,
		sprite.vframes,
		str(sprite.region_enabled),
		str(sprite.region_rect),
	]
