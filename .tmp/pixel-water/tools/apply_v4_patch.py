from pathlib import Path
import re

WORLD = Path('.tmp/pixel-water/addons/pixel_water/pixel_water_world.gd')
BODY = Path('.tmp/pixel-water/addons/pixel_water/buoyant_body.gd')
MAIN = Path('.tmp/pixel-water/demo/main.gd')

world = WORLD.read_text(encoding='utf-8')
body = BODY.read_text(encoding='utf-8')
main = MAIN.read_text(encoding='utf-8')


def once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'missing anchor: {label}')
    return text.replace(old, new, 1)


world = once(world, '@export_range(2, 48, 1) var max_substeps: int = 28', '@export_range(2, 32, 1) var max_substeps: int = 14', 'max_substeps')
world = once(world, '@export_range(0.0, 4.0, 0.01) var linear_flow_damping: float = 0.62', '@export_range(0.0, 4.0, 0.01) var linear_flow_damping: float = 0.82', 'linear damping')
world = once(world, '@export_range(0.0, 2.0, 0.01) var quadratic_flow_damping: float = 0.16', '@export_range(0.0, 2.0, 0.01) var quadratic_flow_damping: float = 0.18', 'quadratic damping')
world = once(world, '@export_range(0.0, 0.8, 0.01) var momentum_neighbor_mix: float = 0.020', '@export_range(0.0, 0.8, 0.01) var momentum_neighbor_mix: float = 0.008', 'momentum mix')
world = once(
    world,
    '@export_range(0.0, 3.0, 0.05) var rest_surface_delta_px: float = 0.45\n@export_range(4.0, 80.0, 1.0) var waterfall_drop_threshold_px: float = 12.0',
    '@export_range(0.0, 3.0, 0.05) var rest_surface_delta_px: float = 0.55\n@export_range(4.0, 40.0, 1.0) var extreme_surface_delta_px: float = 12.0\n@export_range(1, 4, 1) var extreme_relax_passes: int = 2\n@export_range(0.05, 1.0, 0.05) var extreme_relax_fraction: float = 0.70\n@export_range(4.0, 80.0, 1.0) var waterfall_drop_threshold_px: float = 12.0',
    'extreme controls',
)
world = once(world, '@export_range(0.5, 20.0, 0.5) var max_flow_speed_m_s: float = 8.0', '@export_range(0.5, 20.0, 0.5) var max_flow_speed_m_s: float = 4.5', 'max flow')
world = once(world, '@export var max_splash_particles: int = 520', '@export var max_splash_particles: int = 140', 'splash cap')
world = once(world, '@export var max_bubbles: int = 150', '@export var max_bubbles: int = 64', 'bubble cap')
world = once(world, '@export var max_foam_particles: int = 240', '@export var max_foam_particles: int = 100', 'foam cap')
world = once(world, '@export_range(0.0, 1.0, 0.01) var spray_volume_fraction: float = 0.025', '@export_range(0.0, 1.0, 0.001) var spray_volume_fraction: float = 0.008', 'spray fraction')

world = once(
    world,
    'var _momentum_flux_right: PackedFloat32Array\n',
    'var _momentum_flux_right: PackedFloat32Array\nvar _donor_scale: PackedFloat32Array\nvar _surface_relax_delta: PackedFloat32Array\n',
    'scratch vars',
)
world = once(
    world,
    '    _momentum_flux_right.resize(maxi(1, _cell_count - 1))\n',
    '    _momentum_flux_right.resize(maxi(1, _cell_count - 1))\n    _donor_scale.resize(_cell_count)\n    _surface_relax_delta.resize(_cell_count)\n',
    'scratch resize',
)
world = once(
    world,
    '    var donor_scale := PackedFloat32Array()\n    donor_scale.resize(_cell_count)\n    donor_scale.fill(1.0)',
    '    _donor_scale.fill(1.0)',
    'donor allocation',
)
world = world.replace('donor_scale[i] = clampf(', '_donor_scale[i] = clampf(')
world = world.replace('var scale := donor_scale[donor]', 'var scale := _donor_scale[donor]')

