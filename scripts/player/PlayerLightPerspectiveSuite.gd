extends "res://scripts/player/PlayerCombatGuardPetSuite.gd"

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")
const NIGHT_READABILITY_VISUAL_PATHS := [
	NodePath("Body"),
	NodePath("AnimatedSprite2D"),
	NodePath("WIPSouthSprite"),
]


func _setup_character_visual() -> void:
	super._setup_character_visual()
	call_deferred("_configure_player_night_readability")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)


func _configure_player_night_readability() -> void:
	# No unshaded readability material: Juno receives CanvasModulate and the same
	# global Romestead illumination as terrain, creatures and resources.
	for visual_path in NIGHT_READABILITY_VISUAL_PATHS:
		var visual := get_node_or_null(visual_path) as CanvasItem
		if visual != null:
			visual.material = null
			visual.set_meta("player_night_readability_unshaded", false)
	set_meta("player_night_readability_enabled", false)


func is_player_night_readability_enabled() -> bool:
	return false


func _apply_player_light_tuning() -> void:
	# Player-authored light was retired. Remove a stale child from inherited or
	# user-authored player scenes without creating any replacement process.
	var stale_light := get_node_or_null("NightLight")
	if stale_light != null:
		stale_light.queue_free()
	set_meta("player_environment_halo_enabled", false)
	set_meta("player_ground_halo_disabled", true)
	set_meta("player_visible_ground_light_enabled", false)


# Compatibility no-ops for old save/debug callers. They intentionally cannot
# recreate the retired player light.
func set_player_ground_light_strength(_strength: float) -> void:
	pass


func _sync_player_environment_halo_to_world() -> void:
	pass


func is_player_environment_halo_enabled() -> bool:
	return false


func is_player_ground_halo_disabled() -> bool:
	return true


func get_player_ground_light() -> Sprite2D:
	return null


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
