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
		fallback_visual = get_node_or_null("FallbackVisual") as ColorRect
	if fallback_visual != null:
		var color_key := "open_color" if is_open else "closed_color"
		fallback_visual.color = Color.from_string(str(building_data.get(color_key, "#3C7650FF" if is_open else "#6B4028FF")), Color(0.24, 0.46, 0.31, 1.0) if is_open else Color(0.42, 0.25, 0.16, 1.0))
		fallback_visual.size = Vector2(10, 30) if not is_open else Vector2(30, 8)
		fallback_visual.position = -fallback_visual.size * Vector2(0.5, 0.78)
	if collision_shape != null:
		collision_shape.disabled = is_open
	set_meta("door_open", is_open)
