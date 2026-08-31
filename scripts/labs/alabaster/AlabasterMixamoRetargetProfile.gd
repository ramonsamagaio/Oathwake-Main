extends RefCounted
class_name AlabasterMixamoRetargetProfile

const FOLD_PREFIX := "@fold:"

# Mixamo and the UAL/Unreal mannequin use different bone names, but both describe
# the same humanoid semantics consumed by the proven Juno V16 solver. UAL aliases
# are normalized to the canonical Mixamo semantic vocabulary BEFORE AUTO_MAP is
# evaluated. This deliberately reuses Claude's REST/handedness/foot-plane/runtime
# codec path instead of introducing a second lower-fidelity retargeter.
const UAL_ALIASES := {
	"pelvis": "hips",
	"spine_01": "spine",
	"spine_02": "spine1",
	"spine_03": "spine2",
	"neck_01": "neck",
	"head": "head",
	"clavicle_l": "leftshoulder",
	"upperarm_l": "leftarm",
	"lowerarm_l": "leftforearm",
	"hand_l": "lefthand",
	"index_01_l": "lefthandindex1",
	"clavicle_r": "rightshoulder",
	"upperarm_r": "rightarm",
	"lowerarm_r": "rightforearm",
	"hand_r": "righthand",
	"index_01_r": "righthandindex1",
	"thigh_l": "leftupleg",
	"calf_l": "leftleg",
	"foot_l": "leftfoot",
	"ball_l": "lefttoebase",
	"thigh_r": "rightupleg",
	"calf_r": "rightleg",
	"foot_r": "rightfoot",
	"ball_r": "righttoebase",
}

# Default/Dummy semantics discovered from the actual node.position hierarchy:
#   shoulderL/R = attachment pivot, not upper arm
#   armL/R      = upper arm
#   handL/R     = forearm endpoint / hand sprite
#   hipL/R      = attachment pivot, not thigh
#   legL/R      = thigh
#   footL/R     = shin endpoint / foot sprite
#   toeL/R      = foot/toe segment
const AUTO_MAP := {
	"root": "root",
	"hips": "root",
	"spine": "@fold:top",
	"spine1": "@fold:top",
	"spine2": "top",
	"neck": "@fold:head",
	"head": "head",
	"headtopend": "",

	"leftshoulder": "@fold:armL",
	"leftarm": "armL",
	"leftforearm": "handL",
	"lefthand": "@fold:fingerL",
	"lefthandindex1": "fingerL",
	"lefthandindex2": "",
	"lefthandindex3": "",
	"lefthandindex4": "",

	"rightshoulder": "@fold:armR",
	"rightarm": "armR",
	"rightforearm": "handR",
	"righthand": "@fold:fingerR",
	"righthandindex1": "fingerR",
	"righthandindex2": "",
	"righthandindex3": "",
	"righthandindex4": "",

	"leftupleg": "legL",
	"leftleg": "footL",
	"leftfoot": "@fold:toeL",
	"lefttoebase": "toeL",
	"lefttoeend": "",

	"rightupleg": "legR",
	"rightleg": "footR",
	"rightfoot": "@fold:toeR",
	"righttoebase": "toeR",
	"righttoeend": "",
}

const TARGET_CHAINS := {
	"root": ["hips"],
	"top": ["spine", "spine1", "spine2"],
	"head": ["neck", "head"],
	"armL": ["leftshoulder", "leftarm"],
	"handL": ["leftforearm"],
	"fingerL": ["lefthand", "lefthandindex1"],
	"armR": ["rightshoulder", "rightarm"],
	"handR": ["rightforearm"],
	"fingerR": ["righthand", "righthandindex1"],
	"legL": ["leftupleg"],
	"footL": ["leftleg"],
	"toeL": ["leftfoot", "lefttoebase"],
	"legR": ["rightupleg"],
	"footR": ["rightleg"],
	"toeR": ["rightfoot", "righttoebase"],
}

static func normalize(value: String) -> String:
	var clean := value.to_lower().replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "").replace(" ", "").replace("-", "")
	if UAL_ALIASES.has(clean):
		return str(UAL_ALIASES[clean])
	return clean.replace("_", "")

static func detect(source_bones: Array[String]) -> bool:
	var names := {}
	for bone_name in source_bones:
		names[normalize(bone_name)] = true
	for required in ["hips", "spine", "leftarm", "rightarm", "leftupleg", "rightupleg"]:
		if not names.has(required):
			return false
	return true

static func detect_ual(source_bones: Array[String]) -> bool:
	var raw := {}
	for bone_name in source_bones:
		raw[str(bone_name).to_lower().replace(" ", "").replace("-", "")] = true
	for required in ["pelvis", "spine_01", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"]:
		if not raw.has(required):
			return false
	return true

static func make_auto_map(source_bones: Array[String]) -> Dictionary:
	var result := {}
	for source_bone in source_bones:
		result[source_bone] = str(AUTO_MAP.get(normalize(source_bone), ""))
	return result
