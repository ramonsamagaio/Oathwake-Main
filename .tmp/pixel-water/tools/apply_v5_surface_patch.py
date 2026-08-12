from pathlib import Path
import re

ROOT = Path('.tmp/pixel-water')
WORLD = ROOT / 'addons/pixel_water/pixel_water_world.gd'
BODY = ROOT / 'addons/pixel_water/buoyant_body.gd'
BUCKET = ROOT / 'addons/pixel_water/water_bucket.gd'

world = WORLD.read_text(encoding='utf-8')
body = BODY.read_text(encoding='utf-8')
bucket = BUCKET.read_text(encoding='utf-8')


def replace_once(text, old, new, label):
    if old not in text:
        raise RuntimeError(f'missing anchor: {label}')
    return text.replace(old, new, 1)

# -----------------------------------------------------------------------------
# WORLD: object splash is visual only. Real transported water remains reserved
# for waterfalls, overflow and bucket pour/fill.
# -----------------------------------------------------------------------------
impact_pattern = re.compile(r'func register_object_impact\([\s\S]*?\nfunc register_displacement_surge\(', re.M)
impact_replacement = '''func emit_visual_splash(\n    world_point: Vector2,\n    velocity_px_s: Vector2,\n    particle_count: int = 6\n) -> void:\n    var available := max_splash_particles - _droplets.size()\n    if available <= 0:\n        return\n    var count := clampi(particle_count, 1, available)\n    for _n in range(count):\n        _droplets.append({\n            "pos": world_point + Vector2(\n                _rng.randf_range(-cell_size_px * 0.8, cell_size_px * 0.8),\n                _rng.randf_range(-1.5, 1.5)\n            ),\n            "vel": velocity_px_s + Vector2(\n                _rng.randf_range(-15.0, 15.0),\n                _rng.randf_range(-9.0, 9.0)\n            ),\n            "life": _rng.randf_range(0.45, 1.05),\n            "size": cell_size_px * (0.55 if _rng.randf() < 0.65 else 0.85),\n            "amount_m3": 0.0\n        })\n\nfunc register_object_impact(\n    world_x: float,\n    mass_kg: float,\n    vertical_speed_px_s: float,\n    displaced_volume_m3: float,\n    object_width_px: float\n) -> void:\n    # A body entering the surface already affects the conservative solver through\n    # its occupied volume. Secondary coupling must stay subtle, otherwise a\n    # floating object double-counts the same interaction every time it bobs.\n    if vertical_speed_px_s <= 55.0:\n        return\n\n    var speed_m_s := vertical_speed_px_s / pixels_per_meter\n    var impact_energy_j := 0.5 * mass_kg * speed_m_s * speed_m_s\n    var displaced_liters := maxf(displaced_volume_m3 * 1000.0, 0.0)\n    var radius_px := clampf(\n        object_width_px * 0.62 + sqrt(displaced_liters) * 1.25,\n        14.0,\n        92.0\n    )\n\n    var strength_m_s := clampf(\n        sqrt(maxf(impact_energy_j, 0.0)) * 0.010\n        + sqrt(displaced_liters) * 0.012,\n        0.015,\n        0.42\n    )\n    _add_radial_momentum(world_x, radius_px, strength_m_s)\n\n    # Splash particles are deliberately massless visuals. Conservative droplets\n    # are used only by real water transfer such as waterfalls and bucket pouring.\n    var count := clampi(\n        int(1.0 + sqrt(maxf(impact_energy_j, 0.0)) * 0.08 + object_width_px * 0.018),\n        1,\n        8\n    )\n    var sy := surface_y_at(world_x)\n    var launch := 55.0 + minf(120.0, sqrt(maxf(impact_energy_j, 0.0)) * 2.2)\n    emit_visual_splash(\n        Vector2(world_x, sy - cell_size_px * 0.5),\n        Vector2(0.0, -launch),\n        count\n    )\n\n    if impact_energy_j > 18.0:\n        _spawn_foam(world_x, clampf(impact_energy_j / 120.0, 0.35, 0.85))\n\nfunc register_displacement_surge('''
world, n = impact_pattern.subn(impact_replacement, world, count=1)
if n != 1:
    raise RuntimeError('failed to replace impact block')

surge_pattern = re.compile(r'func register_displacement_surge\([\s\S]*?\nfunc register_underwater_motion\(', re.M)
surge_replacement = '''func register_displacement_surge(\n    world_x: float,\n    displaced_volume_delta_m3: float,\n    object_width_px: float,\n    vertical_speed_px_s: float\n) -> void:\n    # Displacement itself is already conservative. This small impulse only helps\n    # very fast entries/exits read visually and is intentionally suppressed for\n    # normal bobbing at the surface.\n    if absf(vertical_speed_px_s) < 85.0:\n        return\n    var liters := absf(displaced_volume_delta_m3) * 1000.0\n    if liters < 0.18:\n        return\n\n    var radius := clampf(object_width_px * 0.55 + sqrt(liters), 12.0, 72.0)\n    var strength := clampf(\n        liters * 0.0025 + absf(vertical_speed_px_s) / pixels_per_meter * 0.018,\n        0.008,\n        0.14\n    )\n    if displaced_volume_delta_m3 < 0.0:\n        strength *= -0.20\n    _add_radial_momentum(world_x, radius, strength)\n\nfunc register_underwater_motion('''
world, n = surge_pattern.subn(surge_replacement, world, count=1)
if n != 1:
    raise RuntimeError('failed to replace displacement surge block')

