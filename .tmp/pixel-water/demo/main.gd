extends Node2D

var water: PixelWaterSimulator2D
var inspector: WaterObjectInspector
var objects: Array[BuoyantPixelBody2D] = []

const BG := Color("#10181f")
const SKY := Color("#d8e6e8")
const GROUND := Color("#30383a")
const GROUND_TOP := Color("#202729")
const GRID_FAINT := Color(0.15, 0.22, 0.25, 0.16)

func _ready() -> void:
    water = $Water as PixelWaterSimulator2D
    _build_terrain_collision()
    _spawn_demo_objects()
    _build_ui()
    queue_redraw()

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
    var body := BuoyantPixelBody2D.new()
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
    inspector.position = Vector2(650, 18)
    inspector.size = Vector2(292, 440)
    canvas.add_child(inspector)

    var title := Label.new()
    title.position = Vector2(20, 16)
    title.text = "PIXEL WATER SIMULATOR"
    title.add_theme_font_size_override("font_size", 24)
    title.modulate = Color("#e8fbff")
    canvas.add_child(title)

    var subtitle := Label.new()
    subtitle.position = Vector2(22, 48)
    subtitle.text = "Archimedes buoyancy • quadratic drag • waves • splashes • foam • bubbles • wetness"
    subtitle.modulate = Color(0.72, 0.86, 0.89)
    canvas.add_child(subtitle)

    var instructions := Label.new()
    instructions.position = Vector2(20, 506)
    instructions.text = "LEFT CLICK + DRAG → pick up   •   RELEASE → throw   •   click an object → tune mass/material/buoyancy"
    instructions.modulate = Color(0.70, 0.78, 0.80)
    canvas.add_child(instructions)

    var reset_all := Button.new()
    reset_all.position = Vector2(20, 78)
    reset_all.text = "Reset all objects"
    reset_all.pressed.connect(_reset_all)
    canvas.add_child(reset_all)

    if not objects.is_empty():
        inspector.inspect(objects[0])

func _on_body_selected(body: BuoyantPixelBody2D) -> void:
    if inspector != null:
        inspector.inspect(body)

func _reset_all() -> void:
    for body in objects:
        body.reset_to_spawn()

func _draw() -> void:
    draw_rect(Rect2(0, 0, 960, 540), BG)
    draw_rect(Rect2(0, 96, 960, 144), SKY)

    for x in range(0, 961, 16):
        draw_line(Vector2(x, 96), Vector2(x, 240), GRID_FAINT, 1.0)
    for y in range(96, 241, 16):
        draw_line(Vector2(0, y), Vector2(960, y), GRID_FAINT, 1.0)

    draw_rect(Rect2(0, water.platform_y, water.basin_left, 300), GROUND)
    draw_rect(Rect2(water.basin_right, water.platform_y, 960 - water.basin_right, 300), GROUND)
    draw_rect(Rect2(water.basin_left, water.bottom_y, water.basin_right - water.basin_left, 40), GROUND)

    draw_rect(Rect2(0, water.platform_y, water.basin_left, 4), GROUND_TOP)
    draw_rect(Rect2(water.basin_right, water.platform_y, 960 - water.basin_right, 4), GROUND_TOP)
    draw_rect(Rect2(water.basin_left, water.bottom_y, water.basin_right - water.basin_left, 4), GROUND_TOP)
    draw_rect(Rect2(water.basin_left, water.platform_y, 4, water.bottom_y - water.platform_y), GROUND_TOP)
    draw_rect(Rect2(water.basin_right - 4, water.platform_y, 4, water.bottom_y - water.platform_y), GROUND_TOP)
