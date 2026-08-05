extends RefCounted

const RefinementCalculatorScript := preload("res://scripts/systems/RefinementCalculator.gd")

const DEFAULT_STATS := {
	"str": 5, "dex": 5, "agi": 5,
	"vit": 5, "wis": 5, "int": 5, "luk": 5,
}


func get_base_player_data(player) -> Dictionary:
	if player == null:
		return {"base_stats": {}}
	var combat_data = player.get_combat_data() if player.has_method("get_combat_data") else {}
	return combat_data


func get_equipment_bonus(equipment_system) -> Dictionary:
	var bonus := {
		"stats_bonus": {"str": 0, "dex": 0, "agi": 0, "vit": 0, "wis": 0, "int": 0, "luk": 0},
		"defense": 0,
		"magic_defense": 0,
		"max_hp_bonus": 0,
		"hit_bonus": 0,
		"flee_bonus": 0,
		"crit_chance_bonus": 0.0,
		"crit_damage_bonus": 0.0,
		"attack_speed_bonus": 0.0,
		"invulnerability_duration_bonus": 0.0,
	}
	if equipment_system == null or not equipment_system.has_method("get_equipment_slots"):
		return bonus

	var content_db := _get_content_db()
	if content_db == null:
		return bonus

	var slots = equipment_system.get_equipment_slots()
	for slot_id in slots:
		var slot_data = slots[slot_id]
		if not slot_data is Dictionary:
			continue
		var item_id := str(slot_data.get("item_id", ""))
		if item_id.is_empty():
			continue
		if content_db.has_method("has_item") and not content_db.has_item(item_id):
			continue
		var item_data: Dictionary = content_db.get_item(item_id)
		item_data = RefinementCalculatorScript.apply_refinement_to_item_data(item_data, slot_data)
		var item_type := str(item_data.get("item_type", "")).to_lower()
		if item_type == "tool" or item_type == "weapon":
			continue

		var item_stats: Dictionary = item_data.get("stats_bonus", {})
		if item_stats is Dictionary:
			for stat_name in bonus["stats_bonus"].keys():
				bonus["stats_bonus"][stat_name] = bonus["stats_bonus"][stat_name] + int(item_stats.get(stat_name, 0))

		bonus["defense"] = bonus["defense"] + int(item_data.get("defense", 0))
		bonus["magic_defense"] = bonus["magic_defense"] + int(item_data.get("magic_defense", 0))
		bonus["max_hp_bonus"] = bonus["max_hp_bonus"] + int(item_data.get("max_hp_bonus", 0))
		bonus["hit_bonus"] = bonus["hit_bonus"] + int(item_data.get("hit_bonus", 0))
		bonus["flee_bonus"] = bonus["flee_bonus"] + int(item_data.get("flee_bonus", 0))
		bonus["crit_chance_bonus"] = bonus["crit_chance_bonus"] + float(item_data.get("crit_chance_bonus", 0.0))
		bonus["crit_damage_bonus"] = bonus["crit_damage_bonus"] + float(item_data.get("crit_damage_bonus", 0.0))
		bonus["attack_speed_bonus"] = bonus["attack_speed_bonus"] + float(item_data.get("attack_speed_bonus", 0.0))
		bonus["invulnerability_duration_bonus"] = bonus["invulnerability_duration_bonus"] + float(item_data.get("invulnerability_duration_bonus", 0.0))

		var item_combat: Dictionary = item_data.get("combat", {})
		if item_combat is Dictionary:
			bonus["crit_chance_bonus"] = bonus["crit_chance_bonus"] + float(item_combat.get("crit_chance_bonus", 0.0))
			bonus["crit_damage_bonus"] = bonus["crit_damage_bonus"] + float(item_combat.get("crit_damage_bonus", 0.0))
			bonus["attack_speed_bonus"] = bonus["attack_speed_bonus"] + float(item_combat.get("attack_speed_bonus", 0.0))
			bonus["invulnerability_duration_bonus"] = bonus["invulnerability_duration_bonus"] + float(item_combat.get("invulnerability_duration_bonus", 0.0))

	return bonus


