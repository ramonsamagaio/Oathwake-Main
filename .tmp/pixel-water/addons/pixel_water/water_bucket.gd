class_name WaterBucket2D
extends InteractiveBuoyantPixelBody2D

## Open-topped, physically grabbed bucket that conserves water with PixelWaterWorld2D.
## Water is removed from the world when the bucket fills and returned as transported
## water droplets when it pours. The contained mass changes the RigidBody2D mass.

@export_category("Bucket")
@export_range(1.0, 30.0, 0.5) var capacity_liters: float = 9.0
@export_range(3.0, 12.0, 1.0) var wall_thickness_px: float = 5.0
@export_range(0.2, 1.0, 0.01) var fill_discharge_coefficient: float = 0.64
@export_range(0.2, 1.0, 0.01) var pour_discharge_coefficient: float = 0.70
@export_range(5.0, 50.0, 1.0) var pour_start_angle_deg: float = 24.0
@export_range(1, 24, 1) var pour_particle_count: int = 8

var contained_volume_m3: float = 0.0
var _dry_mass_kg: float = 0.8
var _internal_surface_fraction: float = 0.0
var _last_contained_volume_m3: float = 0.0

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
    var t := clampf(wall_thickness_px, 3.0, minf(object_size_px.x, object_size_px.y) * 0.22)

    _add_bucket_rect(Vector2(t, object_size_px.y), Vector2(-half.x + t * 0.5, 0.0))
    _add_bucket_rect(Vector2(t, object_size_px.y), Vector2(half.x - t * 0.5, 0.0))
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
    var t := clampf(wall_thickness_px, 3.0, minf(object_size_px.x, object_size_px.y) * 0.22)

    var side_rows := 7
    for row in range(side_rows):
        var y_t := (float(row) + 0.5) / float(side_rows)
        var y := lerpf(-half.y + t * 0.5, half.y - t * 0.5, y_t)
        _sample_points.append(Vector2(-half.x + t * 0.5, y))
        _sample_points.append(Vector2(half.x - t * 0.5, y))

    var bottom_cols := 7
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

    _last_contained_volume_m3 = contained_volume_m3
    _equalize_with_surrounding_water(delta)
    _pour_if_tilted(delta)
    _update_total_mass()

    var target_fraction := contained_volume_m3 / maxf(_capacity_m3(), 0.000001)
    _internal_surface_fraction = lerpf(
        _internal_surface_fraction,
        clampf(target_fraction, 0.0, 1.0),
        1.0 - exp(-10.0 * delta)
    )

    if absf(contained_volume_m3 - _last_contained_volume_m3) > 0.0000005:
        queue_redraw()

func contained_water_liters() -> float:
    return contained_volume_m3 * 1000.0

func clear_contained_water_without_return() -> void:
    contained_volume_m3 = 0.0
    _internal_surface_fraction = 0.0
    _update_total_mass()
    queue_redraw()

func _capacity_m3() -> float:
    return maxf(capacity_liters, 0.1) / 1000.0

func _interior_size_px() -> Vector2:
    var t := clampf(wall_thickness_px, 3.0, minf(object_size_px.x, object_size_px.y) * 0.22)
    return Vector2(
        maxf(4.0, object_size_px.x - t * 2.0),
        maxf(4.0, object_size_px.y - t * 1.8)
    )

func _opening_world_center() -> Vector2:
    var half := object_size_px * 0.5
    return to_global(Vector2(0.0, -half.y + wall_thickness_px * 0.45))

func _left_lip_world() -> Vector2:
    var half := object_size_px * 0.5
    return to_global(Vector2(-half.x + wall_thickness_px * 0.55, -half.y + wall_thickness_px * 0.25))

func _right_lip_world() -> Vector2:
    var half := object_size_px * 0.5
    return to_global(Vector2(half.x - wall_thickness_px * 0.55, -half.y + wall_thickness_px * 0.25))

