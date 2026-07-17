extends "res://scripts/items/WorldItem.gd"

@export var hover_enabled := true
@export var hover_amplitude: float = 2.2
@export var hover_speed: float = 1.35
@export var shadow_opacity: float = 0.30

var _hover_phase := 0.0
var _sprite_base_position := Vector2.ZERO
var _shadow: Polygon2D


func _ready() -> void:
	super._ready()
	_hover_phase = randf_range(0.0, TAU)
	_sprite_base_position = sprite.position if sprite != null else Vector2.ZERO
	_create_ground_shadow()


func _process(delta: float) -> void:
	super._process(delta)
	if collected or not hover_enabled:
		return
	_hover_phase += delta * hover_speed
	var wave := sin(_hover_phase)
	if sprite != null:
		sprite.position = _sprite_base_position + Vector2(0.0, wave * hover_amplitude)
	if _shadow != null:
		var height_factor := (wave + 1.0) * 0.5
		_shadow.scale = Vector2(1.0 - height_factor * 0.10, 1.0 - height_factor * 0.06)
		_shadow.modulate.a = shadow_opacity * (1.0 - height_factor * 0.18)


func _create_ground_shadow() -> void:
	if _shadow != null:
		return
	_shadow = Polygon2D.new()
	_shadow.name = "GroundShadow"
	_shadow.show_behind_parent = true
	_shadow.z_index = -1
	_shadow.position = Vector2(0, 9)
	_shadow.color = Color(0.0, 0.0, 0.0, shadow_opacity)
	_shadow.polygon = PackedVector2Array([
		Vector2(-8, 0), Vector2(-6, -2), Vector2(-2, -3), Vector2(2, -3),
		Vector2(6, -2), Vector2(8, 0), Vector2(6, 2), Vector2(2, 3),
		Vector2(-2, 3), Vector2(-6, 2),
	])
	add_child(_shadow)
	move_child(_shadow, 0)
