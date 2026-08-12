class_name PixelWaterContainer2D
extends Node2D

## Reusable, lightweight, physically-inspired pixel water for side-view games.
## One instance represents one contiguous basin. The simulation uses a 1D free
## surface, explicit water volume, conservative overflow, sparse spray/foam/bubbles
## and a shallow puddle layer outside the basin.
##
## The level is still responsible for real collision geometry. This node only
## simulates water. Configure basin_left/right, rim height and bottom to match it.

@export_category("Container")
@export var basin_left: float = 170.0
@export var basin_right: float = 790.0
@export var rest_surface_y: float = 260.0
@export var bottom_y: float = 500.0
@export var platform_y: float = 240.0
@export var left_rim_y: float = -1.0
@export var right_rim_y: float = -1.0
@export var world_width: float = 960.0
@export var spill_world_left: float = -320.0
@export var spill_world_right: float = 1280.0

@export_category("Pixel simulation")
@export_range(2.0, 8.0, 1.0) var pixel_size: float = 4.0
@export_range(20.0, 220.0, 1.0) var wave_speed_px_s: float = 116.0
@export_range(0.05, 8.0, 0.05) var wave_damping: float = 1.18
@export_range(0.0, 0.35, 0.005) var neighbor_viscosity: float = 0.035
@export_range(0.0, 80.0, 0.5) var surface_restore_strength: float = 7.0
@export_range(0.0, 0.05, 0.0005) var nonlinear_restore_strength: float = 0.0045
@export_range(8.0, 160.0, 1.0) var extreme_damping_start_px: float = 48.0
@export_range(0.0, 0.20, 0.005) var extreme_damping_gain: float = 0.035
@export_range(1.0, 30.0, 0.5) var volume_correction_speed: float = 7.0
@export_range(0.0, 1.0, 0.01) var wall_reflection: float = 0.94
@export_range(1.0, 16.0, 0.5) var minimum_water_depth_px: float = 3.0

@export_category("Physical constants")
@export var water_density_kg_m3: float = 997.0
@export var gravity_px_s2: float = 980.0
@export var pixels_per_meter: float = 100.0
@export_range(0.05, 2.0, 0.01) var fluid_depth_m: float = 0.30

@export_category("Overflow")
@export var overflow_enabled: bool = true
@export_range(0.1, 1.0, 0.01) var overflow_discharge_coefficient: float = 0.68
@export_range(0.0, 0.5, 0.01) var overflow_spray_fraction: float = 0.12
@export_range(1, 16, 1) var overflow_edge_samples: int = 5
@export_range(0.01, 0.5, 0.01) var max_fraction_volume_spilled_per_frame: float = 0.12

@export_category("Outside puddles")
@export_range(2.0, 12.0, 1.0) var puddle_cell_px: float = 4.0
@export_range(0.05, 2.0, 0.01) var puddle_flow_coefficient: float = 0.52
@export_range(0.000001, 0.001, 0.000001) var puddle_evaporation_m_s: float = 0.000035
@export_range(0.0000001, 0.001, 0.0000001) var puddle_visual_threshold_m3: float = 0.000003
@export_range(0.1, 5.0, 0.05) var wetness_evaporation_per_second: float = 0.40

@export_category("Secondary effects")
@export var foam_lifetime: float = 3.15
@export var max_splash_particles: int = 480
@export var max_bubbles: int = 140
@export var max_foam_particles: int = 220

var _surface: PackedFloat32Array
var _velocity: PackedFloat32Array
var _next_velocity: PackedFloat32Array
var _column_count: int = 0

var _droplets: Array[Dictionary] = []
var _bubbles: Array[Dictionary] = []
var _foam: Array[Dictionary] = []
var _wetness: Dictionary = {}
var _puddle_volume_m3: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _foam_accumulator := 0.0
var _base_water_volume_m3 := 0.0
var _water_volume_m3 := 0.0
var _equilibrium_surface_y := 0.0
var _displacement_reports: Dictionary = {}
var _last_total_displacement_m3 := 0.0

const WATER_TOP := Color("#17a9dc")
const WATER_MID := Color("#0b8fc9")
const WATER_DEEP := Color("#087ab2")
const WATER_GLINT := Color("#78dff1")
const CREST_GLINT := Color("#a8f4ff")
const FOAM_COLOR := Color("#d8f8fb")
const WET_COLOR := Color("#253b47")

func _ready() -> void:
    add_to_group("pixel_water_container")
    add_to_group("water_simulator") # Backwards compatibility.
    _rng.seed = 0x51A7E2
    _rebuild_columns()
    _initialize_water_volume()
    queue_redraw()

func _resolved_left_rim_y() -> float:
    return platform_y if left_rim_y < 0.0 else left_rim_y

func _resolved_right_rim_y() -> float:
    return platform_y if right_rim_y < 0.0 else right_rim_y

