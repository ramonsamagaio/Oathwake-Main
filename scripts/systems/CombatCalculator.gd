extends RefCounted

const DEFAULT_STATS := {
	"str": 5,
	"dex": 5,
	"agi": 5,
	"vit": 5,
	"wis": 5,
	"int": 5,
	"luk": 5,
}


func calculate_derived_stats(actor_data: Dictionary, held_item_data: Dictionary = {}) -> Dictionary:
	var level: int = int(actor_data.get("level", 1))
	var base_stats: Dictionary = _get_dictionary(actor_data, "base_stats")
	var base_combat: Dictionary = _get_dictionary(actor_data, "base_combat")
	var combat: Dictionary = _get_dictionary(held_item_data, "combat")

	var str_stat: float = _get_stat(base_stats, "str")
	var dex: float = _get_stat(base_stats, "dex")
	var agi: float = _get_stat(base_stats, "agi")
	var vit: float = _get_stat(base_stats, "vit")
	var wis: float = _get_stat(base_stats, "wis")
	var int_stat: float = _get_stat(base_stats, "int")
	var luk: float = _get_stat(base_stats, "luk")

	var base_max_hp := float(actor_data.get("max_health", base_combat.get("base_max_hp", 100.0)))
	var base_attack := float(base_combat.get("base_attack", actor_data.get("damage", 5.0)))
	var weapon_attack := float(combat.get("attack_power", 0.0))
	var scaling_bonus := _calculate_scaling_bonus(base_stats, _get_dictionary(combat, "stat_scaling"))
	var base_attack_cooldown := float(base_combat.get("attack_cooldown", actor_data.get("attack_cooldown", 1.0)))
	var cooldown_modifier: float = max(float(combat.get("attack_cooldown_modifier", 1.0)), 0.01)
	var attack_speed_bonus := float(base_combat.get("attack_speed_bonus", 0.0))
	attack_speed_bonus += float(actor_data.get("attack_speed_bonus", 0.0))
	attack_speed_bonus += float(held_item_data.get("attack_speed_bonus", 0.0))
	attack_speed_bonus += float(combat.get("attack_speed_bonus", 0.0))
	var attack_speed_divisor := maxf(1.0 + (agi * 0.01) + attack_speed_bonus, 0.05)
	var attack_cooldown := maxf((base_attack_cooldown * cooldown_modifier) / attack_speed_divisor, 0.06)

	var invulnerability_duration := float(base_combat.get("base_invulnerability_duration", actor_data.get("invulnerability_duration", 2.0)))
	invulnerability_duration += float(base_combat.get("invulnerability_duration_bonus", 0.0))
	invulnerability_duration += float(actor_data.get("invulnerability_duration_bonus", 0.0))
	invulnerability_duration += float(held_item_data.get("invulnerability_duration_bonus", 0.0))
	invulnerability_duration += float(combat.get("invulnerability_duration_bonus", 0.0))
	invulnerability_duration = maxf(invulnerability_duration, 0.0)

	return {
		"max_hp": base_max_hp + (vit * 10.0) + (level * 5.0),
		"physical_attack": base_attack + weapon_attack + (str_stat * 0.75) + (dex * 0.25) + (luk * 0.10) + scaling_bonus,
		"defense": float(base_combat.get("base_defense", 0.0)) + (vit * 0.55) + (agi * 0.12),
		"magic_defense": float(base_combat.get("base_magic_defense", 0.0)) + (wis * 0.65) + (int_stat * 0.22),
		"hit": float(base_combat.get("base_hit", 75.0)) + (dex * 1.1) + (luk * 0.2) + (level * 0.5),
		"flee": float(base_combat.get("base_flee", 5.0)) + (agi * 1.1) + (luk * 0.2) + (level * 0.3),
		"crit_chance": float(base_combat.get("base_crit_chance", 0.03)) + (luk * 0.0025) + float(combat.get("crit_chance_bonus", 0.0)),
		"crit_damage": float(base_combat.get("base_crit_damage", 1.5)) + (luk * 0.003) + float(combat.get("crit_damage_bonus", 0.0)),
		"attack_cooldown": attack_cooldown,
		"attack_speed": 1.0 / attack_cooldown,
		"invulnerability_duration": invulnerability_duration,
	}


func calculate_physical_attack(attacker_data: Dictionary, target_data: Dictionary, held_item_data: Dictionary = {}) -> Dictionary:
	return calculate_damage(attacker_data, target_data, held_item_data)


func get_damage_preview(attacker_data: Dictionary, held_item_data: Dictionary = {}) -> Dictionary:
	var derived: Dictionary = calculate_derived_stats(attacker_data, held_item_data)
	var base_stats: Dictionary = _get_dictionary(attacker_data, "base_stats")
	var combat: Dictionary = _get_dictionary(held_item_data, "combat")
	var raw_attack: float = float(derived.get("physical_attack", 1.0))
	var variance: float = float(combat.get("attack_variance", 0.15))
	var dex: float = _get_stat(base_stats, "dex")
	var min_multiplier_bonus: float = min(dex * 0.002, 0.10)
	var min_multiplier: float = min(1.0 - variance + min_multiplier_bonus, 1.0 + variance)
	var max_multiplier: float = 1.0 + variance
	return {
		"min_damage": max(int(round(raw_attack * min_multiplier)), 1),
		"max_damage": max(int(round(raw_attack * max_multiplier)), 1),
		"crit_chance": float(derived.get("crit_chance", 0.0)),
		"crit_damage": float(derived.get("crit_damage", 1.5)),
	}


