extends "res://scripts/player/PlayerLifeAnimationSuite.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")
const MIN_LIGHT_PERSPECTIVE_ANGLE := 15.0
const MAX_LIGHT_PERSPECTIVE_ANGLE := 90.0
const DEFAULT_LIGHT_PERSPECTIVE_ANGLE := 50.0


func _apply_player_light_tuning() -> void:
	super._apply_player_light_tuning()
	var light := get_node_or_null("NightLight") as Node2D
	if light == null:
		return
	var perspective_angle := clampf(
		float(_content_light_config.get("perspective_angle_degrees", DEFAULT_LIGHT_PERSPECTIVE_ANGLE)),
		MIN_LIGHT_PERSPECTIVE_ANGLE,
		MAX_LIGHT_PERSPECTIVE_ANGLE
	)
	# Ninety degrees represents a zenith camera and keeps the light circular.
	# Lower top-down camera angles compress the light vertically into the same
	# ground-plane ellipse that the player would produce in perspective.
	var vertical_projection := clampf(sin(deg_to_rad(perspective_angle)), 0.20, 1.0)
	light.scale = Vector2(1.0, vertical_projection)
	light.set_meta("player_light_perspective_angle", perspective_angle)
	light.set_meta("player_light_vertical_projection", vertical_projection)


func get_current_tool() -> String:
	var item_id := _get_current_held_item_id()
	if item_id.is_empty():
		return super.get_current_tool()
	var item_data := _get_item_data(item_id)
	var slot_data := _get_hotbar_slot_data(current_hotbar_slot_index)
	return RefinementCalculatorScript.get_refined_display_name(item_data, slot_data)


func _get_current_held_item_data() -> Dictionary:
	var item_data := super._get_current_held_item_data()
	if item_data.is_empty():
		return item_data
	var slot_data := _get_hotbar_slot_data(current_hotbar_slot_index)
	return RefinementCalculatorScript.apply_refinement_to_item_data(item_data, slot_data)
