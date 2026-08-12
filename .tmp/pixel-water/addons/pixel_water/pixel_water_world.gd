class_name PixelWaterWorld2D
extends Node2D

## Unified 1D shallow-water world for side-view pixel games.
##
## Every horizontal cell belongs to the same conservative solver whether it is
## inside a deep basin, on a shallow platform, or inside another pit. Terrain
## height is the only thing that separates regions. There is no special puddle
## solver and no invisible basin-edge barrier.
##
## The numerical core is a finite-volume shallow-water approximation with
## hydrostatic reconstruction at terrain steps, CFL sub-stepping, wet/dry cells,
## bottom/turbulent friction, conservative transported spray, object displacement,
## and physically based buoyancy hooks.

@export_category("World grid")
@export var world_left: float = -160.0
@export var world_right: float = 1320.0
@export var default_floor_y: float = 240.0
@export_range(2.0, 10.0, 1.0) var cell_size_px: float = 4.0
@export var pixels_per_meter: float = 100.0
@export_range(0.05, 1.0, 0.01) var fluid_depth_m: float = 0.30

@export_category("Physical constants")
@export var water_density_kg_m3: float = 997.0
@export var gravity_px_s2: float = 980.0

@export_category("Shallow-water solver")
@export_range(0.15, 0.49, 0.01) var cfl_number: float = 0.36
@export_range(2, 32, 1) var max_substeps: int = 14
@export_range(0.0001, 0.03, 0.0001) var dry_depth_m: float = 0.0015
@export_range(0.0, 4.0, 0.01) var linear_flow_damping: float = 0.82
@export_range(0.0, 2.0, 0.01) var quadratic_flow_damping: float = 0.18
@export_range(0.0, 0.8, 0.01) var momentum_neighbor_mix: float = 0.008
@export_range(0.0, 0.20, 0.005) var rest_velocity_m_s: float = 0.035
@export_range(0.0, 3.0, 0.05) var rest_surface_delta_px: float = 0.55
@export_range(4.0, 40.0, 1.0) var extreme_surface_delta_px: float = 12.0
@export_range(1, 4, 1) var extreme_relax_passes: int = 2
@export_range(0.05, 1.0, 0.05) var extreme_relax_fraction: float = 0.70
@export_range(4.0, 80.0, 1.0) var waterfall_drop_threshold_px: float = 12.0
@export_range(0.5, 20.0, 0.5) var max_flow_speed_m_s: float = 4.5
@export_range(0.0, 0.02, 0.0001) var displacement_smoothing: float = 0.0025

@export_category("Secondary effects")
@export var foam_lifetime: float = 2.25
@export var max_splash_particles: int = 140
@export var max_bubbles: int = 64
@export var max_foam_particles: int = 100
@export_range(0.0, 1.0, 0.001) var spray_volume_fraction: float = 0.008

var _cell_count: int = 0
var _floor_y: PackedFloat32Array
var _depth_m: PackedFloat32Array
var _momentum_m2_s: PackedFloat32Array
var _next_depth_m: PackedFloat32Array
var _next_momentum_m2_s: PackedFloat32Array
var _initial_depth_m: PackedFloat32Array
var _solid_fill_m: PackedFloat32Array
var _previous_solid_fill_m: PackedFloat32Array

var _mass_flux: PackedFloat32Array
var _momentum_flux_left: PackedFloat32Array
var _momentum_flux_right: PackedFloat32Array
var _donor_scale: PackedFloat32Array
var _surface_relax_delta: PackedFloat32Array

var _displacement_reports: Dictionary = {}
var _droplets: Array[Dictionary] = []
var _bubbles: Array[Dictionary] = []
var _foam: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _foam_accumulator := 0.0
var _waterfall_pending: Dictionary = {}
var _configured := false

const WATER_TOP := Color("#17a9dc")
const WATER_MID := Color("#0b8fc9")
const WATER_DEEP := Color("#087ab2")
const WATER_GLINT := Color("#78dff1")
const CREST_GLINT := Color("#a8f4ff")
const FOAM_COLOR := Color("#d8f8fb")

func _ready() -> void:
    add_to_group("pixel_water_world")
    add_to_group("pixel_water_container")
    add_to_group("water_simulator")
    _rng.seed = 0x51A7E2
    _rebuild_grid()
    if not _configured:
        configure_world([], [])
    queue_redraw()

func configure_world(
    floor_segments: Array[Dictionary],
    water_regions: Array[Dictionary]
) -> void:
    _rebuild_grid()

    for i in range(_cell_count):
        _floor_y[i] = default_floor_y
        _depth_m[i] = 0.0
        _momentum_m2_s[i] = 0.0
        _solid_fill_m[i] = 0.0
        _previous_solid_fill_m[i] = 0.0

    for segment in floor_segments:
        var left := float(segment.get("left", world_left))
        var right := float(segment.get("right", world_right))
        var floor_y := float(segment.get("floor_y", default_floor_y))
        _paint_floor_segment(left, right, floor_y)

    for region in water_regions:
        var left := float(region.get("left", world_left))
        var right := float(region.get("right", world_right))
        var surface_y := float(region.get("surface_y", default_floor_y))
        _fill_water_region(left, right, surface_y)

    _initial_depth_m = _depth_m.duplicate()
    _displacement_reports.clear()
    _droplets.clear()
    _bubbles.clear()
    _foam.clear()
    _configured = true
    queue_redraw()

