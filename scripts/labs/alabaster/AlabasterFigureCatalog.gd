extends RefCounted
class_name AlabasterFigureCatalog

const LIBRARY_PATH := "res://data/labs/alabaster/figure_library.json"
static var _cache: Dictionary = {}


static func load_library(force_reload := false) -> Dictionary:
	if not force_reload and not _cache.is_empty():
		return _cache.duplicate(true)
	if not FileAccess.file_exists(LIBRARY_PATH):
		push_warning("AlabasterFigureCatalog: missing %s" % LIBRARY_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY_PATH))
	if not parsed is Dictionary:
		push_error("AlabasterFigureCatalog: invalid figure library JSON")
		return {}
	_cache = (parsed as Dictionary).duplicate(true)
	return _cache.duplicate(true)


static func get_family(family_name: String) -> Dictionary:
	var library := load_library()
	var value: Variant = library.get(family_name, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func get_entry(family_name: String, entry_id: String) -> Dictionary:
	var family := get_family(family_name)
	var value: Variant = family.get(entry_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func get_ids(family_name: String) -> Array[String]:
	var result: Array[String] = []
	var family := get_family(family_name)
	for value in family.keys():
		result.append(str(value))
	result.sort()
	return result


static func has_entry(family_name: String, entry_id: String) -> bool:
	return get_family(family_name).has(entry_id)
