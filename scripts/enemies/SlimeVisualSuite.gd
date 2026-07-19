extends "res://scripts/enemies/Slime.gd"

@export_category("Slime Ground Shadow")
@export var ground_shadow_enabled := true
@export_range(0.0, 1.0, 0.01) var ground_shadow_opacity := 0.46
@export var ground_shadow_offset := Vector2(0.0, 11.0)
@export var ground_shadow_scale := Vector2(0.92, 0.34)

@export_category("Slime Glow")
@export var glow_enabled := true
@export var glow_color := Color(0.28, 1.0, 0.48, 0.42)
@export_range(0.0, 4.0, 0.01) var glow_intensity := 1.15
@export var glow_offset := Vector2(0.0, -3.0)
@export var glow_scale := Vector2(0.92, 0.92)
@export_range(0.0, 12.0, 0.01) var glow_pulse_speed := 2.2
@export_range(0.0, 0.8, 0.01) var glow_pulse_strength := 0.12

@onready var ground_shadow: Polygon2D = get_node_or_null("GroundShadow") as Polygon2D
@onready var slime_glow: Sprite2D = get_node_or_null("SlimeGlow") as Sprite2D


func _ready() -> void:
	super._ready()
	_apply_visual_options()


func refresh_visual_options() -> void:
	_apply_visual_options()


func _apply_visual_options() -> void:
	if ground_shadow != null:
		ground_shadow.visible = ground_shadow_enabled
		ground_shadow.position = ground_shadow_offset
		ground_shadow.scale = ground_shadow_scale
		ground_shadow.color = Color(0.01, 0.008, 0.015, ground_shadow_opacity)
		ground_shadow.z_index = 0
		ground_shadow.show_behind_parent = true

	if slime_glow == null:
		return
	slime_glow.visible = glow_enabled
	slime_glow.position = glow_offset
	slime_glow.scale = glow_scale
	slime_glow.z_index = 1
	var material := slime_glow.material as ShaderMaterial
	if material == null or material.shader == null:
		return
	material.set_shader_parameter("enabled", glow_enabled)
	material.set_shader_parameter("glow_color", glow_color)
	material.set_shader_parameter("intensity", glow_intensity)
	material.set_shader_parameter("pulse_speed", glow_pulse_speed)
	material.set_shader_parameter("pulse_strength", glow_pulse_strength)
