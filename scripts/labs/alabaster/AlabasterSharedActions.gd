extends RefCounted
class_name AlabasterSharedActions

# Canonical public animation namespace shared by the mechanic lab and gameplay.
# Preferred names are the names we expect from Juno. The resolver below also
# searches the active rig catalog, because the 419-animation source contains
# historical naming variants and preview hotkeys must not silently die because
# one authored clip has a slightly different name.
const ACTION_TO_ANIMATION := {
	"idle": "idle",
	"walk": "walk",
	"run": "run",
	"jump": "idleJump1",
	"hurt": "damage",
	"death": "dead",
	"block": "guard",
	"parry": "guardParry",
	"respawn": "respawn",
	"cast": "castPoint",
	"dash": "dash",
	"attack": "atkSwordN1",
	"sword_1": "atkSwordN1",
	"sword_2": "atkSwordN2",
	"sword_finisher": "atkSwordNFinisher",
	"sword_triple": "atkSwordTripleSlash",
	"sword_cross": "atkSwordCrossStrike",
	"hammer_1": "atkHammer1fast",
	"hammer_2": "atkHammer2",
	"hammer_3": "atkHammer3",
	"spear_1": "atkSpear1",
	"tonfa_1": "atkTonfa1-punch",
}

# Keys map to semantic actions. The mechanic lab resolves those actions against
# the animation catalog of whichever figure is active.
const QUICK_ACTIONS := {
	KEY_SPACE: "jump",
	KEY_H: "hurt",
	KEY_K: "death",
	KEY_G: "block",
	KEY_P: "parry",
	KEY_X: "respawn",
	KEY_C: "cast",
	KEY_1: "sword_1",
	KEY_2: "sword_2",
	KEY_3: "sword_finisher",
	KEY_4: "sword_triple",
	KEY_5: "sword_cross",
	KEY_6: "hammer_1",
	KEY_7: "hammer_2",
	KEY_8: "hammer_3",
	KEY_9: "spear_1",
	KEY_0: "tonfa_1",
	KEY_KP_1: "sword_1",
	KEY_KP_2: "sword_2",
	KEY_KP_3: "sword_finisher",
	KEY_KP_4: "sword_triple",
	KEY_KP_5: "sword_cross",
	KEY_KP_6: "hammer_1",
	KEY_KP_7: "hammer_2",
	KEY_KP_8: "hammer_3",
	KEY_KP_9: "spear_1",
	KEY_KP_0: "tonfa_1",
}

const GAMEPLAY_ACTIONS := {
	"idle": "idle",
	"walk": "walk",
	"run": "run",
	"attack": "atkSwordN1",
	"block": "guard",
	"death": "dead",
	"hurt": "damage",
	"dash": "dash",
}

const LAB_ACTIONS := [
	"jump", "hurt", "death", "block", "parry", "respawn", "cast",
	"sword_1", "sword_2", "sword_finisher", "sword_triple", "sword_cross",
	"hammer_1", "hammer_2", "hammer_3", "spear_1", "tonfa_1",
]

const ACTION_EXACT_CANDIDATES := {
	"jump": ["idleJump1", "jump", "jump1", "idleJump"],
	"hurt": ["damage", "hurt", "hit"],
	"death": ["dead", "death", "laying"],
	"block": ["guard", "block", "guardIdle"],
	"parry": ["guardParry", "parry", "guard-parry"],
	"respawn": ["respawn", "revive", "getUp"],
	"cast": ["castPoint", "cast", "casting"],
	"attack": ["atkSwordN1", "attack", "punch"],
	"sword_1": ["atkSwordN1", "atkSword1"],
	"sword_2": ["atkSwordN2", "atkSword2"],
	"sword_finisher": ["atkSwordNFinisher", "atkSwordFinisher"],
	"sword_triple": ["atkSwordTripleSlash", "atkSwordTriple"],
	"sword_cross": ["atkSwordCrossStrike", "atkSwordCross"],
	"hammer_1": ["atkHammer1fast", "atkHammer1", "atkHammerN1"],
	"hammer_2": ["atkHammer2", "atkHammerN2"],
	"hammer_3": ["atkHammer3", "atkHammerN3"],
	"spear_1": ["atkSpear1", "atkSpearN1"],
	"tonfa_1": ["atkTonfa1-punch", "atkTonfa1", "atkTonfaN1"],
}

