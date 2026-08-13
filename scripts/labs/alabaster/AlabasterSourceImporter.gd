extends RefCounted
class_name AlabasterSourceImporter

const EXPECTED_ANIMATIONS := 419

# IMPORTANT: Alabaster ships more than one file named juno.json. The animation
# source we need is the FIGURE file from:
#   terra/data/figures/char/player/juno.json
# It has the schema figures.default.anims (419 clips).
#
# The large gameplay/character config also named juno.json contains keys such as
# base/actions/weapons/proxies and only REFERENCES animation names. It does not
# contain bone transforms and cannot be used as an animation bank.
const CANDIDATES := [
	"res://data/labs/alabaster/characters/juno-figure.json",
	"res://data/labs/alabaster/characters/juno.json",
	"res://data/labs/alabaster/source/juno.json",
	"res://data/labs/alabaster/juno.json",
	"res://terra/data/figures/char/player/juno.json",
	"res://data/figures/char/player/juno.json",
]

static var _warned_wrong_schema_paths: Dictionary = {}


static func load_juno_animations() -> Dictionary:
	for source_path_variant in CANDIDATES:
		var source_path := String(source_path_variant)
		var anims := load_juno_animations_from_path(source_path, false)
		if anims.size() == EXPECTED_ANIMATIONS:
			return anims
	return {}


static func load_juno_animations_from_path(source_path: String, report_error: bool = true) -> Dictionary:
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		if report_error:
			push_warning("AlabasterSourceImporter: file not found: %s" % source_path)
		return {}

	var source_text := FileAccess.get_file_as_string(source_path)
	if source_text.is_empty():
		if report_error:
			push_warning("AlabasterSourceImporter: file is empty or unreadable: %s" % source_path)
		return {}

	var parsed: Variant = JSON.parse_string(source_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		if report_error:
			push_warning("AlabasterSourceImporter: selected file is not valid JSON: %s" % source_path)
		return {}

	var root: Dictionary = parsed
	var figures_variant: Variant = root.get("figures", null)
	if typeof(figures_variant) != TYPE_DICTIONARY:
		_report_wrong_juno_schema(source_path, root, report_error)
		return {}
	var figures: Dictionary = figures_variant

	var default_variant: Variant = figures.get("default", null)
	if typeof(default_variant) != TYPE_DICTIONARY:
		if report_error:
			push_warning("AlabasterSourceImporter: Juno figure JSON has no figures.default: %s" % source_path)
		return {}
	var default_figure: Dictionary = default_variant

	var anims_variant: Variant = default_figure.get("anims", null)
	if typeof(anims_variant) != TYPE_DICTIONARY:
		if report_error:
			push_warning("AlabasterSourceImporter: figures.default has no anims dictionary: %s" % source_path)
		return {}
	var anims: Dictionary = anims_variant

	if anims.size() != EXPECTED_ANIMATIONS:
		if report_error:
			push_warning("AlabasterSourceImporter: expected %d animations, found %d in %s" % [EXPECTED_ANIMATIONS, anims.size(), source_path])
		return {}

	print("ALABASTER_SOURCE_JSON_OK animations=%d source=%s" % [anims.size(), source_path])
	return anims


static func _report_wrong_juno_schema(source_path: String, root: Dictionary, report_error: bool) -> void:
	var looks_like_gameplay_config := root.has("actions") or root.has("weapons") or root.has("proxies") or root.has("base")
	if looks_like_gameplay_config:
		if not _warned_wrong_schema_paths.has(source_path):
			_warned_wrong_schema_paths[source_path] = true
			push_warning(
				"AlabasterSourceImporter: %s is the Juno GAMEPLAY config, not the figure animation JSON. " +
				"Copy Alabaster Dawn Demo/terra/data/figures/char/player/juno.json instead; expected schema figures.default.anims with %d clips."
				% [source_path, EXPECTED_ANIMATIONS]
			)
	elif report_error:
		push_warning("AlabasterSourceImporter: JSON has no figures dictionary: %s" % source_path)


static func get_expected_locations() -> String:
	return " | ".join(CANDIDATES)