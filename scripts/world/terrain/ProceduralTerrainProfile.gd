@tool
class_name ProceduralTerrainProfile
extends Resource

@export_category("World")
@export var world_seed: int = 74291
@export_range(16, 128, 1) var tile_size_pixels: int = 64
@export_range(1, 16, 1) var chunk_size_tiles: int = 4

@export_category("Terrain Noise")
@export_range(0.0001, 0.05, 0.0001) var macro_frequency: float = 0.0028
@export_range(0.0001, 0.05, 0.0001) var moisture_frequency: float = 0.0045
@export_range(0.0001, 0.10, 0.0001) var detail_frequency: float = 0.018
@export_range(0.0, 1.0, 0.01) var grass_tile_threshold: float = 0.47
@export_range(0.0, 1.0, 0.01) var dirt_bias: float = 0.12

@export_category("Grass Scatter")
@export_range(1, 64, 1) var tufts_per_tile: int = 18
@export_range(0.0, 1.0, 0.01) var minimum_tuft_density: float = 0.18
@export_range(0.0, 1.0, 0.01) var grass_mask_threshold: float = 0.50
@export var tuft_size_pixels: Vector2 = Vector2(10.0, 12.0)
@export_range(0.25, 2.0, 0.01) var min_tuft_scale: float = 0.72
@export_range(0.25, 2.0, 0.01) var max_tuft_scale: float = 1.18
@export_range(0.0, 0.5, 0.01) var rotation_variation_radians: float = 0.06

@export_category("Grass Palette")
@export var grass_shadow_color: Color = Color(0.105, 0.165, 0.085, 1.0)
@export var grass_base_color: Color = Color(0.175, 0.285, 0.135, 1.0)
@export var grass_tip_color: Color = Color(0.285, 0.405, 0.185, 1.0)
@export_range(0.0, 0.5, 0.01) var color_variation_strength: float = 0.11

@export_category("Grass Motion")
@export_range(1.0, 24.0, 1.0) var wind_fps: float = 7.0
@export_range(0.0, 8.0, 0.05) var wind_speed: float = 1.15
@export_range(0.0, 8.0, 0.1) var wind_strength_pixels: float = 1.8
@export_range(0.0001, 0.2, 0.0001) var wind_world_frequency: float = 0.025
@export_range(0.0, 96.0, 1.0) var interaction_radius_pixels: float = 28.0
@export_range(0.0, 12.0, 0.1) var interaction_bend_pixels: float = 4.0
