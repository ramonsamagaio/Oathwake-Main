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
	_disable_player_ground_halo(light)


func _disable_player_ground_halo(light: Node2D) -> void:
	# The player remains readable through its compact compositor mask and
	# unshaded authored sprites. It must not use the reusable GlowOverlay as a
	# visible aura or ground PointLight, even if an older save/content reload
	# attempts to restore the previous player light tuning.
	light.set("visual_enabled", false)
	light.set("alpha", 0.0)
	light.set("intensity", 0.0)
	light.set("use_point_light", false)
	light.set("point_light_energy", 0.0)
	light.set("day_light_multiplier", 0.0)
	light.set("night_light_multiplier", 0.0)
	var texture_glow := light.get_node_or_null("TextureGlow") as Sprite2D
	if texture_glow != null:
		texture_glow.visible = false
	var procedural_glow := light.get_node_or_null("ProceduralGlow") as Sprite2D
	if procedural_glow != null:
		procedural_glow.visible = false
	var point_light := light.get_node_or_null("PointLight2D") as PointLight2D
	if point_light != null:
		point_light.visible = false
		point_light.enabled = false
		point_light.energy = 0.0
		point_light.texture = null
	if light.has_method("refresh_from_config"):
		light.call("refresh_from_config")
	set_meta("player_ground_halo_disabled", true)


func is_player_ground_halo_disabled() -> bool:
	return bool(get_meta("player_ground_halo_disabled", false))


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
