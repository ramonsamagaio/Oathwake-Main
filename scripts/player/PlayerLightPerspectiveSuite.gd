extends "res://scripts/player/PlayerLifeAnimationSuite.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")
const MIN_LIGHT_PERSPECTIVE_ANGLE := 15.0
const MAX_LIGHT_PERSPECTIVE_ANGLE := 90.0
const DEFAULT_LIGHT_PERSPECTIVE_ANGLE := 50.0
const NIGHT_READABILITY_VISUAL_PATHS := [
	NodePath("Body"),
	NodePath("AnimatedSprite2D"),
	NodePath("WIPSouthSprite"),
]

var _night_readability_material: CanvasItemMaterial


func _setup_character_visual() -> void:
	super._setup_character_visual()
	# WIPPlayer finishes creating its runtime SpriteFrames after this override
	# returns. Deferring keeps every player visual on the same lighting contract.
	call_deferred("_configure_player_night_readability")


func _configure_player_night_readability() -> void:
	if _night_readability_material == null:
		_night_readability_material = CanvasItemMaterial.new()
		_night_readability_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_night_readability_material.resource_name = "Player Night Readability"
	for visual_path in NIGHT_READABILITY_VISUAL_PATHS:
		var visual := get_node_or_null(visual_path) as CanvasItem
		if visual == null:
			continue
		visual.material = _night_readability_material
		visual.set_meta("player_night_readability_unshaded", true)
	set_meta("player_night_readability_enabled", true)


func is_player_night_readability_enabled() -> bool:
	if _night_readability_material == null:
		return false
	return _night_readability_material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED


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
