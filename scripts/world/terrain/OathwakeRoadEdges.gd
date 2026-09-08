extends RefCounted
## Atlas contains all eight-neighbour masks, with bit 256 for the center cell,
## repeated in four color variants with identical alpha for seamless joins.
## Empty-center cells supply concave corner fringes; they are visual only.

const OFFSETS := [
	Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i.ZERO,
]

static func atlas_coord(cells: Dictionary, cell: Vector2i) -> Vector2i:
	var mask := 0
	for bit in range(OFFSETS.size()):
		if cells.has(cell + OFFSETS[bit]):
			mask |= 1 << bit
	var frame := mask + posmod(hash(cell), 4) * 512
	return Vector2i(frame % 16, frame / 16)

static func paint(layer: TileMapLayer, cells: Dictionary, water: Dictionary, terrain_types: Dictionary = {}) -> void:
	var visible_cells: Dictionary = {}
	for cell_value in cells:
		var cell := Vector2i(cell_value)
		for offset in OFFSETS:
			if not water.has(cell + offset):
				visible_cells[cell + offset] = true
	# Soil patches and the road share a material. Include nearby soil in the
	# visual mask so a path merges into it instead of ending as an outlined slab.
	var connected_soil := cells.duplicate()
	for cell_value in visible_cells:
		var cell := Vector2i(cell_value)
		for offset in OFFSETS:
			if int(terrain_types.get(cell + offset, -1)) == 1:
				connected_soil[cell + offset] = true
	for cell_value in visible_cells:
		var cell := Vector2i(cell_value)
		layer.set_cell(cell, 0, atlas_coord(connected_soil, cell))
