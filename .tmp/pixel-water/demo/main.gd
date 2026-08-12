extends Node2D

var water: PixelWaterWorld2D
var inspector: WaterObjectInspector
var objects: Array[BuoyantPixelBody2D] = []

var _camera: Camera2D
var _camera_panning := false
var _title: Label
var _subtitle: Label
var _instructions: Label
var _reset_all_button: Button
var _reset_water_button: Button
var _spawn_select: OptionButton
var _spawn_button: Button
var _water_stats: Label

const PANEL_WIDTH := 238.0
const PANEL_HEIGHT := 382.0
const WORLD_LEFT := -160.0
const WORLD_RIGHT := 1320.0
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

const BG := Color("#10181f")
const SKY := Color("#d8e6e8")
const GROUND := Color("#30383a")
const GROUND_TOP := Color("#202729")
const GRID_FAINT := Color(0.15, 0.22, 0.25, 0.16)

func _ready() -> void:
    water = $Water as PixelWaterWorld2D
    _configure_water_world()
    _setup_camera()
    _build_terrain_collision()
    _spawn_demo_objects()
    _build_ui()
    get_viewport().size_changed.connect(_relayout_ui)
    _relayout_ui()
    set_process(true)
    queue_redraw()

func _configure_water_world() -> void:
    water.world_left = WORLD_LEFT
    water.world_right = WORLD_RIGHT
    water.default_floor_y = PLATFORM_Y
    water.fluid_depth_m = 0.12
    water.cell_size_px = 4.0
    water.linear_flow_damping = 0.36
    water.quadratic_flow_damping = 0.105
    water.momentum_neighbor_mix = 0.030

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
        }
    ]
    water.configure_world(floors, initial_water)

func _setup_camera() -> void:
    _camera = Camera2D.new()
    _camera.name = "SceneCamera"
    _camera.position = Vector2(600.0, 280.0)
    _camera.position_smoothing_enabled = false
    _camera.enabled = true
    add_child(_camera)
    _camera.make_current()

func _build_terrain_collision() -> void:
    var terrain := StaticBody2D.new()
    terrain.name = "TerrainCollision"
    terrain.collision_layer = 1
    terrain.collision_mask = 2

    var material := PhysicsMaterial.new()
    material.friction = 0.50
    material.bounce = 0.025
    terrain.physics_material_override = material
    add_child(terrain)

    # Platform pieces. The holes are actual missing collision, never visual masks.
    _add_static_rect(
        terrain,
        Rect2(
            WORLD_LEFT,
            PLATFORM_Y,
            MAIN_LEFT - WORLD_LEFT,
            WORLD_BOTTOM - PLATFORM_Y
        )
    )
    _add_static_rect(
        terrain,
        Rect2(
            MAIN_RIGHT,
            PLATFORM_Y,
            SMALL_LEFT - MAIN_RIGHT,
            WORLD_BOTTOM - PLATFORM_Y
        )
    )
    _add_static_rect(
        terrain,
        Rect2(
            SMALL_RIGHT,
            PLATFORM_Y,
            WORLD_RIGHT - SMALL_RIGHT,
            WORLD_BOTTOM - PLATFORM_Y
        )
    )

    # Physical basin floors. The vertical sides come from the adjacent platform
    # rectangles, so rigid bodies cannot overlap the grey terrain.
    _add_static_rect(
        terrain,
        Rect2(
            MAIN_LEFT,
            MAIN_BOTTOM,
            MAIN_RIGHT - MAIN_LEFT,
            WORLD_BOTTOM - MAIN_BOTTOM
        )
    )
    _add_static_rect(
        terrain,
        Rect2(
            SMALL_LEFT,
            SMALL_BOTTOM,
            SMALL_RIGHT - SMALL_LEFT,
            WORLD_BOTTOM - SMALL_BOTTOM
        )
    )

func _add_static_rect(parent: StaticBody2D, rect: Rect2) -> void:
    var shape := RectangleShape2D.new()
    shape.size = rect.size
    var collision := CollisionShape2D.new()
    collision.shape = shape
    collision.position = rect.position + rect.size * 0.5
    parent.add_child(collision)