func roll_hit(attacker_derived: Dictionary, target_derived: Dictionary) -> bool:
	var attacker_hit: float = float(attacker_derived.get("hit", 0.0))
	var target_flee: float = float(target_derived.get("flee", 0.0))
	var hit_chance: float = 0.75 + (attacker_hit - target_flee) * 0.005
	hit_chance = clamp(hit_chance, 0.15, 0.97)
	return randf() <= hit_chance


func roll_critical(attacker_derived: Dictionary, held_item_data: Dictionary = {}) -> bool:
	var crit_chance: float = clamp(float(attacker_derived.get("crit_chance", 0.0)), 0.0, 1.0)
	return randf() <= crit_chance


func calculate_damage(attacker_data: Dictionary, target_data: Dictionary, held_item_data: Dictionary = {}) -> Dictionary:
	var attacker_derived: Dictionary = calculate_derived_stats(attacker_data, held_item_data)
	var target_derived: Dictionary = calculate_derived_stats(target_data)
	var combat: Dictionary = _get_dictionary(held_item_data, "combat")
	var damage_type := str(combat.get("damage_type", attacker_data.get("damage_type", "physical"))).strip_edges().to_lower()
	if damage_type.is_empty():
		damage_type = "physical"

	var result := {
		"hit": false,
		"miss": true,
		"damage": 0,
		"is_critical": false,
		"damage_type": damage_type,
	}
	_copy_condition_payload(result, attacker_data, held_item_data, combat)
	if not roll_hit(attacker_derived, target_derived):
		return result

	var is_critical: bool = roll_critical(attacker_derived, held_item_data)
	var raw_attack: float = max(float(attacker_derived.get("physical_attack", 1.0)), 1.0)
	var defense_stat := "defense" if damage_type == "physical" else "magic_defense"
	var target_defense: float = max(float(target_derived.get(defense_stat, 0.0)), 0.0)
	var effective_defense: float = target_defense * (0.45 if is_critical else 1.0)
	var defense_ratio: float = 0.0
	if effective_defense > 0.0:
		defense_ratio = effective_defense / (effective_defense + max(raw_attack * 2.0, 8.0))
	defense_ratio = clamp(defense_ratio, 0.0, 0.75)
	var base_damage: float = max(1.0, raw_attack * (1.0 - defense_ratio))
	var variance: float = float(combat.get("attack_variance", 0.15))
	var dex: float = _get_stat(_get_dictionary(attacker_data, "base_stats"), "dex")
	var min_multiplier_bonus: float = min(dex * 0.002, 0.10)
	var min_multiplier: float = min(1.0 - variance + min_multiplier_bonus, 1.0 + variance)
	var variance_multiplier: float = randf_range(min_multiplier, 1.0 + variance)
	var damage: int = int(round(base_damage * variance_multiplier))
	if is_critical:
		damage = int(round(float(damage) * float(attacker_derived.get("crit_damage", 1.5))))
	damage = max(damage, 1)

	result["hit"] = true
	result["miss"] = false
	result["damage"] = damage
	result["is_critical"] = is_critical
	return result


func _copy_condition_payload(result: Dictionary, attacker_data: Dictionary, held_item_data: Dictionary, combat: Dictionary) -> void:
	var conditions: Variant = combat.get("conditions", held_item_data.get("conditions", attacker_data.get("conditions", [])))
	if conditions is Array or conditions is Dictionary:
		result["conditions"] = conditions
	var condition_id := str(combat.get("condition", held_item_data.get("condition", attacker_data.get("condition", ""))))
	if condition_id.is_empty():
		return
	result["condition"] = condition_id
	result["condition_duration"] = float(combat.get("condition_duration", held_item_data.get("condition_duration", attacker_data.get("condition_duration", -1.0))))
	result["condition_potency"] = float(combat.get("condition_potency", held_item_data.get("condition_potency", attacker_data.get("condition_potency", 1.0))))


func _calculate_scaling_bonus(base_stats: Dictionary, stat_scaling: Dictionary) -> float:
	var bonus := 0.0
	for stat_name in stat_scaling.keys():
		bonus += _get_stat(base_stats, str(stat_name)) * float(stat_scaling[stat_name])
	return bonus


func _get_stat(base_stats: Dictionary, stat_name: String) -> float:
	return float(base_stats.get(stat_name, DEFAULT_STATS.get(stat_name, 5)))


func _get_dictionary(data: Dictionary, key: String) -> Dictionary:
	var value = data.get(key, {})
	if value is Dictionary:
		return value
	return {}
