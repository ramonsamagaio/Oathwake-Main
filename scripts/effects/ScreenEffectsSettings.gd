@tool
extends Node

@export_category("Dash Speed Lines")
@export var dash_lines_enabled := false
@export var dash_line_color := Color(0.72, 0.88, 1.0, 0.12)
@export_range(0.05, 2.0, 0.05) var dash_line_count := 0.45
@export_range(0.0, 1.0, 0.01) var dash_line_density := 0.18
@export_range(0.0, 1.0, 0.01) var dash_line_falloff := 0.20
@export_range(0.0, 1.0, 0.01) var dash_mask_size := 0.18
@export_range(0.0, 1.0, 0.01) var dash_mask_edge := 0.72
@export_range(0.1, 20.0, 0.1) var dash_animation_speed := 7.0
@export_range(0.02, 1.0, 0.01) var dash_effect_duration := 0.16

@export_category("Gaussian Glow")
@export var glow_enabled := true
@export_range(0.0, 2.0, 0.01) var bloom_threshold := 0.68
@export_range(0.0, 5.0, 0.01) var bloom_intensity := 0.78
@export_range(1, 4, 1) var blur_iterations := 1
@export_range(0.0, 0.03, 0.0001) var blur_size := 0.0040
@export_range(4, 16, 1) var blur_subdivisions := 8
@export_range(0.0, 1.0, 0.01) var glow_mix_amount := 0.18