world = replace_once(
    world,
    '    var blend := clampf(delta * 0.45, 0.0, 0.045)',
    '    var blend := clampf(delta * 0.16, 0.0, 0.016)',
    'underwater coupling blend',
)

world = replace_once(
    world,
    '                if has_water:\n                    _add_radial_momentum(',
    '                if has_water and amount > 0.0000001:\n                    _add_radial_momentum(',
    'cosmetic droplet landing impulse',
)

old_draw_loop = '''    var run_start := -1\n    for i in range(_cell_count + 1):\n        var wet := i < _cell_count and _depth_m[i] > dry_depth_m\n        if wet and run_start < 0:\n            run_start = i\n        elif not wet and run_start >= 0:\n            _draw_water_run(run_start, i - 1)\n            run_start = -1\n'''
new_draw_loop = '''    # Split fill geometry whenever terrain height changes. A single giant polygon\n    # spanning basin walls and shallow platforms can become numerically awkward\n    # after violent interactions and Godot may fail to triangulate it, leaving only\n    # the cyan outline. Terrain-continuous runs are cheap and triangulate reliably.\n    var run_start := -1\n    for i in range(_cell_count + 1):\n        var wet := i < _cell_count and _depth_m[i] > dry_depth_m\n        if wet and run_start < 0:\n            run_start = i\n        elif wet and run_start >= 0 and i > run_start:\n            var floor_jump := absf(_floor_y[i] - _floor_y[i - 1])\n            var surface_jump := absf(_surface_y_index(i) - _surface_y_index(i - 1))\n            if floor_jump > 0.5 or surface_jump > maxf(90.0, cell_size_px * 14.0):\n                _draw_water_run(run_start, i - 1)\n                run_start = i\n        elif not wet and run_start >= 0:\n            _draw_water_run(run_start, i - 1)\n            run_start = -1\n'''
world = replace_once(world, old_draw_loop, new_draw_loop, 'robust water renderer')

# -----------------------------------------------------------------------------
# BODY: floating lightweight materials were repeatedly retriggering surface
# effects. Add hysteresis/cooldown and scale secondary coupling by density ratio.
# -----------------------------------------------------------------------------
body = replace_once(
    body,
    'var _spawn_transform: Transform2D\n',
    'var _spawn_transform: Transform2D\nvar _surface_impact_cooldown := 0.0\n',
    'impact cooldown state',
)

body = replace_once(
    body,
    'func _physics_process(delta: float) -> void:\n    if (',
    'func _physics_process(delta: float) -> void:\n    _surface_impact_cooldown = maxf(0.0, _surface_impact_cooldown - delta)\n    if (',
    'impact cooldown tick',
)

old_entry = '''    var just_entered := (\n        _previous_submerged_fraction < 0.03\n        and submerged_fraction >= 0.03\n    )\n    if just_entered and linear_velocity.y > 28.0:\n        _water.register_object_impact(\n            global_position.x,\n            mass,\n            linear_velocity.y,\n            maxf(displaced_volume, object_volume_m3 * 0.08),\n            object_size_px.x\n        )\n\n    _report_displacement_change()\n\n    var sink_ratio := maxf(0.0, predicted_submerged_fraction - 1.0)\n    if linear_velocity.length_squared() > 225.0 or sink_ratio > 0.08:\n        _water.register_underwater_motion(\n            global_position,\n            linear_velocity,\n            maxf(object_size_px.x, object_size_px.y),\n            sink_ratio,\n            delta\n        )\n'''
new_entry = '''    var density_ratio := clampf(\n        mass / maxf(_water.water_density_kg_m3 * object_volume_m3, 0.0001),\n        0.12,\n        1.0\n    )\n    var just_entered := (\n        _previous_submerged_fraction < 0.015\n        and submerged_fraction >= 0.08\n    )\n    if (\n        just_entered\n        and linear_velocity.y > 65.0\n        and _surface_impact_cooldown <= 0.0\n    ):\n        _surface_impact_cooldown = 0.42\n        _water.register_object_impact(\n            global_position.x,\n            mass,\n            linear_velocity.y,\n            maxf(displaced_volume, object_volume_m3 * 0.05) * density_ratio,\n            object_size_px.x\n        )\n\n    _report_displacement_change(density_ratio)\n\n    var sink_ratio := maxf(0.0, predicted_submerged_fraction - 1.0)\n    if linear_velocity.length_squared() > 3600.0 or sink_ratio > 0.10:\n        _water.register_underwater_motion(\n            global_position,\n            linear_velocity * density_ratio,\n            maxf(object_size_px.x, object_size_px.y),\n            sink_ratio,\n            delta\n        )\n'''
body = replace_once(body, old_entry, new_entry, 'surface hysteresis and density scaling')

