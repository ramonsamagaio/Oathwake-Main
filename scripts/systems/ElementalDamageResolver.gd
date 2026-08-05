extends RefCounted

const ELEMENT_PHYSICAL := "physical"
const ELEMENT_FIRE := "fire"
const ELEMENT_POISON := "poison"
const ELEMENT_FROST := "frost"
const ELEMENT_LIGHTNING := "lightning"
const ELEMENT_ARCANE := "arcane"

const ELEMENT_COLORS := {
	ELEMENT_PHYSICAL: Color(0.95, 0.90, 0.82, 1.0),
	ELEMENT_FIRE: Color(1.0, 0.38, 0.10, 1.0),
	ELEMENT_POISON: Color(0.42, 0.92, 0.24, 1.0),
	ELEMENT_FROST: Color(0.38, 0.82, 1.0, 1.0),
	ELEMENT_LIGHTNING: Color(0.95, 0.86, 0.30, 1.0),
	ELEMENT_ARCANE: Color(0.72, 0.42, 1.0, 1.0),
}


static func normalize_element(element: Variant) -> String:
	var value := str(element).strip_edges().to_lower()
	match value:
		"fire", "flame", "burn", "burning":
			return ELEMENT_FIRE
		"poison", "poisoned", "toxic", "nature":
			return ELEMENT_POISON
		"ice", "cold", "frost", "chilled", "frozen":
			return ELEMENT_FROST
		"electric", "shock", "shocked", "lightning":
			return ELEMENT_LIGHTNING
		"magic", "arcane", "void":
			return ELEMENT_ARCANE
		_:
			return ELEMENT_PHYSICAL


static func resolve_damage(base_amount: float, element: Variant, target_data: Dictionary = {}) -> int:
	if base_amount <= 0.0:
		return 0
	var normalized := normalize_element(element)
	var resistance := get_resistance(target_data, normalized)
	return maxi(int(round(base_amount * (1.0 - resistance))), 0)


static func get_resistance(target_data: Dictionary, element: Variant) -> float:
	var normalized := normalize_element(element)
	var value := _read_resistance_map(target_data.get("elemental_resistances", {}), normalized)
	if is_nan(value):
		value = _read_resistance_map(target_data.get("resistances", {}), normalized)
	if is_nan(value):
		var base_stats_value: Variant = target_data.get("base_stats", {})
		if base_stats_value is Dictionary:
			value = _read_resistance_map((base_stats_value as Dictionary).get("elemental_resistances", {}), normalized)
	if is_nan(value):
		value = 0.0
	if absf(value) > 1.0:
		value /= 100.0
	return clampf(value, -0.75, 0.90)


static func get_element_color(element: Variant) -> Color:
	return ELEMENT_COLORS.get(normalize_element(element), ELEMENT_COLORS[ELEMENT_PHYSICAL])


static func _read_resistance_map(map_value: Variant, element: String) -> float:
	if not map_value is Dictionary:
		return NAN
	var resistance_map := map_value as Dictionary
	if resistance_map.has(element):
		return float(resistance_map[element])
	var percent_key := "%s_percent" % element
	if resistance_map.has(percent_key):
		return float(resistance_map[percent_key]) / 100.0
	return NAN
