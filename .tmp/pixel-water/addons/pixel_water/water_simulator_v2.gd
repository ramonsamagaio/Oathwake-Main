class_name PixelWaterSimulatorV2
extends PixelWaterSimulator2D

## Demo/commercial preset. The reusable physics lives in PixelWaterContainer2D.
## This subclass only applies a lively Terraria-like tuning profile.

func _ready() -> void:
    wave_speed_px_s = 118.0
    wave_damping = 1.15
    neighbor_viscosity = 0.032
    surface_restore_strength = 7.5
    nonlinear_restore_strength = 0.0048
    extreme_damping_start_px = 52.0
    extreme_damping_gain = 0.032
    wall_reflection = 0.95

    fluid_depth_m = 0.30
    overflow_discharge_coefficient = 0.70
    overflow_spray_fraction = 0.14
    puddle_flow_coefficient = 0.58

    max_splash_particles = 520
    max_bubbles = 150
    max_foam_particles = 240
    foam_lifetime = 3.2

    super._ready()
