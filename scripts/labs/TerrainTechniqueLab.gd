extends Node2D

const SOURCE_ID := 0
const MASK_TO_ATLAS := {
    0: Vector2i(0, 3), 1: Vector2i(3, 3), 2: Vector2i(0, 2), 3: Vector2i(1, 2),
    4: Vector2i(0, 0), 5: Vector2i(3, 2), 6: Vector2i(2, 3), 7: Vector2i(3, 1),
    8: Vector2i(1, 3), 9: Vector2i(0, 1), 10: Vector2i(1, 0), 11: Vector2i(2, 2),
    12: Vector2i(3, 0), 13: Vector2i(2, 0), 14: Vector2i(1, 1), 15: Vector2i(2, 1),
}

@onready var terrain: TileMapLayer = $DualGridPreview
var logical_cells: Dictionary = {}

func _ready() -> void:
    for y in range(9):
        for x in range(15):
            var dx := (float(x) - 7.0) / 6.0
            var dy := (float(y) - 4.0) / 3.4
            logical_cells[Vector2i(x, y)] = dx * dx + dy * dy < 1.0
    for y in range(3, 6):
        for x in range(6, 9):
            logical_cells[Vector2i(x, y)] = false
    _rebuild()

func _rebuild() -> void:
    terrain.clear()
    for y in range(10):
        for x in range(16):
            var cell := Vector2i(x, y)
            terrain.set_cell(cell, SOURCE_ID, MASK_TO_ATLAS[_mask_for(cell)])

func _mask_for(cell: Vector2i) -> int:
    return (
        (1 if _filled(cell + Vector2i(-1, -1)) else 0)
        | (2 if _filled(cell + Vector2i(0, -1)) else 0)
        | (4 if _filled(cell + Vector2i(-1, 0)) else 0)
        | (8 if _filled(cell) else 0)
    )

func _filled(cell: Vector2i) -> bool:
    return bool(logical_cells.get(cell, false))