old_report = '''func _report_displacement_change() -> void:\n    if _water == null:\n        return\n    var fraction_delta := submerged_fraction - _previous_submerged_fraction\n    if absf(fraction_delta) < 0.012:\n        return\n    _water.register_displacement_surge(\n        global_position.x,\n        object_volume_m3 * fraction_delta,\n        object_size_px.x,\n        linear_velocity.y\n    )\n'''
new_report = '''func _report_displacement_change(density_ratio: float = 1.0) -> void:\n    if _water == null:\n        return\n    var fraction_delta := submerged_fraction - _previous_submerged_fraction\n    if absf(fraction_delta) < 0.05 or absf(linear_velocity.y) < 85.0:\n        return\n    _water.register_displacement_surge(\n        global_position.x,\n        object_volume_m3 * fraction_delta * clampf(density_ratio, 0.12, 1.0),\n        object_size_px.x,\n        linear_velocity.y\n    )\n'''
body = replace_once(body, old_report, new_report, 'calmer displacement reporting')

# Calls made when the object is completely out of water use the default ratio.

# -----------------------------------------------------------------------------
# BUCKET: treat the empty bucket as a boat-like open hull. Interior water adds
# real weight; near full capacity the water mass cancels cavity buoyancy and the
# bucket becomes denser than water, so it sinks.
# -----------------------------------------------------------------------------
bucket = replace_once(
    bucket,
    '@export_range(2, 12, 1) var opening_samples: int = 5\n',
    '@export_range(2, 12, 1) var opening_samples: int = 5\n@export_range(0.1, 4.0, 0.05) var empty_bucket_mass_kg: float = 0.85\n@export_range(1.0, 20.0, 0.1) var hull_displacement_liters: float = 9.6\n',
    'bucket mass exports',
)

bucket = replace_once(
    bucket,
    '    var preset := WaterMaterialPresets.get_preset(material_name)\n    _dry_mass_kg = maxf(0.20, float(preset["density"]) * object_volume_m3)\n    mass = _dry_mass_kg',
    '    _dry_mass_kg = maxf(0.10, empty_bucket_mass_kg)\n    mass = _dry_mass_kg',
    'bucket dry mass',
)

bucket_samples_pattern = re.compile(r'func _build_samples\(\) -> void:[\s\S]*?\nfunc _physics_process\(delta: float\) -> void:', re.M)
bucket_samples_replacement = '''func _build_samples() -> void:\n    _sample_points.clear()\n\n    # An upright open bucket behaves like a tiny boat while its rim stays above\n    # the water: the cavity excludes outside water. As it fills, the contained\n    # water adds the same density back as weight. At full capacity only the shell\n    # surplus remains, so this test bucket becomes slightly denser than water.\n    var cols := 5\n    var rows := 4\n    for y_index in range(rows):\n        var y_t := (float(y_index) + 0.5) / float(rows)\n        var local_y := lerpf(-object_size_px.y * 0.5, object_size_px.y * 0.5, y_t)\n        for x_index in range(cols):\n            var x_t := (float(x_index) + 0.5) / float(cols)\n            var local_x := lerpf(-object_size_px.x * 0.5, object_size_px.x * 0.5, x_t)\n            _sample_points.append(Vector2(local_x, local_y))\n\n    object_volume_m3 = maxf(0.0001, hull_displacement_liters / 1000.0)\n    _update_prediction()\n\nfunc _physics_process(delta: float) -> void:'''
bucket, n = bucket_samples_pattern.subn(bucket_samples_replacement, bucket, count=1)
if n != 1:
    raise RuntimeError('failed to replace bucket buoyancy samples')

old_material_mass = '''    var preset := WaterMaterialPresets.get_preset(new_material)\n    if recalculate_mass:\n        _dry_mass_kg = maxf(\n            0.05,\n            float(preset["density"]) * object_volume_m3\n        )\n    contained_volume_m3 = water_before\n'''
new_material_mass = '''    if recalculate_mass:\n        _dry_mass_kg = maxf(0.10, empty_bucket_mass_kg)\n    contained_volume_m3 = water_before\n'''
bucket = replace_once(bucket, old_material_mass, new_material_mass, 'bucket material mass')

WORLD.write_text(world, encoding='utf-8')
BODY.write_text(body, encoding='utf-8')
BUCKET.write_text(bucket, encoding='utf-8')
print('Water V5 surface stability patch applied')
