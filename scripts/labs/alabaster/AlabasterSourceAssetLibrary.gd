extends RefCounted
class_name AlabasterSourceAssetLibrary

const SOURCE_DIR := "res://data/labs/alabaster/source/"
const MAX_JSON_BYTES := 8 * 1024 * 1024
const MELEE_SIZE := Vector2i(672, 152)
const RANGED_SIZE := Vector2i(672, 92)

static var _json_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _weapon_sheet_cache: Dictionary = {}
static var _weapon_sheet_status_reported: Dictionary = {}


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
	# Weapon atlases are optional source assets. Only a real PNG is accepted here.
	# The old .verified/.chunk/.part payloads were incomplete/corrupt and caused
	# the PNG decoder to emit thousands of CRC/parse errors when a weapon updated.
	# Cache BOTH success and absence so gameplay never performs FileAccess or PNG
	# decoding after the first lookup for a sheet.
	if _weapon_sheet_cache.has(sheet_name):
		return _weapon_sheet_cache[sheet_name] as Texture2D

	var file_name := ""
	var expected_size := Vector2i.ZERO
	match sheet_name:
		"melee":
			file_name = "player-melee.png"
			expected_size = MELEE_SIZE
		"ranged":
			file_name = "player-ranged.png"
			expected_size = RANGED_SIZE
		_:
			_weapon_sheet_cache[sheet_name] = null
			return null

	var path := SOURCE_DIR + file_name
	var texture: Texture2D = null
	if FileAccess.file_exists(path):
		var image := Image.new()
		var error := image.load(path)
		if error == OK and _image_size_is_valid(image, expected_size):
			texture = ImageTexture.create_from_image(image)

	_weapon_sheet_cache[sheet_name] = texture
	if not _weapon_sheet_status_reported.has(sheet_name):
		_weapon_sheet_status_reported[sheet_name] = true
		if texture != null:
			print("BONES_WEAPON_ATLAS_READY sheet=%s path=%s" % [sheet_name, path])
		else:
			print("BONES_WEAPON_ATLAS_OPTIONAL_MISSING sheet=%s fallback=procedural" % sheet_name)
	return texture


static func clear_caches() -> void:
	_json_cache.clear()
	_texture_cache.clear()
	_weapon_sheet_cache.clear()
	_weapon_sheet_status_reported.clear()


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


static func _load_png_b64(file_name: String, expected_size: Vector2i = Vector2i.ZERO) -> Texture2D:
	var path := SOURCE_DIR + file_name
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not FileAccess.file_exists(path):
		push_warning("AlabasterSourceAssetLibrary: missing %s" % path)
		return null
	return _decode_png_text(path, FileAccess.get_file_as_string(path).strip_edges(), expected_size)


static func _decode_png_text(cache_key: String, encoded: String, expected_size: Vector2i = Vector2i.ZERO) -> Texture2D:
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
	if not _image_size_is_valid(image, expected_size):
		push_warning("AlabasterSourceAssetLibrary: rejected %s size=%sx%s expected=%sx%s" % [
			cache_key,
			image.get_width(), image.get_height(),
			expected_size.x, expected_size.y,
		])
		return null
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[cache_key] = texture
	return texture


static func _image_size_is_valid(image: Image, expected_size: Vector2i) -> bool:
	if expected_size == Vector2i.ZERO:
		return true
	return image.get_width() == expected_size.x and image.get_height() == expected_size.y