func _rebuild_grid() -> void:
    _cell_count = maxi(
        4,
        int(ceil((world_right - world_left) / maxf(cell_size_px, 1.0)))
    )

    _floor_y.resize(_cell_count)
    _depth_m.resize(_cell_count)
    _momentum_m2_s.resize(_cell_count)
    _next_depth_m.resize(_cell_count)
    _next_momentum_m2_s.resize(_cell_count)
    _solid_fill_m.resize(_cell_count)
    _previous_solid_fill_m.resize(_cell_count)

    _mass_flux.resize(maxi(1, _cell_count - 1))
    _momentum_flux_left.resize(maxi(1, _cell_count - 1))
    _momentum_flux_right.resize(maxi(1, _cell_count - 1))
    _donor_scale.resize(_cell_count)
    _surface_relax_delta.resize(_cell_count)

    for i in range(_cell_count):
        _floor_y[i] = default_floor_y
        _depth_m[i] = 0.0
        _momentum_m2_s[i] = 0.0
        _next_depth_m[i] = 0.0
        _next_momentum_m2_s[i] = 0.0
        _solid_fill_m[i] = 0.0
        _previous_solid_fill_m[i] = 0.0

func _paint_floor_segment(left: float, right: float, floor_y: float) -> void:
    var first := _index_at(left)
    var last := _index_at(right - 0.001)
    for i in range(first, last + 1):
        _floor_y[i] = floor_y

func _fill_water_region(left: float, right: float, surface_y: float) -> void:
    var first := _index_at(left)
    var last := _index_at(right - 0.001)
    for i in range(first, last + 1):
        var depth_px := maxf(0.0, _floor_y[i] - surface_y)
        _depth_m[i] = maxf(_depth_m[i], depth_px / pixels_per_meter)

func reset_water() -> void:
    if _initial_depth_m.size() != _cell_count:
        return
    _depth_m = _initial_depth_m.duplicate()
    for i in range(_cell_count):
        _momentum_m2_s[i] = 0.0
        _solid_fill_m[i] = 0.0
        _previous_solid_fill_m[i] = 0.0
    _displacement_reports.clear()
    _droplets.clear()
    _bubbles.clear()
    _foam.clear()
    _waterfall_pending.clear()
    queue_redraw()

func _physics_process(delta: float) -> void:
    if _cell_count < 3:
        return

    _rebuild_solid_displacement()

    var g := gravity_px_s2 / pixels_per_meter
    var dx := cell_size_px / pixels_per_meter
    var max_signal_speed := 0.01

    for i in range(_cell_count):
        var h := maxf(_depth_m[i], 0.0)
        if h <= dry_depth_m:
            continue
        var u := _velocity_at_index(i)
        max_signal_speed = maxf(
            max_signal_speed,
            absf(u) + sqrt(maxf(g * h, 0.0))
        )

    var stable_dt := cfl_number * dx / max_signal_speed
    var substeps := clampi(
        int(ceil(delta / maxf(stable_dt, 0.0002))),
        1,
        max_substeps
    )
    var dt := delta / float(substeps)
    _waterfall_pending.clear()

    for _step in range(substeps):
        _shallow_water_substep(dt)

    _relax_extreme_surface_columns()
    _flush_waterfalls()
    _simulate_droplets(delta)
    _simulate_bubbles(delta)
    _simulate_foam(delta)
    _emit_turbulence_foam(delta)
    queue_redraw()

