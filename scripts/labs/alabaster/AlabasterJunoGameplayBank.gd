extends RefCounted
class_name AlabasterJunoGameplayBank

const AnimationBank := preload("res://scripts/labs/alabaster/AlabasterAnimationBank.gd")
const SourceImporter := preload("res://scripts/labs/alabaster/AlabasterSourceImporter.gd")

const RUNTIME_PATH := "res://data/labs/alabaster/juno_runtime.json.gz.b64"
const RUNTIME_MAX_BYTES := 8 * 1024 * 1024
const REQUIRED_LOCOMOTION := ["idle", "walk", "run"]
const SOCKET_NAMES := ["weaponR", "weaponL", "weaponBelt"]

static var _cache: Dictionary = {}
static var _runtime_figure_cache: Dictionary = {}
static var _last_source := "NONE"


static func load_gameplay_bank() -> Dictionary:
	if not _cache.is_empty():
		return _cache.duplicate(true)

	# The raw Alabaster figure JSON is authoritative when it is committed to the
	# repository. It contains figures.default.anims with all 419 authored clips and
	# avoids any ambiguity in the historical packed/chunk exports.
	var source_bank := SourceImporter.load_juno_animations()
	if source_bank.size() == SourceImporter.EXPECTED_ANIMATIONS:
		_cache = source_bank.duplicate(true)
		_last_source = "SOURCE_JSON"
		print("ALABASTER_JUNO_SHARED_BANK source=%s animations=%d" % [_last_source, _cache.size()])
		return _cache.duplicate(true)

	# Repository packed data remains a fully offline fallback for builds where the
	# raw source file is intentionally not distributed.
	var bank := AnimationBank.load_full_animation_bank()
	if bank.is_empty():
		push_warning("AlabasterJunoGameplayBank: repository-local Juno animation bank is empty.")
		_last_source = "NONE"
		return {}

	_cache = bank.duplicate(true)
	var diagnostics := AnimationBank.get_diagnostics()
	_last_source = str(diagnostics.get("source", "ANIMATION_BANK"))
	print("ALABASTER_JUNO_SHARED_BANK source=%s animations=%d" % [_last_source, _cache.size()])
	return _cache.duplicate(true)


static func load_locomotion_bank() -> Dictionary:
	var bank := load_gameplay_bank()
	var result := {}
	for clip in REQUIRED_LOCOMOTION:
		var value: Variant = bank.get(clip, null)
		if value is Dictionary and not (value as Dictionary).is_empty():
			result[clip] = (value as Dictionary).duplicate(true)
	return result


static func load_runtime_figure() -> Dictionary:
	if not _runtime_figure_cache.is_empty():
		return _runtime_figure_cache.duplicate(true)
	if not FileAccess.file_exists(RUNTIME_PATH):
		return {}
	var encoded := _normalize_base64(FileAccess.get_file_as_string(RUNTIME_PATH))
	if encoded.is_empty() or not _looks_like_base64(encoded):
		return {}
	var compressed := Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		return {}
	var raw := compressed.decompress_dynamic(RUNTIME_MAX_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary:
		return {}
	var figure_value: Variant = (parsed as Dictionary).get("figure", {})
	if not figure_value is Dictionary or (figure_value as Dictionary).is_empty():
		return {}
	_runtime_figure_cache = (figure_value as Dictionary).duplicate(true)
	return _runtime_figure_cache.duplicate(true)


static func load_socket_nodes() -> Dictionary:
	var result := {}
	var figure := load_runtime_figure()
	var nodes_value: Variant = figure.get("nodes", {})
	if not nodes_value is Dictionary:
		return result
	var nodes := nodes_value as Dictionary
	for socket_name in SOCKET_NAMES:
		var node_value: Variant = nodes.get(socket_name, {})
		if node_value is Dictionary and not (node_value as Dictionary).is_empty():
			result[socket_name] = (node_value as Dictionary).duplicate(true)
	return result


static func get_source_name() -> String:
	if _cache.is_empty():
		load_gameplay_bank()
	return _last_source


static func clear_cache() -> void:
	_cache.clear()
	_runtime_figure_cache.clear()
	_last_source = "NONE"


static func _strip_base64_whitespace(value: String) -> String:
	return value.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").strip_edges()


static func _normalize_base64(value: String) -> String:
	var clean := _strip_base64_whitespace(value)
	if clean.is_empty():
		return ""
	var remainder := clean.length() % 4
	if remainder == 1:
		return ""
	if remainder == 2:
		clean += "=="
	elif remainder == 3:
		clean += "="
	return clean


static func _looks_like_base64(value: String) -> bool:
	if value.is_empty() or value.length() % 4 != 0:
		return false
	var padding_started := false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if code == 61:
			padding_started = true
			if index < value.length() - 2:
				return false
			continue
		if padding_started:
			return false
		var valid := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 43 or code == 47
		if not valid:
			return false
	return true