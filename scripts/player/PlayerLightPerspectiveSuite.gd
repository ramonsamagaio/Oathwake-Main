extends "res://scripts/player/PlayerCombatGuardPetSuite.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")
const PLAYER_GROUND_LIGHT_TEXTURE: Texture2D = preload("res://assets/sprites/effects/glows/glow2.png")
const MIN_LIGHT_PERSPECTIVE_ANGLE := 15.0
const MAX_LIGHT_PERSPECTIVE_ANGLE := 90.0
const DEFAULT_LIGHT_PERSPECTIVE_ANGLE := 50.0
const DEFAULT_HALO_COLOR := Color(1.0, 0.90, 0.67, 1.0)
const DEFAULT_HALO_ENERGY := 0.52
const DEFAULT_HALO_RADIUS_SCALE := 4.2
const DEFAULT_HALO_GROUND_STRETCH := Vector2(2.0, 0.75)
const DEFAULT_HALO_GROUND_OFFSET := Vector2(0.0, 12.0)
const DEFAULT_GROUND_HALO_ALPHA := 0.22
const DEFAULT_GROUND_HALO_INTENSITY := 0.75
const DEFAULT_GROUND_HALO_TEXTURE_SCALE := 0.20
const DEFAULT_GROUND_HALO_BLUR := 2.0
const NIGHT_READABILITY_VISUAL_PATHS := [
	NodePath("Body"),
	NodePath("AnimatedSprite2D"),
	NodePath("WIPSouthSprite"),
]

var _night_readability_material: CanvasItemMaterial
var _player_ground_light: Sprite2D
var _player_ground_light_material: CanvasItemMaterial
var _player_ground_light_enabled := true
var _player_ground_light_color := DEFAULT_HALO_COLOR
var _player_ground_light_alpha := DEFAULT_GROUND_HALO_ALPHA
var _player_ground_light_intensity := DEFAULT_GROUND_HALO_INTENSITY
var _player_ground_light_blur := DEFAULT_GROUND_HALO_BLUR
var _player_ground_light_texture_scale := DEFAULT_GROUND_HALO_TEXTURE_SCALE


func _setup_character_visual() -> void:
	super._setup_character_visual()
	# WIPPlayer finishes creating its runtime SpriteFrames after this override
	# returns. Deferring keeps every player visual on the same lighting contract.
	call_deferred("_configure_player_night_readability")
	call_deferred("_sync_player_environment_halo_to_world")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_sync_player_environment_halo_to_world()


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
	_sync_player_environment_halo_to_world()


func _configure_player_environment_halo(light: Node2D) -> void:
	# Keep the old compact aura disabled. The player now has two independent light
	# layers: PointLight2D for light-reactive objects and PlayerGroundLight for
	# shader-driven terrain that ignores CanvasItem lighting.
	_player_ground_light_enabled = bool(_content_light_config.get("visual_aura_enabled", true))
	_player_ground_light_color = Color.from_string(
		str(_content_light_config.get("color", "#FFE6AAFF")),
		DEFAULT_HALO_COLOR
	)
	_player_ground_light_alpha = clampf(
		float(_content_light_config.get("ground_halo_alpha", DEFAULT_GROUND_HALO_ALPHA)),
		0.0,
		1.0
	)
	_player_ground_light_intensity = maxf(
		float(_content_light_config.get("ground_halo_intensity", DEFAULT_GROUND_HALO_INTENSITY)),
		0.0
	)
	_player_ground_light_texture_scale = maxf(
		float(_content_light_config.get("ground_halo_texture_scale", DEFAULT_GROUND_HALO_TEXTURE_SCALE)),
		0.01
	)
	_player_ground_light_blur = maxf(
		float(_content_light_config.get("ground_halo_blur", DEFAULT_GROUND_HALO_BLUR)),
		0.0
	)
	var desired_point_light_energy := maxf(
		float(_content_light_config.get("emission", DEFAULT_HALO_ENERGY)),
		DEFAULT_HALO_ENERGY
	)
	var desired_point_light_radius := maxf(
		float(_content_light_config.get("radius_scale", DEFAULT_HALO_RADIUS_SCALE)),
		DEFAULT_HALO_RADIUS_SCALE
	)

	light.visible = true
	light.set("visual_enabled", false)
	light.set("visual_uses_day_night_multiplier", true)
	light.set("use_point_light", true)
	light.set("light_uses_aura_alpha", false)
	light.set("glow_color", _player_ground_light_color)
	light.set("intensity", 1.0)
	light.set("alpha", 1.0)
	light.set("scale_multiplier", 1.0)
	light.set("blur_amount", 0.0)
	light.set("stretch", Vector2.ONE)
	light.set("point_light_energy", desired_point_light_energy)
	light.set("point_light_scale", desired_point_light_radius)
	light.set("day_light_multiplier", 0.0)
	light.set("night_light_multiplier", maxf(float(_content_light_config.get("night_multiplier", 1.0)), 1.0))
	light.set("z_index_value", -6)
	if light.has_method("refresh_from_config"):
		light.call("refresh_from_config")

	var compact_texture_glow := light.get_node_or_null("TextureGlow") as Sprite2D
	if compact_texture_glow != null:
		compact_texture_glow.visible = false
	var procedural_glow := light.get_node_or_null("ProceduralGlow") as Sprite2D
	if procedural_glow != null:
		procedural_glow.visible = false

	_ensure_player_ground_light(light)
	_configure_player_ground_light_geometry()
	_set_player_ground_light_strength(0.0)
	light.set_meta("player_light_desired_energy", desired_point_light_energy)
	light.set_meta("player_light_desired_radius", desired_point_light_radius)
	set_meta("player_environment_halo_enabled", true)
	set_meta("player_ground_halo_disabled", not _player_ground_light_enabled)
	set_meta("player_visible_ground_light_enabled", _player_ground_light_enabled)