func _rebuild_columns() -> void:
    _column_count = maxi(4, int(ceil((basin_right - basin_left) / pixel_size)))
    _surface.resize(_column_count)
    _velocity.resize(_column_count)
    _next_velocity.resize(_column_count)
    for i in range(_column_count):
        _surface[i] = rest_surface_y
        _velocity[i] = 0.0
        _next_velocity[i] = 0.0

func _initialize_water_volume() -> void:
    var width_m := maxf((basin_right - basin_left) / pixels_per_meter, 0.001)
    var depth_m := maxf((bottom_y - rest_surface_y) / pixels_per_meter, 0.0)
    _base_water_volume_m3 = width_m * depth_m * fluid_depth_m
    _water_volume_m3 = _base_water_volume_m3
    _equilibrium_surface_y = rest_surface_y

func reset_water() -> void:
    _water_volume_m3 = _base_water_volume_m3
    _puddle_volume_m3.clear()
    _wetness.clear()
    _droplets.clear()
    _bubbles.clear()
    _foam.clear()
    _displacement_reports.clear()
    _last_total_displacement_m3 = 0.0
    _equilibrium_surface_y = rest_surface_y
    for i in range(_column_count):
        _surface[i] = rest_surface_y
        _velocity[i] = 0.0
        _next_velocity[i] = 0.0
    queue_redraw()

func water_volume_liters() -> float:
    return _water_volume_m3 * 1000.0

func outside_water_volume_liters() -> float:
    var total := 0.0
    for value in _puddle_volume_m3.values():
        total += float(value)
    for d in _droplets:
        total += float(d.get("amount_m3", 0.0))
    return total * 1000.0

func _physics_process(delta: float) -> void:
    _update_equilibrium_surface()
    _simulate_surface(delta)
    _simulate_overflow(delta)
    _simulate_droplets(delta)
    _simulate_bubbles(delta)
    _simulate_foam(delta)
    _simulate_puddles(delta)
    _simulate_wetness(delta)
    queue_redraw()

func report_displacement(body_id: int, displaced_volume_m3: float) -> void:
    _displacement_reports[body_id] = maxf(0.0, displaced_volume_m3)

func _update_equilibrium_surface() -> void:
    var total_displaced_m3 := 0.0
    for volume in _displacement_reports.values():
        total_displaced_m3 += float(volume)
    _displacement_reports.clear()
    _last_total_displacement_m3 = total_displaced_m3

    var width_m := maxf((basin_right - basin_left) / pixels_per_meter, 0.001)
    var cross_section_m2 := maxf(width_m * fluid_depth_m, 0.000001)
    var effective_depth_m := (_water_volume_m3 + total_displaced_m3) / cross_section_m2
    _equilibrium_surface_y = bottom_y - effective_depth_m * pixels_per_meter

    # Empty water naturally rests at the physical bottom, not at an arbitrary
    # symmetrical clamp around the initial surface.
    _equilibrium_surface_y = minf(_equilibrium_surface_y, bottom_y - minimum_water_depth_px)

func _simulate_surface(delta: float) -> void:
    if _column_count < 3:
        return

    # Keep explicit integration inside the wave-equation stability region.
    var max_step := maxf(pixel_size / maxf(wave_speed_px_s, 1.0) * 0.42, 1.0 / 480.0)
    var substeps := clampi(int(ceil(delta / max_step)), 1, 8)
    var dt := delta / float(substeps)

    for _step in range(substeps):
        _surface_substep(dt)

    _foam_accumulator += delta
    if _foam_accumulator >= 0.065:
        _foam_accumulator = 0.0
        _emit_surface_foam()

