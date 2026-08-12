class_name WaterBuoyancy2D
extends Node

## Drop-in buoyancy component for an existing RigidBody2D.
## Add this node as a child of the user's body. The parent keeps its own script,
## collision shapes and gameplay logic; this component only adds water forces.

signal entered_water
signal exited_water
signal submersion_changed(value: float)

@export_category("Quick setup")
@export var enabled: bool = true
@export var water_path: NodePath
@export var auto_detect_collision: bool = true
@export var fallback_size_px: Vector2 = Vector2(96.0, 20.0)
@export_range(0.02, 1.0, 0.01) var physical_depth_m: float = 0.12
@export_range(0.10, 3.0, 0.05) var volume_scale: float = 1.0

@export_category("Hydrodynamics")
@export_range(0.10, 3.0, 0.01) var buoyancy_multiplier: float = 1.0
@export_range(0.10, 3.0, 0.01) var drag_coefficient: float = 1.0
@export_range(6.0, 24.0, 1.0) var target_sample_cell_px: float = 12.0
@export_range(0.5, 2.0, 0.05) var immersion_cell_softness: float = 1.15
@export_range(0.0, 8.0, 0.1) var vertical_heave_damping: float = 2.8
@export_range(0.0, 250.0, 1.0) var angular_water_damping: float = 125.0
@export_range(2.0, 30.0, 0.5) var displacement_follow_hz: float = 11.0
@export_range(0.0, 20.0, 0.5) var equilibrium_capture_hz: float = 7.0
@export var report_displacement: bool = true
@export var surface_effects: bool = true

@export_category("Ground water pushing")
@export var enable_ground_piston: bool = true
@export_range(4.0, 30.0, 1.0) var ground_seal_tolerance_px: float = 12.0
@export_range(0.0, 1.0, 0.05) var ground_piston_efficiency: float = 0.72
@export_range(1.0, 80.0, 1.0) var ground_piston_min_speed_px_s: float = 14.0
@export_range(0.5, 6.0, 0.1) var ground_piston_max_speed_m_s: float = 3.6

var submerged_fraction: float = 0.0
var predicted_submerged_fraction: float = 0.0
var object_volume_m3: float = 0.0
var object_size_px: Vector2 = Vector2.ZERO
var last_buoyant_force: float = 0.0

var _body: RigidBody2D
var _water: PixelWaterWorld2D
var _bounds_local := Rect2()
var _entries: Array[Dictionary] = []
var _sample_points: Array[Vector2] = []
var _sample_columns := 3
var _sample_rows := 3
var _previous_submerged_fraction := 0.0
var _reported_displaced_volume_m3 := 0.0
var _reported_displacement_x := INF
var _impact_cooldown := 0.0
var _was_in_water := false

func _ready() -> void:
    _body = get_parent() as RigidBody2D
    if _body == null:
        push_error("WaterBuoyancy2D must be a child of a RigidBody2D.")
        set_physics_process(false)
        return

    if _body is BuoyantPixelBody2D:
        push_warning(
            "This RigidBody2D already inherits BuoyantPixelBody2D. "
            + "WaterBuoyancy2D was disabled to avoid applying buoyancy twice."
        )
        set_physics_process(false)
        return

    _find_water()
    refresh_geometry()

func _exit_tree() -> void:
    if _water != null and is_instance_valid(_water) and _body != null:
        _water.clear_displacement(_body.get_instance_id())

