class_name WaterBucket2D
extends InteractiveBuoyantPixelBody2D

## Lightweight mobile water container.
##
## The bucket is treated as a moving open basin rather than a pile of tiny
## RigidBody2D particles. Water mass is conserved with PixelWaterWorld2D, while
## the free surface is solved geometrically against world gravity. This gives a
## horizontal world-space waterline at any bucket rotation, continuous filling,
## physically motivated spilling, and a tiny CPU cost.

@export_category("Bucket")
@export_range(1.0, 30.0, 0.5) var capacity_liters: float = 9.0
@export_range(3.0, 12.0, 1.0) var wall_thickness_px: float = 5.0
@export_range(0.2, 1.0, 0.01) var fill_discharge_coefficient: float = 0.66
@export_range(0.2, 1.0, 0.01) var pour_discharge_coefficient: float = 0.70
@export_range(0.1, 8.0, 0.1) var max_transfer_liters_s: float = 4.0
@export_range(2, 12, 1) var opening_samples: int = 5

@export_category("Stable bucket grab")
@export_range(2.0, 30.0, 0.5) var held_angle_response: float = 16.0
@export_range(2.0, 40.0, 0.5) var held_angle_damping: float = 18.0
@export_range(2.0, 20.0, 0.5) var tilt_step_deg: float = 7.5
@export_range(45.0, 140.0, 1.0) var max_held_tilt_deg: float = 110.0

var contained_volume_m3: float = 0.0

var _dry_mass_kg: float = 0.8
var _held_target_angle: float = 0.0
var _last_draw_rotation: float = INF
var _last_draw_volume: float = -1.0

const INTERNAL_WATER := Color("#0b8fc9")
const INTERNAL_WATER_TOP := Color("#17a9dc")
const BUCKET_WALL := Color("#85a9b8")
const BUCKET_RIM := Color("#b8d3dc")

func _ready() -> void:
    display_name = "Transparent bucket"
    shape_kind = "box"
    if object_size_px == Vector2(44.0, 44.0):
        object_size_px = Vector2(68.0, 56.0)
    if material_name == "Pine wood":
        material_name = "Hollow plastic"

    physical_depth_m = 0.14
    auto_mass_from_material = true
    super._ready()

    var preset := WaterMaterialPresets.get_preset(material_name)
    _dry_mass_kg = maxf(0.20, float(preset["density"]) * object_volume_m3)
    mass = _dry_mass_kg
    _update_total_mass()
    queue_redraw()

func _build_collision() -> void:
    for child in get_children():
        if child is CollisionShape2D:
            child.queue_free()

    var half := object_size_px * 0.5
    var t := clampf(
        wall_thickness_px,
        3.0,
        minf(object_size_px.x, object_size_px.y) * 0.22
    )

    _add_bucket_rect(
        Vector2(t, object_size_px.y),
        Vector2(-half.x + t * 0.5, 0.0)
    )
    _add_bucket_rect(
        Vector2(t, object_size_px.y),
        Vector2(half.x - t * 0.5, 0.0)
    )
    _add_bucket_rect(
        Vector2(maxf(t, object_size_px.x - t * 2.0), t),
        Vector2(0.0, half.y - t * 0.5)
    )

func _add_bucket_rect(size: Vector2, local_pos: Vector2) -> void:
    var rect := RectangleShape2D.new()
    rect.size = size
    var collision := CollisionShape2D.new()
    collision.shape = rect
    collision.position = local_pos
    add_child(collision)