func get_total_player_data(player, equipment_system) -> Dictionary:
	var base_data := get_base_player_data(player)
	var base_stats: Dictionary = base_data.get("base_stats", {})
	var equip_bonus := get_equipment_bonus(equipment_system)
	var equip_stats: Dictionary = equip_bonus.get("stats_bonus", {})

	var total_stats := {}
	for stat_name in DEFAULT_STATS.keys():
		total_stats[stat_name] = int(base_stats.get(stat_name, DEFAULT_STATS[stat_name])) + equip_stats.get(stat_name, 0)

	var result: Dictionary = base_data.duplicate(true)
	result["base_stats"] = total_stats

	var base_combat: Dictionary = base_data.get("base_combat", {})
	var merged_combat: Dictionary = base_combat.duplicate(true)
	var add_defense: int = equip_bonus.get("defense", 0)
	var add_magic_defense: int = equip_bonus.get("magic_defense", 0)
	var add_hit: int = equip_bonus.get("hit_bonus", 0)
	var add_flee: int = equip_bonus.get("flee_bonus", 0)
	var add_crit_chance: float = equip_bonus.get("crit_chance_bonus", 0.0)
	var add_crit_damage: float = equip_bonus.get("crit_damage_bonus", 0.0)
	var add_attack_speed: float = equip_bonus.get("attack_speed_bonus", 0.0)
	var add_invulnerability: float = equip_bonus.get("invulnerability_duration_bonus", 0.0)

	if add_defense != 0:
		merged_combat["base_defense"] = float(merged_combat.get("base_defense", 0.0)) + add_defense
	if add_magic_defense != 0:
		merged_combat["base_magic_defense"] = float(merged_combat.get("base_magic_defense", 0.0)) + add_magic_defense
	if add_hit != 0:
		merged_combat["base_hit"] = float(merged_combat.get("base_hit", 75.0)) + add_hit
	if add_flee != 0:
		merged_combat["base_flee"] = float(merged_combat.get("base_flee", 5.0)) + add_flee
	if add_crit_chance != 0.0:
		merged_combat["base_crit_chance"] = float(merged_combat.get("base_crit_chance", 0.03)) + add_crit_chance
	if add_crit_damage != 0.0:
		merged_combat["base_crit_damage"] = float(merged_combat.get("base_crit_damage", 1.5)) + add_crit_damage
	if add_attack_speed != 0.0:
		merged_combat["attack_speed_bonus"] = float(merged_combat.get("attack_speed_bonus", 0.0)) + add_attack_speed
	if add_invulnerability != 0.0:
		merged_combat["invulnerability_duration_bonus"] = float(merged_combat.get("invulnerability_duration_bonus", 0.0)) + add_invulnerability
	result["base_combat"] = merged_combat

	var max_hp_bonus: int = equip_bonus.get("max_hp_bonus", 0)
	if max_hp_bonus != 0:
		result["max_health"] = float(result.get("max_health", 100.0)) + max_hp_bonus

	return result


func get_equipped_weapon_data(equipment_system) -> Dictionary:
	return _get_equipped_item_data(equipment_system, "weapon")


func get_equipped_tool_data(equipment_system) -> Dictionary:
	return _get_equipped_item_data(equipment_system, "tool")


func _get_equipped_item_data(equipment_system, slot_id: String) -> Dictionary:
	if equipment_system == null or not equipment_system.has_method("get_equipped_slot"):
		return {}
	var slot_data = equipment_system.get_equipped_slot(slot_id)
	if not slot_data is Dictionary:
		return {}
	var item_id := str(slot_data.get("item_id", ""))
	if item_id.is_empty():
		return {}
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return {}
	var item_data: Dictionary = content_db.get_item(item_id)
	return RefinementCalculatorScript.apply_refinement_to_item_data(item_data, slot_data)


func _get_content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")