func _equalize_with_surrounding_water(delta: float) -> void:
    var opening := _opening_world_center()
    if opening.x < _water.world_left or opening.x >= _water.world_right:
        return

    var outside_surface_y := _water.surface_y_at(opening.x)
    var outside_floor_y := _water.floor_y_at(opening.x)
    var opening_submerged := (
        _water.depth_m_at(opening.x) > _water.dry_depth_m
        and opening.y >= outside_surface_y
        and opening.y <= outside_floor_y + 1.0
    )

    if not opening_submerged:
        return

    var interior := _interior_size_px()
    var interior_bottom := to_global(Vector2(0.0, object_size_px.y * 0.5 - wall_thickness_px * 1.15))
    var vertical_span_px := maxf(
        4.0,
        interior.y * maxf(absf(cos(global_rotation)), 0.25)
    )

    # At equilibrium the water surface inside an open bucket matches the outside
    # free surface. This gives a partial fill when the rim is only slightly under.
    var target_fraction := clampf(
        (interior_bottom.y - outside_surface_y) / vertical_span_px,
        0.0,
        1.0
    )
    var target_volume := _capacity_m3() * target_fraction
    var difference := target_volume - contained_volume_m3

    if absf(difference) < 0.000002:
        return

    var head_m := absf(opening.y - outside_surface_y) / pixels_per_meter
    head_m = maxf(head_m, 0.008)
    var g := _water.gravity_px_s2 / _water.pixels_per_meter
    var opening_width_m := interior.x / pixels_per_meter
    var opening_area_m2 := opening_width_m * physical_depth_m
    var q_m3_s := (
        fill_discharge_coefficient
        * opening_area_m2
        * sqrt(2.0 * g * head_m)
    )
    var max_transfer := q_m3_s * delta

    if difference > 0.0:
        var requested := minf(difference, max_transfer)
        var extracted := _water.extract_water_at(
            opening.x,
            requested,
            object_size_px.x * 0.45
        )
        contained_volume_m3 += extracted
    else:
        var returned := minf(-difference, max_transfer)
        contained_volume_m3 -= returned
        _water.deposit_water_at(
            opening.x,
            returned,
            linear_velocity.x / pixels_per_meter,
            object_size_px.x * 0.30
        )

func _pour_if_tilted(delta: float) -> void:
    if contained_volume_m3 <= 0.000001:
        return

    var angle := absf(wrapf(global_rotation, -PI, PI))
    var start := deg_to_rad(pour_start_angle_deg)
    if angle <= start:
        return

    var normalized_tilt := clampf(
        (angle - start) / maxf(PI * 0.5 - start, 0.10),
        0.0,
        1.0
    )
    if angle > PI * 0.5:
        normalized_tilt = 1.0

    var retained_fraction := clampf(1.0 - normalized_tilt, 0.0, 1.0)
    var retained_volume := _capacity_m3() * retained_fraction
    if contained_volume_m3 <= retained_volume + 0.000001:
        return

    var excess := contained_volume_m3 - retained_volume
    var fill_fraction := contained_volume_m3 / maxf(_capacity_m3(), 0.000001)
    var interior_height_m := _interior_size_px().y / pixels_per_meter
    var head_m := maxf(0.01, interior_height_m * fill_fraction * maxf(normalized_tilt, 0.15))
    var g := _water.gravity_px_s2 / _water.pixels_per_meter
    var opening_area_m2 := (
        _interior_size_px().x / pixels_per_meter
        * physical_depth_m
        * maxf(normalized_tilt, 0.12)
    )
    var q_m3_s := (
        pour_discharge_coefficient
        * opening_area_m2
        * sqrt(2.0 * g * head_m)
    )
    var poured := minf(excess, q_m3_s * delta)
    if poured <= 0.0:
        return

    contained_volume_m3 -= poured

    var left_lip := _left_lip_world()
    var right_lip := _right_lip_world()
    var spout := left_lip if left_lip.y > right_lip.y else right_lip
    var side := -1.0 if spout == left_lip else 1.0
    var tangent := Vector2(side, 0.0).rotated(global_rotation)
    var out_velocity := linear_velocity + tangent * (90.0 + 170.0 * normalized_tilt)
    out_velocity.y += 35.0 + 85.0 * normalized_tilt

    _water.emit_water_stream(
        spout + tangent * 3.0,
        poured,
        out_velocity,
        clampi(
            int(2.0 + pour_particle_count * normalized_tilt),
            2,
            pour_particle_count
        )
    )

