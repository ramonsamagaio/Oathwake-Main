extends RefCounted
class_name AlabasterJunoGameplayBank

const PLAYER_BANK_PATH := "res://data/labs/alabaster/juno_player_anims.json.gz.b64"
const RUNTIME_PATH := "res://data/labs/alabaster/juno_runtime.json.gz.b64"
const PLAYER_MAX_BYTES := 512 * 1024
const RUNTIME_MAX_BYTES := 8 * 1024 * 1024
const REQUIRED_LOCOMOTION := ["idle", "walk", "run"]

static var _cache: Dictionary = {}


static func load_gameplay_bank() -> Dictionary:
	if not _cache.is_empty():
		return _cache.duplicate(true)

	var result := _load_player_bank()
	var runtime := _load_runtime_bank()
	for animation_name in runtime.keys():
		if not result.has(animation_name):
			result[animation_name] = runtime[animation_name]

	if result.is_empty():
		push_warning("AlabasterJunoGameplayBank: no repository-local Juno gameplay animations could be loaded.")
		return {}

	_cache = result.duplicate(true)
	return _cache.duplicate(true)


static func load_locomotion_bank() -> Dictionary:
	var bank := load_gameplay_bank()
	var result := {}
	for clip in REQUIRED_LOCOMOTION:
		var value: Variant = bank.get(clip, null)
		if value is Dictionary and not (value as Dictionary).is_empty():
			result[clip] = (value as Dictionary).duplicate(true)
	return result


static func clear_cache() -> void:
	_cache.clear()


static func _load_player_bank() -> Dictionary:
	if not FileAccess.file_exists(PLAYER_BANK_PATH):
		return {}
	var encoded := FileAccess.get_file_as_string(PLAYER_BANK_PATH).strip_edges()
	if encoded.is_empty():
		return {}
	var compressed := Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		return {}
	var raw := compressed.decompress_dynamic(PLAYER_MAX_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary:
		return {}
	var anims_value: Variant = (parsed as Dictionary).get("anims", {})
	if not anims_value is Dictionary:
		return {}
	return (anims_value as Dictionary).duplicate(true)


static func _load_runtime_bank() -> Dictionary:
	if not FileAccess.file_exists(RUNTIME_PATH):
		return {}
	var encoded := FileAccess.get_file_as_string(RUNTIME_PATH).strip_edges()
	if encoded.is_empty():
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
	if not figure_value is Dictionary:
		return {}
	var anims_value: Variant = (figure_value as Dictionary).get("anims", {})
	if not anims_value is Dictionary:
		return {}
	return (anims_value as Dictionary).duplicate(true)