func _surface_substep(dt: float) -> void:
    var dx2 := maxf(pixel_size * pixel_size, 0.001)
    var c2 := wave_speed_px_s * wave_speed_px_s

    for i in range(_column_count):
        # Mirrored ghost cells create a reflecting solid-wall boundary.
        var left_y := _surface[i - 1] if i > 0 else _surface[mini(1, _column_count - 1)]
        var center_y := _surface[i]
        var right_y := _surface[i + 1] if i < _column_count - 1 else _surface[maxi(_column_count - 2, 0)]
        var laplacian := (left_y + right_y - 2.0 * center_y) / dx2

        var deviation := center_y - _equilibrium_surface_y
        var nonlinear_restore := nonlinear_restore_strength * deviation * absf(deviation) * absf(deviation)
        var local_damping := wave_damping
        if absf(deviation) > extreme_damping_start_px:
            local_damping += (absf(deviation) - extreme_damping_start_px) * extreme_damping_gain

        var acceleration := (
            c2 * laplacian
            - surface_restore_strength * deviation
            - nonlinear_restore
            - local_damping * _velocity[i]
        )

        # A trough may approach the real basin floor. Instead of a fake lower
        # amplitude line, pressure rises steeply only when the column is almost dry.
        var depth_px := bottom_y - center_y
        if depth_px < minimum_water_depth_px * 2.0:
            var compression := minimum_water_depth_px * 2.0 - depth_px
            acceleration -= compression * compression * 42.0

        _next_velocity[i] = _velocity[i] + acceleration * dt

    for i in range(_column_count):
        var neighbor_v := (
            _next_velocity[maxi(i - 1, 0)]
            + _next_velocity[mini(i + 1, _column_count - 1)]
        ) * 0.5
        _velocity[i] = lerpf(_next_velocity[i], neighbor_v, neighbor_viscosity)

    # Wall energy is mostly reflected, with a small loss to avoid perpetual ringing.
    _velocity[0] *= wall_reflection
    _velocity[_column_count - 1] *= wall_reflection

    for i in range(_column_count):
        _surface[i] += _velocity[i] * dt

        # Only the physical floor is a hard geometric limit.
        var physical_floor_surface := bottom_y - 0.5
        if _surface[i] > physical_floor_surface:
            _surface[i] = physical_floor_surface
            if _velocity[i] > 0.0:
                _velocity[i] *= -0.18

    # Preserve total water volume without imposing a top/bottom wave amplitude.
    var average := 0.0
    for value in _surface:
        average += value
    average /= float(_column_count)
    var correction := (average - _equilibrium_surface_y) * minf(volume_correction_speed * dt, 1.0)
    for i in range(_column_count):
        _surface[i] -= correction

func _emit_surface_foam() -> void:
    if _foam.size() >= max_foam_particles:
        return
    for i in range(1, _column_count - 1, 2):
        var curvature := absf(_surface[i - 1] - 2.0 * _surface[i] + _surface[i + 1])
        var energy := absf(_velocity[i]) + curvature * 10.5
        if energy < 30.0:
            continue
        var probability := clampf((energy - 30.0) / 120.0, 0.0, 0.35)
        if _rng.randf() < probability:
            _spawn_foam(basin_left + i * pixel_size, clampf(energy / 80.0, 0.45, 1.35))

func surface_y_at(world_x: float) -> float:
    if _column_count == 0:
        return rest_surface_y
    var index := int(floor((world_x - basin_left) / pixel_size))
    index = clampi(index, 0, _column_count - 1)
    return _surface[index]

func contains_point(world_point: Vector2) -> bool:
    if world_point.x < basin_left or world_point.x >= basin_right:
        return false
    if world_point.y > bottom_y:
        return false
    return world_point.y >= surface_y_at(world_point.x)

func depth_at(world_point: Vector2) -> float:
    if not contains_point(world_point):
        return 0.0
    return maxf(0.0, world_point.y - surface_y_at(world_point.x))

func add_disturbance(world_x: float, impulse_px_s: float, radius_px: float = 24.0) -> void:
    if world_x < basin_left - radius_px or world_x > basin_right + radius_px:
        return
    var center := int(round((world_x - basin_left) / pixel_size))
    var radius_columns := maxi(1, int(ceil(radius_px / pixel_size)))
    for offset in range(-radius_columns, radius_columns + 1):
        var i := center + offset
        if i < 0 or i >= _column_count:
            continue
        var t := absf(float(offset)) / float(radius_columns + 1)
        var falloff := (1.0 - t) * (1.0 - t)
        _velocity[i] += impulse_px_s * falloff

func register_object_impact(
    world_x: float,
    mass_kg: float,
    vertical_speed_px_s: float,
    displaced_volume_m3: float,
    object_width_px: float
) -> void:
    if vertical_speed_px_s <= 10.0 or _water_volume_m3 <= 0.0:
        return

    var speed_m_s := vertical_speed_px_s / pixels_per_meter
    var impact_energy_j := 0.5 * mass_kg * speed_m_s * speed_m_s
    var displaced_liters := maxf(0.0, displaced_volume_m3 * 1000.0)
    var width_factor := sqrt(maxf(object_width_px, 8.0) / 32.0)

    var splash_score := clampf(
        sqrt(maxf(impact_energy_j, 0.0)) * 1.05
        + sqrt(displaced_liters) * 5.8
        + width_factor * 5.2,
        0.0,
        110.0
    )
    var radius := clampf(object_width_px * 0.98 + sqrt(displaced_liters) * 3.2, 18.0, 170.0)

    # Centre crater + two opposing crests. This is volume-neutral wave energy.
    add_disturbance(world_x, splash_score * 2.35, radius)
    add_disturbance(world_x - radius * 0.44, -splash_score * 0.50, radius * 0.62)
    add_disturbance(world_x + radius * 0.44, -splash_score * 0.50, radius * 0.62)

    var count := clampi(int(4.0 + splash_score * 0.85 + object_width_px * 0.08), 4, 96)
    var energetic_volume_m3 := impact_energy_j / maxf(water_density_kg_m3 * 55.0, 1.0) * 0.001
    var splash_volume_m3 := clampf(
        displaced_volume_m3 * 0.055 + energetic_volume_m3,
        0.0,
        minf(_water_volume_m3 * 0.012, 0.018)
    )

    if splash_volume_m3 > 0.0:
        _remove_water_volume(splash_volume_m3)
        _spawn_impact_spray(world_x, object_width_px, splash_score, count, splash_volume_m3)

    var foam_count := clampi(int(2.0 + splash_score * 0.30 + object_width_px * 0.028), 2, 30)
    for _n in range(foam_count):
        _spawn_foam(
            world_x + _rng.randf_range(-object_width_px * 0.60, object_width_px * 0.60),
            1.0
        )

func _spawn_impact_spray(
    world_x: float,
    object_width_px: float,
    splash_score: float,
    count: int,
    total_volume_m3: float
) -> void:
    var actual_count := mini(count, max_splash_particles - _droplets.size())
    if actual_count <= 0:
        _return_water_volume(total_volume_m3)
        return

    var per_particle := total_volume_m3 / float(actual_count)
    var spread := minf(230.0, object_width_px * 0.78 + 24.0 + splash_score * 1.45)
    var launch := 84.0 + splash_score * 3.55
    var sy := surface_y_at(world_x)

    for _n in range(actual_count):
        _droplets.append({
            "pos": Vector2(
                world_x + _rng.randf_range(-object_width_px * 0.56, object_width_px * 0.56),
                sy - pixel_size
            ),
            "vel": Vector2(
                _rng.randf_range(-spread, spread),
                -_rng.randf_range(launch * 0.48, launch)
            ),
            "life": _rng.randf_range(1.15, 2.9),
            "size": pixel_size if _rng.randf() < 0.84 else pixel_size * 0.5,
            "amount_m3": per_particle
        })

func register_displacement_surge(
    world_x: float,
    displaced_volume_delta_m3: float,
    object_width_px: float,
    vertical_speed_px_s: float
) -> void:
    var liters_delta := absf(displaced_volume_delta_m3) * 1000.0
    if liters_delta < 0.02:
        return

    var entering := displaced_volume_delta_m3 > 0.0
    var width_scale := sqrt(maxf(object_width_px, 8.0) / 32.0)
    var strength := clampf(
        liters_delta * 2.4
        + absf(vertical_speed_px_s) * 0.015
        + width_scale * 2.1,
        1.5,
        72.0
    )
    if not entering:
        strength *= -0.62

    var radius := clampf(object_width_px * 0.80 + sqrt(liters_delta) * 2.2, 14.0, 135.0)
    add_disturbance(world_x, strength, radius)
    add_disturbance(world_x - radius * 0.56, -strength * 0.25, radius * 0.68)
    add_disturbance(world_x + radius * 0.56, -strength * 0.25, radius * 0.68)

func register_underwater_motion(
    world_point: Vector2,
    velocity_px_s: Vector2,
    size_px: float,
    sinking_strength: float = 0.0,
    delta: float = 1.0 / 60.0
) -> void:
    if world_point.x < basin_left or world_point.x >= basin_right:
        return

    var sy := surface_y_at(world_point.x)
    var half_size := maxf(size_px * 0.5, pixel_size)
    var touches_water := world_point.y + half_size >= sy and world_point.y - half_size <= bottom_y
    if not touches_water:
        return

    var speed := velocity_px_s.length()
    var radius := clampf(size_px * 0.64, 10.0, 82.0)

    if absf(velocity_px_s.y) > 22.0:
        var vertical_impulse := clampf(velocity_px_s.y * 0.062, -82.0, 94.0)
        add_disturbance(world_point.x, vertical_impulse, radius)

    if absf(velocity_px_s.x) > 26.0:
        var direction := signf(velocity_px_s.x)
        var size_gain := sqrt(maxf(size_px, 12.0) / 32.0)
        var wake_strength := clampf(absf(velocity_px_s.x) * 0.043 * size_gain, 3.0, 82.0)
        add_disturbance(
            world_point.x + direction * size_px * 0.35,
            wake_strength * 0.66,
            radius * 0.72
        )
        add_disturbance(
            world_point.x - direction * size_px * 0.48,
            -wake_strength,
            radius
        )

    if speed > 165.0 and absf(world_point.y - sy) < half_size * 1.20 and _foam.size() < max_foam_particles:
        var foam_probability := 1.0 - exp(-5.8 * delta)
        if _rng.randf() < foam_probability:
            _spawn_foam(
                world_point.x - signf(velocity_px_s.x) * size_px * 0.24,
                0.75
            )

    var bubble_rate_per_second := clampf(sinking_strength * 3.8, 0.0, 12.0)
    var bubble_probability := 1.0 - exp(-bubble_rate_per_second * delta)
    if (
        sinking_strength > 0.12
        and speed > 24.0
        and _bubbles.size() < max_bubbles
        and _rng.randf() < bubble_probability
    ):
        _bubbles.append({
            "pos": world_point + Vector2(
                _rng.randf_range(-size_px * 0.36, size_px * 0.36),
                _rng.randf_range(-4.0, 8.0)
            ),
            "rise": _rng.randf_range(18.0, 40.0),
            "drift": _rng.randf_range(-7.0, 7.0),
            "size": pixel_size * (0.5 if _rng.randf() < 0.65 else 1.0),
            "life": 5.0
        })

func _simulate_overflow(delta: float) -> void:
    if not overflow_enabled or _column_count < 4 or _water_volume_m3 <= 0.0:
        return

    var samples := clampi(overflow_edge_samples, 1, mini(16, int(_column_count / 2)))
    var left_surface := 0.0
    var right_surface := 0.0
    for i in range(samples):
        left_surface += _surface[i]
        right_surface += _surface[_column_count - 1 - i]
    left_surface /= float(samples)
    right_surface /= float(samples)

    _spill_over_edge(-1, left_surface, _resolved_left_rim_y(), delta)
    _spill_over_edge(1, right_surface, _resolved_right_rim_y(), delta)

func _spill_over_edge(side: int, local_surface_y: float, rim_y: float, delta: float) -> void:
    var head_px := rim_y - local_surface_y
    if head_px <= 0.25:
        return

    var head_m := head_px / pixels_per_meter
    var gravity_m_s2 := gravity_px_s2 / pixels_per_meter
    var opening_area_m2 := maxf(head_m * fluid_depth_m, 0.000001)

    # Torricelli-inspired open-edge discharge:
    # Q = Cd * A * sqrt(2 g h)
    var outflow_m3_s := (
        overflow_discharge_coefficient
        * opening_area_m2
        * sqrt(2.0 * gravity_m_s2 * head_m)
    )
    var out_volume := outflow_m3_s * delta
    out_volume = minf(
        out_volume,
        _water_volume_m3 * max_fraction_volume_spilled_per_frame
    )
    if out_volume <= 0.0:
        return

    _remove_water_volume(out_volume)

    var spray_volume := out_volume * overflow_spray_fraction
    var sheet_volume := out_volume - spray_volume
    var edge_x := basin_left if side < 0 else basin_right

    if sheet_volume > 0.0:
        _add_puddle_volume(
            edge_x + float(side) * puddle_cell_px * 1.25,
            sheet_volume
        )

    if spray_volume > 0.0:
        _spawn_overflow_spray(side, edge_x, rim_y, head_px, spray_volume)

    var impulse := clampf(head_px * 1.7, 4.0, 95.0)
    add_disturbance(
        edge_x + float(side) * pixel_size * 0.5,
        impulse * 0.34,
        maxf(16.0, head_px * 1.5)
    )

func _spawn_overflow_spray(
    side: int,
    edge_x: float,
    rim_y: float,
    head_px: float,
    total_volume_m3: float
) -> void:
    var available := max_splash_particles - _droplets.size()
    if available <= 0:
        _add_puddle_volume(edge_x + float(side) * puddle_cell_px, total_volume_m3)
        return

    var count := clampi(int(2.0 + head_px * 0.42), 2, mini(34, available))
    var per_particle := total_volume_m3 / float(count)
    var exit_speed := sqrt(
        2.0 * (gravity_px_s2 / pixels_per_meter) * (head_px / pixels_per_meter)
    ) * pixels_per_meter

    for _n in range(count):
        _droplets.append({
            "pos": Vector2(
                edge_x + float(side) * pixel_size * 0.5,
                rim_y - _rng.randf_range(0.0, minf(head_px, 14.0))
            ),
            "vel": Vector2(
                float(side) * _rng.randf_range(exit_speed * 0.45, exit_speed * 1.05),
                _rng.randf_range(-28.0, 42.0)
            ),
            "life": _rng.randf_range(0.65, 1.65),
            "size": pixel_size if _rng.randf() < 0.86 else pixel_size * 0.5,
            "amount_m3": per_particle
        })

func _remove_water_volume(amount_m3: float) -> void:
    _water_volume_m3 = maxf(0.0, _water_volume_m3 - maxf(amount_m3, 0.0))

func _return_water_volume(amount_m3: float) -> void:
    _water_volume_m3 += maxf(amount_m3, 0.0)

