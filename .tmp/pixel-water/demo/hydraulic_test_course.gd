extends Node2D

## Extended hydraulic playground placed to the right of the two original basins.
## The same PixelWaterWorld2D solver is reconfigured over the larger domain, so
## ramps, stairs, lips, channels and catch basins are not a separate water mode.

const COURSE_WORLD_LEFT := 1320.0
const COURSE_WORLD_RIGHT := 2400.0
const WORLD_BOTTOM := 900.0
const PLATFORM_Y := 240.0

const MAIN_LEFT := 170.0
const MAIN_RIGHT := 790.0
const MAIN_BOTTOM := 500.0
const MAIN_INITIAL_SURFACE := 275.0

const SMALL_LEFT := 970.0
const SMALL_RIGHT := 1120.0
const SMALL_BOTTOM := 430.0
const SMALL_INITIAL_SURFACE := 405.0

const SOURCE_LEFT := 1360.0
const SOURCE_RIGHT := 1490.0
const SOURCE_BOTTOM := 360.0
const SOURCE_INITIAL_SURFACE := 336.0

const BG := Color("#10181f")
const SKY := Color("#d8e6e8")
const GROUND := Color("#30383a")
const GROUND_TOP := Color("#202729")
const GRID_FAINT := Color(0.15, 0.22, 0.25, 0.16)
const LABEL := Color(0.76, 0.91, 0.93)
const LABEL_DIM := Color(0.58, 0.72, 0.75)

var _water: PixelWaterWorld2D
var _profile: Array[Dictionary] = []

func _ready() -> void:
    call_deferred("_install_course")

func _install_course() -> void:
    _water = get_parent().get_node_or_null("Water") as PixelWaterWorld2D
    if _water == null:
        return

    _water.world_right = COURSE_WORLD_RIGHT
    _water.max_foam_particles = 200
    _water.foam_lifetime = 2.45

    _profile = _build_course_profile()

    var floors: Array[Dictionary] = [
        {
            "left": MAIN_LEFT,
            "right": MAIN_RIGHT,
            "floor_y": MAIN_BOTTOM
        },
        {
            "left": SMALL_LEFT,
            "right": SMALL_RIGHT,
            "floor_y": SMALL_BOTTOM
        }
    ]
    for segment in _profile:
        floors.append(segment)

    var initial_water: Array[Dictionary] = [
        {
            "left": MAIN_LEFT,
            "right": MAIN_RIGHT,
            "surface_y": MAIN_INITIAL_SURFACE
        },
        {
            "left": SMALL_LEFT,
            "right": SMALL_RIGHT,
            "surface_y": SMALL_INITIAL_SURFACE
        },
        {
            "left": SOURCE_LEFT,
            "right": SOURCE_RIGHT,
            "surface_y": SOURCE_INITIAL_SURFACE
        }
    ]

    _water.configure_world(floors, initial_water)
    _build_course_collision()
    _build_world_labels()
    queue_redraw()

func _build_course_profile() -> Array[Dictionary]:
    var result: Array[Dictionary] = []

    # Dry approach from the original scene into the hydraulic playground.
    result.append(_segment(1320.0, 1360.0, PLATFORM_Y))

    # A small source pocket. It begins below the right lip, so users can add
    # water with the bucket until it overtops naturally.
    result.append(_segment(SOURCE_LEFT, SOURCE_RIGHT, SOURCE_BOTTOM))
    result.append(_segment(1490.0, 1520.0, 300.0))

    # Pixel ramp descending into the staircase section.
    result.append_array(_ramp_segments(1520.0, 1690.0, 300.0, 420.0, 12.0))

    # Large steps make individual waterfalls and impact zones easy to inspect.
    result.append(_segment(1690.0, 1742.0, 420.0))
    result.append(_segment(1742.0, 1794.0, 450.0))
    result.append(_segment(1794.0, 1846.0, 480.0))
    result.append(_segment(1846.0, 1898.0, 510.0))
    result.append(_segment(1898.0, 1930.0, 540.0))

    # Lower channel with a raised weir in the middle. Water should pool behind
    # it, overtop it, then continue into the next section.
    result.append(_segment(1930.0, 1998.0, 570.0))
    result.append(_segment(1998.0, 2040.0, 525.0))
    result.append(_segment(2040.0, 2110.0, 570.0))

    # Uphill ramp tests whether shallow flow loses momentum, piles up and only
    # crosses when enough hydraulic head exists.
    result.append_array(_ramp_segments(2110.0, 2254.0, 570.0, 510.0, 12.0))

    # Final catch pocket, followed by a tall dry boundary wall.
    result.append(_segment(2254.0, 2350.0, 560.0))
    result.append(_segment(2350.0, COURSE_WORLD_RIGHT, PLATFORM_Y))

    return result

