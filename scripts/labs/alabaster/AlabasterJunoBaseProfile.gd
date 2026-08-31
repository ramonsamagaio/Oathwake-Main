extends RefCounted
class_name AlabasterJunoBaseProfile

const PROFILE_ID := "juno_base"
const LABEL := "JUNO BASE"

# Intentionally small player-facing bank. These clips cover locomotion,
# survivability, a basic magic gesture and the sword combat family without
# dragging Juno's cutscene/emote/alternate-weapon sprite variants into the base
# character authoring sheet.
const CORE_GROUPS := {
	"locomotion": ["idle", "walk", "run", "dash", "idleJump1"],
	"combat": [
		"damage", "dead", "guard", "guardParry",
		"atkSwordN1", "atkSwordN2", "atkSwordNFinisher",
		"atkSwordTripleSlash", "atkSwordCrossStrike",
	],
	"utility": ["respawn", "castPoint"],
}


static func core_animation_names() -> Array[String]:
	var result: Array[String] = []
	for group_value in CORE_GROUPS.values():
		if not group_value is Array:
			continue
		for name_value in group_value as Array:
			var animation_name := str(name_value)
			if not animation_name.is_empty() and not result.has(animation_name):
				result.append(animation_name)
	return result


static func filter_animation_bank(source: Dictionary) -> Dictionary:
	var result := {}
	for animation_name in core_animation_names():
		var value: Variant = source.get(animation_name, {})
		if value is Dictionary and not (value as Dictionary).is_empty():
			result[animation_name] = (value as Dictionary).duplicate(true)
	return result
