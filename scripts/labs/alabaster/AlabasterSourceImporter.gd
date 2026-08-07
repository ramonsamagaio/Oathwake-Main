extends RefCounted
class_name AlabasterSourceImporter

const EXPECTED_ANIMATIONS := 419
const RELATIVE_JUNO := "steamapps/common/Alabaster Dawn Demo/terra/data/figures/char/player/juno.json"
const CANDIDATES := [
	"C:/Program Files (x86)/Steam/" + RELATIVE_JUNO,
	"C:/Program Files/Steam/" + RELATIVE_JUNO,
	"D:/SteamLibrary/" + RELATIVE_JUNO,
	"E:/SteamLibrary/" + RELATIVE_JUNO,
	"F:/SteamLibrary/" + RELATIVE_JUNO,
	"res://data/labs/alabaster/source/juno.json",
]


static func load_juno_animations() -> Dictionary:
	for source_path_variant in CANDIDATES:
		var source_path := String(source_path_variant)
		if not FileAccess.file_exists(source_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var root: Dictionary = parsed
		var figures_variant: Variant = root.get("figures", {})
		if typeof(figures_variant) != TYPE_DICTIONARY:
			continue
		var figures: Dictionary = figures_variant
		var default_variant: Variant = figures.get("default", {})
		if typeof(default_variant) != TYPE_DICTIONARY:
			continue
		var default_figure: Dictionary = default_variant
		var anims_variant: Variant = default_figure.get("anims", {})
		if typeof(anims_variant) != TYPE_DICTIONARY:
			continue
		var anims: Dictionary = anims_variant
		if anims.size() == EXPECTED_ANIMATIONS:
			print("ALABASTER_SOURCE_JSON_OK animations=%d source=%s" % [anims.size(), source_path])
			return anims
	return {}


static func get_expected_locations() -> String:
	return " | ".join(CANDIDATES)
