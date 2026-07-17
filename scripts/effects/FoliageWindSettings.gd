@tool
extends Node

@export_category("Foliage Assignment")
@export var effect_enabled := true
@export var large_resource_ids := PackedStringArray([
	"tree", "oak_tree", "ash_tree", "maple_tree", "walnut_tree", "ebony_tree", "ironwood_tree"
])
@export var small_resource_ids := PackedStringArray([
	"fiber_bush", "herb_bush", "berry_bush"
])

@export_category("Large Vegetation")
@export_range(0.0, 0.5, 0.005) var large_amplitude := 0.10
@export_range(0.0, 5.0, 0.05) var large_rotation_strength := 1.15
@export var large_rotation_pivot := Vector2(0.5, 1.0)

@export_category("Small Vegetation")
@export_range(0.0, 0.5, 0.005) var small_amplitude := 0.16
@export_range(0.0, 5.0, 0.05) var small_rotation_strength := 1.50
@export var small_rotation_pivot := Vector2(0.5, 1.0)

@export_category("Shared Wind")
@export_range(0.0, 5.0, 0.01) var time_scale := 0.28
@export_range(0.0001, 2.0, 0.0001) var noise_scale := 0.004
@export var render_noise_debug := false
@export var noise_texture: Texture2D


func get_size_class(resource_type_id: String) -> String:
	if large_resource_ids.has(resource_type_id):
		return "large"
	if small_resource_ids.has(resource_type_id):
		return "small"
	return ""
