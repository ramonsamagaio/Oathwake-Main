extends RefCounted
class_name AlabasterMixamoRetargetProfile

const FOLD_PREFIX := "@fold:"

# Mixamo and Alabaster do NOT have anatomical 1:1 bone names.
#
# Default/Dummy semantics discovered from the actual node.position hierarchy:
#   shoulderL/R = attachment pivot, not upper arm
#   armL/R      = upper arm
#   handL/R     = forearm endpoint / hand sprite
#   hipL/R      = attachment pivot, not thigh
#   legL/R      = thigh
#   footL/R     = shin endpoint / foot sprite
#   toeL/R      = foot/toe segment
#
# AUTO FOLD means the source bone contributes to the semantic solve but does not
# independently overwrite another Alabaster bone. V4 intentionally keeps the
# shoulder and hip attachment pivots stabilized to torso/pelvis; the main limb
# motion begins at armL/R and legL/R.
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

# Lower-fidelity track-only fallback for resources that expose no Skeleton3D.
# Raw FBX/GLB should use the Anatomical V4 converter instead.
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
