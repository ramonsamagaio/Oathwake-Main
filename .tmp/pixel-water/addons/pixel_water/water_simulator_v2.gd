class_name PixelWaterSimulatorV2
extends PixelWaterSimulator2D

## Second-pass tuning for stronger, more readable water motion.
## Keeps the inexpensive 1D height field, but increases propagation quality,
## generates wakes from horizontal motion and scales splashes with displaced volume.

const CREST_GLINT := Color("#a8f4ff")

func _ready() -> void:
    # More persistent, faster travelling waves with less numerical smearing.
    wave_speed_px_s = 116.0
    wave_damping = 1.22
    neighbor_viscosity = 0.045
    max_surface_displacement_px = 58.0
    fluid_depth_m = 0.30

    max_splash_particles = 360
    max_bubbles = 120
    foam_lifetime = 3.15
    super._ready()

func _simulate_surface(delta: float) -> void:
    # Two half-steps keep the higher wave speed stable and preserve sharper crests.
    var half_delta := delta * 0.5
    super._simulate_surface(half_delta)
    super._simulate_surface(half_delta)

func register_object_impact(world_x: float, mass_kg: float, vertical_speed_px_s: float, displaced_volume_m3: float, object_width_px: float) -> void:
    if vertical_speed_px_s <= 12.0:
        return

    var speed_m_s := vertical_speed_px_s / pixels_per_meter
    var impact_energy_j := 0.5 * mass_kg * speed_m_s * speed_m_s
    var displaced_liters := maxf(0.0, displaced_volume_m3 * 1000.0)
    var width_factor := sqrt(maxf(object_width_px, 8.0) / 32.0)

    # Volume is deliberately important here. A broad/light object can throw a lot
    # of water even when its mass and impact energy are modest.
    var splash_score := clampf(
        sqrt(maxf(impact_energy_j, 0.0)) * 1.05
        + sqrt(displaced_liters) * 5.6
        + width_factor * 5.0,
        0.0,
        96.0
    )

    var radius := clampf(object_width_px * 0.95 + sqrt(displaced_liters) * 3.0, 18.0, 155.0)
    add_disturbance(world_x, splash_score * 2.25, radius)

    # A shallow crater plus two side crests reads much more like water being
    # displaced instead of a single vertical spike.
    add_disturbance(world_x - radius * 0.42, -splash_score * 0.48, radius * 0.62)
    add_disturbance(world_x + radius * 0.42, -splash_score * 0.48, radius * 0.62)

    var count := clampi(int(4.0 + splash_score * 0.82 + object_width_px * 0.07), 4, 82)
    var spread := minf(210.0, object_width_px * 0.72 + 22.0 + splash_score * 1.35)
    var launch := 80.0 + splash_score * 3.3
    var surface_y := surface_y_at(world_x)

    for n in range(count):
        if _droplets.size() >= max_splash_particles:
            break
        var vx := _rng.randf_range(-spread, spread)
        var vy := -_rng.randf_range(launch * 0.50, launch)
        var px := world_x + _rng.randf_range(-object_width_px * 0.52, object_width_px * 0.52)
        var amount := _rng.randf_range(0.0025, 0.010)
        _droplets.append({
            "pos": Vector2(px, surface_y - pixel_size),
            "vel": Vector2(vx, vy),
            "life": _rng.randf_range(1.15, 2.7),
            "size": pixel_size if _rng.randf() < 0.82 else pixel_size * 0.5,
            "amount": amount
        })
        _remove_surface_water(amount)

    var foam_count := clampi(int(2.0 + splash_score * 0.28 + object_width_px * 0.025), 2, 26)
    for n in range(foam_count):
        _spawn_foam(world_x + _rng.randf_range(-object_width_px * 0.58, object_width_px * 0.58), 1.0)

