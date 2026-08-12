from pathlib import Path
import re

BODY = Path('.tmp/pixel-water/addons/pixel_water/buoyant_body.gd')
text = BODY.read_text(encoding='utf-8')

# Add continuous-coupling controls once.
anchor = '@export var pixels_per_meter: float = 100.0\n'
addition = '''@export var pixels_per_meter: float = 100.0
@export_range(0.5, 2.0, 0.05) var immersion_cell_softness: float = 1.0
@export_range(0.0, 8.0, 0.1) var vertical_heave_damping: float = 2.2
@export_range(2.0, 30.0, 0.5) var displacement_follow_hz: float = 13.0
'''
if 'immersion_cell_softness' not in text:
    if anchor not in text:
        raise RuntimeError('missing hydrodynamics export anchor')
    text = text.replace(anchor, addition, 1)

anchor = 'var _surface_impact_cooldown := 0.0\n'
addition = '''var _surface_impact_cooldown := 0.0
var _reported_displaced_volume_m3 := 0.0
'''
if '_reported_displaced_volume_m3' not in text:
    if anchor not in text:
        raise RuntimeError('missing state anchor')
    text = text.replace(anchor, addition, 1)

start = text.find('func _physics_process(delta: float) -> void:\n')
end = text.find('func set_material_preset(', start)
if start < 0 or end < 0:
    raise RuntimeError('could not locate buoyancy physics block')

