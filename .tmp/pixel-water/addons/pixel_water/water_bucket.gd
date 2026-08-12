class_name WaterBucket2D
extends InteractiveBuoyantPixelBody2D

## Open mobile container backed by a tiny adaptive water grid.
##
## The world water remains the source of truth. When the opening is submerged,
## conservative volumes are removed from PixelWaterWorld2D and become discrete
## micro parcels inside this bucket. Those parcels settle under world gravity,
## respond to container acceleration, occupy the bucket interior and spill back
## into the world as real transported water. There is no painted/preset fill
## polygon and no independent bucket-water amount that can appear from nowhere.

@export_category("Bucket")
@export_range(1.0, 30.0, 0.5) var capacity_liters: float = 9.0
@export_range(3.0, 12.0, 1.0) var wall_thickness_px: float = 5.0
@export_range(2.0, 6.0, 1.0) var micro_cell_px: float = 3.0
@export_range(1, 6, 1) var micro_relax_iterations: int = 3
@export_range(0.2, 1.0, 0.01) var fill_discharge_coefficient: float = 0.72
@export_range(4, 64, 1) var max_fill_parcels_per_frame: int = 36
@export_range(4, 64, 1) var max_pour_parcels_per_frame: int = 30
@export_range(0.0, 1.0, 0.01) var container_inertia_influence: float = 0.28

@export_category("Stable bucket grab")
@export_range(2.0, 30.0, 0.5) var held_angle_response: float = 16.0
@export_range(2.0, 40.0, 0.5) var held_angle_damping: float = 18.0
@export_range(2.0, 20.0, 0.5) var tilt_step_deg: float = 7.5
@export_range(45.0, 140.0, 1.0) var max_held_tilt_deg: float = 110.0

var contained_volume_m3: float = 0.0

var _dry_mass_kg: float = 0.8
var _micro_cols: int = 0
var _micro_rows: int = 0
var _micro_cells: PackedByteArray = PackedByteArray()
var _parcel_volume_m3: float = 0.00005
var _fill_budget_m3: float = 0.0
var _previous_linear_velocity := Vector2.ZERO
var _held_target_angle: float = 0.0

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
    _rebuild_micro_grid()
    mass = _dry_mass_kg
    _previous_linear_velocity = linear_velocity
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

    var side_rows := 8
    for row in range(side_rows):
        var y_t := (float(row) + 0.5) / float(side_rows)
        var y := lerpf(-half.y + t * 0.5, half.y - t * 0.5, y_t)
        _sample_points.append(Vector2(-half.x + t * 0.5, y))
        _sample_points.append(Vector2(half.x - t * 0.5, y))

    var bottom_cols := 9
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
    _fill_micro_water_from_world(delta)
    _simulate_micro_water(delta)
    _spill_micro_water(delta)
    _sync_contained_volume()
    _update_total_mass()

    _previous_linear_velocity = linear_velocity
    queue_redraw()

func _begin_drag() -> void:
    # Buckets are utility tools, not awkward physics toys. Grab through the
    # centre of mass so the mouse spring cannot generate accidental torque.
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
        Vector2(-half.x + t, -half.y + t * 0.80),
        Vector2(
            maxf(4.0, object_size_px.x - t * 2.0),
            maxf(4.0, object_size_px.y - t * 1.80)
        )
    )

func _rebuild_micro_grid() -> void:
    var interior := _interior_rect_local()
    _micro_cols = maxi(2, int(floor(interior.size.x / maxf(micro_cell_px, 1.0))))
    _micro_rows = maxi(2, int(floor(interior.size.y / maxf(micro_cell_px, 1.0))))
    _micro_cells.resize(_micro_cols * _micro_rows)
    _micro_cells.fill(0)
    _parcel_volume_m3 = _capacity_m3() / float(maxi(1, _micro_cols * _micro_rows))
    contained_volume_m3 = 0.0
    _fill_budget_m3 = 0.0

func _micro_index(x: int, y: int) -> int:
    return y * _micro_cols + x

func _micro_occupied(x: int, y: int) -> bool:
    if x < 0 or x >= _micro_cols or y < 0 or y >= _micro_rows:
        return false
    return _micro_cells[_micro_index(x, y)] != 0

func _set_micro_occupied(x: int, y: int, occupied: bool) -> void:
    if x < 0 or x >= _micro_cols or y < 0 or y >= _micro_rows:
        return
    _micro_cells[_micro_index(x, y)] = 1 if occupied else 0

