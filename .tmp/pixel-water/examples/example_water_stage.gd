extends Node2D

## Self-contained water stage used only by the integration examples.
## It does not change the reusable solver. It simply gives F6 examples a real
## tank, initial water and matching collision geometry to interact with.

const TANK_LEFT := 80.0
const TANK_RIGHT := 720.0
const FLOOR_Y := 520.0
const SURFACE_Y := 300.0

@onready var water: PixelWaterWorld2D = $Water

func _ready() -> void:
    water.world_left = TANK_LEFT
    water.world_right = TANK_RIGHT
    water.default_floor_y = FLOOR_Y
    water.configure_world(
        [
            {
                "left": TANK_LEFT,
                "right": TANK_RIGHT,
                "floor_y": FLOOR_Y
            }
        ],
        [
            {
                "left": TANK_LEFT,
                "right": TANK_RIGHT,
                "surface_y": SURFACE_Y
            }
        ]
    )
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(0.0, 0.0, 800.0, 600.0), Color("#111a20"))
    draw_rect(Rect2(0.0, 84.0, 800.0, FLOOR_Y - 84.0), Color("#d9e7e9"))
    draw_line(
        Vector2(TANK_LEFT, SURFACE_Y),
        Vector2(TANK_RIGHT, SURFACE_Y),
        Color(0.20, 0.70, 0.85, 0.22),
        1.0
    )
