extends RefCounted
class_name AlabasterSourceImporter

const EXPECTED_ANIMATIONS := 419
# Repository-local sources only. Runtime must never depend on a user's Steam
# installation. When a raw juno.json is absent, AlabasterAnimationBank supplies
# the committed packed 419-animation bank instead.
const CANDIDATES := [
	"res://data/labs/alabaster/characters/juno.json",
	"res://data/labs/alabaster/source/juno.json",
	"res://data/labs/alabaster/juno.json",
	"res://terra/data/figures/char/player/juno.json",
	"res://data/figures/char/player/juno.json",
]


static func load_juno_animations() -> Dictionary:
	for source_path_variant in CANDIDATES:
		var anims := load_juno_animations_from_path(String(source_path_variant), false)
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
			push_warning("AlabasterSourceImporter: selected file is not a valid Juno figure JSON: %s" % source_path)
		return {}

	var root: Dictionary = parsed
	var figures_variant: Variant = root.get("figures", {})
	if typeof(figures_variant) != TYPE_DICTIONARY:
		if report_error:
			push_warning("AlabasterSourceImporter: JSON has no figures dictionary: %s" % source_path)
		return {}
	var figures: Dictionary = figures_variant
	var default_variant: Variant = figures.get("default", {})
	if typeof(default_variant) != TYPE_DICTIONARY:
		if report_error:
			push_warning("AlabasterSourceImporter: JSON has no figures.default: %s" % source_path)
		return {}
	var default_figure: Dictionary = default_variant
	var anims_variant: Variant = default_figure.get("anims", {})
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


static func get_expected_locations() -> String:
	return " | ".join(CANDIDATES)
