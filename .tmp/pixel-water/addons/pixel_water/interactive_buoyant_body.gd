class_name InteractiveBuoyantPixelBody2D
extends BuoyantPixelBody2D

## Drag interaction that remains part of the physics world while held.
## The held body becomes a frozen kinematic rigid body, so it can push other
## rigid bodies while the mouse controls it. Water displacement/wakes are still
## sampled every physics frame and the release velocity comes from the real drag.

@export_category("Live drag")
@export_range(300.0, 2600.0, 10.0) var max_drag_speed_px_s: float = 1800.0
@export_range(0.05, 1.0, 0.01) var drag_velocity_smoothing: float = 0.42

var _drag_grab_offset := Vector2.ZERO
var _last_drag_target := Vector2.ZERO

func _physics_process(delta: float) -> void:
    if not _dragging:
        var fraction_before := submerged_fraction
        super._physics_process(delta)
        _report_displacement_surge(fraction_before, submerged_fraction, linear_velocity)
        return

    if _water == null:
        _find_water()

    var mouse := get_global_mouse_position()
    var target := mouse + _drag_grab_offset
    var instantaneous_velocity := (target - _last_drag_target) / maxf(delta, 0.0001)
    _drag_velocity = _drag_velocity.lerp(instantaneous_velocity, drag_velocity_smoothing)
    _drag_velocity = _drag_velocity.limit_length(max_drag_speed_px_s)
    _last_drag_target = target
    _last_mouse_pos = mouse

    # FREEZE_MODE_KINEMATIC keeps this RigidBody2D collision-active while held.
    # Moving the transform therefore pushes/collides with other physics bodies
    # instead of becoming a ghost until release.
    global_position = target
    linear_velocity = _drag_velocity
    angular_velocity = 0.0

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
    _water.report_displacement(get_instance_id(), object_volume_m3 * submerged_fraction)

    # A held object should move exactly with the user's hand, so buoyancy/drag do
    # not fight the cursor. The water itself still receives displacement, impact
    # and wake information from the held object's real motion.
    var just_entered := _previous_submerged_fraction < 0.03 and submerged_fraction >= 0.03
    if just_entered and _drag_velocity.y > 20.0:
        _water.register_object_impact(
            global_position.x,
            mass,
            _drag_velocity.y,
            object_volume_m3 * maxf(submerged_fraction, 0.12),
            object_size_px.x
        )

    _report_displacement_surge(_previous_submerged_fraction, submerged_fraction, _drag_velocity)

    if submerged_fraction > 0.0:
        var sink_ratio := maxf(0.0, predicted_submerged_fraction - 1.0)
        _water.register_underwater_motion(
            global_position,
            _drag_velocity,
            maxf(object_size_px.x, object_size_px.y),
            sink_ratio,
            delta
        )

func _begin_drag() -> void:
    _dragging = true
    freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
    freeze = true
    sleeping = false
    continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE

    var mouse := get_global_mouse_position()
    _drag_grab_offset = global_position - mouse
    _last_drag_target = global_position
    _last_mouse_pos = mouse
    _drag_velocity = linear_velocity
    set_process_unhandled_input(true)

func _end_drag() -> void:
    var release_transform := global_transform
    var release_velocity := _drag_velocity.limit_length(max_drag_speed_px_s)

    _dragging = false
    freeze = false
    sleeping = false

    # Explicitly synchronize the final held transform with the physics server.
    # This prevents the rigid body from snapping back to the transform it had
    # before the drag when it becomes dynamic again.
    global_transform = release_transform
    PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, release_transform)
    linear_velocity = release_velocity
    angular_velocity = 0.0
    set_process_unhandled_input(false)

func _report_displacement_surge(old_fraction: float, new_fraction: float, motion_velocity: Vector2) -> void:
    if _water == null or not _water.has_method("register_displacement_surge"):
        return
    var fraction_delta := new_fraction - old_fraction
    if absf(fraction_delta) < 0.004:
        return
    _water.call(
        "register_displacement_surge",
        global_position.x,
        object_volume_m3 * fraction_delta,
        object_size_px.x,
        motion_velocity.y
    )
