extends RefCounted


func get_tier_modifier(resource_tier: int, tool_tier: int) -> float:
	var tier_difference: int = resource_tier - tool_tier
	if tier_difference <= -2:
		return 1.5
	if tier_difference == -1:
		return 1.25
	if tier_difference == 0:
		return 1.0
	if tier_difference == 1:
		return 0.6
	if tier_difference == 2:
		return 0.25
	return 0.0


func can_damage_resource(resource_data: Dictionary, tool_data: Dictionary) -> bool:
	return bool(calculate_gather_damage(resource_data, tool_data).get("can_damage", false))


func calculate_gather_damage(resource_data: Dictionary, tool_data: Dictionary, actor_data: Dictionary = {}, skill_data: Dictionary = {}) -> Dictionary:
	var resource_tier: int = int(resource_data.get("resource_tier", 1))
	var tool_tier: int = int(tool_data.get("tool_tier", tool_data.get("tier", 1)))
	var tool_type: String = str(tool_data.get("tool_type", "hands"))
	var required_tool_type: String = str(resource_data.get("required_tool_type", ""))
	var allow_hands: bool = bool(resource_data.get("allow_hands", resource_tier == 1 and required_tool_type.is_empty()))

	if not required_tool_type.is_empty() and tool_type != required_tool_type:
		if not (tool_type == "hands" and allow_hands and resource_tier == 1):
			return _blocked_result("Wrong tool type")

	var tier_modifier: float = get_tier_modifier(resource_tier, tool_tier)
	if tier_modifier <= 0.0:
		return _blocked_result("Tool tier too low")

	var tool_damage: float = float(tool_data.get("tool_damage", tool_data.get("damage", 1)))
	var skill_bonus: float = _get_skill_bonus(skill_data)
	var attribute_bonus: float = _get_attribute_bonus(str(resource_data.get("skill_type", "")), actor_data)
	var damage: float = (tool_damage * tier_modifier) + skill_bonus + attribute_bonus
	var is_critical: bool = _roll_tool_critical(tool_data)
	if is_critical:
		var crit_power: float = max(float(tool_data.get("crit_power", 1.5)), 1.0)
		damage *= crit_power
	var final_damage: int = max(int(round(damage)), 1)

	return {
		"can_damage": true,
		"damage": final_damage,
		"is_critical": is_critical,
		"tier_modifier": tier_modifier,
		"reason": "",
	}


func _blocked_result(reason: String) -> Dictionary:
	return {
		"can_damage": false,
		"damage": 0,
		"is_critical": false,
		"tier_modifier": 0.0,
		"reason": reason,
	}


func _get_skill_bonus(skill_data: Dictionary) -> float:
	if skill_data.is_empty():
		return 0.0

	return float(skill_data.get("skill_level", skill_data.get("level", 0))) * 0.2


func _get_attribute_bonus(skill_type: String, actor_data: Dictionary) -> float:
	var base_stats: Dictionary = _get_dictionary(actor_data, "base_stats")
	if base_stats.is_empty():
		return 0.0

	var str_stat: float = float(base_stats.get("str", 0.0))
	var dex: float = float(base_stats.get("dex", 0.0))
	var wis: float = float(base_stats.get("wis", 0.0))

	match skill_type:
		"mining":
			return (str_stat * 0.25) + (dex * 0.15)
		"lumbering":
			return (str_stat * 0.30) + (dex * 0.10)
		"farming":
			return (dex * 0.20) + (wis * 0.10)
		_:
			return 0.0


func _roll_tool_critical(tool_data: Dictionary) -> bool:
	var crit_chance: float = clamp(float(tool_data.get("crit_chance", 0.0)), 0.0, 1.0)
	return randf() <= crit_chance


func _get_dictionary(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	if value is Dictionary:
		return value
	return {}
