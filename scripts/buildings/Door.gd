extends "res://scripts/buildings/BuildingLightingSuite.gd"

var is_open := false

func _ready() -> void:
	super._ready()
	add_to_group("interactable_building")
	_apply_door_state()

func setup(new_building_id: String, new_data: Dictionary = {}) -> void:
	super.setup(new_building_id, new_data)
	interaction_range = float(building_data.get("interaction_range", interaction_range))
	_apply_door_state()

func try_interact_with_player(player: Node2D) -> bool:
	if player == null or global_position.distance_to(player.global_position) > interaction_range:
		return false
	set_open(not is_open)
	return true

func set_open(open_state: bool) -> void:
	is_open = open_state
	_apply_door_state()

func get_open() -> bool:
	return is_open

func _apply_door_state() -> void:
	if fallback_visual == null:
		fallback_visual = get_node_or_null("FallbackVisual") as Node2D
	if fallback_visual != null and fallback_visual.has_method("set_door_open"):
		fallback_visual.call("set_door_open", is_open)
	if collision_shape != null:
		collision_shape.disabled = is_open
	set_meta("door_open", is_open)