func _micro_center_local(x: int, y: int) -> Vector2:
    var interior := _interior_rect_local()
    return Vector2(
        interior.position.x
        + (float(x) + 0.5) * interior.size.x / float(_micro_cols),
        interior.position.y
        + (float(y) + 0.5) * interior.size.y / float(_micro_rows)
    )

func _occupied_parcel_count() -> int:
    var count := 0
    for value in _micro_cells:
        if value != 0:
            count += 1
    return count

func _sync_contained_volume() -> void:
    contained_volume_m3 = float(_occupied_parcel_count()) * _parcel_volume_m3

func contained_water_liters() -> float:
    return contained_volume_m3 * 1000.0

func clear_contained_water_without_return() -> void:
    _micro_cells.fill(0)
    _fill_budget_m3 = 0.0
    _sync_contained_volume()
    _update_total_mass()
    queue_redraw()

func _opening_sample_points() -> Array[Vector2]:
    var half := object_size_px * 0.5
    var t := wall_thickness_px
    var left := -half.x + t * 1.20
    var right := half.x - t * 1.20
    var local_y := -half.y + t * 0.45
    var points: Array[Vector2] = []
    for i in range(7):
        var x := lerpf(left, right, float(i) / 6.0)
        points.append(to_global(Vector2(x, local_y)))
    return points

func _fill_micro_water_from_world(delta: float) -> void:
    var samples := _opening_sample_points()
    var submerged := 0
    var deepest_head_m := 0.0
    var average_x := 0.0

    for p in samples:
        if _water.contains_point(p):
            submerged += 1
            average_x += p.x
            deepest_head_m = maxf(
                deepest_head_m,
                (p.y - _water.surface_y_at(p.x)) / pixels_per_meter
            )

    if submerged == 0:
        _fill_budget_m3 = minf(_fill_budget_m3, _parcel_volume_m3 * 0.5)
        return

    var empty_count := _micro_cols * _micro_rows - _occupied_parcel_count()
    if empty_count <= 0:
        return

    average_x /= float(submerged)
    var submerged_fraction := float(submerged) / float(samples.size())
    var interior := _interior_rect_local()
    var opening_width_m := interior.size.x / pixels_per_meter
    var opening_area_m2 := opening_width_m * physical_depth_m * submerged_fraction
    var g := _water.gravity_px_s2 / _water.pixels_per_meter
    var head_m := maxf(deepest_head_m, 0.012)
    var flow_m3_s := (
        fill_discharge_coefficient
        * opening_area_m2
        * sqrt(2.0 * g * head_m)
    )

    _fill_budget_m3 += flow_m3_s * delta
    var wanted := mini(
        empty_count,
        mini(
            max_fill_parcels_per_frame,
            int(floor(_fill_budget_m3 / maxf(_parcel_volume_m3, 0.0000001)))
        )
    )
    if wanted <= 0:
        return

    var requested := float(wanted) * _parcel_volume_m3
    var extracted := _water.extract_water_at(
        average_x,
        requested,
        object_size_px.x * 0.72
    )
    var parcels_from_world := mini(
        wanted,
        int(floor(extracted / maxf(_parcel_volume_m3, 0.0000001) + 0.0001))
    )

    var inserted := _insert_parcels_from_opening(parcels_from_world)
    var used_volume := float(inserted) * _parcel_volume_m3
    var unused_volume := maxf(0.0, extracted - used_volume)
    if unused_volume > 0.0:
        _water.deposit_water_at(
            average_x,
            unused_volume,
            linear_velocity.x / pixels_per_meter,
            object_size_px.x * 0.45
        )

    _fill_budget_m3 = maxf(0.0, _fill_budget_m3 - used_volume)

func _insert_parcels_from_opening(requested: int) -> int:
    var inserted := 0
    if requested <= 0:
        return 0

    var center := float(_micro_cols - 1) * 0.5
    for _n in range(requested):
        var best_x := -1
        var best_y := -1
        var best_score := INF

        # Enter through the open side, then let gravity move the parcel through
        # the interior. Searching only the first few rows keeps the motion legible.
        var search_rows := mini(_micro_rows, 5)
        for y in range(search_rows):
            for x in range(_micro_cols):
                if _micro_occupied(x, y):
                    continue
                var score := float(y) * 3.0 + absf(float(x) - center)
                if score < best_score:
                    best_score = score
                    best_x = x
                    best_y = y

        if best_x < 0:
            break
        _set_micro_occupied(best_x, best_y, true)
        inserted += 1

        # Make room for the next packet instead of visually teleporting a whole
        # fill level at once.
        _relax_micro_water_once(_effective_gravity_local())

    return inserted