func _shallow_water_substep(dt: float) -> void:
    var g := gravity_px_s2 / pixels_per_meter
    var dx := cell_size_px / pixels_per_meter

    # Hydrostatic reconstruction at each terrain face. The same interface flux is
    # used everywhere: deep basin, rim, shallow puddle and second basin.
    for face in range(_cell_count - 1):
        var left := face
        var right := face + 1

        var h_l_raw := maxf(_depth_m[left], 0.0)
        var h_r_raw := maxf(_depth_m[right], 0.0)
        var solid_l := maxf(_solid_fill_m[left], 0.0)
        var solid_r := maxf(_solid_fill_m[right], 0.0)

        var z_l := -_floor_y[left] / pixels_per_meter
        var z_r := -_floor_y[right] / pixels_per_meter

        # Displaced object volume is represented as a temporary rise of the
        # local effective bed. This preserves water mass while reducing storage
        # capacity, which is the 1D analogue of an immersed solid occupying space.
        var z_l_effective := z_l + solid_l
        var z_r_effective := z_r + solid_r
        var eta_l := z_l_effective + h_l_raw
        var eta_r := z_r_effective + h_r_raw
        var z_star := maxf(z_l_effective, z_r_effective)

        var h_l := maxf(0.0, eta_l - z_star)
        var h_r := maxf(0.0, eta_r - z_star)

        # Reconstructed hydraulic depth can include displaced solid volume. Actual
        # transported mass is still clamped to available water after the update.
        var u_l := _velocity_at_index(left) if h_l_raw > dry_depth_m else 0.0
        var u_r := _velocity_at_index(right) if h_r_raw > dry_depth_m else 0.0

        var q_l := h_l * u_l
        var q_r := h_r * u_r
        var f_l_mass := q_l
        var f_r_mass := q_r
        var f_l_momentum := q_l * u_l + 0.5 * g * h_l * h_l
        var f_r_momentum := q_r * u_r + 0.5 * g * h_r * h_r

        var wave_l := absf(u_l) + sqrt(maxf(g * h_l, 0.0))
        var wave_r := absf(u_r) + sqrt(maxf(g * h_r, 0.0))
        var max_wave_speed: float = maxf(wave_l, wave_r)

        var mass_flux := (
            0.5 * (f_l_mass + f_r_mass)
            - 0.5 * max_wave_speed * (h_r - h_l)
        )
        var momentum_flux := (
            0.5 * (f_l_momentum + f_r_momentum)
            - 0.5 * max_wave_speed * (q_r - q_l)
        )

        # Hydrostatic source corrections keep a still lake still across floor steps.
        _mass_flux[face] = mass_flux
        _momentum_flux_left[face] = (
            momentum_flux
            + 0.5 * g * (h_l_raw * h_l_raw - h_l * h_l)
        )
        _momentum_flux_right[face] = (
            momentum_flux
            + 0.5 * g * (h_r_raw * h_r_raw - h_r * h_r)
        )

    # Positivity-preserving draining limiter. A face may never remove more
    # water from its donor cell than that cell actually owns during this step.
    # Without this, clamping negative depth to zero can create water in the
    # receiver and is the main source of runaway vertical columns.
    _limit_outflow_fluxes(dt, dx)

    # A shallow-water height field cannot show ballistic free-fall at a cliff.
    # Route flux over a real downward terrain step into conservative droplets
    # until the receiving basin rises high enough to submerge the lip.
    _route_waterfall_fluxes(dt, dx)

    for i in range(_cell_count):
        var h := maxf(_depth_m[i], 0.0)
        var hu := _momentum_m2_s[i]

        var incoming_mass := 0.0
        var outgoing_mass := 0.0
        var incoming_momentum := 0.0
        var outgoing_momentum := 0.0

        if i > 0:
            incoming_mass = _mass_flux[i - 1]
            incoming_momentum = _momentum_flux_right[i - 1]
        if i < _cell_count - 1:
            outgoing_mass = _mass_flux[i]
            outgoing_momentum = _momentum_flux_left[i]

        var h_new := h - (dt / dx) * (outgoing_mass - incoming_mass)
        var hu_new := hu - (dt / dx) * (outgoing_momentum - incoming_momentum)

        # Wet/dry positivity fix. If a numerical flux attempts to remove more water
        # than the cell owns, the cell dries instead of becoming negative.
        if h_new < 0.0:
            h_new = 0.0
            hu_new = 0.0

        if h_new <= dry_depth_m:
            if h_new < dry_depth_m * 0.35:
                h_new = 0.0
                hu_new = 0.0
        else:
            var u := hu_new / h_new

            # Macro-scale water does not stop because of gravity alone. Bottom
            # friction and turbulence dissipate wave energy while gravity supplies
            # the restoring force through the shallow-water pressure term above.
            u *= exp(-linear_flow_damping * dt)
            var nonlinear_loss := (
                quadratic_flow_damping
                * absf(u)
                * u
                / maxf(h_new, 0.02)
                * dt
            )
            u -= nonlinear_loss
            u = clampf(u, -max_flow_speed_m_s, max_flow_speed_m_s)

            if absf(u) <= rest_velocity_m_s and _surface_is_locally_calm(i):
                u = 0.0

            hu_new = u * h_new

        _next_depth_m[i] = h_new
        _next_momentum_m2_s[i] = hu_new

    if momentum_neighbor_mix > 0.0:
        for i in range(1, _cell_count - 1):
            var neighbor := (
                _next_momentum_m2_s[i - 1]
                + _next_momentum_m2_s[i + 1]
            ) * 0.5
            _next_momentum_m2_s[i] = lerpf(
                _next_momentum_m2_s[i],
                neighbor,
                momentum_neighbor_mix
            )

    for i in range(_cell_count):
        _depth_m[i] = maxf(0.0, _next_depth_m[i])
        _momentum_m2_s[i] = _next_momentum_m2_s[i]

func _relax_extreme_surface_columns() -> void:
    if _cell_count < 2 or extreme_relax_passes <= 0:
        return

    var threshold_m := extreme_surface_delta_px / pixels_per_meter

    for _pass in range(extreme_relax_passes):
        _surface_relax_delta.fill(0.0)
        var touched := false

        for face in range(_cell_count - 1):
            var left := face
            var right := face + 1
            var z_l := -_floor_y[left] / pixels_per_meter + maxf(_solid_fill_m[left], 0.0)
            var z_r := -_floor_y[right] / pixels_per_meter + maxf(_solid_fill_m[right], 0.0)
            var eta_l := z_l + maxf(_depth_m[left], 0.0)
            var eta_r := z_r + maxf(_depth_m[right], 0.0)
            var diff := eta_l - eta_r

            if absf(diff) <= threshold_m:
                continue

            var donor := left if diff > 0.0 else right
            var receiver := right if diff > 0.0 else left
            var donor_z := z_l if donor == left else z_r
            var receiver_z := z_r if receiver == right else z_l
            var donor_eta := eta_l if donor == left else eta_r
            var receiver_eta := eta_r if receiver == right else eta_l
            var crest_z := maxf(donor_z, receiver_z)

            if donor_eta <= crest_z + dry_depth_m:
                continue

            var excess_head := maxf(0.0, donor_eta - receiver_eta - threshold_m)
            var above_lip := maxf(0.0, donor_eta - crest_z)
            var transfer := minf(
                excess_head * 0.5 * extreme_relax_fraction,
                above_lip * extreme_relax_fraction
            )
            transfer = minf(
                transfer,
                maxf(_depth_m[donor] - dry_depth_m * 0.25, 0.0)
            )
            if transfer <= 0.000001:
                continue

            _surface_relax_delta[donor] -= transfer
            _surface_relax_delta[receiver] += transfer
            touched = true

        if not touched:
            break

        for i in range(_cell_count):
            var delta_h := _surface_relax_delta[i]
            if absf(delta_h) <= 0.0000001:
                continue
            var old_h := maxf(_depth_m[i], 0.0)
            var old_u := _velocity_at_index(i)
            _depth_m[i] = maxf(0.0, old_h + delta_h)
            _momentum_m2_s[i] = _depth_m[i] * old_u * 0.55