func _build_samples() -> void:
    _sample_points.clear()
    var half := object_size_px * 0.5
    var t := clampf(
        wall_thickness_px,
        3.0,
        minf(object_size_px.x, object_size_px.y) * 0.22
    )

    # The shell alone displaces outside water. The empty interior is not a solid.
    var side_rows := 5
    for row in range(side_rows):
        var y_t := (float(row) + 0.5) / float(side_rows)
        var y := lerpf(-half.y + t * 0.5, half.y - t * 0.5, y_t)
        _sample_points.append(Vector2(-half.x + t * 0.5, y))
        _sample_points.append(Vector2(half.x - t * 0.5, y))

    var bottom_cols := 6
    for col in range(bottom_cols):
        var x_t := (float(col) + 0.5) / float(bottom_cols)
        var x := lerpf(-half.x + t, half.x - t, x_t)
        _sample_points.append(Vector2(x, half.y - t * 0.5))

    var shell_area_px2 := (
        2.0 * t * object_size_px.y
        + maxf(object_size_px.x - t * 2.0, 0.0) * t
    )
    object_volume_m3 = maxf(
        0.00001,
        shell_area_px2
        / (pixels_per_meter * pixels_per_meter)
        * physical_depth_m
    )
    _update_prediction()

func _physics_process(delta: float) -> void:
    super._physics_process(delta)
    if _water == null:
        return

    _stabilize_held_bucket(delta)
    _equalize_with_world(delta)
    _spill_if_needed(delta)
    _update_total_mass()

    if (
        absf(global_rotation - _last_draw_rotation) > 0.002
        or absf(contained_volume_m3 - _last_draw_volume) > 0.000002
    ):
        _last_draw_rotation = global_rotation
        _last_draw_volume = contained_volume_m3
        queue_redraw()

func _begin_drag() -> void:
    # Tool-like grab: the cursor pulls the center of mass, so merely picking up
    # the bucket never injects accidental angular momentum.
    _dragging = true
    sleeping = false
    _grab_local_point = Vector2.ZERO
    _held_target_angle = 0.0
    angular_velocity = 0.0
    set_process_unhandled_input(true)

func _end_drag() -> void:
    _dragging = false
    sleeping = false
    set_process_unhandled_input(false)

func _unhandled_input(event: InputEvent) -> void:
    if is_being_dragged():
        if event is InputEventMouseButton and event.pressed:
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                _held_target_angle -= deg_to_rad(tilt_step_deg)
                _clamp_held_target()
                get_viewport().set_input_as_handled()
                return
            if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                _held_target_angle += deg_to_rad(tilt_step_deg)
                _clamp_held_target()
                get_viewport().set_input_as_handled()
                return

        if event is InputEventKey and event.pressed and not event.echo:
            if event.keycode == KEY_Q:
                _held_target_angle -= deg_to_rad(tilt_step_deg)
                _clamp_held_target()
                get_viewport().set_input_as_handled()
                return
            if event.keycode == KEY_E:
                _held_target_angle += deg_to_rad(tilt_step_deg)
                _clamp_held_target()
                get_viewport().set_input_as_handled()
                return

    super._unhandled_input(event)

func _clamp_held_target() -> void:
    var limit := deg_to_rad(max_held_tilt_deg)
    _held_target_angle = clampf(_held_target_angle, -limit, limit)

func _stabilize_held_bucket(delta: float) -> void:
    if not is_being_dragged():
        return
    var error := wrapf(_held_target_angle - global_rotation, -PI, PI)
    var desired_angular_velocity := error * held_angle_response
    var blend := 1.0 - exp(-held_angle_damping * delta)
    angular_velocity = lerpf(
        angular_velocity,
        desired_angular_velocity,
        clampf(blend, 0.0, 1.0)
    )

func _capacity_m3() -> float:
    return maxf(capacity_liters, 0.1) / 1000.0

func _interior_rect_local() -> Rect2:
    var half := object_size_px * 0.5
    var t := clampf(
        wall_thickness_px,
        3.0,
        minf(object_size_px.x, object_size_px.y) * 0.22
    )
    return Rect2(
        Vector2(-half.x + t, -half.y + t * 0.75),
        Vector2(
            maxf(4.0, object_size_px.x - t * 2.0),
            maxf(4.0, object_size_px.y - t * 1.75)
        )
    )