new_block = r'''func _sample_vertical_half_extent_px() -> float:
    # Every sample represents a small patch of object area, not a binary point.
    # Project that patch onto world Y so rotation remains smooth as well.
    var cols := maxf(float(maxi(sample_columns, 2)), 1.0)
    var rows := maxf(float(maxi(sample_rows, 2)), 1.0)
    var half_w := object_size_px.x / cols * 0.5
    var half_h := object_size_px.y / rows * 0.5
    var projected := (
        absf(sin(global_rotation)) * half_w
        + absf(cos(global_rotation)) * half_h
    )
    return maxf(1.5, projected * immersion_cell_softness)

func _immersion_weight(world_point: Vector2, half_extent_px: float) -> float:
    if _water == null:
        return 0.0
    if world_point.x < _water.world_left or world_point.x >= _water.world_right:
        return 0.0
    if _water.depth_m_at(world_point.x) <= _water.dry_depth_m:
        return 0.0

    var surface_y := _water.surface_y_at(world_point.x)
    var signed_depth_px := world_point.y - surface_y
    return smoothstep(-half_extent_px, half_extent_px, signed_depth_px)

func _physics_process(delta: float) -> void:
    _surface_impact_cooldown = maxf(0.0, _surface_impact_cooldown - delta)
    if (
        _water == null
        or global_position.x < _water.world_left - object_size_px.x
        or global_position.x > _water.world_right + object_size_px.x
    ):
        _find_water()

    if _water == null or _sample_points.is_empty():
        return

    _previous_submerged_fraction = submerged_fraction

    # Continuous hydrostatic occupancy. The old binary test made one sample worth
    # ~5% of the object, so a light floater at the waterline repeatedly jumped
    # between discrete buoyancy states. Each sample now contributes continuously
    # according to how much of its represented patch lies below the free surface.
    var half_extent_px := _sample_vertical_half_extent_px()
    var immersion_sum := 0.0
    for local_point in _sample_points:
        immersion_sum += _immersion_weight(to_global(local_point), half_extent_px)

    submerged_fraction = clampf(
        immersion_sum / float(maxi(_sample_points.size(), 1)),
        0.0,
        1.0
    )
    _update_prediction()

    var displaced_volume := object_volume_m3 * submerged_fraction
    var follow := 1.0 - exp(-maxf(displacement_follow_hz, 0.01) * delta)
    _reported_displaced_volume_m3 = lerpf(
        _reported_displaced_volume_m3,
        displaced_volume,
        clampf(follow, 0.0, 1.0)
    )
    if _reported_displaced_volume_m3 < 0.0000001:
        _reported_displaced_volume_m3 = 0.0

    _water.report_displacement(
        get_instance_id(),
        global_position.x,
        object_size_px.x,
        _reported_displaced_volume_m3
    )

    if submerged_fraction <= 0.0005:
        last_buoyant_force = 0.0
        return

    # Archimedes, integrated over the continuously submerged sample patches.
    var volume_per_sample := object_volume_m3 / float(_sample_points.size())
    var base_force_per_sample := (
        _water.water_density_kg_m3
        * _water.gravity_px_s2
        * volume_per_sample
        * buoyancy_multiplier
    )
    last_buoyant_force = 0.0

    for local_point in _sample_points:
        var world_point := to_global(local_point)
        var weight := _immersion_weight(world_point, half_extent_px)
        if weight <= 0.0005:
            continue
        var sample_force := base_force_per_sample * weight
        last_buoyant_force += sample_force
        apply_force(
            Vector2(0.0, -sample_force),
            world_point - global_position
        )

    # Quadratic hydrodynamic drag: Fd = 1/2 rho Cd A v^2.
    var velocity_m_s: Vector2 = linear_velocity / pixels_per_meter
    var speed_m_s: float = velocity_m_s.length()
    if speed_m_s > 0.01:
        var width_m := object_size_px.x / pixels_per_meter
        var height_m := object_size_px.y / pixels_per_meter
        var direction: Vector2 = velocity_m_s.normalized()
        var projected_length_m: float = (
            absf(direction.y) * width_m
            + absf(direction.x) * height_m
        )
        var projected_area_m2: float = maxf(0.0001, projected_length_m * physical_depth_m)
        var drag_newtons: float = (
            0.5
            * _water.water_density_kg_m3
            * drag_coefficient
            * projected_area_m2
            * speed_m_s
            * speed_m_s
        )
        var drag_force_px: Vector2 = (
            -linear_velocity.normalized()
            * drag_newtons
            * pixels_per_meter
            * submerged_fraction
        )

        var max_drag: float = (
            mass
            * maxf(linear_velocity.length(), 1.0)
            / maxf(delta, 0.001)
            * 0.72
        )
        if drag_force_px.length() > max_drag:
            drag_force_px = drag_force_px.normalized() * max_drag
        apply_central_force(drag_force_px)

    # Heave/radiation damping is a real energy-loss mechanism for a floating body.
    # It damps vertical bobbing without suppressing horizontal water flow or waves.
    if vertical_heave_damping > 0.0 and absf(linear_velocity.y) > 0.05:
        var heave_factor := sqrt(clampf(submerged_fraction, 0.0, 1.0))
        apply_central_force(Vector2(
            0.0,
            -linear_velocity.y * mass * vertical_heave_damping * heave_factor
        ))

    apply_torque(-angular_velocity * mass * 115.0 * submerged_fraction)

    var density_ratio := clampf(
        mass / maxf(_water.water_density_kg_m3 * object_volume_m3, 0.0001),
        0.12,
        1.0
    )
    var just_entered := (
        _previous_submerged_fraction < 0.02
        and submerged_fraction >= 0.10
    )
    if (
        just_entered
        and linear_velocity.y > 75.0
        and _surface_impact_cooldown <= 0.0
    ):
        _surface_impact_cooldown = 0.48
        _water.register_object_impact(
            global_position.x,
            mass,
            linear_velocity.y,
            maxf(displaced_volume, object_volume_m3 * 0.05) * density_ratio,
            object_size_px.x
        )

    # Floating bodies already disturb the conservative water field through their
    # smoothly changing occupied volume. Do not layer another surge on every bob.
    if predicted_submerged_fraction >= 0.90:
        _report_displacement_change(density_ratio)

    var sink_ratio := maxf(0.0, predicted_submerged_fraction - 1.0)
    if (
        sink_ratio > 0.10
        or (
            submerged_fraction > 0.68
            and linear_velocity.length_squared() > 6400.0
        )
    ):
        _water.register_underwater_motion(
            global_position,
            linear_velocity * density_ratio,
            maxf(object_size_px.x, object_size_px.y),
            sink_ratio,
            delta
        )

func _report_displacement_change(density_ratio: float = 1.0) -> void:
    if _water == null:
        return
    var fraction_delta := submerged_fraction - _previous_submerged_fraction
    if absf(fraction_delta) < 0.075 or absf(linear_velocity.y) < 110.0:
        return
    _water.register_displacement_surge(
        global_position.x,
        object_volume_m3 * fraction_delta * clampf(density_ratio, 0.12, 1.0),
        object_size_px.x,
        linear_velocity.y
    )

'''

text = text[:start] + new_block + text[end:]

# Reset filtered displacement when returning an object to spawn.
needle = '    submerged_fraction = 0.0\n    _previous_submerged_fraction = 0.0\n'
replacement = '    submerged_fraction = 0.0\n    _previous_submerged_fraction = 0.0\n    _reported_displaced_volume_m3 = 0.0\n'
if needle in text and '_reported_displaced_volume_m3 = 0.0\n    await' not in text:
    text = text.replace(needle, replacement, 1)

BODY.write_text(text, encoding='utf-8')
print('Water V6 continuous buoyancy patch applied')