func _limit_outflow_fluxes(dt: float, dx: float) -> void:
    if dt <= 0.0 or dx <= 0.0:
        return

    _donor_scale.fill(1.0)

    for i in range(_cell_count):
        var outgoing := 0.0
        if i > 0:
            outgoing += maxf(-_mass_flux[i - 1], 0.0)
        if i < _cell_count - 1:
            outgoing += maxf(_mass_flux[i], 0.0)

        if outgoing <= 0.0000001:
            continue

        var owned_depth := maxf(_depth_m[i], 0.0)
        var max_outgoing_flux := owned_depth * dx / dt
        _donor_scale[i] = clampf(
            max_outgoing_flux / outgoing,
            0.0,
            1.0
        )

    for face in range(_cell_count - 1):
        var flux := _mass_flux[face]
        if absf(flux) <= 0.0000001:
            continue
        var donor := face if flux > 0.0 else face + 1
        var scale := _donor_scale[donor]
        if scale >= 0.99999:
            continue
        _mass_flux[face] *= scale
        _momentum_flux_left[face] *= scale
        _momentum_flux_right[face] *= scale

func _route_waterfall_fluxes(dt: float, dx: float) -> void:
    if dt <= 0.0 or dx <= 0.0:
        return

    for face in range(_cell_count - 1):
        var flux := _mass_flux[face]
        if absf(flux) <= 0.0000001:
            continue

        var donor := face if flux > 0.0 else face + 1
        var receiver := face + 1 if flux > 0.0 else face
        var donor_floor := _floor_y[donor]
        var receiver_floor := _floor_y[receiver]
        var drop_px := receiver_floor - donor_floor
        if drop_px < waterfall_drop_threshold_px:
            continue

        var receiver_has_water := _depth_m[receiver] > dry_depth_m
        if receiver_has_water:
            var receiver_surface := _surface_y_index(receiver)
            if receiver_surface <= donor_floor + cell_size_px * 0.5:
                continue

        var transfer_depth := absf(flux) * dt / dx
        transfer_depth = minf(
            transfer_depth,
            maxf(_depth_m[donor] - dry_depth_m * 0.25, 0.0)
        )
        if transfer_depth <= 0.0:
            _mass_flux[face] = 0.0
            _momentum_flux_left[face] = 0.0
            _momentum_flux_right[face] = 0.0
            continue

        var donor_u := _velocity_at_index(donor)
        _depth_m[donor] = maxf(0.0, _depth_m[donor] - transfer_depth)
        _momentum_m2_s[donor] = _depth_m[donor] * donor_u

        var volume_m3 := transfer_depth * dx * fluid_depth_m
        var face_x := world_left + float(face + 1) * cell_size_px
        var key := face
        var packet: Dictionary = _waterfall_pending.get(key, {})
        if packet.is_empty():
            packet = {
                "volume_m3": 0.0,
                "x": face_x,
                "y": donor_floor - cell_size_px * 0.35,
                "vx_px_s": donor_u * pixels_per_meter
            }
        packet["volume_m3"] = float(packet["volume_m3"]) + volume_m3
        packet["vx_px_s"] = lerpf(
            float(packet["vx_px_s"]),
            donor_u * pixels_per_meter,
            0.35
        )
        _waterfall_pending[key] = packet

        _mass_flux[face] = 0.0
        _momentum_flux_left[face] = 0.0
        _momentum_flux_right[face] = 0.0

func _flush_waterfalls() -> void:
    for key in _waterfall_pending.keys():
        var packet: Dictionary = _waterfall_pending[key]
        var amount := maxf(float(packet.get("volume_m3", 0.0)), 0.0)
        if amount <= 0.0:
            continue

        var liters := amount * 1000.0
        var count := clampi(
            int(ceil(1.0 + sqrt(maxf(liters, 0.0)) * 1.6)),
            1,
            6
        )
        emit_water_stream(
            Vector2(
                float(packet.get("x", 0.0)),
                float(packet.get("y", 0.0))
            ),
            amount,
            Vector2(float(packet.get("vx_px_s", 0.0)), 24.0),
            count
        )
    _waterfall_pending.clear()

func _surface_is_locally_calm(i: int) -> bool:
    var sy := _surface_y_index(i)
    if i > 0 and _depth_m[i - 1] > dry_depth_m:
        if absf(_surface_y_index(i - 1) - sy) > rest_surface_delta_px:
            return false
    if i < _cell_count - 1 and _depth_m[i + 1] > dry_depth_m:
        if absf(_surface_y_index(i + 1) - sy) > rest_surface_delta_px:
            return false
    return true

