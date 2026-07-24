extends "res://scripts/buildings/BuildingLightingSuite.gd"

@onready var visual: Polygon2D = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var is_open := false
var closed_color := Color("6f4a2f")
var open_color := Color("5d9660")


func _ready() -> void:
	add_to_group("interactable_building")
	super._ready()
	_apply_door_state()


func interact(_player: Node = null) -> void:
	set_open(not is_open)


func set_open(value: bool) -> void:
	is_open = value
	_apply_door_state()


func get_open() -> bool:
	return is_open


func _apply_door_state() -> void:
	if visual == null or collision_shape == null:
		return
	if is_open:
		visual.color = open_color
		visual.polygon = PackedVector2Array([
			Vector2(-15.0, -5.0),
			Vector2(15.0, -5.0),
			Vector2(15.0, 5.0),
			Vector2(-15.0, 5.0),
		])
		collision_shape.disabled = true
	else:
		visual.color = closed_color
		visual.polygon = PackedVector2Array([
			Vector2(-6.0, -15.0),
			Vector2(6.0, -15.0),
			Vector2(6.0, 15.0),
			Vector2(-6.0, 15.0),
		])
		collision_shape.disabled = false
