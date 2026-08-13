class_name BuoyantPixelBody2D
extends RigidBody2D

signal selected(body: BuoyantPixelBody2D)

@export_category("Object")
@export var display_name: String = "Test object"
@export_enum("box", "circle") var shape_kind: String = "box"
@export var object_size_px: Vector2 = Vector2(44.0, 44.0)
@export_range(0.05, 1.0, 0.01) var physical_depth_m: float = 0.25
@export var material_name: String = "Pine wood"
@export var auto_mass_from_material: bool = true

@export_category("Hydrodynamics")
@export_range(0.1, 3.0, 0.01) var buoyancy_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.01) var drag_coefficient: float = 1.0
@export_range(3, 11, 1) var sample_columns: int = 5
@export_range(3, 11, 1) var sample_rows: int = 4
@export var auto_sample_wide_bodies: bool = true
@export_range(6.0, 18.0, 0.5) var target_sample_cell_px: float = 10.0
@export var pixels_per_meter: float = 100.0
@export_range(0.5, 2.0, 0.05) var immersion_cell_softness: float = 1.15
@export_range(0.0, 8.0, 0.1) var vertical_heave_damping: float = 2.8
@export_range(2.0, 30.0, 0.5) var displacement_follow_hz: float = 11.0
@export_range(2.0, 30.0, 0.5) var displacement_position_follow_hz: float = 16.0
@export_range(0.0, 20.0, 0.5) var equilibrium_capture_hz: float = 7.0

@export_category("Ground water pushing")
@export var enable_ground_piston: bool = true
@export_range(4.0, 30.0, 1.0) var ground_seal_tolerance_px: float = 12.0
@export_range(0.0, 1.0, 0.05) var ground_piston_efficiency: float = 0.72
@export_range(1.0, 80.0, 1.0) var ground_piston_min_speed_px_s: float = 14.0
@export_range(0.5, 6.0, 0.1) var ground_piston_max_speed_m_s: float = 3.6

var submerged_fraction: float = 0.0
var predicted_submerged_fraction: float = 0.0
var effective_density_kg_m3: float = 0.0
var object_volume_m3: float = 0.0
var last_buoyant_force: float = 0.0

var _water: PixelWaterWorld2D
var _sample_points: Array[Vector2] = []
var _previous_submerged_fraction := 0.0
var _material_color := Color("#b97943")
var _spawn_transform: Transform2D
var _surface_impact_cooldown := 0.0
var _reported_displaced_volume_m3 := 0.0
var _reported_displacement_x := INF

func _ready() -> void:
    collision_layer = 2
    collision_mask = 1 | 2
    contact_monitor = false
    max_contacts_reported = 0
    continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
    input_pickable = false
    linear_damp = 0.12
    angular_damp = 0.20
    _spawn_transform = global_transform

    _find_water()
    _apply_material(material_name, auto_mass_from_material)
    _build_collision()
    _build_samples()
    queue_redraw()

func _exit_tree() -> void:
    if _water != null and is_instance_valid(_water):
        _water.clear_displacement(get_instance_id())

func _find_water() -> void:
    var nodes := get_tree().get_nodes_in_group("pixel_water_world")
    if nodes.is_empty():
        nodes = get_tree().get_nodes_in_group("pixel_water_container")
    if nodes.is_empty():
        nodes = get_tree().get_nodes_in_group("water_simulator")
    if nodes.is_empty():
        _water = null
        return

    var best: PixelWaterWorld2D = null
    var best_distance: float = INF
    for node in nodes:
        var candidate: PixelWaterWorld2D = node as PixelWaterWorld2D
        if candidate == null:
            continue
        var dx: float = 0.0
        if global_position.x < candidate.world_left:
            dx = candidate.world_left - global_position.x
        elif global_position.x > candidate.world_right:
            dx = global_position.x - candidate.world_right
        if dx < best_distance:
            best_distance = dx
            best = candidate
    _water = best

func _build_collision() -> void:
    for child in get_children():
        if child is CollisionShape2D:
            child.queue_free()

    var collision := CollisionShape2D.new()
    if shape_kind == "circle":
        var circle := CircleShape2D.new()
        circle.radius = minf(object_size_px.x, object_size_px.y) * 0.5
        collision.shape = circle
    else:
        var rect := RectangleShape2D.new()
        rect.size = object_size_px
        collision.shape = rect
    add_child(collision)