func _rebuild_solid_displacement() -> void:
    var frame := Engine.get_physics_frames()
    for i in range(_cell_count):
        _previous_solid_fill_m[i] = _solid_fill_m[i]
        _solid_fill_m[i] = 0.0

    var stale: Array = []
    var cell_width_m := cell_size_px / pixels_per_meter
    var cell_plan_area_m2 := maxf(cell_width_m * fluid_depth_m, 0.000001)

    for key in _displacement_reports.keys():
        var report: Dictionary = _displacement_reports[key]
        if frame - int(report.get("frame", frame)) > 3:
            stale.append(key)
            continue

        var volume_m3 := maxf(0.0, float(report.get("volume_m3", 0.0)))
        if volume_m3 <= 0.0:
            continue

        var center_x := float(report.get("x", 0.0))
        var width_px := maxf(float(report.get("width_px", cell_size_px)), cell_size_px)
        var radius_px := maxf(width_px * 0.55, cell_size_px)
        var first := _index_at(center_x - radius_px)
        var last := _index_at(center_x + radius_px)

        var weight_sum := 0.0
        for i in range(first, last + 1):
            var x := _cell_center_x(i)
            var normalized := absf(x - center_x) / maxf(radius_px, 0.001)
            var w := maxf(0.0, 1.0 - normalized)
            weight_sum += w * w

        if weight_sum <= 0.0:
            continue

        for i in range(first, last + 1):
            var x := _cell_center_x(i)
            var normalized := absf(x - center_x) / maxf(radius_px, 0.001)
            var w := maxf(0.0, 1.0 - normalized)
            w *= w
            _solid_fill_m[i] += volume_m3 * (w / weight_sum) / cell_plan_area_m2

    for key in stale:
        _displacement_reports.erase(key)

    # Soften only tiny sample jitter; large displacement changes remain immediate.
    if displacement_smoothing > 0.0:
        for i in range(_cell_count):
            var delta := _solid_fill_m[i] - _previous_solid_fill_m[i]
            if absf(delta) < displacement_smoothing:
                _solid_fill_m[i] = lerpf(
                    _previous_solid_fill_m[i],
                    _solid_fill_m[i],
                    0.55
                )

func report_displacement(
    body_id: int,
    world_x: float,
    object_width_px: float,
    displaced_volume_m3: float
) -> void:
    _displacement_reports[body_id] = {
        "x": world_x,
        "width_px": maxf(object_width_px, cell_size_px),
        "volume_m3": maxf(displaced_volume_m3, 0.0),
        "frame": Engine.get_physics_frames()
    }

func clear_displacement(body_id: int) -> void:
    _displacement_reports.erase(body_id)

func surface_y_at(world_x: float) -> float:
    var i := _index_at(world_x)
    return _surface_y_index(i)

func floor_y_at(world_x: float) -> float:
    return _floor_y[_index_at(world_x)]

func depth_m_at(world_x: float) -> float:
    return maxf(_depth_m[_index_at(world_x)], 0.0)

func contains_point(world_point: Vector2) -> bool:
    if world_point.x < world_left or world_point.x >= world_right:
        return false
    var i := _index_at(world_point.x)
    if _depth_m[i] <= dry_depth_m:
        return false
    var sy := _surface_y_index(i)
    return world_point.y >= sy and world_point.y <= _floor_y[i] + 0.5

func depth_at(world_point: Vector2) -> float:
    if not contains_point(world_point):
        return 0.0
    return maxf(0.0, world_point.y - surface_y_at(world_point.x))

func water_volume_liters() -> float:
    return total_water_volume_m3() * 1000.0

func total_water_volume_m3() -> float:
    var cell_width_m := cell_size_px / pixels_per_meter
    var total := 0.0
    for h in _depth_m:
        total += maxf(float(h), 0.0) * cell_width_m * fluid_depth_m
    for droplet in _droplets:
        total += maxf(float(droplet.get("amount_m3", 0.0)), 0.0)
    return total

func volume_liters_in_range(left_x: float, right_x: float) -> float:
    var first := _index_at(left_x)
    var last := _index_at(right_x - 0.001)
    var cell_width_m := cell_size_px / pixels_per_meter
    var total := 0.0
    for i in range(first, last + 1):
        total += maxf(_depth_m[i], 0.0) * cell_width_m * fluid_depth_m
    return total * 1000.0

func extract_water_at(
    world_x: float,
    requested_volume_m3: float,
    radius_px: float = 18.0
) -> float:
    var requested := maxf(requested_volume_m3, 0.0)
    if requested <= 0.0:
        return 0.0

    var center := _index_at(world_x)
    var radius_cells := maxi(1, int(ceil(radius_px / cell_size_px)))
    var first := maxi(0, center - radius_cells)
    var last := mini(_cell_count - 1, center + radius_cells)
    var cell_width_m := cell_size_px / pixels_per_meter
    var cell_area := maxf(cell_width_m * fluid_depth_m, 0.000001)

    var capacities: Array[float] = []
    var capacity_sum := 0.0
    for i in range(first, last + 1):
        var available := maxf(_depth_m[i], 0.0) * cell_area
        var distance := absf(float(i - center)) / float(radius_cells + 1)
        var kernel := 0.38 + 0.62 * maxf(0.0, 1.0 - distance)
        var capacity := available * 0.30 * kernel
        capacities.append(capacity)
        capacity_sum += capacity

    var target := minf(requested, capacity_sum)
    if target <= 0.0:
        return 0.0

    var extracted := 0.0
    var cursor := 0
    for i in range(first, last + 1):
        var capacity := capacities[cursor]
        cursor += 1
        if capacity <= 0.0:
            continue
        var take := target * capacity / maxf(capacity_sum, 0.000001)
        take = minf(take, capacity)
        var old_h := maxf(_depth_m[i], 0.0)
        var old_u := _velocity_at_index(i)
        var dh := take / cell_area
        _depth_m[i] = maxf(0.0, old_h - dh)
        _momentum_m2_s[i] = _depth_m[i] * old_u
        extracted += take

    return extracted