func _interior_world_polygon() -> PackedVector2Array:
    var r := _interior_rect_local()
    return PackedVector2Array([
        to_global(r.position),
        to_global(Vector2(r.end.x, r.position.y)),
        to_global(r.end),
        to_global(Vector2(r.position.x, r.end.y))
    ])

func _polygon_area(poly: PackedVector2Array) -> float:
    if poly.size() < 3:
        return 0.0
    var area := 0.0
    for i in range(poly.size()):
        var a := poly[i]
        var b := poly[(i + 1) % poly.size()]
        area += a.x * b.y - b.x * a.y
    return absf(area) * 0.5

func _clip_polygon_below_y(poly: PackedVector2Array, line_y: float) -> PackedVector2Array:
    var output := PackedVector2Array()
    if poly.is_empty():
        return output

    var previous := poly[poly.size() - 1]
    var previous_inside := previous.y >= line_y

    for current in poly:
        var current_inside := current.y >= line_y
        if current_inside != previous_inside:
            var dy := current.y - previous.y
            if absf(dy) > 0.00001:
                var t := (line_y - previous.y) / dy
                output.append(previous.lerp(current, clampf(t, 0.0, 1.0)))
        if current_inside:
            output.append(current)
        previous = current
        previous_inside = current_inside

    return output

func _fraction_below_world_y(line_y: float) -> float:
    var poly := _interior_world_polygon()
    var total_area := _polygon_area(poly)
    if total_area <= 0.0001:
        return 0.0
    return clampf(
        _polygon_area(_clip_polygon_below_y(poly, line_y)) / total_area,
        0.0,
        1.0
    )

func _waterline_world_y_for_fraction(fraction: float) -> float:
    var poly := _interior_world_polygon()
    if poly.is_empty():
        return global_position.y

    var min_y := INF
    var max_y := -INF
    for p in poly:
        min_y = minf(min_y, p.y)
        max_y = maxf(max_y, p.y)

    var target := clampf(fraction, 0.0, 1.0)
    if target <= 0.000001:
        return max_y + 0.01
    if target >= 0.999999:
        return min_y - 0.01

    var low := min_y
    var high := max_y
    for _i in range(12):
        var mid := (low + high) * 0.5
        var current_fraction := _fraction_below_world_y(mid)
        if current_fraction > target:
            low = mid
        else:
            high = mid
    return (low + high) * 0.5

func _opening_world_points() -> Array[Vector2]:
    var half := object_size_px * 0.5
    var t := wall_thickness_px
    var left := -half.x + t * 1.20
    var right := half.x - t * 1.20
    var local_y := -half.y + t * 0.42
    var count := maxi(opening_samples, 2)
    var points: Array[Vector2] = []
    for i in range(count):
        points.append(
            to_global(Vector2(
                lerpf(left, right, float(i) / float(count - 1)),
                local_y
            ))
        )
    return points

func _left_lip_world() -> Vector2:
    var half := object_size_px * 0.5
    return to_global(Vector2(
        -half.x + wall_thickness_px * 0.70,
        -half.y + wall_thickness_px * 0.30
    ))

func _right_lip_world() -> Vector2:
    var half := object_size_px * 0.5
    return to_global(Vector2(
        half.x - wall_thickness_px * 0.70,
        -half.y + wall_thickness_px * 0.30
    ))

