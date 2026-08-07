extends SceneTree

const DATA_PATH := "res://data/labs/alabaster/juno_runtime.json.gz.b64"
const FULL_RUNTIME_MAX_BYTES := 8 * 1024 * 1024
const MIN_EXPECTED_ANIMATIONS := 400
const REQUIRED_ANIMATIONS := [
	"idle", "walk", "run",
	"idleJump1", "damage", "dead", "guard", "guardParry", "respawn",
	"atkSwordN1", "atkSwordN2", "atkSwordNFinisher",
	"atkSwordTripleSlash", "atkSwordCrossStrike",
	"atkHammer1fast", "atkHammer2", "atkHammer3",
	"atkSpear1", "atkTonfa1-punch", "castPoint",
]
const ATLAS_PARTS := [
	"res://data/labs/alabaster/juno_atlas_00.part",
	"res://data/labs/alabaster/juno_atlas_01.part",
	"res://data/labs/alabaster/juno_atlas_02.part",
	"res://data/labs/alabaster/juno_atlas_03.part"
]
const LAB_PATH := "res://scenes/labs/alabaster/AlabasterMechanicLab.tscn"


func _init() -> void:
	var failures: Array[String] = []
	var parsed: Variant = null
	if not FileAccess.file_exists(DATA_PATH):
		failures.append("missing runtime source %s" % DATA_PATH)
	else:
		var compressed := Marshalls.base64_to_raw(FileAccess.get_file_as_string(DATA_PATH).strip_edges())
		var raw := compressed.decompress_dynamic(FULL_RUNTIME_MAX_BYTES, FileAccess.COMPRESSION_GZIP)
		if raw.is_empty():
			failures.append("runtime source failed to decompress")
		else:
			parsed = JSON.parse_string(raw.get_string_from_utf8())
			if typeof(parsed) != TYPE_DICTIONARY:
				failures.append("runtime JSON does not parse")

	for atlas_path in ATLAS_PARTS:
		if not FileAccess.file_exists(atlas_path):
			failures.append("missing atlas part %s" % atlas_path)

	if typeof(parsed) == TYPE_DICTIONARY:
		var figure: Dictionary = (parsed as Dictionary).get("figure", {})
		var nodes: Dictionary = figure.get("nodes", {})
		var anims: Dictionary = figure.get("anims", {})
		for required_node in ["root", "top", "head", "armL", "armR", "bottom", "legL", "legR", "footL", "footR"]:
			if not nodes.has(required_node):
				failures.append("missing node %s" % required_node)
		if anims.size() < MIN_EXPECTED_ANIMATIONS:
			failures.append("full animation catalog missing: expected at least %d, found %d" % [MIN_EXPECTED_ANIMATIONS, anims.size()])
		for required_anim in REQUIRED_ANIMATIONS:
			if not anims.has(required_anim):
				failures.append("missing animation %s" % required_anim)

	var packed := load(LAB_PATH) as PackedScene
	if packed == null:
		failures.append("lab scene failed to load")
	else:
		var instance := packed.instantiate()
		if instance == null:
			failures.append("lab scene failed to instantiate")
		else:
			instance.free()

	if failures.is_empty():
		print("ALABASTER_MECHANIC_VALIDATION_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("ALABASTER_MECHANIC_VALIDATION_FAILURE: %s" % failure)
		quit(1)
