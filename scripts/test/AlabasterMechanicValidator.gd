extends SceneTree

const DATA_PATH := "res://data/labs/alabaster/juno_runtime.json.gz.b64"
const FULL_RUNTIME_MAX_BYTES := 8 * 1024 * 1024
const FULL_ANIMATION_MAX_BYTES := 64 * 1024 * 1024
const FULL_ANIMATION_PARTS := [
	"res://data/labs/alabaster/anims/juno_anims_bin_00.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_01.part",
]
const MIN_EXPECTED_ANIMATIONS := 419
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
		var parsed_dict: Dictionary = parsed
		var figure: Dictionary = parsed_dict.get("figure", {})
		var nodes: Dictionary = figure.get("nodes", {})
		for required_node in ["root", "top", "head", "armL", "armR", "bottom", "legL", "legR", "footL", "footR"]:
			if not nodes.has(required_node):
				failures.append("missing node %s" % required_node)

	var anims := _load_full_animation_bank(failures)
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
		print("ALABASTER_MECHANIC_VALIDATION_OK animations=%d" % anims.size())
		quit(0)
	else:
		for failure in failures:
			push_error("ALABASTER_MECHANIC_VALIDATION_FAILURE: %s" % failure)
		quit(1)


func _load_full_animation_bank(failures: Array[String]) -> Dictionary:
	var encoded := ""
	for part_path_variant in FULL_ANIMATION_PARTS:
		var part_path := String(part_path_variant)
		if not FileAccess.file_exists(part_path):
			failures.append("missing full animation part %s" % part_path)
			return {}
		encoded += FileAccess.get_file_as_string(part_path).strip_edges()

	var compressed := Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		failures.append("full animation bank base64 decode failed")
		return {}

	var raw := compressed.decompress_dynamic(FULL_ANIMATION_MAX_BYTES, FileAccess.COMPRESSION_ZSTD)
	if raw.is_empty():
		failures.append("full animation bank ZSTD decode failed")
		return {}

	var parsed_json: Variant = JSON.parse_string(raw.get_string_from_utf8())
	var anims := _extract_animation_dictionary(parsed_json)
	if not anims.is_empty():
		return anims

	var parsed_variant: Variant = bytes_to_var(raw)
	anims = _extract_animation_dictionary(parsed_variant)
	if anims.is_empty():
		failures.append("full animation bank decoded but contained no animation dictionary")
	return anims


func _extract_animation_dictionary(payload: Variant) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	var root: Dictionary = payload
	if root.has("figure"):
		var figure_variant: Variant = root.get("figure", {})
		if typeof(figure_variant) == TYPE_DICTIONARY:
			var figure_data: Dictionary = figure_variant
			var figure_anims: Variant = figure_data.get("anims", {})
			if typeof(figure_anims) == TYPE_DICTIONARY:
				var figure_anims_dict: Dictionary = figure_anims
				if not figure_anims_dict.is_empty():
					return figure_anims_dict
	var direct_anims: Variant = root.get("anims", null)
	if typeof(direct_anims) == TYPE_DICTIONARY:
		var direct_anims_dict: Dictionary = direct_anims
		if not direct_anims_dict.is_empty():
			return direct_anims_dict
	if root.has("idle") and root.has("walk") and root.has("run"):
		return root
	return {}
