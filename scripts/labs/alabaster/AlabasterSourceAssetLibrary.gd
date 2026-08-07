extends RefCounted
class_name AlabasterSourceAssetLibrary

const SOURCE_DIR := "res://data/labs/alabaster/source/"
const MAX_JSON_BYTES := 8 * 1024 * 1024

static var _json_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func load_male_dummy_figure() -> Dictionary:
	var payload := _load_gzip_json("male_dummy_figure.json.gz.b64")
	return payload.duplicate(true) if not payload.is_empty() else {}


static func load_player_weapon_source() -> Dictionary:
	return _load_gzip_json("player-weapon.json.gz.b64")


static func load_skin_texture(profile_id: String) -> Texture2D:
	match profile_id:
		"male_dummy":
			return _load_png_b64("dummy.png.b64")
		"male_temp":
			return _load_png_b64("male-temp01.png.b64")
		_:
			return null


static func load_player_weapon_sheet(sheet_name: String) -> Texture2D:
	# Source JSON names these sheets "melee" and "ranged". The loader accepts
	# a real PNG copied into SOURCE_DIR or an embedded .b64/.chunkXX bundle.
	match sheet_name:
		"melee":
			return _load_png_flexible("player-melee.png")
		"ranged":
			return _load_png_flexible("player-ranged.png")
		_:
			return null


static func clear_caches() -> void:
	_json_cache.clear()
	_texture_cache.clear()


static func _load_gzip_json(file_name: String) -> Dictionary:
	var path := SOURCE_DIR + file_name
	if _json_cache.has(path):
		return (_json_cache[path] as Dictionary).duplicate(true)
	if not FileAccess.file_exists(path):
		push_warning("AlabasterSourceAssetLibrary: missing %s" % path)
		return {}
	var encoded := FileAccess.get_file_as_string(path).strip_edges()
	var compressed := Marshalls.base64_to_raw(encoded)
	var raw := compressed.decompress_dynamic(MAX_JSON_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		push_error("AlabasterSourceAssetLibrary: failed to decompress %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary:
		push_error("AlabasterSourceAssetLibrary: invalid JSON in %s" % path)
		return {}
	var result: Dictionary = (parsed as Dictionary).duplicate(true)
	_json_cache[path] = result
	return result.duplicate(true)


static func _load_png_flexible(file_name: String) -> Texture2D:
	var direct_path := SOURCE_DIR + file_name
	if FileAccess.file_exists(direct_path):
		if _texture_cache.has(direct_path):
			return _texture_cache[direct_path]
		var image := Image.new()
		var error := image.load(direct_path)
		if error == OK:
			var texture := ImageTexture.create_from_image(image)
			_texture_cache[direct_path] = texture
			return texture

	var base64_path := direct_path + ".b64"
	if FileAccess.file_exists(base64_path):
		var single := _load_png_b64(file_name + ".b64")
		if single != null:
			return single

	# Current repository representation. Chunks are slices of one base64 PNG
	# string and must be concatenated before decoding.
	var chunk_text := _read_indexed_text(direct_path + ".b64.chunk")
	if not chunk_text.is_empty():
		var chunk_texture := _decode_png_text(direct_path + "#chunks", chunk_text)
		if chunk_texture != null:
			return chunk_texture

	# Compatibility with the first import pass, which used .part00/.part01...
	# for the larger melee atlas. This gives the melee weapons a second valid
	# source path instead of silently disappearing if one embedded bundle is bad.
	var part_text := _read_indexed_text(direct_path + ".b64.part")
	if not part_text.is_empty():
		var part_texture := _decode_png_text(direct_path + "#parts", part_text)
		if part_texture != null:
			return part_texture

	push_warning("AlabasterSourceAssetLibrary: no valid PNG payload for %s" % direct_path)
	return null


static func _read_indexed_text(prefix: String) -> String:
	var encoded := ""
	var index := 0
	while true:
		var path := prefix + "%02d" % index
		if not FileAccess.file_exists(path):
			break
		encoded += FileAccess.get_file_as_string(path).strip_edges()
		index += 1
	return encoded if index > 0 else ""


static func _load_png_b64(file_name: String) -> Texture2D:
	var path := SOURCE_DIR + file_name
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not FileAccess.file_exists(path):
		push_warning("AlabasterSourceAssetLibrary: missing %s" % path)
		return null
	return _decode_png_text(path, FileAccess.get_file_as_string(path).strip_edges())


static func _decode_png_text(cache_key: String, encoded: String) -> Texture2D:
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	if encoded.is_empty():
		return null
	var raw := Marshalls.base64_to_raw(encoded)
	if raw.is_empty():
		push_warning("AlabasterSourceAssetLibrary: embedded PNG base64 is empty for %s" % cache_key)
		return null
	var image := Image.new()
	var error := image.load_png_from_buffer(raw)
	if error != OK:
		push_warning("AlabasterSourceAssetLibrary: failed to decode embedded PNG %s, error=%s" % [cache_key, error])
		return null
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture
