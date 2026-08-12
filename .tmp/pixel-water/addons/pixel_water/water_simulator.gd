class_name PixelWaterSimulator2D
extends Node2D

## Lightweight pixel water intended for Terraria-like side views.
## The main body is a 1D shallow-water/height-field surface, while splash droplets,
## bubbles, foam and wetness are sparse particles. This keeps the demo cheap enough
## for gameplay while still coupling to RigidBody2D objects with real-world-inspired forces.

@export_category("Container")
@export var basin_left: float = 170.0
@export var basin_right: float = 790.0
@export var rest_surface_y: float = 260.0
@export var bottom_y: float = 500.0
@export var platform_y: float = 240.0
@export var world_width: float = 960.0

@export_category("Pixel simulation")
@export_range(2.0, 8.0, 1.0) var pixel_size: float = 4.0
@export_range(20.0, 180.0, 1.0) var wave_speed_px_s: float = 78.0
@export_range(0.1, 8.0, 0.1) var wave_damping: float = 2.4
@export_range(0.0, 0.5, 0.01) var neighbor_viscosity: float = 0.10
@export var max_surface_displacement_px: float = 34.0

@export_category("Physical constants")
@export var water_density_kg_m3: float = 997.0
@export var gravity_px_s2: float = 980.0
@export var pixels_per_meter: float = 100.0
@export_range(0.05, 2.0, 0.01) var fluid_depth_m: float = 0.40

@export_category("Secondary effects")
@export var evaporation_per_second: float = 0.022
@export var foam_lifetime: float = 2.8
@export var max_splash_particles: int = 220
@export var max_bubbles: int = 90

var _surface: PackedFloat32Array
var _velocity: PackedFloat32Array
var _next_velocity: PackedFloat32Array
var _column_count: int = 0
var _droplets: Array[Dictionary] = []
var _bubbles: Array[Dictionary] = []
var _foam: Array[Dictionary] = []
var _wetness: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _foam_accumulator := 0.0
var _overflow_accumulator := 0.0
var _base_surface_y := 0.0
var _equilibrium_surface_y := 0.0
var _water_loss_height_px := 0.0
var _displacement_reports: Dictionary = {}

const WATER_TOP := Color("#17a9dc")
const WATER_MID := Color("#0b8fc9")
const WATER_DEEP := Color("#087ab2")
const WATER_GLINT := Color("#78dff1")
const FOAM_COLOR := Color("#d8f8fb")
const WET_COLOR := Color("#253b47")

func _ready() -> void:
    add_to_group("water_simulator")
    _rng.seed = 0x51A7E2
    _base_surface_y = rest_surface_y
    _equilibrium_surface_y = rest_surface_y
    _rebuild_columns()
    queue_redraw()

func _rebuild_columns() -> void:
    _column_count = maxi(4, int(ceil((basin_right - basin_left) / pixel_size)))
    _surface.resize(_column_count)
    _velocity.resize(_column_count)
    _next_velocity.resize(_column_count)
    for i in range(_column_count):
        _surface[i] = rest_surface_y
        _velocity[i] = 0.0
        _next_velocity[i] = 0.0

func _physics_process(delta: float) -> void:
    _update_equilibrium_surface()
    _simulate_surface(delta)
    _simulate_overflow(delta)
    _simulate_droplets(delta)
    _simulate_bubbles(delta)
    _simulate_foam(delta)
    _simulate_wetness(delta)
    queue_redraw()

func _simulate_surface(delta: float) -> void:
    # Discrete damped wave equation: d²y/dt² = c² * Laplacian(y) - damping * dy/dt.
    # The visual surface is intentionally quantized when drawn, not while simulated.
    var dx2 := pixel_size * pixel_size
    var c2 := wave_speed_px_s * wave_speed_px_s
    for i in range(_column_count):
        var left_y := _surface[maxi(i - 1, 0)]
        var center_y := _surface[i]
        var right_y := _surface[mini(i + 1, _column_count - 1)]
        var laplacian := (left_y + right_y - 2.0 * center_y) / dx2
        var acceleration := c2 * laplacian - wave_damping * _velocity[i]
        _next_velocity[i] = _velocity[i] + acceleration * delta

    for i in range(_column_count):
        var neighbor_v := (_next_velocity[maxi(i - 1, 0)] + _next_velocity[mini(i + 1, _column_count - 1)]) * 0.5
        _velocity[i] = lerpf(_next_velocity[i], neighbor_v, neighbor_viscosity)
        _surface[i] += _velocity[i] * delta
        _surface[i] = clampf(_surface[i], _equilibrium_surface_y - max_surface_displacement_px, _equilibrium_surface_y + max_surface_displacement_px)

    # Tiny global volume correction prevents long-term numerical drift.
    var average := 0.0
    for value in _surface:
        average += value
    average /= float(_column_count)
    var correction := (average - _equilibrium_surface_y) * minf(delta * 2.5, 1.0)
    for i in range(_column_count):
        _surface[i] -= correction

    _foam_accumulator += delta
    if _foam_accumulator > 0.08:
        _foam_accumulator = 0.0
        for i in range(1, _column_count - 1, 3):
            var turbulence := absf(_velocity[i]) + absf(_surface[i - 1] - 2.0 * _surface[i] + _surface[i + 1]) * 10.0
            if turbulence > 34.0 and _foam.size() < 140 and _rng.randf() < 0.18:
                _spawn_foam(basin_left + i * pixel_size, 0.65)

func report_displacement(body_id: int, displaced_volume_m3: float) -> void:
    _displacement_reports[body_id] = maxf(0.0, displaced_volume_m3)

func _update_equilibrium_surface() -> void:
    var total_displaced_m3 := 0.0
    for volume in _displacement_reports.values():
        total_displaced_m3 += float(volume)
    _displacement_reports.clear()
    var basin_width_m := maxf((basin_right - basin_left) / pixels_per_meter, 0.01)
    var rise_m := total_displaced_m3 / maxf(basin_width_m * fluid_depth_m, 0.001)
    var rise_px := rise_m * pixels_per_meter
    _equilibrium_surface_y = _base_surface_y + _water_loss_height_px - rise_px

func _remove_surface_water(amount_height_px: float) -> void:
    _water_loss_height_px = clampf(_water_loss_height_px + maxf(amount_height_px, 0.0), 0.0, maxf(0.0, bottom_y - _base_surface_y - 8.0))

func _return_surface_water(amount_height_px: float) -> void:
    _water_loss_height_px = maxf(0.0, _water_loss_height_px - maxf(amount_height_px, 0.0))

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

func register_object_impact(world_x: float, mass_kg: float, vertical_speed_px_s: float, displaced_volume_m3: float, object_width_px: float) -> void:
    if vertical_speed_px_s <= 20.0:
        return
    var speed_m_s := vertical_speed_px_s / pixels_per_meter
    var impact_energy_j := 0.5 * mass_kg * speed_m_s * speed_m_s
    var normalized := clampf(sqrt(maxf(impact_energy_j, 0.0)) * 0.85 + displaced_volume_m3 * 80.0, 0.0, 65.0)
    add_disturbance(world_x, normalized * 2.2, maxf(object_width_px * 0.85, 18.0))

    var count := clampi(int(2.0 + normalized * 0.65), 2, 38)
    for n in range(count):
        if _droplets.size() >= max_splash_particles:
            break
        var surface_y := surface_y_at(world_x)
        var spread := minf(110.0, 24.0 + normalized * 1.5)
        var launch := 70.0 + normalized * 4.0
        var vx := _rng.randf_range(-spread, spread)
        var vy := -_rng.randf_range(launch * 0.55, launch)
        var px := world_x + _rng.randf_range(-object_width_px * 0.35, object_width_px * 0.35)
        _droplets.append({
            "pos": Vector2(px, surface_y - pixel_size),
            "vel": Vector2(vx, vy),
            "life": _rng.randf_range(1.1, 2.5),
            "size": pixel_size if _rng.randf() < 0.78 else pixel_size * 0.5,
            "amount": _rng.randf_range(0.004, 0.016)
        })
        _remove_surface_water(float(_droplets[_droplets.size() - 1].amount))
    for n in range(clampi(int(normalized * 0.22), 1, 12)):
        _spawn_foam(world_x + _rng.randf_range(-object_width_px * 0.45, object_width_px * 0.45), 1.0)

func register_underwater_motion(world_point: Vector2, velocity_px_s: Vector2, size_px: float, sinking_strength: float = 0.0, delta: float = 1.0 / 60.0) -> void:
    if not contains_point(world_point):
        return
    var speed := velocity_px_s.length()
    if speed > 45.0:
        add_disturbance(world_point.x, velocity_px_s.y * 0.72 * delta, clampf(size_px * 0.55, 8.0, 34.0))
    var bubble_rate_per_second := clampf(sinking_strength * 3.2, 0.0, 10.0)
    var bubble_probability := 1.0 - exp(-bubble_rate_per_second * delta)
    if sinking_strength > 0.15 and speed > 28.0 and _bubbles.size() < max_bubbles and _rng.randf() < bubble_probability:
        _bubbles.append({
            "pos": world_point + Vector2(_rng.randf_range(-size_px * 0.35, size_px * 0.35), _rng.randf_range(-4.0, 8.0)),
            "rise": _rng.randf_range(18.0, 38.0),
            "drift": _rng.randf_range(-7.0, 7.0),
            "size": pixel_size * (0.5 if _rng.randf() < 0.65 else 1.0),
            "life": 5.0
        })

func _simulate_overflow(delta: float) -> void:
    _overflow_accumulator += delta
    if _overflow_accumulator < 0.055 or _column_count < 4:
        return
    _overflow_accumulator = 0.0

    var left_height := (_surface[0] + _surface[1] + _surface[2]) / 3.0
    if left_height < platform_y - 0.5 and _droplets.size() < max_splash_particles:
        var excess := platform_y - left_height
        var amount := clampf(excess * 0.003, 0.004, 0.035)
        _droplets.append({
            "pos": Vector2(basin_left - pixel_size * 0.5, platform_y - pixel_size),
            "vel": Vector2(-_rng.randf_range(30.0, 85.0), -_rng.randf_range(10.0, 48.0)),
            "life": 1.4,
            "size": pixel_size,
            "amount": amount
        })
        _remove_surface_water(amount)
        _velocity[0] *= 0.72
        _velocity[1] *= 0.82

    var r := _column_count - 1
    var right_height := (_surface[r] + _surface[r - 1] + _surface[r - 2]) / 3.0
    if right_height < platform_y - 0.5 and _droplets.size() < max_splash_particles:
        var excess_r := platform_y - right_height
        var amount_r := clampf(excess_r * 0.003, 0.004, 0.035)
        _droplets.append({
            "pos": Vector2(basin_right + pixel_size * 0.5, platform_y - pixel_size),
            "vel": Vector2(_rng.randf_range(30.0, 85.0), -_rng.randf_range(10.0, 48.0)),
            "life": 1.4,
            "size": pixel_size,
            "amount": amount_r
        })
        _remove_surface_water(amount_r)
        _velocity[r] *= 0.72
        _velocity[r - 1] *= 0.82

func _simulate_droplets(delta: float) -> void:
    for i in range(_droplets.size() - 1, -1, -1):
        var d := _droplets[i]
        d.vel.y += gravity_px_s2 * delta
        d.pos += d.vel * delta
        d.life -= delta

        if d.pos.x >= basin_left and d.pos.x < basin_right and d.pos.y >= surface_y_at(d.pos.x):
            add_disturbance(d.pos.x, clampf(d.vel.y * 0.08, -30.0, 45.0), 10.0)
            _return_surface_water(float(d.amount))
            _droplets.remove_at(i)
            continue

        if d.pos.y >= platform_y and (d.pos.x < basin_left or d.pos.x >= basin_right) and d.pos.x >= 0.0 and d.pos.x < world_width:
            _add_wetness(d.pos.x, float(d.amount) * 14.0)
            _droplets.remove_at(i)
            continue

        if d.life <= 0.0 or d.pos.y > bottom_y + 120.0 or d.pos.x < -40.0 or d.pos.x > world_width + 40.0:
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
            add_disturbance(b.pos.x, -8.0, 8.0)
            if _rng.randf() < 0.55:
                _spawn_foam(b.pos.x, 0.45)
            _bubbles.remove_at(i)
            continue
        if b.life <= 0.0:
            _bubbles.remove_at(i)
            continue
        _bubbles[i] = b