func _spawn_demo_objects() -> void:
    _spawn_object_from_preset(0, Vector2(285, 108))
    _spawn_object_from_preset(1, Vector2(375, 108))
    _spawn_object_from_preset(2, Vector2(468, 106))
    _spawn_object_from_preset(3, Vector2(560, 108))
    _spawn_object_from_preset(4, Vector2(675, 108))
    _spawn_object_from_preset(5, Vector2(865, 112))

func _object_presets() -> Array[Dictionary]:
    return [
        {
            "name": "Cork cube",
            "type": "body",
            "kind": "box",
            "size": Vector2(36, 36),
            "material": "Cork",
            "depth": 0.12
        },
        {
            "name": "Rubber ball",
            "type": "body",
            "kind": "circle",
            "size": Vector2(34, 34),
            "material": "Rubber",
            "depth": 0.12
        },
        {
            "name": "Hollow plastic",
            "type": "body",
            "kind": "box",
            "size": Vector2(42, 46),
            "material": "Hollow plastic",
            "depth": 0.12
        },
        {
            "name": "Steel brick",
            "type": "body",
            "kind": "box",
            "size": Vector2(44, 30),
            "material": "Steel",
            "depth": 0.12
        },
        {
            "name": "Oak plank",
            "type": "body",
            "kind": "box",
            "size": Vector2(112, 18),
            "material": "Oak wood",
            "depth": 0.12
        },
        {
            "name": "Transparent bucket",
            "type": "bucket",
            "kind": "box",
            "size": Vector2(68, 56),
            "material": "Hollow plastic",
            "depth": 0.14
        }
    ]

func _spawn_object_from_preset(index: int, forced_position: Vector2 = Vector2(999999.0, 999999.0)) -> void:
    var presets := _object_presets()
    if index < 0 or index >= presets.size():
        return
    var preset: Dictionary = presets[index]
    var size: Vector2 = preset["size"]
    var pos := forced_position
    if absf(pos.x) > 900000.0 or absf(pos.y) > 900000.0:
        pos = _find_clear_spawn_position(size)

    var body: BuoyantPixelBody2D
    if String(preset["type"]) == "bucket":
        var bucket := WaterBucket2D.new()
        bucket.capacity_liters = 16.0
        bucket.object_size_px = size
        body = bucket
    else:
        body = InteractiveBuoyantPixelBody2D.new()

    body.display_name = String(preset["name"])
    body.name = "%s_%d" % [
        String(preset["name"]).replace(" ", ""),
        objects.size()
    ]
    body.shape_kind = String(preset["kind"])
    body.object_size_px = size
    body.position = pos
    body.material_name = String(preset["material"])
    body.physical_depth_m = float(preset["depth"])
    body.auto_mass_from_material = true
    body.selected.connect(_on_body_selected)
    add_child(body)
    objects.append(body)

    if inspector != null:
        inspector.inspect(body)

