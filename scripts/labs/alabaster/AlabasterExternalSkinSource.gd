extends RefCounted
class_name AlabasterExternalSkinSource

const SourceImporter := preload("res://scripts/labs/alabaster/AlabasterSourceImporter.gd")

const PROFILE_FILES := {
	"male_dummy": ["dummy.json"],
	"male_temp": ["male-temp-01.json", "male-temp01.json"],
}
const PROFILE_FIGURES := {
	"male_dummy": "Male-Dummy",
	"male_temp": "Male-Temp-01",
}

static var _figure_cache: Dictionary = {}


static func load_skin_figure(profile_id: String) -> Dictionary:
	if _figure_cache.has(profile_id):
		var cached: Variant = _figure_cache[profile_id]
		if cached is Dictionary:
			return _runtime_figure_copy(cached as Dictionary)

	var file_names_value: Variant = PROFILE_FILES.get(profile_id, [])
	if not file_names_value is Array:
		return {}
	var file_names := file_names_value as Array
	var figure_name := str(PROFILE_FIGURES.get(profile_id, ""))
	if figure_name.is_empty():
		return {}

	# Juno already proves which Alabaster Dawn installation is available on the
	# current development machine. Reuse the same candidate roots and look for the
	# native Dummy/Male figure next to juno.json. This is intentionally a source
	# fallback, not a production dependency: packaged builds can still use the
	# embedded source assets when no demo installation exists.
	for juno_path_value in SourceImporter.CANDIDATES:
		var juno_path := str(juno_path_value)
		var base_dir := juno_path.get_base_dir()
		for file_name_value in file_names:
			var source_path := base_dir.path_join(str(file_name_value))
			var figure := _load_figure_from_path(source_path, figure_name)
			if not figure.is_empty():
				_figure_cache[profile_id] = figure
				print("ALABASTER_SKIN_EXTERNAL_SOURCE_OK profile=%s figure=%s source=%s nodes=%d anims=%d" % [
					profile_id,
					figure_name,
					source_path,
					(figure.get("nodes", {}) as Dictionary).size() if figure.get("nodes", {}) is Dictionary else 0,
					(figure.get("anims", {}) as Dictionary).size() if figure.get("anims", {}) is Dictionary else 0,
				])
				return _runtime_figure_copy(figure)

	return {}


static func clear_cache() -> void:
	_figure_cache.clear()


static func _load_figure_from_path(source_path: String, figure_name: String) -> Dictionary:
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {}
	var source_text := FileAccess.get_file_as_string(source_path)
	if source_text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(source_text) != OK:
		push_warning("AlabasterExternalSkinSource: invalid JSON source=%s line=%d error=%s" % [
			source_path,
			json.get_error_line(),
			json.get_error_message(),
		])
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {}
	var payload := parsed as Dictionary

	# Some supplied files are already the concrete figure at the root.
	if payload.get("nodes", {}) is Dictionary and payload.get("anims", {}) is Dictionary:
		if not (payload.get("nodes", {}) as Dictionary).is_empty():
			return _runtime_figure_copy(payload)

	# Other source files use the demo's normal { figures: { Name: figure } } wrapper.
	var figures_value: Variant = payload.get("figures", {})
	if not figures_value is Dictionary:
		return {}
	var figures := figures_value as Dictionary
	var figure_value: Variant = figures.get(figure_name, {})
	if figure_value is Dictionary and not (figure_value as Dictionary).is_empty():
		return _runtime_figure_copy(figure_value as Dictionary)
	return {}


static func _runtime_figure_copy(source: Dictionary) -> Dictionary:
	var result := source.duplicate(false)
	var nodes_value: Variant = source.get("nodes", {})
	result["nodes"] = (nodes_value as Dictionary).duplicate(false) if nodes_value is Dictionary else {}
	var anims_value: Variant = source.get("anims", {})
	result["anims"] = (anims_value as Dictionary).duplicate(false) if anims_value is Dictionary else {}
	return result
