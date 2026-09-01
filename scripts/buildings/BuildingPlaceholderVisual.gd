extends Node2D

## Small procedural pixel-art stand-ins for construction pieces that do not have
## final sprites yet. The shapes deliberately use integer-aligned filled rects so
## they read like old-school RPG tiles without introducing texture dependencies.

@export var building_id: String = "wall"

var building_data: Dictionary = {}
var door_open := false

const OUTLINE := Color("2a1c18")
const SHADOW := Color("3b2821")
const WOOD_DARK := Color("533626")
const WOOD := Color("765039")
const WOOD_LIGHT := Color("a37650")
const WOOD_HIGHLIGHT := Color("c69a6a")
const PLASTER_DARK := Color("8d765a")
const PLASTER := Color("b6a07b")
const PLASTER_LIGHT := Color("d1bf96")
const STONE_DARK := Color("4b4b46")
const STONE := Color("74736b")
const STONE_LIGHT := Color("99978b")
const METAL_DARK := Color("383c3f")
const METAL := Color("62686b")
const METAL_LIGHT := Color("9a9d96")
const GLASS_DARK := Color("31545c")
const GLASS := Color("4d7c83")
const GLASS_LIGHT := Color("7fa5a5")
const CLOTH_DARK := Color("5c485f")
const CLOTH := Color("806783")
const CLOTH_LIGHT := Color("aa8da8")
const FIRE_DARK := Color("9a3b20")
const FIRE := Color("e26b2d")
const FIRE_LIGHT := Color("f3bb4c")
const GREEN_DARK := Color("405441")
const GREEN := Color("60745a")
const GOLD := Color("d3a746")


func _ready() -> void:
	queue_redraw()


func configure(new_building_id: String, new_data: Dictionary = {}) -> void:
	building_id = new_building_id
	building_data = new_data.duplicate(true)
	queue_redraw()


func set_door_open(open_state: bool) -> void:
	door_open = open_state
	queue_redraw()


func _draw() -> void:
	match building_id:
		"wall":
			_draw_wall()
		"floor":
			_draw_floor()
		"stairs_up":
			_draw_stairs(true)
		"stairs_down":
			_draw_stairs(false)
		"door":
			_draw_door()
		"window", "window_wall":
			_draw_window()
		"bed":
			_draw_bed()
		"workbench", "iron_workbench", "steel_workbench":
			_draw_workbench()
		"anvil":
			_draw_anvil()
		"laboratory":
			_draw_laboratory()
		"chest":
			_draw_chest()
		"campfire":
			_draw_campfire()
		_:
			_draw_from_type()


func _draw_from_type() -> void:
	match str(building_data.get("building_type", "")):
		"wall":
			_draw_wall()
		"floor":
			_draw_floor()
		"stairs":
			_draw_stairs(true)
		"door":
			_draw_door()
		"bed":
			_draw_bed()
		"workstation":
			_draw_workbench()
		"storage":
			_draw_chest()
		"light":
			_draw_campfire()
		_:
			_draw_crate()


func _rect(x: float, y: float, width: float, height: float, color: Color) -> void:
	draw_rect(Rect2(x, y, width, height), color, true)


func _draw_floor() -> void:
	# Horizontal planks, alternating seams, and a dark perimeter make this read as
	# flooring rather than a generic brown square even when several tiles repeat.
	_rect(-16, -16, 32, 32, OUTLINE)
	_rect(-15, -15, 30, 30, WOOD)
	for y in [-10, -4, 2, 8]:
		_rect(-15, y, 30, 1, WOOD_DARK)
	_rect(-2, -15, 1, 5, WOOD_DARK)
	_rect(7, -9, 1, 5, WOOD_DARK)
	_rect(-8, -3, 1, 5, WOOD_DARK)
	_rect(3, 3, 1, 5, WOOD_DARK)
	_rect(-4, 9, 1, 6, WOOD_DARK)
	_rect(-14, -14, 28, 1, WOOD_LIGHT)
	_rect(-13, -8, 8, 1, WOOD_LIGHT)
	_rect(2, 4, 9, 1, WOOD_LIGHT)


