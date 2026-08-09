extends RefCounted
class_name AlabasterSharedActions

# Canonical public animation namespace shared by the mechanic lab and gameplay.
# Dummy/Male install Juno animations under these exact names on
# AlabasterPlayableSkinRig, so no lab-only alias is required.
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

const QUICK_KEYS := {
	KEY_SPACE: "idleJump1",
	KEY_H: "damage",
	KEY_K: "dead",
	KEY_G: "guard",
	KEY_P: "guardParry",
	KEY_X: "respawn",
	KEY_C: "castPoint",
	KEY_1: "atkSwordN1",
	KEY_2: "atkSwordN2",
	KEY_3: "atkSwordNFinisher",
	KEY_4: "atkSwordTripleSlash",
	KEY_5: "atkSwordCrossStrike",
	KEY_6: "atkHammer1fast",
	KEY_7: "atkHammer2",
	KEY_8: "atkHammer3",
	KEY_9: "atkSpear1",
	KEY_0: "atkTonfa1-punch",
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

const LAB_ACTION_ANIMATIONS := [
	"idleJump1", "damage", "dead", "guard", "guardParry", "respawn", "castPoint",
	"atkSwordN1", "atkSwordN2", "atkSwordNFinisher", "atkSwordTripleSlash", "atkSwordCrossStrike",
	"atkHammer1fast", "atkHammer2", "atkHammer3", "atkSpear1", "atkTonfa1-punch",
]


static func animation_for_action(action_name: String) -> String:
	return str(ACTION_TO_ANIMATION.get(action_name, ""))


static func gameplay_action_map() -> Dictionary:
	return GAMEPLAY_ACTIONS.duplicate(true)


static func missing_lab_actions(rig: Object) -> Array[String]:
	var missing: Array[String] = []
	for animation_name_value in LAB_ACTION_ANIMATIONS:
		var animation_name := str(animation_name_value)
		if rig == null or not rig.has_method("has_animation") or not bool(rig.call("has_animation", animation_name)):
			missing.append(animation_name)
	return missing
