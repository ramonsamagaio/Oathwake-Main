extends Node

const BUILD_CELL_PX := 32.0
const CUTAWAY_ALPHA := 0.18
const RESTORE_ALPHA := 1.0
const REFRESH_INTERVAL := 0.12
const STRUCTURAL_TYPES := ["wall", "door", "wall_window", "wall_doorway"]
const CARDINAL := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _elapsed := 0.0
var _build_system: Node
var _player: Node2D
var _last_cutaway: Dictionary = {}

func _ready() -> void:
	process_priority = 900
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_resolve_context()
	if _build_system == null or _player == null:
		_restore_all()
		return
	_apply_room_cutaway()

func _resolve_context() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _build_system == null or not is_instance_valid(_build_system):
		_build_system = _find_named_node(get_tree().current_scene, "BuildSystem")

func _find_named_node(root: Node, wanted: String) -> Node:
	if root == null:
		return null
	if root.name == wanted:
		return root
	for child in root.get_children():
		var found := _find_named_node(child, wanted)
		if found != null:
			return found
	return null

func _apply_room_cutaway() -> void:
	if not _build_system.has_method("get_built_buildings"):
		_restore_all()
		return
	var entries: Array = _build_system.call("get_built_buildings")
	var structural: Dictionary = {}
	for value in entries:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var kind := str(entry.get("type", ""))
		if not STRUCTURAL_TYPES.has(kind):
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		structural[cell] = kind
	if structural.is_empty():
		_restore_all()
		return

	var player_cell := _world_to_build_cell(_player.global_position)
	var inside := _is_inside_closed_room(player_cell, structural)
	if not inside:
		_restore_all()
		return

	var desired: Dictionary = {}
	for cell_value in structural.keys():
		var cell := cell_value as Vector2i
		# Camera is top-down. Positive Y is foreground/south, so walls on and below
		# the player's row are the ones most likely to cover the character.
		if cell.y >= player_cell.y:
			desired[cell] = true
	_apply_alpha_map(desired)

func _is_inside_closed_room(player_cell: Vector2i, structural: Dictionary) -> bool:
	if structural.has(player_cell):
		return false
	var min_x := player_cell.x
	var max_x := player_cell.x
	var min_y := player_cell.y
	var max_y := player_cell.y
	for cell_value in structural.keys():
		var cell := cell_value as Vector2i
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	min_x -= 2; max_x += 2; min_y -= 2; max_y += 2
	if player_cell.x < min_x or player_cell.x > max_x or player_cell.y < min_y or player_cell.y > max_y:
		return false

	var outside := Vector2i(min_x, min_y)
	var queue: Array[Vector2i] = [outside]
	var visited: Dictionary = {outside: true}
	while not queue.is_empty():
		var current := queue.pop_front()
		if current == player_cell:
			return false
		for direction in CARDINAL:
			var next := current + direction
			if next.x < min_x or next.x > max_x or next.y < min_y or next.y > max_y:
				continue
			if structural.has(next) or visited.has(next):
				continue
			visited[next] = true
			queue.append(next)
	return true

func _apply_alpha_map(desired: Dictionary) -> void:
	var scene_map: Variant = _build_system.get("building_scene_by_cell")
	if not scene_map is Dictionary:
		return
	var by_cell := scene_map as Dictionary
	for key_value in by_cell.keys():
		var cell := _parse_cell_key(str(key_value))
		var node := by_cell[key_value] as CanvasItem
		if node == null or not is_instance_valid(node):
			continue
		var alpha := CUTAWAY_ALPHA if desired.has(cell) else RESTORE_ALPHA
		var color := node.modulate
		color.a = alpha
		node.modulate = color
	_last_cutaway = desired.duplicate()

func _restore_all() -> void:
	if _last_cutaway.is_empty() or _build_system == null or not is_instance_valid(_build_system):
		_last_cutaway.clear()
		return
	var scene_map: Variant = _build_system.get("building_scene_by_cell")
	if scene_map is Dictionary:
		for node_value in (scene_map as Dictionary).values():
			var node := node_value as CanvasItem
			if node != null and is_instance_valid(node):
				var color := node.modulate
				color.a = RESTORE_ALPHA
				node.modulate = color
	_last_cutaway.clear()

func _world_to_build_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / BUILD_CELL_PX), floori(world_position.y / BUILD_CELL_PX))

func _parse_cell_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() >= 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(2147483647, 2147483647)