func _build_samples() -> void:
    _sample_points.clear()
    var cols := maxi(sample_columns, 2)
    var rows := maxi(sample_rows, 2)
    if auto_sample_wide_bodies:
        cols = maxi(
            cols,
            clampi(int(ceil(object_size_px.x / target_sample_cell_px)), 3, 10)
        )
        rows = maxi(
            rows,
            clampi(int(ceil(object_size_px.y / target_sample_cell_px)), 3, 6)
        )

    for y_index in range(rows):
        var y_t := (float(y_index) + 0.5) / float(rows)
        var local_y := lerpf(-object_size_px.y * 0.5, object_size_px.y * 0.5, y_t)

        for x_index in range(cols):
            var x_t := (float(x_index) + 0.5) / float(cols)
            var local_x := lerpf(-object_size_px.x * 0.5, object_size_px.x * 0.5, x_t)
            var p := Vector2(local_x, local_y)

            if shape_kind == "circle":
                var rx := maxf(object_size_px.x * 0.5, 0.001)
                var ry := maxf(object_size_px.y * 0.5, 0.001)
                if (p.x * p.x) / (rx * rx) + (p.y * p.y) / (ry * ry) > 1.0:
                    continue

            _sample_points.append(p)

    _recalculate_volume()

func _recalculate_volume() -> void:
    var width_m := object_size_px.x / pixels_per_meter
    var height_m := object_size_px.y / pixels_per_meter
    var area_m2 := width_m * height_m
    if shape_kind == "circle":
        area_m2 *= PI * 0.25
    object_volume_m3 = maxf(0.00001, area_m2 * physical_depth_m)
    _update_prediction()

func _update_prediction() -> void:
    if _water == null:
        effective_density_kg_m3 = mass / maxf(object_volume_m3, 0.00001)
        return

    var displaced_mass_capacity: float = (
        _water.water_density_kg_m3
        * object_volume_m3
        * buoyancy_multiplier
    )
    predicted_submerged_fraction = mass / maxf(displaced_mass_capacity, 0.0001)
    effective_density_kg_m3 = mass / maxf(object_volume_m3, 0.00001)

func _sample_vertical_half_extent_px() -> float:
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

    var surface_y := _water.surface_y_for_body_at(
        world_point.x,
        get_instance_id()
    )
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

    if is_inf(_reported_displacement_x):
        _reported_displacement_x = global_position.x
    var position_follow := 1.0 - exp(
        -maxf(displacement_position_follow_hz, 0.01) * delta
    )
    _reported_displacement_x = lerpf(
        _reported_displacement_x,
        global_position.x,
        clampf(position_follow, 0.0, 1.0)
    )

    _water.report_displacement(
        get_instance_id(),
        _reported_displacement_x,
        object_size_px.x,
        _reported_displaced_volume_m3
    )

    _apply_ground_piston_coupling(delta)

    _water.register_object_activity_fx(
        global_position,
        linear_velocity,
        maxf(object_size_px.x, object_size_px.y),
        submerged_fraction,
        submerged_fraction - _previous_submerged_fraction,
        angular_velocity,
        delta
    )

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
    if adaptive_heave > 0.0 and absf(linear_velocity.y) > 0.02:
        var heave_factor := sqrt(clampf(submerged_fraction, 0.0, 1.0))
        apply_central_force(Vector2(
            0.0,
            -linear_velocity.y * mass * adaptive_heave * heave_factor
        ))

    var equilibrium_fraction := clampf(predicted_submerged_fraction, 0.0, 1.0)
    var equilibrium_error := absf(submerged_fraction - equilibrium_fraction)
    if (
        predicted_submerged_fraction < 0.98
        and equilibrium_error < 0.035
        and absf(linear_velocity.y) < 10.0
        and equilibrium_capture_hz > 0.0
    ):
        var settle := 1.0 - exp(-equilibrium_capture_hz * delta)
        linear_velocity.y = lerpf(linear_velocity.y, 0.0, settle)
        if absf(linear_velocity.y) < 0.30:
            linear_velocity.y = 0.0
        angular_velocity *= exp(-2.4 * floatiness * delta)

    apply_torque(-angular_velocity * mass * 125.0 * submerged_fraction)

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

