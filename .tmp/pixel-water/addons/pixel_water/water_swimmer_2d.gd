class_name WaterSwimmer2D
extends Node

## Drop-in swimming bridge for an existing CharacterBody2D.
## The user's controller remains in charge. Add one line after normal movement /
## gravity code and immediately before move_and_slide():
## velocity = $WaterSwimmer2D.apply_water_motion(velocity, delta)

signal entered_water
signal exited_water
signal head_submerged
signal head_emerged
signal submersion_changed(value: float)

@export_category("Quick setup")
@export var enabled: bool = true
@export var water_path: NodePath
@export var auto_detect_collision: bool = true
@export var fallback_body_size_px: Vector2 = Vector2(28.0, 52.0)
@export_range(0.02, 1.0, 0.01) var physical_depth_m: float = 0.12
@export_range(0.10, 3.0, 0.05) var volume_scale: float = 1.0
@export var displace_water: bool = true

@export_category("Swimming feel")
@export_range(0.0, 1.5, 0.01) var gravity_cancel_ratio: float = 0.86
@export_range(0.0, 1000.0, 10.0) var passive_buoyancy_px_s2: float = 70.0
@export_range(0.0, 12.0, 0.1) var horizontal_water_drag: float = 2.0
@export_range(0.0, 12.0, 0.1) var vertical_water_drag: float = 2.8
@export_range(0.0, 2400.0, 10.0) var swim_acceleration_px_s2: float = 760.0
@export_range(20.0, 800.0, 10.0) var max_vertical_swim_speed_px_s: float = 220.0
@export var use_builtin_swim_input: bool = true
@export var swim_up_action: StringName = &"ui_accept"
@export var swim_down_action: StringName = &"ui_down"

@export_category("Interaction")
@export_range(0.01, 0.50, 0.01) var water_enter_threshold: float = 0.05
@export var entry_splash: bool = true
@export var underwater_wake: bool = false
@export_range(2.0, 30.0, 0.5) var displacement_follow_hz: float = 12.0

var submersion_ratio: float = 0.0
var water_surface_y: float = INF
var head_is_submerged: bool = false
var body_volume_m3: float = 0.0

var _body: CharacterBody2D
var _water: PixelWaterWorld2D
var _bounds_local := Rect2()
var _entries: Array[Dictionary] = []
var _was_in_water := false
var _was_head_submerged := false
var _reported_displaced_volume_m3 := 0.0
var _last_report_x := INF

func _ready() -> void:
    _body = get_parent() as CharacterBody2D
    if _body == null:
        push_error("WaterSwimmer2D must be a child of a CharacterBody2D.")
        set_physics_process(false)
        return

    # State detection runs before a normal player controller (priority 0), but this
    # component never calls move_and_slide() or replaces the user's controller.
    process_physics_priority = -100
    _find_water()
    refresh_geometry()
    _update_water_state(0.0)

func _exit_tree() -> void:
    if _water != null and is_instance_valid(_water) and _body != null:
        _water.clear_displacement(_body.get_instance_id())

func refresh_geometry() -> void:
    if _body == null:
        return
    _entries = WaterIntegrationUtil.collision_entries(_body) if auto_detect_collision else []
    _bounds_local = WaterIntegrationUtil.collision_bounds_local(
        _body,
        fallback_body_size_px
    )
    if not auto_detect_collision:
        _bounds_local = Rect2(-fallback_body_size_px * 0.5, fallback_body_size_px)

    var ratio := WaterIntegrationUtil.estimate_area_ratio(
        _bounds_local,
        _entries,
        8,
        8
    )
    var ppm := _pixels_per_meter()
    body_volume_m3 = maxf(
        0.00001,
        _bounds_local.size.x / ppm
        * _bounds_local.size.y / ppm
        * ratio
        * physical_depth_m
        * maxf(volume_scale, 0.01)
    )

func get_water() -> PixelWaterWorld2D:
    return _water

func is_in_water() -> bool:
    return submersion_ratio >= water_enter_threshold

func get_submersion() -> float:
    return submersion_ratio

func get_surface_y() -> float:
    return water_surface_y

func is_head_underwater() -> bool:
    return head_is_submerged

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

func _physics_process(delta: float) -> void:
    if not enabled or _body == null:
        return
    if (
        _water == null
        or _body.global_position.x < _water.world_left - _bounds_local.size.x
        or _body.global_position.x > _water.world_right + _bounds_local.size.x
    ):
        _find_water()
    _update_water_state(delta)

func _update_water_state(delta: float) -> void:
    if _body == null or _water == null:
        _set_dry_state()
        return

    var x := _body.global_position.x
    if x < _water.world_left or x >= _water.world_right:
        _set_dry_state()
        return
    if _water.depth_m_at(x) <= _water.dry_depth_m:
        _set_dry_state()
        return

    water_surface_y = _water.surface_y_for_body_at(x, _body.get_instance_id())
    var corners := [
        _body.to_global(_bounds_local.position),
        _body.to_global(Vector2(_bounds_local.end.x, _bounds_local.position.y)),
        _body.to_global(_bounds_local.end),
        _body.to_global(Vector2(_bounds_local.position.x, _bounds_local.end.y))
    ]
    var top_y := INF
    var bottom_y := -INF
    for corner in corners:
        top_y = minf(top_y, corner.y)
        bottom_y = maxf(bottom_y, corner.y)

    var height := maxf(bottom_y - top_y, 1.0)
    submersion_ratio = clampf(
        (bottom_y - water_surface_y) / height,
        0.0,
        1.0
    )
    head_is_submerged = top_y > water_surface_y

    _update_signals()
    _report_character_displacement(delta)
    _emit_optional_interaction(delta)