world = once(
    world,
    '    _previous_solid_fill_m = _solid_fill_m.duplicate()\n    for i in range(_cell_count):\n        _solid_fill_m[i] = 0.0',
    '    for i in range(_cell_count):\n        _previous_solid_fill_m[i] = _solid_fill_m[i]\n        _solid_fill_m[i] = 0.0',
    'solid fill copy',
)

old_weights = '''        var weights: Array[float] = []
        var weight_sum := 0.0
        for i in range(first, last + 1):
            var x := _cell_center_x(i)
            var normalized := absf(x - center_x) / maxf(radius_px, 0.001)
            var w := maxf(0.0, 1.0 - normalized)
            w = w * w
            weights.append(w)
            weight_sum += w

        if weight_sum <= 0.0:
            continue

        var cursor := 0
        for i in range(first, last + 1):
            var share := weights[cursor] / weight_sum
            cursor += 1
            var equivalent_height_m := (
                volume_m3 * share / cell_plan_area_m2
            )
            _solid_fill_m[i] += equivalent_height_m
'''
new_weights = '''        var weight_sum := 0.0
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
'''
world = once(world, old_weights, new_weights, 'displacement temporary weights')

world = once(
    world,
    '    for _step in range(substeps):\n        _shallow_water_substep(dt)\n\n    _relax_extreme_surface_columns()\n    _flush_waterfalls()' if '_relax_extreme_surface_columns()' in world else '    for _step in range(substeps):\n        _shallow_water_substep(dt)\n\n    _flush_waterfalls()',
    '    for _step in range(substeps):\n        _shallow_water_substep(dt)\n\n    _relax_extreme_surface_columns()\n    _flush_waterfalls()',
    'extreme limiter call',
)

if 'func _relax_extreme_surface_columns() -> void:' not in world:
    surface_helper = '''func _relax_extreme_surface_columns() -> void:
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

'''
    marker = 'func _limit_outflow_fluxes(dt: float, dx: float) -> void:\n'
    if marker not in world:
        raise RuntimeError('missing surface helper insertion marker')
    world = world.replace(marker, surface_helper + marker, 1)

world = once(world, '        sqrt(maxf(impact_energy_j, 0.0)) * 0.055\n        + sqrt(displaced_liters) * 0.10,\n        0.12,\n        3.2', '        sqrt(maxf(impact_energy_j, 0.0)) * 0.018\n        + sqrt(displaced_liters) * 0.035,\n        0.04,\n        0.90', 'impact energy')
world = once(world, '        + impact_energy_j / 350000.0,\n        0.012', '        + impact_energy_j / 1200000.0,\n        0.003', 'splash volume')
world = once(world, '            int(4.0 + sqrt(maxf(impact_energy_j, 0.0)) * 0.35 + object_width_px * 0.06),\n            4,\n            72', '            int(2.0 + sqrt(maxf(impact_energy_j, 0.0)) * 0.12 + object_width_px * 0.025),\n            2,\n            16', 'splash count')
world = once(world, '        var launch := 110.0 + minf(330.0, sqrt(maxf(impact_energy_j, 0.0)) * 8.0)', '        var launch := 70.0 + minf(180.0, sqrt(maxf(impact_energy_j, 0.0)) * 3.5)', 'splash launch')
world = once(world, '    for _n in range(clampi(int(2.0 + displaced_liters * 0.10), 2, 24)):', '    for _n in range(clampi(int(1.0 + displaced_liters * 0.035), 1, 8)):', 'foam count')
world = once(world, '    if liters < 0.015:', '    if liters < 0.080:', 'surge threshold')
world = once(world, '        liters * 0.026 + absf(vertical_speed_px_s) / pixels_per_meter * 0.20,\n        0.04,\n        1.9', '        liters * 0.008 + absf(vertical_speed_px_s) / pixels_per_meter * 0.050,\n        0.015,\n        0.45', 'surge strength')
world = once(world, '        strength *= -0.48', '        strength *= -0.32', 'negative surge')
world = once(world, '    var blend := clampf(delta * 1.8, 0.0, 0.18)', '    var blend := clampf(delta * 0.45, 0.0, 0.045)', 'underwater wake')
world = once(world, '                        clampf(absf(d.vel.y) / pixels_per_meter * 0.08, 0.02, 0.35)', '                        clampf(absf(d.vel.y) / pixels_per_meter * 0.025, 0.01, 0.12)', 'landing wake')
world = once(world, '            int(ceil(2.0 + sqrt(maxf(liters, 0.0)) * 5.0)),\n            2,\n            24', '            int(ceil(1.0 + sqrt(maxf(liters, 0.0)) * 1.6)),\n            1,\n            6', 'waterfall packets')
world = once(world, '            "life": _rng.randf_range(1.2, 3.5),', '            "life": _rng.randf_range(0.75, 1.65),', 'particle lifetime')

