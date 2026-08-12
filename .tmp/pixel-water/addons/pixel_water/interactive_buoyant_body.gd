class_name InteractiveBuoyantPixelBody2D
extends BuoyantPixelBody2D

## Mouse grab that never teleports the rigid body.
## A spring-damper force pulls the clicked point toward the mouse while Godot's
## collision solver, buoyancy, drag, torque and CCD all continue to run normally.
## This means walls and other bodies remain real obstacles while the object is held.

@export_category("Physical grab")
@export_range(10.0, 180.0, 1.0) var grab_stiffness: float = 92.0
@export_range(1.0, 40.0, 0.5) var grab_damping: float = 18.0
@export_range(1000.0, 60000.0, 100.0) var max_grab_acceleration_px_s2: float = 26000.0
@export_range(100.0, 4000.0, 10.0) var max_held_speed_px_s: float = 1900.0
@export_range(0.0, 30.0, 0.5) var held_angular_damping: float = 4.0

var _dragging := false
var _grab_local_point := Vector2.ZERO

func _ready() -> void:
    super._ready()
    input_pickable = true
    continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE

func _physics_process(delta: float) -> void:
    super._physics_process(delta)

    if not _dragging:
        return

    var target := get_global_mouse_position()
    var grab_world := to_global(_grab_local_point)
    var r := grab_world - global_position

    # Velocity of the grabbed point, including angular motion.
    var point_velocity := linear_velocity + Vector2(
        -angular_velocity * r.y,
        angular_velocity * r.x
    )
    var position_error := target - grab_world

    var spring_force := position_error * (mass * grab_stiffness)
    var damping_force := -point_velocity * (mass * grab_damping)
    var force := spring_force + damping_force

    var max_force := mass * max_grab_acceleration_px_s2
    if force.length() > max_force:
        force = force.normalized() * max_force

    apply_force(force, r)

    # Keep absurd mouse flicks from injecting unbounded solver energy without
    # replacing the body's physical velocity with a synthetic throw value.
    if linear_velocity.length() > max_held_speed_px_s:
        var excess := linear_velocity.length() - max_held_speed_px_s
        apply_central_force(
            -linear_velocity.normalized()
            * excess
            * mass
            * 40.0
        )

    if held_angular_damping > 0.0:
        apply_torque(-angular_velocity * mass * held_angular_damping * 120.0)

func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if (
        event is InputEventMouseButton
        and event.button_index == MOUSE_BUTTON_LEFT
        and event.pressed
    ):
        selected.emit(self)
        _begin_drag()
        get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
    if not _dragging:
        return
    if (
        event is InputEventMouseButton
        and event.button_index == MOUSE_BUTTON_LEFT
        and not event.pressed
    ):
        _end_drag()
        get_viewport().set_input_as_handled()

func _begin_drag() -> void:
    _dragging = true
    sleeping = false
    _grab_local_point = to_local(get_global_mouse_position())
    set_process_unhandled_input(true)

func _end_drag() -> void:
    _dragging = false
    sleeping = false
    # No transform snap and no fabricated release velocity are required.
    # The RigidBody2D already owns the exact physical velocity it had at release.
    set_process_unhandled_input(false)

func is_being_dragged() -> bool:
    return _dragging
