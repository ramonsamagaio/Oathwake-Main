@tool
extends Node2D

@export_category("Multi-floor Building")
@export var building_id := "building_01"
@export_range(0, 32, 1) var floor_index := 0
@export var show_lower_floors := true
@export var disable_processing_when_inactive := true
@export var collision_root: NodePath

var _collision_nodes: Array[CollisionObject2D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_cache_collision_nodes()
	FloorManager.register_floor_layer(building_id, floor_index, self)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	FloorManager.unregister_floor_layer(building_id, floor_index, self)


func apply_floor_state(active_floor: int) -> void:
	var should_be_visible := floor_index == active_floor or (show_lower_floors and floor_index < active_floor)
	visible = should_be_visible

	var is_active := floor_index == active_floor
	for collision_object: CollisionObject2D in _collision_nodes:
		if is_instance_valid(collision_object):
			collision_object.set_deferred("collision_layer", collision_object.get_meta("floor_original_collision_layer", collision_object.collision_layer) if is_active else 0)
			collision_object.set_deferred("collision_mask", collision_object.get_meta("floor_original_collision_mask", collision_object.collision_mask) if is_active else 0)

	if disable_processing_when_inactive:
		process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED


func _cache_collision_nodes() -> void:
	_collision_nodes.clear()
	var root: Node = get_node_or_null(collision_root) if not collision_root.is_empty() else self
	if root == null:
		root = self
	_collect_collision_nodes(root)


func _collect_collision_nodes(node: Node) -> void:
	if node is CollisionObject2D:
		var collision_object := node as CollisionObject2D
		collision_object.set_meta("floor_original_collision_layer", collision_object.collision_layer)
		collision_object.set_meta("floor_original_collision_mask", collision_object.collision_mask)
		_collision_nodes.append(collision_object)
	for child: Node in node.get_children():
		_collect_collision_nodes(child)