func _effective_gravity_local() -> Vector2:
    var world_gravity := Vector2(0.0, _water.gravity_px_s2)
    var body_accel := Vector2.ZERO
    var physics_delta := maxf(get_physics_process_delta_time(), 0.0001)
    body_accel = (linear_velocity - _previous_linear_velocity) / physics_delta
    body_accel = body_accel.limit_length(_water.gravity_px_s2 * 1.75)

    var effective_world := (
        world_gravity
        - body_accel * clampf(container_inertia_influence, 0.0, 1.0)
    )
    if effective_world.length_squared() < 0.001:
        effective_world = world_gravity
    return effective_world.rotated(-global_rotation).normalized()

func _simulate_micro_water(_delta: float) -> void:
    if _occupied_parcel_count() == 0:
        return

    var gravity_local := _effective_gravity_local()
    for _iteration in range(micro_relax_iterations):
        _relax_micro_water_once(gravity_local)

func _relax_micro_water_once(gravity_local: Vector2) -> void:
    var y_start := _micro_rows - 1 if gravity_local.y >= 0.0 else 0
    var y_end := -1 if gravity_local.y >= 0.0 else _micro_rows
    var y_step := -1 if gravity_local.y >= 0.0 else 1
    var x_start := _micro_cols - 1 if gravity_local.x >= 0.0 else 0
    var x_end := -1 if gravity_local.x >= 0.0 else _micro_cols
    var x_step := -1 if gravity_local.x >= 0.0 else 1

    for y in range(y_start, y_end, y_step):
        for x in range(x_start, x_end, x_step):
            if not _micro_occupied(x, y):
                continue

            var best_x := x
            var best_y := y
            var best_score := 0.12

            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    if dx == 0 and dy == 0:
                        continue
                    var nx := x + dx
                    var ny := y + dy
                    if nx < 0 or nx >= _micro_cols or ny < 0 or ny >= _micro_rows:
                        continue
                    if _micro_occupied(nx, ny):
                        continue

                    var direction := Vector2(float(dx), float(dy)).normalized()
                    var score := direction.dot(gravity_local)
                    if score > best_score:
                        best_score = score
                        best_x = nx
                        best_y = ny

            if best_x != x or best_y != y:
                _set_micro_occupied(x, y, false)
                _set_micro_occupied(best_x, best_y, true)

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

func _spill_micro_water(delta: float) -> void:
    var count := _occupied_parcel_count()
    if count <= 0:
        return

    var left_lip := _left_lip_world()
    var right_lip := _right_lip_world()
    var spill_lip := left_lip if left_lip.y > right_lip.y else right_lip
    var spill_line_y := spill_lip.y - micro_cell_px * 0.10

    var candidates: Array[Vector2i] = []
    var highest_candidate_y := INF
    for y in range(_micro_rows):
        for x in range(_micro_cols):
            if not _micro_occupied(x, y):
                continue
            var world_p := to_global(_micro_center_local(x, y))
            if world_p.y < spill_line_y:
                candidates.append(Vector2i(x, y))
                highest_candidate_y = minf(highest_candidate_y, world_p.y)

    if candidates.is_empty():
        return

    var head_m := maxf(
        0.008,
        (spill_line_y - highest_candidate_y) / pixels_per_meter
    )
    var g := _water.gravity_px_s2 / _water.pixels_per_meter
    var opening_width_m := _interior_rect_local().size.x / pixels_per_meter
    var flow_m3_s := (
        0.68
        * opening_width_m
        * physical_depth_m
        * sqrt(2.0 * g * head_m)
    )
    var allowed_by_flow := maxi(
        1,
        int(ceil(flow_m3_s * delta / maxf(_parcel_volume_m3, 0.0000001)))
    )
    var remove_count := mini(
        candidates.size(),
        mini(max_pour_parcels_per_frame, allowed_by_flow)
    )

    # Highest world-space parcels leave first. That makes the free surface seek
    # the lower lip naturally as the bucket tilts.
    for _n in range(remove_count):
        var best_idx := 0
        var best_world_y := INF
        for i in range(candidates.size()):
            var cell := candidates[i]
            var wy := to_global(_micro_center_local(cell.x, cell.y)).y
            if wy < best_world_y:
                best_world_y = wy
                best_idx = i
        var chosen := candidates[best_idx]
        _set_micro_occupied(chosen.x, chosen.y, false)
        candidates.remove_at(best_idx)

    var poured_volume := float(remove_count) * _parcel_volume_m3
    if poured_volume <= 0.0:
        return

    var side := -1.0 if spill_lip == left_lip else 1.0
    var local_out := Vector2(side, 0.55).normalized()
    var world_out := local_out.rotated(global_rotation)
    var out_velocity := (
        linear_velocity
        + world_out * (80.0 + sqrt(2.0 * g * head_m) * pixels_per_meter)
    )

    _water.emit_water_stream(
        spill_lip + world_out * 3.0,
        poured_volume,
        out_velocity,
        clampi(remove_count, 2, 18)
    )