func _simulate_droplets(delta: float) -> void:
    for i in range(_droplets.size() - 1, -1, -1):
        var d := _droplets[i]
        d.vel.y += gravity_px_s2 * delta
        d.pos += d.vel * delta
        d.life -= delta

        var amount_m3 := float(d.get("amount_m3", 0.0))

        if (
            d.pos.x >= basin_left
            and d.pos.x < basin_right
            and d.pos.y >= surface_y_at(d.pos.x)
            and d.pos.y <= bottom_y
        ):
            add_disturbance(
                d.pos.x,
                clampf(d.vel.y * 0.09, -34.0, 52.0),
                10.0
            )
            _return_water_volume(amount_m3)
            _droplets.remove_at(i)
            continue

        if (
            d.pos.y >= platform_y
            and (d.pos.x < basin_left or d.pos.x >= basin_right)
            and d.pos.x >= spill_world_left
            and d.pos.x <= spill_world_right
        ):
            _add_puddle_volume(d.pos.x, amount_m3)
            _add_wetness(d.pos.x, clampf(amount_m3 * 4200.0, 0.08, 1.4))
            _droplets.remove_at(i)
            continue

        if (
            d.life <= 0.0
            or d.pos.y > bottom_y + 180.0
            or d.pos.x < spill_world_left - 80.0
            or d.pos.x > spill_world_right + 80.0
        ):
            # Volume that leaves the configured world is genuinely lost.
            _droplets.remove_at(i)
            continue

        _droplets[i] = d

func _simulate_bubbles(delta: float) -> void:
    for i in range(_bubbles.size() - 1, -1, -1):
        var b := _bubbles[i]
        b.pos.y -= b.rise * delta
        b.pos.x += b.drift * delta
        b.life -= delta

        if b.pos.x < basin_left or b.pos.x >= basin_right:
            _bubbles.remove_at(i)
            continue

        var sy := surface_y_at(b.pos.x)
        if b.pos.y <= sy + pixel_size:
            add_disturbance(b.pos.x, -8.5, 8.0)
            if _rng.randf() < 0.58:
                _spawn_foam(b.pos.x, 0.46)
            _bubbles.remove_at(i)
            continue

        if b.life <= 0.0:
            _bubbles.remove_at(i)
            continue

        _bubbles[i] = b

func _spawn_foam(world_x: float, intensity: float) -> void:
    if world_x < basin_left or world_x >= basin_right:
        return
    if _foam.size() >= max_foam_particles:
        return
    _foam.append({
        "x": snappedf(world_x, pixel_size),
        "life": foam_lifetime * _rng.randf_range(0.55, 1.15),
        "max_life": foam_lifetime,
        "drift": _rng.randf_range(-6.0, 6.0),
        "intensity": intensity
    })

func _simulate_foam(delta: float) -> void:
    for i in range(_foam.size() - 1, -1, -1):
        var f := _foam[i]
        f.life -= delta
        f.x += f.drift * delta
        f.x = clampf(f.x, basin_left, basin_right - pixel_size)
        if f.life <= 0.0:
            _foam.remove_at(i)
            continue
        _foam[i] = f

func _puddle_key(world_x: float) -> int:
    return int(floor(world_x / puddle_cell_px))

func _puddle_cell_center_x(key: int) -> float:
    return (float(key) + 0.5) * puddle_cell_px

func _is_outside_basin_x(world_x: float) -> bool:
    return world_x < basin_left or world_x >= basin_right

func _add_puddle_volume(world_x: float, amount_m3: float) -> void:
    if amount_m3 <= 0.0:
        return
    var x := clampf(world_x, spill_world_left, spill_world_right)
    if not _is_outside_basin_x(x):
        _return_water_volume(amount_m3)
        return
    var key := _puddle_key(x)
    _puddle_volume_m3[key] = float(_puddle_volume_m3.get(key, 0.0)) + amount_m3

func _puddle_cell_area_m2() -> float:
    return maxf((puddle_cell_px / pixels_per_meter) * fluid_depth_m, 0.000001)

func _puddle_depth_m(key: int) -> float:
    return float(_puddle_volume_m3.get(key, 0.0)) / _puddle_cell_area_m2()

func _simulate_puddles(delta: float) -> void:
    if _puddle_volume_m3.is_empty():
        return

    # A few small conservative passes approximate a 1D shallow sheet.
    var passes := 2
    var dt := delta / float(passes)
    for _pass in range(passes):
        _puddle_flow_pass(dt)
        _drain_edge_puddles_back_into_basin(dt)

    var area_m2 := _puddle_cell_area_m2()
    var evaporated_per_cell := puddle_evaporation_m_s * area_m2 * delta

    var keys := _puddle_volume_m3.keys()
    for key_variant in keys:
        var key := int(key_variant)
        var volume := float(_puddle_volume_m3.get(key, 0.0))
        if volume <= 0.0:
            _puddle_volume_m3.erase(key)
            continue

        volume = maxf(0.0, volume - evaporated_per_cell)

        if volume <= puddle_visual_threshold_m3:
            var x := _puddle_cell_center_x(key)
            _add_wetness(x, clampf(volume * 50000.0 + 0.10, 0.10, 1.25))
            _puddle_volume_m3.erase(key)
        else:
            _puddle_volume_m3[key] = volume