func _draw_wall() -> void:
	# Timber frame + plaster infill. Strong vertical posts distinguish it from the
	# floor tile and give contiguous wall runs an obvious architectural rhythm.
	_rect(-16, -30, 32, 32, OUTLINE)
	_rect(-14, -27, 28, 26, PLASTER_DARK)
	_rect(-12, -25, 24, 22, PLASTER)
	_rect(-12, -24, 24, 3, PLASTER_LIGHT)
	_rect(-16, -30, 32, 6, WOOD_DARK)
	_rect(-14, -28, 28, 2, WOOD_LIGHT)
	_rect(-15, -24, 5, 24, WOOD_DARK)
	_rect(10, -24, 5, 24, WOOD_DARK)
	_rect(-11, -14, 22, 4, WOOD)
	_rect(-10, -13, 20, 1, WOOD_LIGHT)
	_rect(-16, -2, 32, 4, SHADOW)


func _draw_window() -> void:
	_draw_wall()
	_rect(-10, -22, 20, 16, OUTLINE)
	_rect(-8, -20, 16, 12, GLASS_DARK)
	_rect(-7, -19, 14, 10, GLASS)
	_rect(-6, -18, 5, 3, GLASS_LIGHT)
	_rect(-1, -20, 3, 12, WOOD_DARK)
	_rect(-8, -15, 16, 3, WOOD_DARK)
	_rect(-10, -7, 20, 3, WOOD_LIGHT)


func _draw_stairs(goes_up: bool) -> void:
	_rect(-16, -16, 32, 32, OUTLINE)
	_rect(-13, -14, 26, 28, WOOD_DARK)
	_rect(-10, -13, 20, 26, SHADOW)
	var tread_y := -12
	for index in range(6):
		var t := index if goes_up else 5 - index
		var tread_color := WOOD_LIGHT if t < 2 else WOOD
		_rect(-9, tread_y, 18, 3, tread_color)
		_rect(-9, tread_y + 3, 18, 1, WOOD_DARK)
		tread_y += 4
	_rect(-14, -13, 3, 26, WOOD)
	_rect(11, -13, 3, 26, WOOD)
	_rect(-13, -12, 1, 24, WOOD_HIGHLIGHT)
	if goes_up:
		_rect(-7, -14, 14, 2, WOOD_HIGHLIGHT)
	else:
		_rect(-7, 11, 14, 2, WOOD_HIGHLIGHT)


func _draw_door() -> void:
	if door_open:
		# Frame remains vertical while the leaf swings to the right, making the state
		# change readable without relying on a color swap.
		_rect(-13, -30, 26, 4, OUTLINE)
		_rect(-13, -27, 4, 29, OUTLINE)
		_rect(9, -27, 4, 29, OUTLINE)
		_rect(-11, -27, 2, 27, WOOD_LIGHT)
		_rect(9, -27, 2, 27, WOOD_DARK)
		_rect(10, -3, 22, 10, OUTLINE)
		_rect(12, -1, 18, 6, WOOD)
		_rect(14, 0, 14, 1, WOOD_LIGHT)
		_rect(25, 1, 2, 2, GOLD)
		return

	_rect(-13, -30, 26, 32, OUTLINE)
	_rect(-10, -27, 20, 27, WOOD_DARK)
	_rect(-8, -25, 16, 23, WOOD)
	_rect(-7, -24, 14, 3, WOOD_LIGHT)
	_rect(-7, -17, 14, 2, WOOD_DARK)
	_rect(-7, -9, 14, 2, WOOD_DARK)
	_rect(-2, -24, 2, 22, WOOD_DARK)
	_rect(4, -13, 3, 3, GOLD)
	_rect(-13, -30, 26, 4, WOOD_DARK)
	_rect(-11, -28, 22, 2, WOOD_HIGHLIGHT)