func _set_dry_state() -> void:
    submersion_ratio = 0.0
    water_surface_y = INF
    head_is_submerged = false
    _update_signals()
    if _water != null and _body != null:
        _water.clear_displacement(_body.get_instance_id())
    _reported_displaced_volume_m3 = 0.0
    _last_report_x = INF

func _update_signals() -> void:
    var now_in_water := is_in_water()
    if now_in_water != _was_in_water:
        _was_in_water = now_in_water
        if now_in_water:
            entered_water.emit()
            if entry_splash and _water != null and _body != null and _body.velocity.y > 70.0:
                _water.emit_visual_splash(
                    Vector2(_body.global_position.x, water_surface_y - _water.cell_size_px * 0.5),
                    Vector2(_body.velocity.x * 0.18, -minf(absf(_body.velocity.y) * 0.28, 130.0)),
                    4
                )
        else:
            exited_water.emit()

    if head_is_submerged != _was_head_submerged:
        _was_head_submerged = head_is_submerged
        if head_is_submerged:
            head_submerged.emit()
        else:
            head_emerged.emit()

    submersion_changed.emit(submersion_ratio)

func _report_character_displacement(delta: float) -> void:
    if not displace_water or _water == null or _body == null:
        return

    var target := body_volume_m3 * submersion_ratio
    var follow := 1.0 - exp(-maxf(displacement_follow_hz, 0.01) * maxf(delta, 0.0))
    _reported_displaced_volume_m3 = lerpf(
        _reported_displaced_volume_m3,
        target,
        clampf(follow, 0.0, 1.0)
    )
    if _reported_displaced_volume_m3 < 0.0000001:
        _reported_displaced_volume_m3 = 0.0

    if is_inf(_last_report_x):
        _last_report_x = _body.global_position.x
    _last_report_x = lerpf(
        _last_report_x,
        _body.global_position.x,
        clampf(1.0 - exp(-16.0 * maxf(delta, 0.0)), 0.0, 1.0)
    )

    _water.report_displacement(
        _body.get_instance_id(),
        _last_report_x,
        maxf(_bounds_local.size.x, _water.cell_size_px),
        _reported_displaced_volume_m3
    )

func _emit_optional_interaction(delta: float) -> void:
    if not underwater_wake or _water == null or _body == null:
        return
    if submersion_ratio < 0.55 or _body.velocity.length_squared() < 14400.0:
        return
    _water.register_underwater_motion(
        _body.global_position,
        _body.velocity * 0.28,
        maxf(_bounds_local.size.x, _bounds_local.size.y),
        0.0,
        delta
    )

func apply_water_motion(current_velocity: Vector2, delta: float) -> Vector2:
    ## Call this after the user's normal movement/gravity calculations and before
    ## CharacterBody2D.move_and_slide(). Outside water it returns velocity unchanged.
    if not enabled or _body == null:
        return current_velocity

    # Refresh here as well so the one-line integration always uses current state,
    # even if the buyer changes physics processing priorities in their controller.
    _update_water_state(0.0)
    if not is_in_water():
        return current_velocity

    var wet := smoothstep(
        maxf(water_enter_threshold, 0.001),
        0.95,
        submersion_ratio
    )
    var result := current_velocity

    result.x *= exp(-horizontal_water_drag * wet * delta)
    result.y *= exp(-vertical_water_drag * wet * delta)

    var project_gravity := float(ProjectSettings.get_setting(
        "physics/2d/default_gravity",
        980.0
    ))
    result.y -= (
        project_gravity * gravity_cancel_ratio
        + passive_buoyancy_px_s2
    ) * wet * delta

    if use_builtin_swim_input:
        var swim_axis := Input.get_axis(swim_up_action, swim_down_action)
        result.y += swim_axis * swim_acceleration_px_s2 * wet * delta

    var max_speed := maxf(max_vertical_swim_speed_px_s, 1.0)
    result.y = clampf(result.y, -max_speed, max_speed)
    return result

func apply_water_motion_with_axis(
    current_velocity: Vector2,
    delta: float,
    vertical_swim_axis: float
) -> Vector2:
    ## Same as apply_water_motion(), but lets a custom controller provide its own
    ## vertical swim input. -1 = up, +1 = down.
    var old_builtin := use_builtin_swim_input
    use_builtin_swim_input = false
    var result := apply_water_motion(current_velocity, delta)
    use_builtin_swim_input = old_builtin
    if not is_in_water():
        return result

    var wet := smoothstep(
        maxf(water_enter_threshold, 0.001),
        0.95,
        submersion_ratio
    )
    result.y += clampf(vertical_swim_axis, -1.0, 1.0) * swim_acceleration_px_s2 * wet * delta
    var max_speed := maxf(max_vertical_swim_speed_px_s, 1.0)
    result.y = clampf(result.y, -max_speed, max_speed)
    return result