func _puddle_flow_pass(dt: float) -> void:
    var candidate_keys: Dictionary = {}
    for key_variant in _puddle_volume_m3.keys():
        var key := int(key_variant)
        candidate_keys[key] = true
        candidate_keys[key - 1] = true
        candidate_keys[key + 1] = true

    var sorted_keys: Array = candidate_keys.keys()
    sorted_keys.sort()

    var transfers: Dictionary = {}
    var cell_area := _puddle_cell_area_m2()
    var g := gravity_px_s2 / pixels_per_meter

    for key_variant in sorted_keys:
        var key := int(key_variant)
        var next_key := key + 1
        var x_a := _puddle_cell_center_x(key)
        var x_b := _puddle_cell_center_x(next_key)

        if x_a < spill_world_left or x_b > spill_world_right:
            continue
        if not _is_outside_basin_x(x_a) or not _is_outside_basin_x(x_b):
            continue
        # Do not transfer through the basin void from one side to the other.
        if (x_a < basin_left and x_b >= basin_right) or (x_b < basin_left and x_a >= basin_right):
            continue

        var volume_a := float(_puddle_volume_m3.get(key, 0.0))
        var volume_b := float(_puddle_volume_m3.get(next_key, 0.0))
        var depth_a := volume_a / cell_area
        var depth_b := volume_b / cell_area
        var head_diff := depth_a - depth_b

        if absf(head_diff) < 0.00001:
            continue

        var donor_key := key if head_diff > 0.0 else next_key
        var receiver_key := next_key if head_diff > 0.0 else key
        var donor_volume := volume_a if head_diff > 0.0 else volume_b
        if donor_volume <= 0.0:
            continue

        var hydraulic_depth := maxf(maxf(depth_a, depth_b), 0.0005)
        var flow_area := hydraulic_depth * fluid_depth_m
        var q_m3_s := (
            puddle_flow_coefficient
            * flow_area
            * sqrt(2.0 * g * absf(head_diff))
        )
        var transfer := minf(q_m3_s * dt, donor_volume * 0.42)
        transfer = minf(transfer, absf(volume_a - volume_b) * 0.48)
        if transfer <= 0.0:
            continue

        transfers[donor_key] = float(transfers.get(donor_key, 0.0)) - transfer
        transfers[receiver_key] = float(transfers.get(receiver_key, 0.0)) + transfer

    for key_variant in transfers.keys():
        var key := int(key_variant)
        var next_volume := float(_puddle_volume_m3.get(key, 0.0)) + float(transfers[key])
        if next_volume <= 0.000000001:
            _puddle_volume_m3.erase(key)
        else:
            _puddle_volume_m3[key] = next_volume

func _drain_edge_puddles_back_into_basin(delta: float) -> void:
    if _column_count == 0:
        return

    var left_key := _puddle_key(basin_left - puddle_cell_px * 0.5)
    var right_key := _puddle_key(basin_right + puddle_cell_px * 0.5)

    _drain_single_edge_puddle(left_key, basin_left + pixel_size, _resolved_left_rim_y(), delta)
    _drain_single_edge_puddle(right_key, basin_right - pixel_size, _resolved_right_rim_y(), delta)

func _drain_single_edge_puddle(key: int, inside_x: float, rim_y: float, delta: float) -> void:
    var volume := float(_puddle_volume_m3.get(key, 0.0))
    if volume <= 0.0:
        return

    var inside_surface := surface_y_at(inside_x)
    if inside_surface <= rim_y + 0.5:
        return

    # Outside water sitting beside an open hole falls back into the basin.
    var depth_m := _puddle_depth_m(key)
    var drop_m := maxf((inside_surface - rim_y) / pixels_per_meter, 0.001)
    var g := gravity_px_s2 / pixels_per_meter
    var q := (
        overflow_discharge_coefficient
        * fluid_depth_m
        * maxf(depth_m, 0.001)
        * sqrt(2.0 * g * drop_m)
    )
    var drained := minf(volume, q * delta)
    if drained <= 0.0:
        return

    var remaining := volume - drained
    if remaining <= 0.000000001:
        _puddle_volume_m3.erase(key)
    else:
        _puddle_volume_m3[key] = remaining
    _return_water_volume(drained)
    add_disturbance(inside_x, 10.0 + drained * 8000.0, 12.0)

func _wet_key(world_x: float) -> int:
    return int(floor(world_x / pixel_size))

func _add_wetness(world_x: float, amount: float) -> void:
    var key := _wet_key(world_x)
    var current := float(_wetness.get(key, 0.0))
    _wetness[key] = clampf(current + amount, 0.0, 2.5)
    if amount > 0.1:
        var neighbor := key + _rng.randi_range(-1, 1)
        _wetness[neighbor] = clampf(
            float(_wetness.get(neighbor, 0.0)) + amount * 0.35,
            0.0,
            2.5
        )