func deposit_water_at(
    world_x: float,
    volume_m3: float,
    incoming_horizontal_velocity_m_s: float = 0.0,
    radius_px: float = 8.0
) -> void:
    var amount := maxf(volume_m3, 0.0)
    if amount <= 0.0:
        return

    var liters := amount * 1000.0
    radius_px = maxf(
        radius_px,
        cell_size_px * 1.5 + sqrt(maxf(liters, 0.0)) * 2.8
    )

    var first := _index_at(world_x - radius_px)
    var last := _index_at(world_x + radius_px)
    var weights: Array[float] = []
    var weight_sum := 0.0

    for i in range(first, last + 1):
        var distance := absf(_cell_center_x(i) - world_x)
        var w := maxf(0.05, 1.0 - distance / maxf(radius_px + cell_size_px, 0.001))
        weights.append(w)
        weight_sum += w

    var cell_width_m := cell_size_px / pixels_per_meter
    var cell_area := cell_width_m * fluid_depth_m
    var cursor := 0
    for i in range(first, last + 1):
        var share := weights[cursor] / maxf(weight_sum, 0.000001)
        cursor += 1
        var added_volume := amount * share
        var dh := added_volume / maxf(cell_area, 0.000001)
        var old_h := maxf(_depth_m[i], 0.0)
        var old_momentum := _momentum_m2_s[i]
        _depth_m[i] = old_h + dh
        _momentum_m2_s[i] = (
            old_momentum + dh * incoming_horizontal_velocity_m_s
        )

func emit_water_stream(
    world_point: Vector2,
    volume_m3: float,
    velocity_px_s: Vector2,
    particle_count: int = 8
) -> void:
    var amount := maxf(volume_m3, 0.0)
    if amount <= 0.0:
        return

    var available := max_splash_particles - _droplets.size()
    if available <= 0:
        deposit_water_at(
            world_point.x,
            amount,
            velocity_px_s.x / pixels_per_meter,
            cell_size_px
        )
        return

    var count := clampi(particle_count, 1, available)
    var per_particle := amount / float(count)
    for _n in range(count):
        _droplets.append({
            "pos": world_point + Vector2(
                _rng.randf_range(-cell_size_px, cell_size_px),
                _rng.randf_range(-2.0, 2.0)
            ),
            "vel": velocity_px_s + Vector2(
                _rng.randf_range(-24.0, 24.0),
                _rng.randf_range(-14.0, 14.0)
            ),
            "life": _rng.randf_range(0.75, 1.65),
            "size": cell_size_px if _rng.randf() < 0.80 else cell_size_px * 0.5,
            "amount_m3": per_particle
        })

func emit_visual_splash(
    world_point: Vector2,
    velocity_px_s: Vector2,
    particle_count: int = 6
) -> void:
    var available := max_splash_particles - _droplets.size()
    if available <= 0:
        return
    var count := clampi(particle_count, 1, available)
    for _n in range(count):
        _droplets.append({
            "pos": world_point + Vector2(
                _rng.randf_range(-cell_size_px * 0.8, cell_size_px * 0.8),
                _rng.randf_range(-1.5, 1.5)
            ),
            "vel": velocity_px_s + Vector2(
                _rng.randf_range(-15.0, 15.0),
                _rng.randf_range(-9.0, 9.0)
            ),
            "life": _rng.randf_range(0.45, 1.05),
            "size": cell_size_px * (0.55 if _rng.randf() < 0.65 else 0.85),
            "amount_m3": 0.0
        })

func register_object_impact(
    world_x: float,
    mass_kg: float,
    vertical_speed_px_s: float,
    displaced_volume_m3: float,
    object_width_px: float
) -> void:
    # A body entering the surface already affects the conservative solver through
    # its occupied volume. Secondary coupling must stay subtle, otherwise a
    # floating object double-counts the same interaction every time it bobs.
    if vertical_speed_px_s <= 55.0:
        return

    var speed_m_s := vertical_speed_px_s / pixels_per_meter
    var impact_energy_j := 0.5 * mass_kg * speed_m_s * speed_m_s
    var displaced_liters := maxf(displaced_volume_m3 * 1000.0, 0.0)
    var radius_px := clampf(
        object_width_px * 0.62 + sqrt(displaced_liters) * 1.25,
        14.0,
        92.0
    )

    var strength_m_s := clampf(
        sqrt(maxf(impact_energy_j, 0.0)) * 0.010
        + sqrt(displaced_liters) * 0.012,
        0.015,
        0.42
    )
    _add_radial_momentum(world_x, radius_px, strength_m_s)

    # Splash particles are deliberately massless visuals. Conservative droplets
    # are used only by real water transfer such as waterfalls and bucket pouring.
    var count := clampi(
        int(1.0 + sqrt(maxf(impact_energy_j, 0.0)) * 0.08 + object_width_px * 0.018),
        1,
        8
    )
    var sy := surface_y_at(world_x)
    var launch := 55.0 + minf(120.0, sqrt(maxf(impact_energy_j, 0.0)) * 2.2)
    emit_visual_splash(
        Vector2(world_x, sy - cell_size_px * 0.5),
        Vector2(0.0, -launch),
        count
    )

    if impact_energy_j > 18.0:
        _spawn_foam(world_x, clampf(impact_energy_j / 120.0, 0.35, 0.85))

func register_displacement_surge(
    world_x: float,
    displaced_volume_delta_m3: float,
    object_width_px: float,
    vertical_speed_px_s: float
) -> void:
    # Displacement itself is already conservative. This small impulse only helps
    # very fast entries/exits read visually and is intentionally suppressed for
    # normal bobbing at the surface.
    if absf(vertical_speed_px_s) < 85.0:
        return
    var liters := absf(displaced_volume_delta_m3) * 1000.0
    if liters < 0.18:
        return

    var radius := clampf(object_width_px * 0.55 + sqrt(liters), 12.0, 72.0)
    var strength := clampf(
        liters * 0.0025 + absf(vertical_speed_px_s) / pixels_per_meter * 0.018,
        0.008,
        0.14
    )
    if displaced_volume_delta_m3 < 0.0:
        strength *= -0.20
    _add_radial_momentum(world_x, radius, strength)