func refresh_geometry() -> void:
    if _body == null:
        return

    _entries = WaterIntegrationUtil.collision_entries(_body) if auto_detect_collision else []
    _bounds_local = WaterIntegrationUtil.collision_bounds_local(_body, fallback_size_px)
    if not auto_detect_collision:
        _bounds_local = Rect2(-fallback_size_px * 0.5, fallback_size_px)

    object_size_px = Vector2(
        maxf(_bounds_local.size.x, 2.0),
        maxf(_bounds_local.size.y, 2.0)
    )

    _sample_columns = clampi(
        int(ceil(object_size_px.x / maxf(target_sample_cell_px, 2.0))),
        3,
        12
    )
    _sample_rows = clampi(
        int(ceil(object_size_px.y / maxf(target_sample_cell_px, 2.0))),
        3,
        8
    )

    _sample_points.clear()
    for y_index in range(_sample_rows):
        var ty := (float(y_index) + 0.5) / float(_sample_rows)
        var y := lerpf(_bounds_local.position.y, _bounds_local.end.y, ty)
        for x_index in range(_sample_columns):
            var tx := (float(x_index) + 0.5) / float(_sample_columns)
            var x := lerpf(_bounds_local.position.x, _bounds_local.end.x, tx)
            var point := Vector2(x, y)
            if _entries.is_empty() or WaterIntegrationUtil.point_inside_entries(point, _entries):
                _sample_points.append(point)

    if _sample_points.is_empty():
        _sample_points.append(_bounds_local.get_center())

    var occupied_ratio := (
        float(_sample_points.size())
        / float(maxi(_sample_columns * _sample_rows, 1))
    )
    var ppm := _pixels_per_meter()
    var area_m2 := (
        object_size_px.x / ppm
        * object_size_px.y / ppm
        * clampf(occupied_ratio, 0.05, 1.0)
    )
    object_volume_m3 = maxf(
        0.00001,
        area_m2 * physical_depth_m * maxf(volume_scale, 0.01)
    )
    _update_prediction()

func get_water() -> PixelWaterWorld2D:
    return _water

func is_in_water() -> bool:
    return submerged_fraction > 0.02

func _find_water() -> void:
    if _body == null:
        return
    if not water_path.is_empty():
        var explicit := get_node_or_null(water_path) as PixelWaterWorld2D
        if explicit != null:
            _water = explicit
            return
    _water = WaterIntegrationUtil.find_water(self, _body.global_position.x)

func _pixels_per_meter() -> float:
    if _water != null:
        return maxf(_water.pixels_per_meter, 1.0)
    return 100.0

func _update_prediction() -> void:
    if _body == null:
        return
    if _water == null:
        predicted_submerged_fraction = 0.0
        return
    var capacity_mass := (
        _water.water_density_kg_m3
        * object_volume_m3
        * buoyancy_multiplier
    )
    predicted_submerged_fraction = _body.mass / maxf(capacity_mass, 0.0001)

func _sample_vertical_half_extent_px() -> float:
    var half_w := object_size_px.x / float(maxi(_sample_columns, 1)) * 0.5
    var half_h := object_size_px.y / float(maxi(_sample_rows, 1)) * 0.5
    var projected := (
        absf(sin(_body.global_rotation)) * half_w
        + absf(cos(_body.global_rotation)) * half_h
    )
    return maxf(1.5, projected * immersion_cell_softness)

func _immersion_weight(world_point: Vector2, half_extent_px: float) -> float:
    if _water == null or _body == null:
        return 0.0
    if world_point.x < _water.world_left or world_point.x >= _water.world_right:
        return 0.0
    if _water.depth_m_at(world_point.x) <= _water.dry_depth_m:
        return 0.0

    var surface_y := _water.surface_y_for_body_at(
        world_point.x,
        _body.get_instance_id()
    )
    var signed_depth_px := world_point.y - surface_y
    return smoothstep(-half_extent_px, half_extent_px, signed_depth_px)