func _segment(left: float, right: float, floor_y: float) -> Dictionary:
    return {
        "left": left,
        "right": right,
        "floor_y": floor_y
    }

func _ramp_segments(
    left: float,
    right: float,
    start_y: float,
    end_y: float,
    step_width: float
) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var x := left
    var span := maxf(right - left, 0.001)
    while x < right - 0.001:
        var next_x := minf(x + step_width, right)
        var t := clampf((x - left) / span, 0.0, 1.0)
        var floor_y := snappedf(lerpf(start_y, end_y, t), 6.0)
        result.append(_segment(x, next_x, floor_y))
        x = next_x
    return result

func _build_course_collision() -> void:
    var old := get_node_or_null("FlowCourseTerrain")
    if old != null:
        old.queue_free()

    var terrain := StaticBody2D.new()
    terrain.name = "FlowCourseTerrain"
    terrain.collision_layer = 1
    terrain.collision_mask = 2

    var material := PhysicsMaterial.new()
    material.friction = 0.52
    material.bounce = 0.02
    terrain.physics_material_override = material
    add_child(terrain)

    for segment in _profile:
        var left := float(segment["left"])
        var right := float(segment["right"])
        var floor_y := float(segment["floor_y"])
        _add_static_rect(
            terrain,
            Rect2(
                left,
                floor_y,
                right - left,
                WORLD_BOTTOM - floor_y
            )
        )

func _add_static_rect(parent: StaticBody2D, rect: Rect2) -> void:
    if rect.size.x <= 0.0 or rect.size.y <= 0.0:
        return
    var shape := RectangleShape2D.new()
    shape.size = rect.size
    var collision := CollisionShape2D.new()
    collision.shape = shape
    collision.position = rect.position + rect.size * 0.5
    parent.add_child(collision)

func _build_world_labels() -> void:
    _add_label(
        "HYDRAULIC FLOW COURSE",
        Vector2(1350.0, 108.0),
        18,
        LABEL
    )
    _add_label(
        "fill source pocket  →  overflow lip  →  ramp  →  stairs  →  weir  →  uphill ramp  →  catch",
        Vector2(1350.0, 136.0),
        11,
        LABEL_DIM
    )
    _add_label("SOURCE", Vector2(1374.0, 286.0), 10, LABEL_DIM)
    _add_label("PIXEL RAMP", Vector2(1540.0, 270.0), 10, LABEL_DIM)
    _add_label("STAIRS", Vector2(1760.0, 368.0), 10, LABEL_DIM)
    _add_label("WEIR", Vector2(1998.0, 484.0), 10, LABEL_DIM)
    _add_label("UPHILL RAMP", Vector2(2108.0, 486.0), 10, LABEL_DIM)
    _add_label("CATCH", Vector2(2270.0, 510.0), 10, LABEL_DIM)

func _add_label(text: String, pos: Vector2, font_size: int, color: Color) -> void:
    var label := Label.new()
    label.text = text
    label.position = pos
    label.add_theme_font_size_override("font_size", font_size)
    label.modulate = color
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(label)

func _draw() -> void:
    draw_rect(
        Rect2(
            COURSE_WORLD_LEFT,
            -540.0,
            COURSE_WORLD_RIGHT - COURSE_WORLD_LEFT,
            1620.0
        ),
        BG
    )
    draw_rect(
        Rect2(
            COURSE_WORLD_LEFT,
            96.0,
            COURSE_WORLD_RIGHT - COURSE_WORLD_LEFT,
            144.0
        ),
        SKY
    )

    for x in range(int(COURSE_WORLD_LEFT), int(COURSE_WORLD_RIGHT) + 1, 16):
        draw_line(Vector2(x, 96.0), Vector2(x, 240.0), GRID_FAINT, 1.0)
    for y in range(96, 241, 16):
        draw_line(
            Vector2(COURSE_WORLD_LEFT, y),
            Vector2(COURSE_WORLD_RIGHT, y),
            GRID_FAINT,
            1.0
        )

    for segment in _profile:
        var left := float(segment["left"])
        var right := float(segment["right"])
        var floor_y := float(segment["floor_y"])
        var rect := Rect2(
            left,
            floor_y,
            right - left,
            WORLD_BOTTOM - floor_y
        )
        draw_rect(rect, GROUND)
        draw_rect(
            Rect2(rect.position, Vector2(rect.size.x, 4.0)),
            GROUND_TOP
        )