func register_displacement_surge(world_x: float, displaced_volume_delta_m3: float, object_width_px: float, vertical_speed_px_s: float) -> void:
    var liters_delta := absf(displaced_volume_delta_m3) * 1000.0
    if liters_delta < 0.025:
        return

    var entering := displaced_volume_delta_m3 > 0.0
    var width_scale := sqrt(maxf(object_width_px, 8.0) / 32.0)
    var strength := clampf(
        liters_delta * 2.3
        + absf(vertical_speed_px_s) * 0.014
        + width_scale * 2.0,
        1.5,
        58.0
    )
    if not entering:
        strength *= -0.62

    var radius := clampf(object_width_px * 0.78 + sqrt(liters_delta) * 2.0, 14.0, 120.0)
    add_disturbance(world_x, strength, radius)
    add_disturbance(world_x - radius * 0.55, -strength * 0.24, radius * 0.68)
    add_disturbance(world_x + radius * 0.55, -strength * 0.24, radius * 0.68)

func register_underwater_motion(world_point: Vector2, velocity_px_s: Vector2, size_px: float, sinking_strength: float = 0.0, delta: float = 1.0 / 60.0) -> void:
    if world_point.x < basin_left or world_point.x >= basin_right:
        return

    var surface_y := surface_y_at(world_point.x)
    var half_size := maxf(size_px * 0.5, pixel_size)
    var touches_water := world_point.y + half_size >= surface_y and world_point.y - half_size <= bottom_y
    if touches_water:
        var speed := velocity_px_s.length()
        var radius := clampf(size_px * 0.62, 10.0, 72.0)

        # Vertical movement pumps the surface directly.
        if absf(velocity_px_s.y) > 24.0:
            var vertical_impulse := clampf(velocity_px_s.y * 0.060, -72.0, 82.0)
            add_disturbance(world_point.x, vertical_impulse, radius)

        # Horizontal movement produces a bow wave and a trailing trough.
        if absf(velocity_px_s.x) > 28.0:
            var direction := signf(velocity_px_s.x)
            var size_gain := sqrt(maxf(size_px, 12.0) / 32.0)
            var wake_strength := clampf(absf(velocity_px_s.x) * 0.040 * size_gain, 3.0, 68.0)
            var lead_x := world_point.x + direction * size_px * 0.34
            var trail_x := world_point.x - direction * size_px * 0.46
            add_disturbance(lead_x, wake_strength * 0.62, radius * 0.72)
            add_disturbance(trail_x, -wake_strength, radius)

        # Fast movement close to the surface leaves intermittent foam streaks.
        if speed > 170.0 and absf(world_point.y - surface_y) < half_size * 1.15 and _foam.size() < 190:
            var foam_probability := 1.0 - exp(-5.5 * delta)
            if _rng.randf() < foam_probability:
                _spawn_foam(world_point.x - signf(velocity_px_s.x) * size_px * 0.25, 0.72)

    # Preserve the original bubble generation and secondary turbulence for points
    # whose centre is actually underwater.
    super.register_underwater_motion(world_point, velocity_px_s, size_px, sinking_strength, delta)

func _draw() -> void:
    super._draw()
    if _column_count < 3:
        return

    # Small moving highlights make wave crests/troughs legible without smoothing
    # away the pixel-art silhouette.
    for i in range(1, _column_count - 1, 2):
        var curvature := absf(_surface[i - 1] - 2.0 * _surface[i] + _surface[i + 1])
        var energy := absf(_velocity[i]) + curvature * 9.0
        if energy < 19.0:
            continue
        var x := basin_left + i * pixel_size
        var y := snappedf(_surface[i] - pixel_size * 0.5, pixel_size * 0.5)
        var width := pixel_size * (2.0 if energy > 52.0 else 1.0)
        var c := CREST_GLINT
        c.a = clampf(0.35 + energy / 150.0, 0.35, 0.88)
        draw_rect(Rect2(x, y, width, maxf(1.0, pixel_size * 0.5)), c)
