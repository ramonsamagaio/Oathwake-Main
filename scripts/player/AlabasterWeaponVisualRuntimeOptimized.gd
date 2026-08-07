extends "res://scripts/player/AlabasterWeaponVisualRuntime.gd"
class_name AlabasterWeaponVisualRuntimeOptimized

const OptimizedSourceAssets := preload("res://scripts/labs/alabaster/AlabasterSourceAssetLibrary.gd")


func set_item(new_item_id: String, item_record: Dictionary) -> void:
	super.set_item(new_item_id, item_record)
	_prewarm_equipped_weapon()


func set_attacking(value: bool) -> void:
	if attacking == value:
		return
	# Do not invalidate/rebuild the held FIG merely because attack state changed.
	# Tonfa has eight gfx pieces; rebuilding them on every attack caused avoidable
	# allocation/free churn in the exact frame input was pressed.
	attacking = value
	_update_visibility()


func _prewarm_equipped_weapon() -> void:
	if not has_weapon():
		return

	# Decode the relevant source atlas while equipping/selecting the weapon,
	# never on the first attack frame.
	var kind := str(weapon_data.get("kind", ""))
	var sheet_name := "ranged" if kind in ["crossbow", "chakram", "kama", "bomb", "gauntlet"] else "melee"
	OptimizedSourceAssets.load_player_weapon_sheet(sheet_name)

	# Attack-only weapons can keep their held figure alive while hidden. This is
	# especially important for dual-piece/dual-hand figures such as Tonfa.
	var held_figure := str(weapon_data.get("source_figure", "")).strip_edges()
	if not held_figure.is_empty() and _has_source_figure(held_figure):
		_build_source_figure(held_figure)