func _physics_process(delta: float) -> void:
    if not enabled or _body == null:
        return

    _impact_cooldown = maxf(0.0, _impact_cooldown - delta)
    if (
        _water == null
        or _body.global_position.x < _water.world_left - object_size_px.x
        or _body.global_position.x > _water.world_right + object_size_px.x
    ):
        _find_water()

    if _water == null or _sample_points.is_empty():
        return

    _previous_submerged_fraction = submerged_fraction
    var half_extent_px := _sample_vertical_half_extent_px()
    var immersion_sum := 0.0
    for local_point in _sample_points:
        immersion_sum += _immersion_weight(_body.to_global(local_point), half_extent_px)

    submerged_fraction = clampf(
        immersion_sum / float(maxi(_sample_points.size(), 1)),
        0.0,
        1.0
    )
    _update_prediction()
    _update_water_signals()

    var displaced_volume := object_volume_m3 * submerged_fraction
    if report_displacement:
        var follow := 1.0 - exp(-maxf(displacement_follow_hz, 0.01) * delta)
        _reported_displaced_volume_m3 = lerpf(
            _reported_displaced_volume_m3,
            displaced_volume,
            clampf(follow, 0.0, 1.0)
        )
        if _reported_displaced_volume_m3 < 0.0000001:
            _reported_displaced_volume_m3 = 0.0

        if is_inf(_reported_displacement_x):
            _reported_displacement_x = _body.global_position.x
        _reported_displacement_x = lerpf(
            _reported_displacement_x,
            _body.global_position.x,
            clampf(1.0 - exp(-16.0 * delta), 0.0, 1.0)
        )

        _water.report_displacement(
            _body.get_instance_id(),
            _reported_displacement_x,
            _projected_horizontal_size_px(),
            _reported_displaced_volume_m3
        )

    _apply_ground_piston_coupling(delta)

    if submerged_fraction <= 0.0005:
        last_buoyant_force = 0.0
        return

    var volume_per_sample := object_volume_m3 / float(_sample_points.size())
    var base_force_per_sample := (
        _water.water_density_kg_m3
        * _water.gravity_px_s2
        * volume_per_sample
        * buoyancy_multiplier
    )
    last_buoyant_force = 0.0

    for local_point in _sample_points:
        var world_point := _body.to_global(local_point)
        var weight := _immersion_weight(world_point, half_extent_px)
        if weight <= 0.0005:
            continue
        var sample_force := base_force_per_sample * weight
        last_buoyant_force += sample_force
        _body.apply_force(
            Vector2(0.0, -sample_force),
            world_point - _body.global_position
        )

    _apply_water_drag(delta)
    _apply_surface_stability(delta)
    _apply_secondary_effects(displaced_volume, delta)

func _apply_water_drag(delta: float) -> void:
    var ppm := _pixels_per_meter()
    var velocity_m_s := _body.linear_velocity / ppm
    var speed_m_s := velocity_m_s.length()
    if speed_m_s > 0.01:
        var direction := velocity_m_s.normalized()
        var width_m := object_size_px.x / ppm
        var height_m := object_size_px.y / ppm
        var projected_length_m := (
            absf(direction.y) * width_m
            + absf(direction.x) * height_m
        )
        var projected_area_m2 := maxf(0.0001, projected_length_m * physical_depth_m)
        var drag_newtons := (
            0.5
            * _water.water_density_kg_m3
            * drag_coefficient
            * projected_area_m2
            * speed_m_s
            * speed_m_s
        )
        var drag_force_px := (
            -_body.linear_velocity.normalized()
            * drag_newtons
            * ppm
            * submerged_fraction
        )
        var max_drag := (
            _body.mass
            * maxf(_body.linear_velocity.length(), 1.0)
            / maxf(delta, 0.001)
            * 0.72
        )
        if drag_force_px.length() > max_drag:
            drag_force_px = drag_force_px.normalized() * max_drag
        _body.apply_central_force(drag_force_px)

func _apply_surface_stability(delta: float) -> void:
    var floatiness := 1.0 - clampf(predicted_submerged_fraction, 0.0, 1.0)
    var aspect_ratio := maxf(
        object_size_px.x / maxf(object_size_px.y, 1.0),
        1.0
    )
    var waterplane_factor := 1.0 + minf(0.65, (sqrt(aspect_ratio) - 1.0) * 0.32)
    var adaptive_heave := (
        vertical_heave_damping
        * (1.0 + floatiness * 0.75)
        * waterplane_factor
    )

    if adaptive_heave > 0.0 and absf(_body.linear_velocity.y) > 0.02:
        var heave_factor := sqrt(clampf(submerged_fraction, 0.0, 1.0))
        _body.apply_central_force(Vector2(
            0.0,
            -_body.linear_velocity.y * _body.mass * adaptive_heave * heave_factor
        ))

    var equilibrium_fraction := clampf(predicted_submerged_fraction, 0.0, 1.0)
    var equilibrium_error := absf(submerged_fraction - equilibrium_fraction)
    if (
        predicted_submerged_fraction < 0.98
        and equilibrium_error < 0.035
        and absf(_body.linear_velocity.y) < 10.0
        and equilibrium_capture_hz > 0.0
    ):
        var settle := 1.0 - exp(-equilibrium_capture_hz * delta)
        _body.linear_velocity.y = lerpf(_body.linear_velocity.y, 0.0, settle)
        if absf(_body.linear_velocity.y) < 0.30:
            _body.linear_velocity.y = 0.0
        _body.angular_velocity *= exp(-2.4 * floatiness * delta)

    if angular_water_damping > 0.0:
        _body.apply_torque(
            -_body.angular_velocity
            * _body.mass
            * angular_water_damping
            * submerged_fraction
        )