func _equalize_with_world(delta: float) -> void:
    var points := _opening_world_points()
    var submerged_count := 0
    var outside_surface_sum := 0.0
    var sample_x_sum := 0.0
    var deepest_head_m := 0.0

    for p in points:
        if not _water.contains_point(p):
            continue
        submerged_count += 1
        var outside_y := _water.surface_y_at(p.x)
        outside_surface_sum += outside_y
        sample_x_sum += p.x
        deepest_head_m = maxf(
            deepest_head_m,
            maxf(0.0, p.y - outside_y) / pixels_per_meter
        )

    if submerged_count == 0:
        return

    var outside_surface_y := outside_surface_sum / float(submerged_count)
    var average_x := sample_x_sum / float(submerged_count)

    # An open moving container seeks the same hydrostatic free surface as the
    # surrounding water whenever its opening is submerged.
    var target_fraction := _fraction_below_world_y(outside_surface_y)
    var target_volume := _capacity_m3() * target_fraction
    var difference := target_volume - contained_volume_m3
    if absf(difference) < 0.000002:
        return

    var fill_fraction := contained_volume_m3 / maxf(_capacity_m3(), 0.000001)
    var internal_surface_y := _waterline_world_y_for_fraction(fill_fraction)
    var head_m := maxf(
        deepest_head_m,
        absf(internal_surface_y - outside_surface_y) / pixels_per_meter
    )
    head_m = maxf(head_m, 0.006)

    var g := _water.gravity_px_s2 / _water.pixels_per_meter
    var opening_width_m := _interior_rect_local().size.x / pixels_per_meter
    var submerged_fraction := float(submerged_count) / float(points.size())
    var opening_area_m2 := opening_width_m * physical_depth_m * submerged_fraction
    var q_m3_s := (
        fill_discharge_coefficient
        * opening_area_m2
        * sqrt(2.0 * g * head_m)
    )
    q_m3_s = minf(q_m3_s, max_transfer_liters_s / 1000.0)
    var transfer := minf(absf(difference), q_m3_s * delta)
    if transfer <= 0.0:
        return

    if difference > 0.0:
        var extracted := _water.extract_water_at(
            average_x,
            transfer,
            object_size_px.x * 0.70
        )
        contained_volume_m3 = minf(
            _capacity_m3(),
            contained_volume_m3 + extracted
        )
    else:
        transfer = minf(transfer, contained_volume_m3)
        contained_volume_m3 -= transfer
        _water.deposit_water_at(
            average_x,
            transfer,
            linear_velocity.x / pixels_per_meter,
            object_size_px.x * 0.55
        )

func _spill_if_needed(delta: float) -> void:
    if contained_volume_m3 <= 0.000001:
        return

    var left_lip := _left_lip_world()
    var right_lip := _right_lip_world()
    var lower_lip := left_lip if left_lip.y > right_lip.y else right_lip
    var retained_fraction := _fraction_below_world_y(lower_lip.y)
    var retained_volume := _capacity_m3() * retained_fraction
    var excess := contained_volume_m3 - retained_volume
    if excess <= 0.000002:
        return

    var fill_fraction := contained_volume_m3 / maxf(_capacity_m3(), 0.000001)
    var surface_y := _waterline_world_y_for_fraction(fill_fraction)
    var head_m := maxf(0.004, (lower_lip.y - surface_y) / pixels_per_meter)
    var g := _water.gravity_px_s2 / _water.pixels_per_meter
    var opening_width_m := _interior_rect_local().size.x / pixels_per_meter
    var q_m3_s := (
        pour_discharge_coefficient
        * opening_width_m
        * physical_depth_m
        * sqrt(2.0 * g * head_m)
    )
    q_m3_s = minf(q_m3_s, max_transfer_liters_s / 1000.0)
    var poured := minf(excess, q_m3_s * delta)
    if poured <= 0.0:
        return

    contained_volume_m3 -= poured

    var side := -1.0 if lower_lip == left_lip else 1.0
    var tangent := Vector2(side, 0.45).normalized().rotated(global_rotation)
    var out_speed := sqrt(2.0 * g * head_m) * pixels_per_meter
    var out_velocity := linear_velocity + tangent * maxf(45.0, out_speed)

    _water.emit_water_stream(
        lower_lip + tangent * 2.0,
        poured,
        out_velocity,
        3
    )

func contained_water_liters() -> float:
    return contained_volume_m3 * 1000.0

func clear_contained_water_without_return() -> void:
    contained_volume_m3 = 0.0
    _update_total_mass()
    queue_redraw()

func _update_total_mass() -> void:
    var density := 997.0
    if _water != null:
        density = _water.water_density_kg_m3
    mass = maxf(0.05, _dry_mass_kg + contained_volume_m3 * density)
    _update_prediction()

