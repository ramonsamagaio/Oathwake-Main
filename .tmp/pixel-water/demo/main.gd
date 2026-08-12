extends Node2D

var water: PixelWaterSimulator2D
var inspector: WaterObjectInspector
var objects: Array[BuoyantPixelBody2D] = []

var _camera: Camera2D
var _camera_panning := false
var _title: Label
var _subtitle: Label
var _instructions: Label
var _reset_all_button: Button

const PANEL_WIDTH := 238.0
const PANEL_HEIGHT := 382.0
const BG := Color("#10181f")
const SKY := Color("#d8e6e8")
const GROUND := Color("#30383a")
const GROUND_TOP := Color("#202729")
const GRID_FAINT := Color(0.15, 0.22, 0.25, 0.16)

func _ready() -> void:
    water = $Water as PixelWaterSimulator2D
    _setup_camera()
    _build_terrain_collision()
    _spawn_demo_objects()
    _build_ui()
    get_viewport().size_changed.connect(_relayout_ui)
    _relayout_ui()
    queue_redraw()

func _setup_camera() -> void:
    _camera = Camera2D.new()
    _camera.name = "SceneCamera"
    _camera.position = Vector2(water.world_width * 0.5, 270.0)
    _camera.position_smoothing_enabled = false
    _camera.enabled = true
    add_child(_camera)
    _camera.make_current()

func _build_terrain_collision() -> void:
    var terrain := StaticBody2D.new()
    terrain.name = "TerrainCollision"
    terrain.collision_layer = 1
    terrain.collision_mask = 2
    add_child(terrain)

    _add_static_rect(terrain, Rect2(-30.0, water.platform_y, water.basin_left + 30.0, 360.0))
    _add_static_rect(terrain, Rect2(water.basin_right, water.platform_y, water.world_width - water.basin_right + 30.0, 360.0))
    _add_static_rect(terrain, Rect2(water.basin_left, water.bottom_y, water.basin_right - water.basin_left, 70.0))

func _add_static_rect(parent: StaticBody2D, rect: Rect2) -> void:
    var shape := RectangleShape2D.new()
    shape.size = rect.size
    var collision := CollisionShape2D.new()
    collision.shape = shape
    collision.position = rect.position + rect.size * 0.5
    parent.add_child(collision)

func _spawn_demo_objects() -> void:
    _spawn_object("Cork cube", "box", Vector2(36, 36), Vector2(295, 105), "Cork", 0.28)
    _spawn_object("Rubber ball", "circle", Vector2(34, 34), Vector2(385, 105), "Rubber", 0.24)
    _spawn_object("Hollow plastic", "box", Vector2(42, 46), Vector2(480, 104), "Hollow plastic", 0.20)
    _spawn_object("Steel brick", "box", Vector2(44, 30), Vector2(575, 106), "Steel", 0.20)
    _spawn_object("Oak plank", "box", Vector2(112, 18), Vector2(690, 108), "Oak wood", 0.18)

func _spawn_object(name_text: String, kind: String, size: Vector2, pos: Vector2, material: String, depth_m: float) -> void:
    var body := InteractiveBuoyantPixelBody2D.new()
    body.display_name = name_text
    body.name = name_text.replace(" ", "")
    body.shape_kind = kind
    body.object_size_px = size
    body.position = pos
    body.material_name = material
    body.physical_depth_m = depth_m
    body.auto_mass_from_material = true
    body.selected.connect(_on_body_selected)
    add_child(body)
    objects.append(body)

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
    _subtitle.text = "Live drag collisions • real-time displacement • stronger wakes • volume-scaled splashes"
    _subtitle.modulate = Color(0.72, 0.86, 0.89)
    _subtitle.add_theme_font_size_override("font_size", 11)
    _subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    canvas.add_child(_subtitle)

    _instructions = Label.new()
    _instructions.text = "LMB + DRAG: move / throw objects   •   RMB + DRAG: navigate scene   •   maximize the window freely"
    _instructions.modulate = Color(0.70, 0.78, 0.80)
    _instructions.add_theme_font_size_override("font_size", 11)
    _instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    canvas.add_child(_instructions)

    _reset_all_button = Button.new()
    _reset_all_button.text = "Reset objects"
    _reset_all_button.custom_minimum_size = Vector2(112.0, 28.0)
    _reset_all_button.pressed.connect(_reset_all)
    canvas.add_child(_reset_all_button)

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
    _reset_all_button.size = Vector2(112.0, 28.0)

    _instructions.position = Vector2(18.0, maxf(112.0, viewport_size.y - 44.0))
    _instructions.size = Vector2(maxf(300.0, viewport_size.x - 36.0), 36.0)

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

func _on_body_selected(body: BuoyantPixelBody2D) -> void:
    if inspector != null:
        inspector.inspect(body)

func _reset_all() -> void:
    for body in objects:
        body.reset_to_spawn()

func _draw() -> void:
    draw_rect(Rect2(-960, -540, 2880, 1620), BG)
    draw_rect(Rect2(-960, 96, 2880, 144), SKY)

    for x in range(-960, 1921, 16):
        draw_line(Vector2(x, 96), Vector2(x, 240), GRID_FAINT, 1.0)
    for y in range(96, 241, 16):
        draw_line(Vector2(-960, y), Vector2(1920, y), GRID_FAINT, 1.0)

    draw_rect(Rect2(-960, water.platform_y, water.basin_left + 960, 300), GROUND)
    draw_rect(Rect2(water.basin_right, water.platform_y, 1920 - water.basin_right, 300), GROUND)
    draw_rect(Rect2(water.basin_left, water.bottom_y, water.basin_right - water.basin_left, 40), GROUND)

    draw_rect(Rect2(-960, water.platform_y, water.basin_left + 960, 4), GROUND_TOP)
    draw_rect(Rect2(water.basin_right, water.platform_y, 1920 - water.basin_right, 4), GROUND_TOP)
    draw_rect(Rect2(water.basin_left, water.bottom_y, water.basin_right - water.basin_left, 4), GROUND_TOP)
    draw_rect(Rect2(water.basin_left, water.platform_y, 4, water.bottom_y - water.platform_y), GROUND_TOP)
    draw_rect(Rect2(water.basin_right - 4, water.platform_y, 4, water.bottom_y - water.platform_y), GROUND_TOP)