func _find_clear_spawn_position(size: Vector2) -> Vector2:
    var x_candidates := [
        250.0, 340.0, 430.0, 520.0, 610.0, 700.0,
        835.0, 905.0, 1015.0, 1090.0, 1180.0
    ]
    var y_candidates := [110.0, 62.0, 25.0, -25.0, -75.0]
    var radius := size.length() * 0.52 + 8.0

    for y in y_candidates:
        for x in x_candidates:
            var candidate := Vector2(x, y)
            var clear := true
            for existing in objects:
                if existing == null or not is_instance_valid(existing):
                    continue
                var existing_radius := existing.object_size_px.length() * 0.52 + 8.0
                if candidate.distance_to(existing.global_position) < radius + existing_radius:
                    clear = false
                    break
            if clear:
                return candidate

    return Vector2(850.0 + objects.size() * 12.0, -110.0 - objects.size() * 4.0)

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    canvas.layer = 10
    add_child(canvas)

    inspector = WaterObjectInspector.new()
    canvas.add_child(inspector)

    _title = Label.new()
    _title.text = "PIXEL WATER SIMULATOR"
    _title.add_theme_font_size_override("font_size", 22)
    _title.modulate = Color("#e8fbff")
    canvas.add_child(_title)

    _subtitle = Label.new()
    _subtitle.text = (
        "ONE WATER WORLD • conservative shallow-water flow • physical displacement • "
        + "scoop + pour between basins"
    )
    _subtitle.modulate = Color(0.72, 0.86, 0.89)
    _subtitle.add_theme_font_size_override("font_size", 11)
    _subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    canvas.add_child(_subtitle)

    _instructions = Label.new()
    _instructions.text = (
        "LMB + DRAG: physically grab / throw   •   RMB + DRAG: navigate   •   "
        + "dip the transparent bucket, lift it, tilt to pour into the small basin"
    )
    _instructions.modulate = Color(0.70, 0.78, 0.80)
    _instructions.add_theme_font_size_override("font_size", 11)
    _instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    canvas.add_child(_instructions)

    _reset_all_button = Button.new()
    _reset_all_button.text = "Reset objects"
    _reset_all_button.custom_minimum_size = Vector2(108.0, 28.0)
    _reset_all_button.pressed.connect(_reset_all)
    canvas.add_child(_reset_all_button)

    _reset_water_button = Button.new()
    _reset_water_button.text = "Reset water"
    _reset_water_button.custom_minimum_size = Vector2(98.0, 28.0)
    _reset_water_button.pressed.connect(_reset_water)
    canvas.add_child(_reset_water_button)

    _spawn_select = OptionButton.new()
    _spawn_select.custom_minimum_size = Vector2(142.0, 28.0)
    for preset in _object_presets():
        _spawn_select.add_item(String(preset["name"]))
    canvas.add_child(_spawn_select)

    _spawn_button = Button.new()
    _spawn_button.text = "Spawn"
    _spawn_button.custom_minimum_size = Vector2(70.0, 28.0)
    _spawn_button.pressed.connect(_spawn_selected)
    canvas.add_child(_spawn_button)

    _water_stats = Label.new()
    _water_stats.add_theme_font_size_override("font_size", 11)
    _water_stats.modulate = Color(0.62, 0.90, 0.96)
    _water_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    canvas.add_child(_water_stats)

    if not objects.is_empty():
        inspector.inspect(objects[0])

func _relayout_ui() -> void:
    if inspector == null:
        return

    var viewport_size := get_viewport().get_visible_rect().size
    var margin := 12.0
    var panel_height := minf(PANEL_HEIGHT, maxf(250.0, viewport_size.y - margin * 2.0))

    inspector.position = Vector2(maxf(margin, viewport_size.x - PANEL_WIDTH - margin), margin)
    inspector.size = Vector2(PANEL_WIDTH, panel_height)

    _title.position = Vector2(18.0, 14.0)
    _title.size = Vector2(maxf(220.0, viewport_size.x - PANEL_WIDTH - 54.0), 30.0)

    var left_area_width := maxf(300.0, viewport_size.x - PANEL_WIDTH - 52.0)
    _subtitle.position = Vector2(20.0, 44.0)
    _subtitle.size = Vector2(left_area_width, 34.0)

    _reset_all_button.position = Vector2(20.0, 79.0)
    _reset_all_button.size = Vector2(108.0, 28.0)
    _reset_water_button.position = Vector2(134.0, 79.0)
    _reset_water_button.size = Vector2(98.0, 28.0)

    _spawn_select.position = Vector2(240.0, 79.0)
    _spawn_select.size = Vector2(142.0, 28.0)
    _spawn_button.position = Vector2(388.0, 79.0)
    _spawn_button.size = Vector2(70.0, 28.0)

    _water_stats.position = Vector2(20.0, 111.0)
    _water_stats.size = Vector2(left_area_width, 38.0)

    _instructions.position = Vector2(18.0, maxf(154.0, viewport_size.y - 44.0))
    _instructions.size = Vector2(maxf(300.0, viewport_size.x - 36.0), 36.0)