func register_underwater_motion(
    world_point: Vector2,
    velocity_px_s: Vector2,
    size_px: float,
    sinking_strength: float = 0.0,
    delta: float = 1.0 / 60.0
) -> void:
    if world_point.x < world_left or world_point.x >= world_right:
        return
    if depth_m_at(world_point.x) <= dry_depth_m:
        return

    var half_size := maxf(size_px * 0.5, cell_size_px)
    var sy := surface_y_at(world_point.x)
    if world_point.y + half_size < sy:
        return

    var center := _index_at(world_point.x)
    var radius_cells := maxi(1, int(ceil(size_px * 0.55 / cell_size_px)))
    var target_u := velocity_px_s.x / pixels_per_meter
    var blend := clampf(delta * 0.16, 0.0, 0.016)

    for offset in range(-radius_cells, radius_cells + 1):
        var i := center + offset
        if i < 0 or i >= _cell_count or _depth_m[i] <= dry_depth_m:
            continue
        var falloff := 1.0 - absf(float(offset)) / float(radius_cells + 1)
        var u := _velocity_at_index(i)
        u = lerpf(u, target_u, blend * falloff)
        _momentum_m2_s[i] = u * _depth_m[i]

    var speed := velocity_px_s.length()
    if speed > 155.0 and absf(world_point.y - sy) < half_size * 1.15:
        var p := 1.0 - exp(-5.0 * delta)
        if _rng.randf() < p:
            _spawn_foam(world_point.x, 0.75)

    var bubble_rate := clampf(sinking_strength * 4.0, 0.0, 12.0)
    var bubble_p := 1.0 - exp(-bubble_rate * delta)
    if (
        sinking_strength > 0.12
        and speed > 24.0
        and _bubbles.size() < max_bubbles
        and _rng.randf() < bubble_p
    ):
        _bubbles.append({
            "pos": world_point + Vector2(
                _rng.randf_range(-size_px * 0.35, size_px * 0.35),
                _rng.randf_range(-4.0, 8.0)
            ),
            "rise": _rng.randf_range(18.0, 42.0),
            "drift": _rng.randf_range(-7.0, 7.0),
            "size": cell_size_px * (0.5 if _rng.randf() < 0.65 else 1.0),
            "life": 5.0
        })

func _add_radial_momentum(
    world_x: float,
    radius_px: float,
    strength_m_s: float
) -> void:
    var center := _index_at(world_x)
    var radius_cells := maxi(1, int(ceil(radius_px / cell_size_px)))
    for offset in range(-radius_cells, radius_cells + 1):
        if offset == 0:
            continue
        var i := center + offset
        if i < 0 or i >= _cell_count or _depth_m[i] <= dry_depth_m:
            continue
        var t := absf(float(offset)) / float(radius_cells + 1)
        var falloff := (1.0 - t) * (1.0 - t)
        var direction := -1.0 if offset < 0 else 1.0
        var u := _velocity_at_index(i)
        u += direction * strength_m_s * falloff
        u = clampf(u, -max_flow_speed_m_s, max_flow_speed_m_s)
        _momentum_m2_s[i] = u * _depth_m[i]

func _simulate_droplets(delta: float) -> void:
    for i in range(_droplets.size() - 1, -1, -1):
        var d := _droplets[i]
        d.vel.y += gravity_px_s2 * delta
        d.pos += d.vel * delta
        d.life -= delta

        var amount := maxf(float(d.get("amount_m3", 0.0)), 0.0)

        if d.pos.x >= world_left and d.pos.x < world_right:
            var floor_y := floor_y_at(d.pos.x)
            var sy := surface_y_at(d.pos.x)
            var has_water := depth_m_at(d.pos.x) > dry_depth_m
            var landing_y := sy if has_water else floor_y

            if d.pos.y >= landing_y:
                deposit_water_at(
                    d.pos.x,
                    amount,
                    d.vel.x / pixels_per_meter,
                    cell_size_px * 1.5
                )
                if has_water and amount > 0.0000001:
                    _add_radial_momentum(
                        d.pos.x,
                        10.0,
                        clampf(absf(d.vel.y) / pixels_per_meter * 0.025, 0.01, 0.12)
                    )
                _droplets.remove_at(i)
                continue

        if (
            d.life <= 0.0
            or d.pos.y > 900.0
            or d.pos.x < world_left - 80.0
            or d.pos.x > world_right + 80.0
        ):
            # Leaving the configured world is a real loss from this simulation domain.
            _droplets.remove_at(i)
            continue

        _droplets[i] = d

func _simulate_bubbles(delta: float) -> void:
    for i in range(_bubbles.size() - 1, -1, -1):
        var b := _bubbles[i]
        b.pos.y -= b.rise * delta
        b.pos.x += b.drift * delta
        b.life -= delta

        if (
            b.pos.x < world_left
            or b.pos.x >= world_right
            or depth_m_at(b.pos.x) <= dry_depth_m
        ):
            _bubbles.remove_at(i)
            continue

        if b.pos.y <= surface_y_at(b.pos.x) + cell_size_px:
            _spawn_foam(b.pos.x, 0.45)
            _bubbles.remove_at(i)
            continue

        if b.life <= 0.0:
            _bubbles.remove_at(i)
            continue
        _bubbles[i] = b

