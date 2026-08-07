extends "res://scripts/player/AlabasterWeaponVisualRuntime.gd"
class_name BonesWeapons

# Production weapon attachment layer for bone-driven characters.
# Weapon FIG data is prepared when an item changes, never when attack input is
# pressed. The character attack clip is also compiled at equip time.

const SourceAssets := preload("res://scripts/labs/alabaster/AlabasterSourceAssetLibrary.gd")


func set_item(new_item_id: String, item_record: Dictionary) -> void:
	super.set_item(new_item_id, item_record)
	_prewarm_equipped_weapon()


func set_attacking(value: bool) -> void:
	if attacking == value:
		return
	# Attack state only changes visibility/pose. Do not invalidate a FIG and do
	# not create/free Sprite2D nodes on the combat input frame.
	attacking = value
	_update_visibility()


func _prewarm_equipped_weapon() -> void:
	if not has_weapon():
		return

	var attack_animation := get_attack_animation()
	if not attack_animation.is_empty() and rig != null and rig.has_method("prewarm_animation"):
		rig.call("prewarm_animation", attack_animation)

	# Decode both source atlases through the shared static cache. The source FIG
	# itself chooses which one each piece uses, so combat never pays PNG decode.
	SourceAssets.load_player_weapon_sheet("melee")
	SourceAssets.load_player_weapon_sheet("ranged")

	var held_figure := str(weapon_data.get("source_figure", "")).strip_edges()
	if not held_figure.is_empty() and _has_source_figure(held_figure):
		_build_source_figure(held_figure)