func set_mass_kg(value: float) -> void:
    var density := 997.0
    if _water != null:
        density = _water.water_density_kg_m3
    _dry_mass_kg = maxf(0.05, value - contained_volume_m3 * density)
    auto_mass_from_material = false
    _update_total_mass()

func set_material_preset(
    new_material: String,
    recalculate_mass: bool = true
) -> void:
    var water_before := contained_volume_m3
    contained_volume_m3 = 0.0
    super.set_material_preset(new_material, false)
    _build_samples()
    var preset := WaterMaterialPresets.get_preset(new_material)
    if recalculate_mass:
        _dry_mass_kg = maxf(
            0.05,
            float(preset["density"]) * object_volume_m3
        )
    contained_volume_m3 = water_before
    _update_total_mass()

func reset_to_spawn() -> void:
    if contained_volume_m3 > 0.0 and _water != null:
        _water.deposit_water_at(
            global_position.x,
            contained_volume_m3,
            linear_velocity.x / pixels_per_meter,
            object_size_px.x * 0.70
        )
    contained_volume_m3 = 0.0
    _held_target_angle = 0.0
    _update_total_mass()
    await super.reset_to_spawn()
    queue_redraw()

func _waterline_intersections_world(line_y: float) -> PackedVector2Array:
    var poly := _interior_world_polygon()
    var points := PackedVector2Array()
    for i in range(poly.size()):
        var a := poly[i]
        var b := poly[(i + 1) % poly.size()]
        if (a.y - line_y) * (b.y - line_y) > 0.0:
            continue
        var dy := b.y - a.y
        if absf(dy) <= 0.00001:
            continue
        var t := (line_y - a.y) / dy
        if t >= 0.0 and t <= 1.0:
            var p := a.lerp(b, t)
            var duplicate := false
            for existing in points:
                if existing.distance_squared_to(p) < 0.01:
                    duplicate = true
                    break
            if not duplicate:
                points.append(p)
    return points

func _draw() -> void:
    var half := object_size_px * 0.5
    var t := clampf(
        wall_thickness_px,
        3.0,
        minf(object_size_px.x, object_size_px.y) * 0.22
    )
    var interior := _interior_rect_local()

    draw_rect(interior, Color(0.78, 0.88, 0.92, 0.07))

    var fill_fraction := contained_volume_m3 / maxf(_capacity_m3(), 0.000001)
    if fill_fraction > 0.0001:
        var waterline_y := _waterline_world_y_for_fraction(fill_fraction)
        var clipped_world := _clip_polygon_below_y(
            _interior_world_polygon(),
            waterline_y
        )
        if clipped_world.size() >= 3:
            var local_poly := PackedVector2Array()
            for p in clipped_world:
                local_poly.append(to_local(p))
            draw_colored_polygon(local_poly, INTERNAL_WATER)

        var intersections := _waterline_intersections_world(waterline_y)
        if intersections.size() >= 2:
            draw_line(
                to_local(intersections[0]),
                to_local(intersections[1]),
                INTERNAL_WATER_TOP,
                2.0
            )

    draw_rect(
        Rect2(Vector2(-half.x, -half.y), Vector2(t, object_size_px.y)),
        BUCKET_WALL
    )
    draw_rect(
        Rect2(Vector2(half.x - t, -half.y), Vector2(t, object_size_px.y)),
        BUCKET_WALL
    )
    draw_rect(
        Rect2(Vector2(-half.x, half.y - t), Vector2(object_size_px.x, t)),
        BUCKET_WALL
    )
    draw_rect(
        Rect2(Vector2(-half.x - 1.0, -half.y), Vector2(t + 2.0, 3.0)),
        BUCKET_RIM
    )
    draw_rect(
        Rect2(Vector2(half.x - t - 1.0, -half.y), Vector2(t + 2.0, 3.0)),
        BUCKET_RIM
    )