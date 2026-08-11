extends RefCounted
class_name AlabasterMixamoRetargetProfile

const FOLD_PREFIX := "@fold:"

# One visible owner per Alabaster bone. Intermediate Mixamo bones are folded
# into a target chain instead of being independently written to the same bone.
const AUTO_MAP := {
	"root": "root",
	"hips": "bottom",
	"spine": "@fold:top",
	"spine1": "@fold:top",
	"spine2": "top",
	"neck": "@fold:head",
	"head": "head",
	"headtopend": "",
	"leftshoulder": "@fold:shoulderL",
	"leftarm": "shoulderL",
	"leftforearm": "armL",
	"lefthand": "handL",
	"lefthandindex1": "fingerL",
	"lefthandindex2": "",
	"lefthandindex3": "",
	"lefthandindex4": "",
	"rightshoulder": "@fold:shoulderR",
	"rightarm": "shoulderR",
	"rightforearm": "armR",
	"righthand": "handR",
	"righthandindex1": "fingerR",
	"righthandindex2": "",
	"righthandindex3": "",
	"righthandindex4": "",
	"leftupleg": "hipL",
	"leftleg": "legL",
	"leftfoot": "footL",
	"lefttoebase": "toeL",
	"lefttoeend": "",
	"rightupleg": "hipR",
	"rightleg": "legR",
	"rightfoot": "footR",
	"righttoebase": "toeR",
	"righttoeend": "",
}

# Mixamo Hips owns the Spine tree; Alabaster top/bottom are siblings. Therefore
# Hips must contribute to both bottom and the collapsed upper-body chain.
const TARGET_CHAINS := {
	"root": ["root"],
	"bottom": ["hips"],
	"top": ["hips", "spine", "spine1", "spine2"],
	"head": ["neck", "head"],
	"shoulderL": ["leftshoulder", "leftarm"],
	"armL": ["leftforearm"],
	"handL": ["lefthand"],
	"fingerL": ["lefthandindex1"],
	"shoulderR": ["rightshoulder", "rightarm"],
	"armR": ["rightforearm"],
	"handR": ["righthand"],
	"fingerR": ["righthandindex1"],
	"hipL": ["leftupleg"],
	"legL": ["leftleg"],
	"footL": ["leftfoot"],
	"toeL": ["lefttoebase"],
	"hipR": ["rightupleg"],
	"legR": ["rightleg"],
	"footR": ["rightfoot"],
	"toeR": ["righttoebase"],
}

static func normalize(value: String) -> String:
	return value.to_lower().replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "").replace(" ", "").replace("-", "").replace("_", "")

static func detect(source_bones: Array[String]) -> bool:
	var names := {}
	for bone_name in source_bones:
		names[normalize(bone_name)] = true
	for required in ["hips", "spine", "leftarm", "rightarm", "leftupleg", "rightupleg"]:
		if not names.has(required):
			return false
	return true

static func make_auto_map(source_bones: Array[String]) -> Dictionary:
	var result := {}
	for source_bone in source_bones:
		result[source_bone] = str(AUTO_MAP.get(normalize(source_bone), ""))
	return result