func _spawn_foam(world_x: float, intensity: float) -> void:
    if world_x < basin_left or world_x >= basin_right:
        return
    _foam.append({
        "x": snappedf(world_x, pixel_size),
        "life": foam_lifetime * _rng.randf_range(0.55, 1.15),
        "max_life": foam_lifetime,
        "drift": _rng.randf_range(-5.0, 5.0),
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

func _wet_key(world_x: float) -> int:
    return int(floor(world_x / pixel_size))

func _add_wetness(world_x: float, amount: float) -> void:
    var key := _wet_key(world_x)
    var current := float(_wetness.get(key, 0.0))
    _wetness[key] = clampf(current + amount, 0.0, 2.5)
    if amount > 0.1:
        var neighbor := key + (_rng.randi_range(-1, 1))
        _wetness[neighbor] = clampf(float(_wetness.get(neighbor, 0.0)) + amount * 0.35, 0.0, 2.5)

func _simulate_wetness(delta: float) -> void:
    var keys := _wetness.keys()
    for key in keys:
        var saturation := float(_wetness[key])
        # Larger puddles evaporate more slowly per unit water.
        var rate := evaporation_per_second / maxf(1.0, saturation * 0.8)
        saturation -= rate * delta
        if saturation <= 0.01:
            _wetness.erase(key)
        else:
            _wetness[key] = saturation

func _draw() -> void:
    if _column_count == 0:
        return

    # Water body: one vertical pixel column each. The top edge is quantized to the pixel grid.
    for i in range(_column_count):
        var x := basin_left + i * pixel_size
        var sy := snappedf(_surface[i], pixel_size)
        var h := maxf(0.0, bottom_y - sy)
        if h <= 0.0:
            continue
        draw_rect(Rect2(x, sy, pixel_size + 0.5, h), WATER_MID)
        draw_rect(Rect2(x, maxf(sy, bottom_y - 68.0), pixel_size + 0.5, minf(68.0, h)), WATER_DEEP)
        draw_rect(Rect2(x, sy, pixel_size + 0.5, pixel_size), WATER_TOP)
        if i % 7 == 0 and absf(_velocity[i]) < 16.0:
            draw_rect(Rect2(x, sy + pixel_size, pixel_size, pixel_size * 0.5), WATER_GLINT)

    for f in _foam:
        var alpha := clampf(float(f.life) / maxf(float(f.max_life), 0.001), 0.0, 1.0)
        var x := snappedf(float(f.x), pixel_size)
        var y := snappedf(surface_y_at(x) - pixel_size, pixel_size)
        var c := FOAM_COLOR
        c.a = alpha
        draw_rect(Rect2(x, y, pixel_size, pixel_size * 0.5), c)

    for b in _bubbles:
        var s := float(b.size)
        var p: Vector2 = b.pos
        draw_rect(Rect2(snappedf(p.x, pixel_size * 0.5), snappedf(p.y, pixel_size * 0.5), s, s), FOAM_COLOR, false, maxf(1.0, pixel_size * 0.25))

    for d in _droplets:
        var p: Vector2 = d.pos
        var s := float(d.size)
        draw_rect(Rect2(snappedf(p.x, pixel_size * 0.5), snappedf(p.y, pixel_size * 0.5), s, s), WATER_GLINT)

    for key in _wetness.keys():
        var x := float(key) * pixel_size
        if x >= basin_left and x < basin_right:
            continue
        var saturation := float(_wetness[key])
        var c := WET_COLOR
        c.a = clampf(0.22 + saturation * 0.28, 0.22, 0.82)
        var thickness := pixel_size if saturation < 1.0 else pixel_size * 2.0
        draw_rect(Rect2(x, platform_y - 1.0, pixel_size, thickness), c)