const ACTION_TOKEN_GROUPS := {
	"jump": [["jump"]],
	"hurt": [["damage"], ["hurt"]],
	"death": [["dead"], ["death"], ["laying"]],
	"block": [["guard"], ["block"]],
	"parry": [["parry"]],
	"respawn": [["respawn"], ["revive"], ["getup"]],
	"cast": [["cast"]],
	"attack": [["sword", "n1"], ["sword", "1"], ["punch"]],
	"sword_1": [["sword", "n1"], ["sword", "1"]],
	"sword_2": [["sword", "n2"], ["sword", "2"]],
	"sword_finisher": [["sword", "finisher"]],
	"sword_triple": [["sword", "triple"]],
	"sword_cross": [["sword", "cross"]],
	"hammer_1": [["hammer", "1"]],
	"hammer_2": [["hammer", "2"]],
	"hammer_3": [["hammer", "3"]],
	"spear_1": [["spear", "1"], ["spear"]],
	"tonfa_1": [["tonfa", "1"], ["tonfa"]],
}

const FAMILY_ORDINAL := {
	"sword_1": ["sword", 0],
	"sword_2": ["sword", 1],
	"sword_finisher": ["sword", 2],
	"sword_triple": ["sword", 3],
	"sword_cross": ["sword", 4],
	"hammer_1": ["hammer", 0],
	"hammer_2": ["hammer", 1],
	"hammer_3": ["hammer", 2],
	"spear_1": ["spear", 0],
	"tonfa_1": ["tonfa", 0],
}


static func animation_for_action(action_name: String) -> String:
	return str(ACTION_TO_ANIMATION.get(action_name, ""))


static func gameplay_action_map() -> Dictionary:
	return GAMEPLAY_ACTIONS.duplicate(true)


static func resolve_action_animation(rig: Object, action_name: String) -> String:
	if rig == null or not rig.has_method("has_animation"):
		return ""

	var preferred := animation_for_action(action_name)
	if not preferred.is_empty() and bool(rig.call("has_animation", preferred)):
		return preferred

	var exact_value: Variant = ACTION_EXACT_CANDIDATES.get(action_name, [])
	if exact_value is Array:
		for candidate_value in exact_value as Array:
			var candidate := str(candidate_value)
			if bool(rig.call("has_animation", candidate)):
				return candidate

	var catalog_names := _catalog_names(rig)
	var token_groups_value: Variant = ACTION_TOKEN_GROUPS.get(action_name, [])
	if token_groups_value is Array:
		for group_value in token_groups_value as Array:
			if not group_value is Array:
				continue
			var match := _first_token_match(catalog_names, group_value as Array)
			if not match.is_empty():
				return match

	var family_value: Variant = FAMILY_ORDINAL.get(action_name, [])
	if family_value is Array and (family_value as Array).size() >= 2:
		var family := str((family_value as Array)[0])
		var ordinal := int((family_value as Array)[1])
		var family_matches: Array[String] = []
		for name in catalog_names:
			if _normalized(name).contains(_normalized(family)):
				family_matches.append(name)
		family_matches.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		if ordinal >= 0 and ordinal < family_matches.size():
			return family_matches[ordinal]

	# A normal attack should always remain testable in the lab. If no sword-ish
	# clip exists, use the first COMBAT clip instead of making LMB look dead.
	if action_name == "attack" and rig.has_method("get_animation_catalog"):
		var catalog_value: Variant = rig.call("get_animation_catalog")
		if catalog_value is Array:
			for entry_value in catalog_value as Array:
				if entry_value is Dictionary and str((entry_value as Dictionary).get("category", "")) == "COMBAT":
					return str((entry_value as Dictionary).get("name", ""))
	return ""


static func missing_lab_actions(rig: Object) -> Array[String]:
	var missing: Array[String] = []
	for action_name in LAB_ACTIONS:
		if resolve_action_animation(rig, action_name).is_empty():
			missing.append(action_name)
	return missing


static func resolved_lab_actions(rig: Object) -> Dictionary:
	var result := {}
	for action_name in LAB_ACTIONS:
		result[action_name] = resolve_action_animation(rig, action_name)
	return result


static func _catalog_names(rig: Object) -> Array[String]:
	var result: Array[String] = []
	if rig == null or not rig.has_method("get_animation_catalog"):
		return result
	var catalog_value: Variant = rig.call("get_animation_catalog")
	if not catalog_value is Array:
		return result
	for entry_value in catalog_value as Array:
		if entry_value is Dictionary:
			var name := str((entry_value as Dictionary).get("name", ""))
			if not name.is_empty():
				result.append(name)
	return result


static func _first_token_match(names: Array[String], token_values: Array) -> String:
	var normalized_tokens: Array[String] = []
	for token_value in token_values:
		normalized_tokens.append(_normalized(str(token_value)))
	var matches: Array[String] = []
	for name in names:
		var normalized_name := _normalized(name)
		var all_match := true
		for token in normalized_tokens:
			if not normalized_name.contains(token):
				all_match = false
				break
		if all_match:
			matches.append(name)
	matches.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return matches[0] if not matches.is_empty() else ""


static func _normalized(value: String) -> String:
	return value.to_lower().replace("_", "").replace("-", "").replace(" ", "")