func _apply_secondary_effects(displaced_volume: float, delta: float) -> void:
    if not surface_effects:
        return

    var just_entered := (
        _previous_submerged_fraction < 0.02
        and submerged_fraction >= 0.10
    )
    if just_entered and _body.linear_velocity.y > 75.0 and _impact_cooldown <= 0.0:
        _impact_cooldown = 0.48
        var density_ratio := clampf(
            _body.mass / maxf(_water.water_density_kg_m3 * object_volume_m3, 0.0001),
            0.12,
            1.0
        )
        _water.register_object_impact(
            _body.global_position.x,
            _body.mass,
            _body.linear_velocity.y,
            maxf(displaced_volume, object_volume_m3 * 0.05) * density_ratio,
            _projected_horizontal_size_px()
        )

    if (
        submerged_fraction > 0.72
        and _body.linear_velocity.length_squared() > 10000.0
    ):
        _water.register_underwater_motion(
            _body.global_position,
            _body.linear_velocity * 0.55,
            maxf(object_size_px.x, object_size_px.y),
            maxf(0.0, predicted_submerged_fraction - 1.0),
            delta
        )

func _update_water_signals() -> void:
    var now_in_water := submerged_fraction > 0.02
    if now_in_water != _was_in_water:
        _was_in_water = now_in_water
        if now_in_water:
            entered_water.emit()
        else:
            exited_water.emit()
    if absf(submerged_fraction - _previous_submerged_fraction) > 0.002:
        submersion_changed.emit(submerged_fraction)

func _projected_horizontal_size_px() -> float:
    return (
        absf(cos(_body.global_rotation)) * object_size_px.x
        + absf(sin(_body.global_rotation)) * object_size_px.y
    )

func _projected_vertical_half_extent_px() -> float:
    return (
        absf(cos(_body.global_rotation)) * object_size_px.y * 0.5
        + absf(sin(_body.global_rotation)) * object_size_px.x * 0.5
    )

func _apply_ground_piston_coupling(delta: float) -> void:
    if (
        not enable_ground_piston
        or _water == null
        or delta <= 0.0
        or absf(_body.linear_velocity.x) < ground_piston_min_speed_px_s
    ):
        return

    var bottom_y := _body.global_position.y + _projected_vertical_half_extent_px()
    var floor_y := _water.floor_y_at(_body.global_position.x)
    var floor_gap := absf(floor_y - bottom_y)
    var seal := 1.0 - clampf(
        floor_gap / maxf(ground_seal_tolerance_px, 1.0),
        0.0,
        1.0
    )
    if seal <= 0.02:
        return

    var direction := -1.0 if _body.linear_velocity.x < 0.0 else 1.0
    var front_x := (
        _body.global_position.x
        + direction * _projected_horizontal_size_px() * 0.5
    )
    if front_x < _water.world_left or front_x >= _water.world_right:
        return

    var front_depth_m := _water.depth_m_at(front_x)
    if front_depth_m <= _water.dry_depth_m:
        return

    var ppm := _pixels_per_meter()
    var body_u := clampf(
        _body.linear_velocity.x / ppm,
        -ground_piston_max_speed_m_s,
        ground_piston_max_speed_m_s
    )
    var body_height_m := object_size_px.y / ppm
    var wetted_height_m := minf(body_height_m, front_depth_m)
    var requested_m3 := (
        wetted_height_m
        * physical_depth_m
        * absf(body_u)
        * delta
        * ground_piston_efficiency
        * seal
    )
    requested_m3 = minf(requested_m3, object_volume_m3 * 0.085)
    if requested_m3 <= 0.0000001:
        return

    var source_radius := maxf(
        object_size_px.x * 0.38,
        _water.cell_size_px * 2.0
    )
    var moved := _water.extract_water_at(front_x, requested_m3, source_radius)
    if moved <= 0.0:
        return

    var target_x := (
        front_x
        + direction * maxf(object_size_px.x * 0.30, _water.cell_size_px * 2.0)
    )
    _water.deposit_water_at(
        target_x,
        moved,
        body_u * 0.92,
        maxf(object_size_px.x * 0.42, _water.cell_size_px * 2.0)
    )