func _spawn_foam(world_x: float, intensity: float) -> void:
    if _foam.size() >= max_foam_particles:
        return
    if depth_m_at(world_x) <= dry_depth_m:
        return
    _foam.append({
        "x": snappedf(world_x, cell_size_px),
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
        if (
            f.life <= 0.0
            or f.x < world_left
            or f.x >= world_right
            or depth_m_at(f.x) <= dry_depth_m
        ):
            _foam.remove_at(i)
            continue
        _foam[i] = f

func _emit_turbulence_foam(delta: float) -> void:
    _foam_accumulator += delta
    if _foam_accumulator < 0.075:
        return
    _foam_accumulator = 0.0

    for i in range(1, _cell_count - 1, 3):
        if _depth_m[i] <= dry_depth_m:
            continue
        var u := absf(_velocity_at_index(i))
        var sy_l := _surface_y_index(i - 1)
        var sy := _surface_y_index(i)
        var sy_r := _surface_y_index(i + 1)
        var curvature := absf(sy_l - 2.0 * sy + sy_r)
        var froude := u / maxf(
            sqrt((gravity_px_s2 / pixels_per_meter) * maxf(_depth_m[i], 0.001)),
            0.001
        )
        var energy := u * 18.0 + curvature * 1.6 + froude * 12.0
        if energy > 24.0 and _rng.randf() < clampf((energy - 24.0) / 95.0, 0.0, 0.30):
            _spawn_foam(_cell_center_x(i), clampf(energy / 70.0, 0.45, 1.30))

func _velocity_at_index(i: int) -> float:
    var h := maxf(_depth_m[i], 0.0)
    if h <= dry_depth_m:
        return 0.0
    return _momentum_m2_s[i] / maxf(h, dry_depth_m)

func _surface_y_index(i: int) -> float:
    var total_fill_m := maxf(_depth_m[i], 0.0) + maxf(_solid_fill_m[i], 0.0)
    return _floor_y[i] - total_fill_m * pixels_per_meter

func _index_at(world_x: float) -> int:
    var i := int(floor((world_x - world_left) / maxf(cell_size_px, 1.0)))
    return clampi(i, 0, maxi(_cell_count - 1, 0))

func _cell_center_x(i: int) -> float:
    return world_left + (float(i) + 0.5) * cell_size_px

func _draw() -> void:
    if _cell_count == 0:
        return

    # Split fill geometry whenever terrain height changes. A single giant polygon
    # spanning basin walls and shallow platforms can become numerically awkward
    # after violent interactions and Godot may fail to triangulate it, leaving only
    # the cyan outline. Terrain-continuous runs are cheap and triangulate reliably.
    var run_start := -1
    for i in range(_cell_count + 1):
        var wet := i < _cell_count and _depth_m[i] > dry_depth_m
        if wet and run_start < 0:
            run_start = i
        elif wet and run_start >= 0 and i > run_start:
            var floor_jump := absf(_floor_y[i] - _floor_y[i - 1])
            var surface_jump := absf(_surface_y_index(i) - _surface_y_index(i - 1))
            if floor_jump > 0.5 or surface_jump > maxf(90.0, cell_size_px * 14.0):
                _draw_water_run(run_start, i - 1)
                run_start = i
        elif not wet and run_start >= 0:
            _draw_water_run(run_start, i - 1)
            run_start = -1

    for f in _foam:
        var alpha := clampf(float(f.life) / maxf(float(f.max_life), 0.001), 0.0, 1.0)
        var x := snappedf(float(f.x), cell_size_px)
        var y := snappedf(surface_y_at(x) - cell_size_px, cell_size_px * 0.5)
        var c := FOAM_COLOR
        c.a = alpha
        draw_rect(Rect2(x, y, cell_size_px, maxf(1.0, cell_size_px * 0.45)), c)

    for b in _bubbles:
        var s := float(b.size)
        var p: Vector2 = b.pos
        draw_rect(Rect2(snappedf(p.x, cell_size_px * 0.5), snappedf(p.y, cell_size_px * 0.5), s, s), FOAM_COLOR, false, 1.0)

    for d in _droplets:
        var p: Vector2 = d.pos
        var s := float(d.size)
        draw_rect(Rect2(snappedf(p.x, cell_size_px * 0.5), snappedf(p.y, cell_size_px * 0.5), s, s), WATER_MID)

func _draw_water_run(first: int, last: int) -> void:
    if first < 0 or last < first:
        return

    var polygon := PackedVector2Array()
    var surface_line := PackedVector2Array()

    for i in range(first, last + 1):
        var x0 := world_left + float(i) * cell_size_px
        var x1 := x0 + cell_size_px
        var sy := snappedf(_surface_y_index(i), cell_size_px * 0.5)
        polygon.append(Vector2(x0, sy))
        polygon.append(Vector2(x1, sy))
        surface_line.append(Vector2(x0, sy))
        surface_line.append(Vector2(x1, sy))

    for i in range(last, first - 1, -1):
        var x0 := world_left + float(i) * cell_size_px
        var x1 := x0 + cell_size_px
        var floor_y := _floor_y[i]
        polygon.append(Vector2(x1, floor_y))
        polygon.append(Vector2(x0, floor_y))

    if polygon.size() >= 3:
        draw_colored_polygon(polygon, WATER_MID)
    if surface_line.size() >= 2:
        draw_polyline(surface_line, WATER_TOP, maxf(1.0, cell_size_px * 0.35))