func _process(_delta: float) -> void:
    if _water_stats == null or water == null:
        return

    var main_l: float = water.volume_liters_in_range(MAIN_LEFT, MAIN_RIGHT)
    var small_l: float = water.volume_liters_in_range(SMALL_LEFT, SMALL_RIGHT)
    var mobile_l := 0.0
    for body in objects:
        if body != null and is_instance_valid(body) and body.has_method("contained_water_liters"):
            mobile_l += float(body.call("contained_water_liters"))

    _water_stats.text = (
        "Main basin: %.1f L   •   Small basin: %.1f L   •   In buckets: %.1f L   •   "
        + "world + spray: %.1f L"
    ) % [
        main_l,
        small_l,
        mobile_l,
        water.water_volume_liters()
    ]

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        _camera_panning = event.pressed
        get_viewport().set_input_as_handled()
        return

    if event is InputEventMouseMotion and _camera_panning and _camera != null:
        var zoom_x := maxf(_camera.zoom.x, 0.001)
        var zoom_y := maxf(_camera.zoom.y, 0.001)
        _camera.position -= Vector2(event.relative.x / zoom_x, event.relative.y / zoom_y)
        get_viewport().set_input_as_handled()

func _spawn_selected() -> void:
    if _spawn_select == null:
        return
    _spawn_object_from_preset(_spawn_select.selected)

func _on_body_selected(body: BuoyantPixelBody2D) -> void:
    if inspector != null:
        inspector.inspect(body)

func _reset_all() -> void:
    for body in objects:
        if body != null and is_instance_valid(body):
            body.reset_to_spawn()

func _reset_water() -> void:
    for body in objects:
        if body != null and is_instance_valid(body) and body.has_method("clear_contained_water_without_return"):
            body.call("clear_contained_water_without_return")
    water.reset_water()

func _draw() -> void:
    draw_rect(Rect2(WORLD_LEFT, -540, WORLD_RIGHT - WORLD_LEFT, 1620), BG)
    draw_rect(Rect2(WORLD_LEFT, 96, WORLD_RIGHT - WORLD_LEFT, 144), SKY)

    for x in range(int(WORLD_LEFT), int(WORLD_RIGHT) + 1, 16):
        draw_line(Vector2(x, 96), Vector2(x, 240), GRID_FAINT, 1.0)
    for y in range(96, 241, 16):
        draw_line(Vector2(WORLD_LEFT, y), Vector2(WORLD_RIGHT, y), GRID_FAINT, 1.0)

    # Three platform solids create two physical holes.
    _draw_ground_rect(Rect2(WORLD_LEFT, PLATFORM_Y, MAIN_LEFT - WORLD_LEFT, WORLD_BOTTOM - PLATFORM_Y))
    _draw_ground_rect(Rect2(MAIN_RIGHT, PLATFORM_Y, SMALL_LEFT - MAIN_RIGHT, WORLD_BOTTOM - PLATFORM_Y))
    _draw_ground_rect(Rect2(SMALL_RIGHT, PLATFORM_Y, WORLD_RIGHT - SMALL_RIGHT, WORLD_BOTTOM - PLATFORM_Y))
    _draw_ground_rect(Rect2(MAIN_LEFT, MAIN_BOTTOM, MAIN_RIGHT - MAIN_LEFT, WORLD_BOTTOM - MAIN_BOTTOM))
    _draw_ground_rect(Rect2(SMALL_LEFT, SMALL_BOTTOM, SMALL_RIGHT - SMALL_LEFT, WORLD_BOTTOM - SMALL_BOTTOM))

    _draw_basin_edges(MAIN_LEFT, MAIN_RIGHT, PLATFORM_Y, MAIN_BOTTOM)
    _draw_basin_edges(SMALL_LEFT, SMALL_RIGHT, PLATFORM_Y, SMALL_BOTTOM)

func _draw_ground_rect(rect: Rect2) -> void:
    draw_rect(rect, GROUND)
    draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), GROUND_TOP)

func _draw_basin_edges(left: float, right: float, top: float, bottom: float) -> void:
    draw_rect(Rect2(left, bottom, right - left, 4.0), GROUND_TOP)
    draw_rect(Rect2(left, top, 4.0, bottom - top), GROUND_TOP)
    draw_rect(Rect2(right - 4.0, top, 4.0, bottom - top), GROUND_TOP)