draw_start = world.find('func _draw() -> void:\n')
if draw_start < 0:
    raise RuntimeError('missing _draw')
world = world[:draw_start] + '''func _draw() -> void:
    if _cell_count == 0:
        return

    var run_start := -1
    for i in range(_cell_count + 1):
        var wet := i < _cell_count and _depth_m[i] > dry_depth_m
        if wet and run_start < 0:
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
'''

body = once(body, '@export_range(3, 11, 1) var sample_columns: int = 7', '@export_range(3, 11, 1) var sample_columns: int = 5', 'sample cols')
body = once(body, '@export_range(3, 11, 1) var sample_rows: int = 6', '@export_range(3, 11, 1) var sample_rows: int = 4', 'sample rows')
body = once(body, '    contact_monitor = true\n    max_contacts_reported = 16', '    contact_monitor = false\n    max_contacts_reported = 0', 'contact monitor')
body = once(body, '    if absf(fraction_delta) < 0.003:', '    if absf(fraction_delta) < 0.012:', 'displacement threshold')
old_motion = '''    var sink_ratio := maxf(0.0, predicted_submerged_fraction - 1.0)
    _water.register_underwater_motion(
        global_position,
        linear_velocity,
        maxf(object_size_px.x, object_size_px.y),
        sink_ratio,
        delta
    )
'''
new_motion = '''    var sink_ratio := maxf(0.0, predicted_submerged_fraction - 1.0)
    if linear_velocity.length_squared() > 225.0 or sink_ratio > 0.08:
        _water.register_underwater_motion(
            global_position,
            linear_velocity,
            maxf(object_size_px.x, object_size_px.y),
            sink_ratio,
            delta
        )
'''
body = once(body, old_motion, new_motion, 'conditional underwater motion')

main = once(main, '    water.cell_size_px = 4.0', '    water.cell_size_px = 6.0', 'demo grid')
main = once(
    main,
    '    water.linear_flow_damping = 0.68\n    water.quadratic_flow_damping = 0.17\n    water.momentum_neighbor_mix = 0.018',
    '    water.cfl_number = 0.42\n    water.max_substeps = 14\n    water.linear_flow_damping = 0.82\n    water.quadratic_flow_damping = 0.18\n    water.momentum_neighbor_mix = 0.008\n    water.rest_velocity_m_s = 0.045\n    water.rest_surface_delta_px = 0.55\n    water.max_flow_speed_m_s = 4.5\n    water.max_splash_particles = 140\n    water.max_bubbles = 64\n    water.max_foam_particles = 100\n    water.spray_volume_fraction = 0.008',
    'demo tuning',
)
main = once(main, 'var _water_stats: Label\n', 'var _water_stats: Label\nvar _stats_accumulator := 0.0\n', 'stats accumulator')
main = once(
    main,
    'func _process(_delta: float) -> void:\n    if _water_stats == null or water == null:\n        return\n',
    'func _process(delta: float) -> void:\n    if _water_stats == null or water == null:\n        return\n    _stats_accumulator += delta\n    if _stats_accumulator < 0.25:\n        return\n    _stats_accumulator = 0.0\n',
    'stats throttle',
)
main = once(
    main,
    '        + "world + spray: %.1f L"\n    ) % [\n        main_l,\n        small_l,\n        mobile_l,\n        water.water_volume_liters()\n    ]',
    '        + "world + spray: %.1f L   •   FPS: %d"\n    ) % [\n        main_l,\n        small_l,\n        mobile_l,\n        water.water_volume_liters(),\n        int(Engine.get_frames_per_second())\n    ]',
    'fps stat',
)

WORLD.write_text(world, encoding='utf-8')
BODY.write_text(body, encoding='utf-8')
MAIN.write_text(main, encoding='utf-8')
print('Water V4 optimization patch applied')
