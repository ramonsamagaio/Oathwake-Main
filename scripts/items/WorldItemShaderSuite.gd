extends "res://scripts/items/WorldItemEnhanced.gd"

@onready var outline_sprite: Sprite2D = $OutlineSprite
@onready var outline_settings: Node = $OutlineSettings


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
	outline_sprite.texture = sprite.texture
	outline_sprite.centered = sprite.centered
	outline_sprite.offset = sprite.offset
	outline_sprite.region_enabled = sprite.region_enabled
	outline_sprite.region_rect = sprite.region_rect
	outline_sprite.hframes = sprite.hframes
	outline_sprite.vframes = sprite.vframes
	outline_sprite.frame = sprite.frame
	outline_sprite.flip_h = sprite.flip_h
	outline_sprite.flip_v = sprite.flip_v
	outline_sprite.scale = sprite.scale
	outline_sprite.position = sprite.position
	outline_sprite.visible = bool(outline_settings.get("effect_enabled")) and outline_sprite.texture != null

	var shader_material := outline_sprite.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("enabled", bool(outline_settings.get("effect_enabled")))
	shader_material.set_shader_parameter("outline_color", outline_settings.get("outline_color"))
	shader_material.set_shader_parameter("outline_size", float(outline_settings.get("outline_size")))
	shader_material.set_shader_parameter("alpha_threshold", float(outline_settings.get("alpha_threshold")))
	shader_material.set_shader_parameter("samples", int(outline_settings.get("samples")))


func _sync_outline_transform() -> void:
	if outline_sprite == null or sprite == null:
		return
	outline_sprite.position = sprite.position
	outline_sprite.scale = sprite.scale
	outline_sprite.frame = sprite.frame
	outline_sprite.flip_h = sprite.flip_h
	outline_sprite.flip_v = sprite.flip_v
