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

@export_category("Selective Bloom")
@export var glow_enabled := true
@export var selective_bloom_enabled := true
@export_range(0.0, 2.0, 0.01) var bloom_threshold := 0.68
@export_range(0.0, 5.0, 0.01) var bloom_intensity := 0.78
@export_range(1, 4, 1) var blur_iterations := 1
@export_range(0.0, 0.03, 0.0001) var blur_size := 0.0040
@export_range(4, 16, 1) var blur_subdivisions := 8
@export_range(0.0, 1.0, 0.01) var glow_mix_amount := 0.18
@export_range(0.0, 2.0, 0.01) var colored_glow_boost := 0.12
@export_range(0.0, 1.0, 0.01) var emissive_chroma_threshold := 0.18
@export_range(0.0, 2.0, 0.01) var emissive_luminance_threshold := 0.62
@export_range(0.0, 1.0, 0.01) var neutral_suppression := 0.82
@export_range(0.0, 2.0, 0.01) var warm_emissive_boost := 0.24

@export_category("World Color Grading")
@export var grading_enabled := true
@export var day_tint := Color(1.02, 1.00, 0.96, 1.0)
@export var night_tint := Color(0.66, 0.76, 1.08, 1.0)
@export_range(0.0, 2.0, 0.01) var day_saturation := 1.02
@export_range(0.0, 2.0, 0.01) var night_saturation := 0.82
@export_range(0.5, 2.0, 0.01) var day_contrast := 1.03
@export_range(0.5, 2.0, 0.01) var night_contrast := 1.10
@export_range(-0.5, 0.5, 0.01) var day_brightness := 0.0
@export_range(-0.5, 0.5, 0.01) var night_brightness := -0.035
@export_range(0.0, 1.0, 0.01) var warm_light_preservation := 0.78
@export_range(0.0, 0.25, 0.005) var night_shadow_lift := 0.035
@export_range(0.0, 1.0, 0.01) var night_cool_shadow_strength := 0.32
