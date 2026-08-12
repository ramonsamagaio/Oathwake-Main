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
@export var pixels_per_meter: float = 100.0

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

func _physics_process(delta: float) -> void:
    if (
        _water == null
        or global_position.x < _water.world_left - object_size_px.x
        or global_position.x > _water.world_right + object_size_px.x
    ):
        _find_water()

    if _water == null or _sample_points.is_empty():
        return

    _previous_submerged_fraction = submerged_fraction
    var submerged_points: Array[Vector2] = []

    for local_point in _sample_points:
        var world_point := to_global(local_point)
        if _water.contains_point(world_point):
            submerged_points.append(world_point)

    submerged_fraction = float(submerged_points.size()) / float(_sample_points.size())
    _update_prediction()

    var displaced_volume: float = object_volume_m3 * submerged_fraction
    _water.report_displacement(
        get_instance_id(),
        global_position.x,
        object_size_px.x,
        displaced_volume
    )

    if submerged_points.is_empty():
        last_buoyant_force = 0.0
        _report_displacement_change()
        return

    # Archimedes: Fb = rho * g * displaced volume. Forces are applied at sampled
    # points so an unevenly submerged body receives a real stabilizing torque.
    var volume_per_sample: float = object_volume_m3 / float(_sample_points.size())
    var force_per_sample: float = (
        _water.water_density_kg_m3
        * _water.gravity_px_s2
        * volume_per_sample
        * buoyancy_multiplier
    )
    last_buoyant_force = force_per_sample * float(submerged_points.size())

    for world_point in submerged_points:
        apply_force(
            Vector2(0.0, -force_per_sample),
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

    apply_torque(-angular_velocity * mass * 115.0 * submerged_fraction)

    var just_entered := (
        _previous_submerged_fraction < 0.03
        and submerged_fraction >= 0.03
    )
    if just_entered and linear_velocity.y > 28.0:
        _water.register_object_impact(
            global_position.x,
            mass,
            linear_velocity.y,
            maxf(displaced_volume, object_volume_m3 * 0.08),
            object_size_px.x
        )

    _report_displacement_change()

    var sink_ratio := maxf(0.0, predicted_submerged_fraction - 1.0)
    if linear_velocity.length_squared() > 225.0 or sink_ratio > 0.08:
        _water.register_underwater_motion(
            global_position,
            linear_velocity,
            maxf(object_size_px.x, object_size_px.y),
            sink_ratio,
            delta
        )

func _report_displacement_change() -> void:
    if _water == null:
        return
    var fraction_delta := submerged_fraction - _previous_submerged_fraction
    if absf(fraction_delta) < 0.012:
        return
    _water.register_displacement_surge(
        global_position.x,
        object_volume_m3 * fraction_delta,
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