func _update_total_mass() -> void:
    var water_mass := contained_volume_m3 * (_water.water_density_kg_m3 if _water != null else 997.0)
    mass = maxf(0.05, _dry_mass_kg + water_mass)
    _update_prediction()

func set_mass_kg(value: float) -> void:
    var water_mass := contained_volume_m3 * (_water.water_density_kg_m3 if _water != null else 997.0)
    _dry_mass_kg = maxf(0.05, value - water_mass)
    auto_mass_from_material = false
    _update_total_mass()

func set_material_preset(new_material: String, recalculate_mass: bool = true) -> void:
    var water_before := contained_volume_m3
    contained_volume_m3 = 0.0
    super.set_material_preset(new_material, false)
    _build_samples()
    var preset := WaterMaterialPresets.get_preset(new_material)
    if recalculate_mass:
        _dry_mass_kg = maxf(0.05, float(preset["density"]) * object_volume_m3)
    contained_volume_m3 = water_before
    _update_total_mass()

func reset_to_spawn() -> void:
    if contained_volume_m3 > 0.0 and _water != null:
        # Resetting an object should not destroy water mass. Return its contents
        # near the bucket before moving it back to the spawn shelf.
        _water.deposit_water_at(
            global_position.x,
            contained_volume_m3,
            0.0,
            object_size_px.x * 0.35
        )
    contained_volume_m3 = 0.0
    _internal_surface_fraction = 0.0
    _update_total_mass()
    await super.reset_to_spawn()
    queue_redraw()

func _draw() -> void:
    var half := object_size_px * 0.5
    var t := clampf(wall_thickness_px, 3.0, minf(object_size_px.x, object_size_px.y) * 0.22)

    # Translucent interior so the contained water level is visible.
    var interior_rect := Rect2(
        Vector2(-half.x + t, -half.y + t * 0.55),
        Vector2(object_size_px.x - t * 2.0, object_size_px.y - t * 1.55)
    )
    draw_rect(interior_rect, Color(0.78, 0.88, 0.92, 0.10))

    if _internal_surface_fraction > 0.002:
        var fill_h := interior_rect.size.y * clampf(_internal_surface_fraction, 0.0, 1.0)
        var base_y := interior_rect.position.y + interior_rect.size.y
        var nominal_y := base_y - fill_h

        # Counter-rotate the local waterline so it remains approximately horizontal
        # in world space while the bucket rotates.
        var slope := -tan(clampf(global_rotation, -1.25, 1.25))
        var left_y := nominal_y - slope * interior_rect.size.x * 0.5
        var right_y := nominal_y + slope * interior_rect.size.x * 0.5
        left_y = clampf(left_y, interior_rect.position.y, base_y)
        right_y = clampf(right_y, interior_rect.position.y, base_y)

        var water_poly := PackedVector2Array([
            Vector2(interior_rect.position.x, left_y),
            Vector2(interior_rect.end.x, right_y),
            Vector2(interior_rect.end.x, base_y),
            Vector2(interior_rect.position.x, base_y)
        ])
        draw_colored_polygon(water_poly, Color("#1aa9dc"))
        draw_line(
            Vector2(interior_rect.position.x, left_y),
            Vector2(interior_rect.end.x, right_y),
            Color("#8be8f6"),
            2.0
        )

    var wall_color := Color("#85a9b8")
    var rim_color := Color("#b8d3dc")
    draw_rect(Rect2(Vector2(-half.x, -half.y), Vector2(t, object_size_px.y)), wall_color)
    draw_rect(Rect2(Vector2(half.x - t, -half.y), Vector2(t, object_size_px.y)), wall_color)
    draw_rect(
        Rect2(
            Vector2(-half.x, half.y - t),
            Vector2(object_size_px.x, t)
        ),
        wall_color
    )
    draw_rect(Rect2(Vector2(-half.x - 1.0, -half.y), Vector2(t + 2.0, 3.0)), rim_color)
    draw_rect(Rect2(Vector2(half.x - t - 1.0, -half.y), Vector2(t + 2.0, 3.0)), rim_color)