func _draw_bed() -> void:
	_rect(-14, -27, 28, 29, OUTLINE)
	_rect(-12, -25, 24, 25, WOOD_DARK)
	_rect(-10, -23, 20, 21, CLOTH)
	_rect(-9, -22, 18, 6, PLASTER_LIGHT)
	_rect(-7, -21, 14, 2, Color("e2d4ae"))
	_rect(-9, -14, 18, 12, CLOTH_LIGHT)
	_rect(-9, -5, 18, 3, CLOTH_DARK)
	_rect(-14, -28, 4, 30, WOOD)
	_rect(10, -28, 4, 30, WOOD)


func _draw_workbench() -> void:
	_rect(-16, -21, 32, 9, OUTLINE)
	_rect(-14, -19, 28, 5, WOOD)
	_rect(-13, -18, 26, 2, WOOD_LIGHT)
	_rect(-12, -12, 5, 14, OUTLINE)
	_rect(7, -12, 5, 14, OUTLINE)
	_rect(-10, -12, 2, 12, WOOD_DARK)
	_rect(8, -12, 2, 12, WOOD_DARK)
	_rect(-8, -25, 3, 8, METAL_DARK)
	_rect(-7, -27, 7, 3, METAL)
	_rect(3, -25, 8, 3, METAL_LIGHT)
	_rect(8, -27, 3, 7, METAL_DARK)


func _draw_anvil() -> void:
	_rect(-11, -21, 22, 7, OUTLINE)
	_rect(-8, -19, 16, 4, METAL)
	_rect(-14, -21, 8, 4, OUTLINE)
	_rect(-12, -20, 6, 2, METAL_LIGHT)
	_rect(6, -20, 8, 3, OUTLINE)
	_rect(-6, -14, 12, 8, METAL_DARK)
	_rect(-3, -6, 6, 8, OUTLINE)
	_rect(-10, 0, 20, 3, OUTLINE)


func _draw_laboratory() -> void:
	_draw_workbench()
	_rect(-10, -30, 6, 10, OUTLINE)
	_rect(-8, -28, 2, 6, GLASS_LIGHT)
	_rect(-7, -22, 4, 3, GLASS)
	_rect(0, -27, 7, 8, OUTLINE)
	_rect(2, -25, 3, 4, Color("8d6fa0"))
	_rect(7, -24, 5, 5, OUTLINE)
	_rect(8, -23, 3, 3, GREEN)


func _draw_chest() -> void:
	_rect(-15, -20, 30, 22, OUTLINE)
	_rect(-13, -17, 26, 17, WOOD_DARK)
	_rect(-11, -15, 22, 13, WOOD)
	_rect(-15, -22, 30, 9, OUTLINE)
	_rect(-13, -20, 26, 5, WOOD_LIGHT)
	_rect(-11, -19, 22, 2, WOOD_HIGHLIGHT)
	_rect(-3, -14, 6, 9, METAL_DARK)
	_rect(-2, -12, 4, 5, GOLD)
	_rect(-13, -4, 26, 2, WOOD_DARK)


func _draw_campfire() -> void:
	_rect(-13, -8, 7, 6, STONE_DARK)
	_rect(6, -8, 7, 6, STONE_DARK)
	_rect(-6, -11, 6, 7, STONE)
	_rect(1, -11, 6, 7, STONE_LIGHT)
	_rect(-8, -4, 16, 4, WOOD_DARK)
	_rect(-6, -5, 12, 2, WOOD_LIGHT)
	_rect(-5, -18, 10, 15, FIRE_DARK)
	_rect(-3, -22, 6, 17, FIRE)
	_rect(-1, -17, 3, 10, FIRE_LIGHT)


func _draw_crate() -> void:
	_rect(-14, -22, 28, 24, OUTLINE)
	_rect(-12, -20, 24, 20, WOOD)
	_rect(-10, -18, 20, 3, WOOD_LIGHT)
	_rect(-10, -4, 20, 3, WOOD_DARK)
	_rect(-3, -18, 6, 17, WOOD_DARK)
