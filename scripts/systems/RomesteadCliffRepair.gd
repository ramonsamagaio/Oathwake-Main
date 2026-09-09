extends Node
## Re-renders PlainsCliff using the native Romestead atlas contract.
##
## The imported world already owns the deterministic cliff topology. This pass
## only corrects the visual stack: cap two native tiles above the logical cell,
## two face rows down to the logical cell, and faces only on a true southern
## boundary. It also restores Romestead's InOrderXy authored variant selection.

const ATLAS_COLUMNS := 8
const FACE_HEIGHT := 2
const FACE_MASK := 0x3F3E
const BASE_FRAMES := [
	[], [32, 36], [34, 38], [99, 103], [35, 39], [0, 2], [98, 102], [67, 71],
	[33, 37], [96, 100], [1, 3], [64, 68], [97, 101], [65, 69], [66, 70], [4, 5],
]

var _attached_world: Node
var _rebuild_serial := 0


func _ready() -> void:
	process_priority = 940
	call_deferred("_try_attach")


func _process(_delta: float) -> void:
	if _attached_world == null or not is_instance_valid(_attached_world):
		_try_attach()


func _try_attach() -> void:
	var world := get_tree().get_first_node_in_group("procedural_resource_world")
	if world == null or world == _attached_world:
		return
	_attached_world = world
	if world.has_signal("world_generated"):
		var callback := Callable(self, "_on_world_generated")
		if not world.is_connected("world_generated", callback):
			world.connect("world_generated", callback)
	_schedule_repair()


func _on_world_generated(_seed: int, _counts: Dictionary) -> void:
	_schedule_repair()


func _schedule_repair() -> void:
	_rebuild_serial += 1
	_repair_after_generation(_rebuild_serial)


func _repair_after_generation(serial: int) -> void:
	# Let the world and streaming/bootstrap passes finish touching the same layers.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if serial != _rebuild_serial:
		return
	_repair_cliff_layers()


func _repair_cliff_layers() -> void:
	if _attached_world == null or not is_instance_valid(_attached_world):
		return
	var cliffs_value: Variant = _attached_world.get("_plains_cliffs")
	var layers_value: Variant = _attached_world.get("_plains_cliff_layers")
	var collision_value: Variant = _attached_world.get("_plains_cliff_collision")
	if not (cliffs_value is Dictionary) or not (layers_value is Array):
		return
	var cliffs := cliffs_value as Dictionary
	var layers := layers_value as Array
	if layers.size() < 3:
		return
	var top := layers[0] as TileMapLayer
	var face_1 := layers[1] as TileMapLayer
	var face_2 := layers[2] as TileMapLayer
	var collision := collision_value as TileMapLayer
	if top == null or face_1 == null or face_2 == null:
		return

	top.clear()
	face_1.clear()
	face_2.clear()
	if collision != null:
		collision.clear()

	for cliff_value in cliffs.keys():
		if not (cliff_value is Vector2i):
			continue
		var cell := cliff_value as Vector2i
		var mask := int(_attached_world.call("_plains_cliff_mask", cell))
		if mask <= 0 or mask >= BASE_FRAMES.size():
			continue
		var options := BASE_FRAMES[mask] as Array
		if options.is_empty():
			continue
		# Native MultiTilePattern.Mode.InOrderXy.
		var frame := int(options[posmod(cell.x + cell.y, options.size())])
		var cap_coord := Vector2i(frame % ATLAS_COLUMNS, frame / ATLAS_COLUMNS)
		top.set_cell(cell + Vector2i.UP * FACE_HEIGHT, 0, cap_coord, 0)

		var exposes_face := ((1 << mask) & FACE_MASK) != 0
		var southern_boundary := not cliffs.has(cell + Vector2i.DOWN)
		if exposes_face and southern_boundary:
			var middle_frame := frame + ATLAS_COLUMNS
			var bottom_frame := frame + ATLAS_COLUMNS * 2
			face_1.set_cell(
				cell + Vector2i.UP,
				0,
				Vector2i(middle_frame % ATLAS_COLUMNS, middle_frame / ATLAS_COLUMNS),
				0
			)
			face_2.set_cell(
				cell,
				0,
				Vector2i(bottom_frame % ATLAS_COLUMNS, bottom_frame / ATLAS_COLUMNS),
				0
			)

		if collision != null:
			collision.set_cell(cell, 0, Vector2i(0, 4), 0)

	top.update_internals()
	face_1.update_internals()
	face_2.update_internals()
	if collision != null:
		collision.update_internals()