func _ensure_player_ground_light(light: Node2D) -> void:
	if _player_ground_light != null and is_instance_valid(_player_ground_light):
		return
	_player_ground_light = light.get_node_or_null("PlayerGroundLight") as Sprite2D
	if _player_ground_light == null:
		_player_ground_light = Sprite2D.new()
		_player_ground_light.name = "PlayerGroundLight"
		light.add_child(_player_ground_light)
	_player_ground_light.texture = PLAYER_GROUND_LIGHT_TEXTURE
	_player_ground_light.centered = true
	_player_ground_light.show_behind_parent = true
	_player_ground_light.z_index = -6
	_player_ground_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _player_ground_light_material == null:
		_player_ground_light_material = CanvasItemMaterial.new()
		_player_ground_light_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_player_ground_light_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_player_ground_light_material.resource_name = "Player Projected Ground Light"
	_player_ground_light.material = _player_ground_light_material
	_player_ground_light.set_meta("player_projected_ground_light", true)


func _configure_player_ground_light_geometry() -> void:
	if _player_ground_light == null:
		return
	var blur_scale := 1.0 + (_player_ground_light_blur * 0.06)
	_player_ground_light.scale = Vector2.ONE * _player_ground_light_texture_scale * blur_scale
	_player_ground_light.set_meta("ground_light_texture_scale", _player_ground_light_texture_scale)
	_player_ground_light.set_meta("ground_light_blur", _player_ground_light_blur)


func _set_player_ground_light_strength(strength: float) -> void:
	if _player_ground_light == null or not is_instance_valid(_player_ground_light):
		return
	var resolved_strength := clampf(strength, 0.0, 1.0)
	var blur_alpha_divisor := 1.0 + (_player_ground_light_blur * 0.10)
	var resolved_alpha := (_player_ground_light_alpha / blur_alpha_divisor) * resolved_strength
	var resolved_intensity := _player_ground_light_intensity * resolved_strength
	_player_ground_light.visible = _player_ground_light_enabled and resolved_alpha > 0.001
	_player_ground_light.modulate = Color(
		_player_ground_light_color.r * resolved_intensity,
		_player_ground_light_color.g * resolved_intensity,
		_player_ground_light_color.b * resolved_intensity,
		resolved_alpha
	)
	_player_ground_light.set_meta("player_ground_light_strength", resolved_strength)
	_player_ground_light.set_meta("player_ground_light_alpha", resolved_alpha)


func set_player_ground_light_strength(strength: float) -> void:
	_set_player_ground_light_strength(strength)
	var light := get_node_or_null("NightLight") as Node2D
	if light != null and light.has_method("set_day_night_strength"):
		light.call("set_day_night_strength", clampf(strength, 0.0, 1.0))


func _sync_player_environment_halo_to_world() -> void:
	if not is_inside_tree():
		return
	var light := get_node_or_null("NightLight") as Node2D
	if light == null or not light.has_method("set_day_night_strength"):
		return
	var found_cycle := false
	var strongest_night := 0.0
	for cycle in get_tree().get_nodes_in_group("day_night_cycle"):
		if cycle == null or not is_instance_valid(cycle) or not cycle.has_method("get_night_strength"):
			continue
		found_cycle = true
		strongest_night = maxf(strongest_night, clampf(float(cycle.call("get_night_strength")), 0.0, 1.0))
	if not found_cycle:
		return
	light.call("set_day_night_strength", strongest_night)
	_set_player_ground_light_strength(strongest_night)
	light.set_meta("player_light_synced_night_strength", strongest_night)


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


func get_player_ground_light() -> Sprite2D:
	return _player_ground_light if _player_ground_light != null and is_instance_valid(_player_ground_light) else null


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
