extends RefCounted
class_name AlabasterMixamoRetargetProfile

const FOLD_PREFIX := "@fold:"

# Mixamo and Alabaster do NOT have the same hierarchy.
#
# Mixamo Hips is the common parent of both spine and legs. In Alabaster that
# semantic role belongs to `root`, because `top` and `bottom` are both children
# of root. Mapping Hips -> bottom (the old profile) forced the whole torso and
# leg tree through the pelvis child and was structurally wrong.
#
# AUTO FOLD rows are informational ownership markers for the smart converter.
# They do not independently write another transform to the destination bone.
const AUTO_MAP := {
	"root": "root",
	"hips": "root",
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
	# The Alabaster finger sprite is too coarse to benefit from Mixamo's finger
	# chain. Keep it rigidly parented to the hand instead of importing noisy hand
	# articulation into a single 8 px part.
	"lefthandindex1": "",
	"lefthandindex2": "",
	"lefthandindex3": "",
	"lefthandindex4": "",
	"rightshoulder": "@fold:shoulderR",
	"rightarm": "shoulderR",
	"rightforearm": "armR",
	"righthand": "handR",
	"righthandindex1": "",
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

# Track-only fallback for AnimationLibrary sources that do not expose a
# Skeleton3D. Packed Mixamo FBX/GLB should use AlabasterMixamoRestSpaceConverter
# instead. Notice that Hips is now owned by root, and top receives only the
# relative spine chain, preventing the old double-Hips rotation.
const TARGET_CHAINS := {
	"root": ["hips"],
	"top": ["spine", "spine1", "spine2"],
	"head": ["neck", "head"],
	"shoulderL": ["leftshoulder", "leftarm"],
	"armL": ["leftforearm"],
	"handL": ["lefthand"],
	"shoulderR": ["rightshoulder", "rightarm"],
	"armR": ["rightforearm"],
	"handR": ["righthand"],
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
