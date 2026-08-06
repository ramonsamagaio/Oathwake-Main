extends "res://scripts/player/PlayerCombatGuardPetSuite.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")
const MIN_LIGHT_PERSPECTIVE_ANGLE := 15.0
const MAX_LIGHT_PERSPECTIVE_ANGLE := 90.0
const DEFAULT_LIGHT_PERSPECTIVE_ANGLE := 50.0
const DEFAULT_HALO_COLOR := Color(1.0, 0.90, 0.67, 1.0)
const DEFAULT_HALO_ENERGY := 0.52
const DEFAULT_HALO_RADIUS_SCALE := 4.2
const DEFAULT_HALO_GROUND_STRETCH := Vector2(2.0, 0.75)
const DEFAULT_HALO_GROUND_OFFSET := Vector2(0.0, 12.0)
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
	# The player light is projected onto the ground plane, not wrapped around the
	# character. Horizontal expansion establishes the broad footprint while the
	# camera angle compresses its vertical axis to sell top-down depth.
	var vertical_projection := clampf(sin(deg_to_rad(perspective_angle)), 0.20, 1.0)
	var authored_stretch := _light_vector_config("ground_ellipse_scale", DEFAULT_HALO_GROUND_STRETCH)
	var ground_stretch := Vector2(
		maxf(authored_stretch.x, 1.0),
		clampf(authored_stretch.y, 0.20, 1.0)
	)
	var projected_scale := Vector2(ground_stretch.x, ground_stretch.y * vertical_projection)
	light.scale = projected_scale
	light.position = _light_vector_config("ground_ellipse_offset", DEFAULT_HALO_GROUND_OFFSET)
	light.set_meta("player_light_perspective_angle", perspective_angle)
	light.set_meta("player_light_vertical_projection", vertical_projection)
	light.set_meta("player_light_ground_stretch", ground_stretch)
	light.set_meta("player_light_projected_scale", projected_scale)
	_configure_player_environment_halo(light)


func _configure_player_environment_halo(light: Node2D) -> void:
	# Only the broad PointLight2D is rendered. A second TextureGlow layer creates
	# a hard-edged disc over pixel-art terrain, so it stays disabled while the
	# parent node scale still projects the light into the authored ground ellipse.
	light.visible = true
	light.set("visual_enabled", false)
	light.set("visual_uses_day_night_multiplier", false)
	light.set("use_point_light", true)
	light.set("light_uses_aura_alpha", false)
	light.set("glow_color", Color.from_string(str(_content_light_config.get("color", "#FFE6AAFF")), DEFAULT_HALO_COLOR))
	light.set("intensity", 1.0)
	light.set("alpha", 1.0)
	light.set("scale_multiplier", 1.0)
	light.set("stretch", Vector2.ONE)
	light.set("point_light_energy", maxf(float(_content_light_config.get("emission", DEFAULT_HALO_ENERGY)), DEFAULT_HALO_ENERGY))
	light.set("point_light_scale", maxf(float(_content_light_config.get("radius_scale", DEFAULT_HALO_RADIUS_SCALE)), DEFAULT_HALO_RADIUS_SCALE))
	light.set("day_light_multiplier", 0.0)
	light.set("night_light_multiplier", maxf(float(_content_light_config.get("night_multiplier", 1.0)), 1.0))
	light.set("z_index_value", -6)
	if light.has_method("refresh_from_config"):
		light.call("refresh_from_config")
	var texture_glow := light.get_node_or_null("TextureGlow") as Sprite2D
	if texture_glow != null:
		texture_glow.visible = false
	var procedural_glow := light.get_node_or_null("ProceduralGlow") as Sprite2D
	if procedural_glow != null:
		procedural_glow.visible = false
	set_meta("player_environment_halo_enabled", true)
	set_meta("player_ground_halo_disabled", true)


func _light_vector_config(key: String, fallback: Vector2) -> Vector2:
	var value: Variant = _content_light_config.get(key, fallback)
	if value is Vector2:
		return value as Vector2
	if value is Dictionary:
		var dictionary := value as Dictionary
		return Vector2(
			float(dictionary.get("x", fallback.x)),
			float(dictionary.get("y", fallback.y))
		)
	return fallback


func is_player_environment_halo_enabled() -> bool:
	return bool(get_meta("player_environment_halo_enabled", false))


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