func _simulate_wetness(delta: float) -> void:
    var keys := _wetness.keys()
    for key_variant in keys:
        var key := int(key_variant)
        var saturation := float(_wetness[key])
        var rate := wetness_evaporation_per_second / maxf(1.0, saturation * 0.8)
        saturation -= rate * delta
        if saturation <= 0.01:
            _wetness.erase(key)
        else:
            _wetness[key] = saturation

func _draw() -> void:
    if _column_count == 0:
        return

    for i in range(_column_count):
        var x := basin_left + i * pixel_size
        var sy := snappedf(_surface[i], pixel_size)
        var h := maxf(0.0, bottom_y - sy)
        if h <= 0.0:
            continue

        draw_rect(Rect2(x, sy, pixel_size + 0.5, h), WATER_MID)
        draw_rect(
            Rect2(
                x,
                maxf(sy, bottom_y - 68.0),
                pixel_size + 0.5,
                minf(68.0, h)
            ),
            WATER_DEEP
        )
        draw_rect(Rect2(x, sy, pixel_size + 0.5, pixel_size), WATER_TOP)

        var curvature := 0.0
        if i > 0 and i < _column_count - 1:
            curvature = absf(_surface[i - 1] - 2.0 * _surface[i] + _surface[i + 1])
        var energy := absf(_velocity[i]) + curvature * 9.0
        if energy > 20.0 and i % 2 == 0:
            var c := CREST_GLINT
            c.a = clampf(0.32 + energy / 165.0, 0.32, 0.88)
            draw_rect(
                Rect2(
                    x,
                    snappedf(sy - pixel_size * 0.5, pixel_size * 0.5),
                    pixel_size * (2.0 if energy > 58.0 else 1.0),
                    maxf(1.0, pixel_size * 0.5)
                ),
                c
            )
        elif i % 7 == 0 and absf(_velocity[i]) < 14.0:
            draw_rect(
                Rect2(x, sy + pixel_size, pixel_size, pixel_size * 0.5),
                WATER_GLINT
            )

    for f in _foam:
        var alpha := clampf(
            float(f.life) / maxf(float(f.max_life), 0.001),
            0.0,
            1.0
        )
        var x := snappedf(float(f.x), pixel_size)
        var y := snappedf(surface_y_at(x) - pixel_size, pixel_size)
        var c := FOAM_COLOR
        c.a = alpha
        var width := pixel_size * clampf(float(f.intensity), 0.75, 2.0)
        draw_rect(Rect2(x, y, width, pixel_size * 0.5), c)

    for b in _bubbles:
        var s := float(b.size)
        var p: Vector2 = b.pos
        draw_rect(
            Rect2(
                snappedf(p.x, pixel_size * 0.5),
                snappedf(p.y, pixel_size * 0.5),
                s,
                s
            ),
            FOAM_COLOR,
            false,
            maxf(1.0, pixel_size * 0.25)
        )

    for d in _droplets:
        var p: Vector2 = d.pos
        var s := float(d.size)
        draw_rect(
            Rect2(
                snappedf(p.x, pixel_size * 0.5),
                snappedf(p.y, pixel_size * 0.5),
                s,
                s
            ),
            WATER_GLINT
        )

    _draw_puddles()
    _draw_wetness()

func _draw_puddles() -> void:
    var area_m2 := _puddle_cell_area_m2()
    for key_variant in _puddle_volume_m3.keys():
        var key := int(key_variant)
        var volume := float(_puddle_volume_m3[key])
        if volume <= 0.0:
            continue

        var x := float(key) * puddle_cell_px
        if not _is_outside_basin_x(x + puddle_cell_px * 0.5):
            continue

        var depth_m := volume / area_m2
        var depth_px := maxf(pixel_size * 0.5, depth_m * pixels_per_meter)
        var y := platform_y - depth_px
        draw_rect(
            Rect2(
                snappedf(x, pixel_size * 0.5),
                snappedf(y, pixel_size * 0.5),
                puddle_cell_px + 0.5,
                depth_px + 1.0
            ),
            WATER_TOP
        )
        if depth_px >= pixel_size * 1.5:
            draw_rect(
                Rect2(
                    snappedf(x, pixel_size * 0.5),
                    snappedf(y, pixel_size * 0.5),
                    puddle_cell_px + 0.5,
                    pixel_size * 0.5
                ),
                WATER_GLINT
            )

func _draw_wetness() -> void:
    for key_variant in _wetness.keys():
        var key := int(key_variant)
        var x := float(key) * pixel_size
        if x >= basin_left and x < basin_right:
            continue
        var saturation := float(_wetness[key])
        var c := WET_COLOR
        c.a = clampf(0.22 + saturation * 0.28, 0.22, 0.82)
        var thickness := pixel_size if saturation < 1.0 else pixel_size * 2.0
        draw_rect(
            Rect2(x, platform_y - 1.0, pixel_size, thickness),
            c
        )