func _apply_ground_piston_coupling(delta: float) -> void:
    if (
        not enable_ground_piston
        or _water == null
        or delta <= 0.0
        or absf(linear_velocity.x) < ground_piston_min_speed_px_s
    ):
        return

    var vertical_half_extent := (
        absf(cos(global_rotation)) * object_size_px.y * 0.5
        + absf(sin(global_rotation)) * object_size_px.x * 0.5
    )
    var bottom_y := global_position.y + vertical_half_extent
    var floor_y := _water.floor_y_at(global_position.x)
    var floor_gap := absf(floor_y - bottom_y)
    var seal := 1.0 - clampf(
        floor_gap / maxf(ground_seal_tolerance_px, 1.0),
        0.0,
        1.0
    )
    if seal <= 0.02:
        return

    var direction := -1.0 if linear_velocity.x < 0.0 else 1.0
    var horizontal_half_extent := (
        absf(cos(global_rotation)) * object_size_px.x * 0.5
        + absf(sin(global_rotation)) * object_size_px.y * 0.5
    )
    var front_x := global_position.x + direction * horizontal_half_extent
    if front_x < _water.world_left or front_x >= _water.world_right:
        return

    var front_depth_m := _water.depth_m_at(front_x)
    if front_depth_m <= _water.dry_depth_m:
        return

    # Swept-volume coupling for a floor-sealed moving solid.  The same water is
    # extracted at the moving face and deposited just ahead, so this behaves like
    # a piston/squeegee without creating mass or relying on a cosmetic wave.
    var body_u := clampf(
        linear_velocity.x / pixels_per_meter,
        -ground_piston_max_speed_m_s,
        ground_piston_max_speed_m_s
    )
    var body_height_m := object_size_px.y / pixels_per_meter
    var wetted_height_m := minf(body_height_m, front_depth_m)
    var swept_cross_section_m2 := maxf(
        0.0,
        wetted_height_m * physical_depth_m
    )
    var requested_m3 := (
        swept_cross_section_m2
        * absf(body_u)
        * delta
        * ground_piston_efficiency
        * seal
    )
    requested_m3 = minf(requested_m3, object_volume_m3 * 0.085)
    if requested_m3 <= 0.0000001:
        return

    var source_radius := maxf(object_size_px.x * 0.38, _water.cell_size_px * 2.0)
    var moved := _water.extract_water_at(
        front_x,
        requested_m3,
        source_radius
    )
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

func set_material_preset(new_material: String, recalculate_mass: bool = true) -> void:
    material_name = new_material
    _apply_material(new_material, recalculate_mass)

func _apply_material(new_material: String, recalculate_mass: bool) -> void:
    var preset := WaterMaterialPresets.get_preset(new_material)
    material_name = new_material
    _material_color = preset["color"]
    drag_coefficient = float(preset["drag"])
    _recalculate_volume()

    if recalculate_mass:
        mass = maxf(0.05, float(preset["density"]) * object_volume_m3)

    _update_prediction()
    queue_redraw()

func set_mass_kg(value: float) -> void:
    mass = maxf(0.05, value)
    auto_mass_from_material = false
    _update_prediction()

func set_buoyancy_multiplier(value: float) -> void:
    buoyancy_multiplier = clampf(value, 0.1, 3.0)
    _update_prediction()

func set_drag_coefficient(value: float) -> void:
    drag_coefficient = clampf(value, 0.1, 3.0)

func reset_to_spawn() -> void:
    if _water != null:
        _water.clear_displacement(get_instance_id())
    freeze = true
    global_transform = _spawn_transform
    PhysicsServer2D.body_set_state(
        get_rid(),
        PhysicsServer2D.BODY_STATE_TRANSFORM,
        _spawn_transform
    )
    linear_velocity = Vector2.ZERO
    angular_velocity = 0.0
    submerged_fraction = 0.0
    _previous_submerged_fraction = 0.0
    _reported_displaced_volume_m3 = 0.0
    _reported_displacement_x = INF
    await get_tree().physics_frame
    freeze = false
    sleeping = false

func float_state_text() -> String:
    if predicted_submerged_fraction < 0.98:
        return "FLOATS  •  equilibrium ≈ %d%% submerged" % int(
            clampf(predicted_submerged_fraction, 0.0, 1.0) * 100.0
        )
    if predicted_submerged_fraction <= 1.03:
        return "NEUTRAL / borderline buoyancy"
    return "SINKS  •  needs >100%% displacement"

func _draw() -> void:
    var half := object_size_px * 0.5
    var rect := Rect2(-half, object_size_px)

    if shape_kind == "circle":
        draw_circle(Vector2.ZERO, minf(half.x, half.y), _material_color)
        draw_circle(
            Vector2(-half.x * 0.25, -half.y * 0.25),
            maxf(2.0, minf(half.x, half.y) * 0.13),
            _material_color.lightened(0.26)
        )
    else:
        draw_rect(rect, _material_color)
        draw_rect(
            Rect2(
                rect.position + Vector2(3.0, 3.0),
                Vector2(maxf(3.0, rect.size.x - 6.0), 3.0)
            ),
            _material_color.lightened(0.20)
        )
        draw_rect(
            Rect2(
                rect.position + Vector2(3.0, rect.size.y - 5.0),
                Vector2(maxf(3.0, rect.size.x - 6.0), 2.0)
            ),
            _material_color.darkened(0.20)
        )