func _update_total_mass() -> void:
    var density := 997.0
    if _water != null:
        density = _water.water_density_kg_m3
    var water_mass := contained_volume_m3 * density
    mass = maxf(0.05, _dry_mass_kg + water_mass)
    _update_prediction()

func set_mass_kg(value: float) -> void:
    var density := 997.0
    if _water != null:
        density = _water.water_density_kg_m3
    var water_mass := contained_volume_m3 * density
    _dry_mass_kg = maxf(0.05, value - water_mass)
    auto_mass_from_material = false
    _update_total_mass()

func set_material_preset(
    new_material: String,
    recalculate_mass: bool = true
) -> void:
    var parcels := _occupied_parcel_count()
    super.set_material_preset(new_material, false)
    _build_samples()
    var preset := WaterMaterialPresets.get_preset(new_material)
    if recalculate_mass:
        _dry_mass_kg = maxf(
            0.05,
            float(preset["density"]) * object_volume_m3
        )

    # Preserve the actual micro-water occupancy when changing shell material.
    if _micro_cells.size() == 0:
        _rebuild_micro_grid()
    contained_volume_m3 = float(parcels) * _parcel_volume_m3
    _update_total_mass()

func reset_to_spawn() -> void:
    _sync_contained_volume()
    if contained_volume_m3 > 0.0 and _water != null:
        _water.deposit_water_at(
            global_position.x,
            contained_volume_m3,
            linear_velocity.x / pixels_per_meter,
            object_size_px.x * 0.65
        )

    _micro_cells.fill(0)
    _fill_budget_m3 = 0.0
    contained_volume_m3 = 0.0
    _held_target_angle = 0.0
    _update_total_mass()
    await super.reset_to_spawn()
    _previous_linear_velocity = linear_velocity
    queue_redraw()

func _draw() -> void:
    var half := object_size_px * 0.5
    var t := clampf(
        wall_thickness_px,
        3.0,
        minf(object_size_px.x, object_size_px.y) * 0.22
    )
    var interior := _interior_rect_local()

    draw_rect(interior, Color(0.78, 0.88, 0.92, 0.08))

    # Each occupied micro cell is drawn independently. Counter-rotating each tiny
    # quad keeps the water pixels approximately world-aligned while the bucket
    # itself rotates, so it reads as fluid parcels instead of a texture glued to it.
    var parcel_size := maxf(1.5, micro_cell_px * 0.92)
    var half_parcel := parcel_size * 0.5
    for y in range(_micro_rows):
        for x in range(_micro_cols):
            if not _micro_occupied(x, y):
                continue
            var center := _micro_center_local(x, y)
            var corners := PackedVector2Array([
                center + Vector2(-half_parcel, -half_parcel).rotated(-global_rotation),
                center + Vector2(half_parcel, -half_parcel).rotated(-global_rotation),
                center + Vector2(half_parcel, half_parcel).rotated(-global_rotation),
                center + Vector2(-half_parcel, half_parcel).rotated(-global_rotation)
            ])
            draw_colored_polygon(corners, INTERNAL_WATER)

    # A few exposed parcel tops get the same cyan surface accent used by world water.
    for x in range(_micro_cols):
        for y in range(_micro_rows):
            if not _micro_occupied(x, y):
                continue
            if y == 0 or not _micro_occupied(x, y - 1):
                var center := _micro_center_local(x, y)
                var a := center + Vector2(-half_parcel, -half_parcel).rotated(-global_rotation)
                var b := center + Vector2(half_parcel, -half_parcel).rotated(-global_rotation)
                draw_line(a, b, INTERNAL_WATER_TOP, 1.0)
                break

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
