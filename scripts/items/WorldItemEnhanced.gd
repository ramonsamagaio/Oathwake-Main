extends "res://scripts/items/WorldItem.gd"

const DirectionalShadowRuntime := preload("res://scripts/effects/DirectionalShadowRuntime.gd")

@export var hover_enabled := true
@export var hover_amplitude: float = 2.2
@export var hover_speed: float = 1.35
@export var shadow_opacity: float = 0.32

var _hover_phase := 0.0
var _sprite_base_position := Vector2.ZERO
var _shadow: Polygon2D


func _ready() -> void:
	super._ready()
	_hover_phase = randf_range(0.0, TAU)
	_sprite_base_position = sprite.position if sprite != null else Vector2.ZERO
	_refresh_projected_shadow()


func _process(delta: float) -> void:
	super._process(delta)
	if collected or not hover_enabled:
		return
	_hover_phase += delta * hover_speed
	var wave := sin(_hover_phase)
	if sprite != null:
		sprite.position = _sprite_base_position + Vector2(0.0, wave * hover_amplitude)


func _refresh_projected_shadow() -> void:
	if sprite == null:
		return
	var visual_size := DirectionalShadowRuntime.estimate_target_visual_size(self)
	var foot_offset := DirectionalShadowRuntime.estimate_target_foot_offset(self)
	_shadow = DirectionalShadowRuntime.apply_to_target(
		self,
		{
			"enabled": true,
			"opacity": shadow_opacity,
			"z_index": 0,
		},
		visual_size,
		foot_offset,
		sprite
	)
