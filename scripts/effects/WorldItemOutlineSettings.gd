@tool
extends Node

@export_category("World Item Outline")
@export var effect_enabled := true
@export var outline_color := Color(0.08, 0.06, 0.04, 0.95)
@export_range(0.0, 0.2, 0.001) var outline_size := 0.018
@export_range(0.0, 1.0, 0.05) var alpha_threshold := 0.5
@export_range(4, 32, 1) var samples := 12
