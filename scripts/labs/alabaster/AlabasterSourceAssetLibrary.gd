extends RefCounted
class_name AlabasterSourceAssetLibrary

const SOURCE_DIR := "res://data/labs/alabaster/source/"
const WEAPON_PLAYER_DIR := "res://assets/sprites/weapons/"
const MAX_JSON_BYTES := 8 * 1024 * 1024
const SKIN_SIZE := Vector2i(672, 120)
const SKIN_CHROMA := Color8(255, 0, 195, 255)
const MELEE_SIZE := Vector2i(672, 152)
const RANGED_SIZE := Vector2i(672, 88)

const SKIN_FIGURE_NAMES := {
	"male_dummy": "Male-Dummy",
	"male_temp": "Male-Temp-01",
}

const WEAPON_SHEET_PATHS := {
	"melee": WEAPON_PLAYER_DIR + "player-melee.png",
	"ranged": WEAPON_PLAYER_DIR + "player-ranged.png",
}

static var _json_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _weapon_sheet_cache: Dictionary = {}
static var _weapon_sheet_status_reported: Dictionary = {}


static func load_male_dummy_figure() -> Dictionary:
	return _load_named_skin_figure("male_dummy", "male_dummy_figure.json.gz.b64")


static func load_male_temp_figure() -> Dictionary:
	return _load_named_skin_figure("male_temp", "male_temp_figure.json.gz.b64")


static func load_skin_figure(profile_id: String) -> Dictionary:
	match profile_id:
		"male_dummy":
			return load_male_dummy_figure()
		"male_temp":
			return load_male_temp_figure()
		_:
			return {}


static func get_skin_figure_name(profile_id: String) -> String:
	return str(SKIN_FIGURE_NAMES.get(profile_id, ""))


static func _load_named_skin_figure(profile_id: String, file_name: String) -> Dictionary:
	var payload := _load_gzip_json(file_name)
	if payload.is_empty():
		return {}
	return _extract_skin_figure(payload, profile_id)


static func _extract_skin_figure(payload: Dictionary, profile_id: String) -> Dictionary:
	# The original Alabaster figure files are NOT figure dictionaries at their
	# root. They are wrappers shaped like:
	#   {"figures":{"Male-Dummy":{...figure...}}}
	# Older generated fixtures may already contain the extracted figure, so keep
	# that shape supported too.
	if payload.has("nodes") and payload.has("anims"):
		return payload.duplicate(true)

	var figure_name := get_skin_figure_name(profile_id)
	if figure_name.is_empty():
		push_error("AlabasterSourceAssetLibrary: unknown skin profile %s" % profile_id)
		return {}

	var figures_value: Variant = payload.get("figures", {})
	if not figures_value is Dictionary:
		push_error("AlabasterSourceAssetLibrary: %s source has no figures dictionary" % profile_id)
		return {}
	var figures := figures_value as Dictionary
	var figure_value: Variant = figures.get(figure_name, {})
	if figure_value is Dictionary and not (figure_value as Dictionary).is_empty():
		var figure := (figure_value as Dictionary).duplicate(true)
		print("ALABASTER_SKIN_FIGURE_EXTRACTED profile=%s figure=%s nodes=%d anims=%d" % [
			profile_id,
			figure_name,
			(figure.get("nodes", {}) as Dictionary).size() if figure.get("nodes", {}) is Dictionary else 0,
			(figure.get("anims", {}) as Dictionary).size() if figure.get("anims", {}) is Dictionary else 0,
		])
		return figure

	# Be tolerant of a renamed wrapper only when the source contains exactly one
	# figure. This keeps the loader useful for future NPC/monster source files
	# without silently selecting the wrong entry from a multi-figure JSON.
	if figures.size() == 1:
		var only_name := str(figures.keys()[0])
		var only_value: Variant = figures[figures.keys()[0]]
		if only_value is Dictionary:
			push_warning("AlabasterSourceAssetLibrary: expected figure %s for %s, using sole source figure %s" % [figure_name, profile_id, only_name])
			return (only_value as Dictionary).duplicate(true)

	push_error("AlabasterSourceAssetLibrary: figure %s not found for profile %s; available=%s" % [figure_name, profile_id, str(figures.keys())])
	return {}


static func load_player_weapon_source() -> Dictionary:
	return _load_gzip_json("player-weapon.json.gz.b64")


static func load_skin_texture(profile_id: String) -> Texture2D:
	match profile_id:
		"male_dummy":
			return _load_skin_png_b64("dummy.png.b64")
		"male_temp":
			return _load_skin_png_b64("male-temp01.png.b64")
		_:
			return null


static func get_player_weapon_sheet_path(sheet_name: String) -> String:
	return str(WEAPON_SHEET_PATHS.get(sheet_name, ""))


static func load_player_weapon_sheet(sheet_name: String) -> Texture2D:
	if _weapon_sheet_cache.has(sheet_name):
		return _weapon_sheet_cache[sheet_name] as Texture2D

	var path := get_player_weapon_sheet_path(sheet_name)
	if path.is_empty():
		_weapon_sheet_cache[sheet_name] = null
		_report_weapon_sheet(sheet_name, path, null, "unknown sheet")
		return null

	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			texture = resource as Texture2D

	if texture != null:
		var expected_size := MELEE_SIZE if sheet_name == "melee" else RANGED_SIZE
		if texture.get_width() != expected_size.x or texture.get_height() != expected_size.y:
			_report_weapon_sheet(
				sheet_name,
				path,
				null,
				"wrong size %dx%d expected %dx%d" % [texture.get_width(), texture.get_height(), expected_size.x, expected_size.y]
			)
			texture = null

	_weapon_sheet_cache[sheet_name] = texture
	_report_weapon_sheet(sheet_name, path, texture, "missing/unimported asset")
	return texture


static func has_player_weapon_sheet(sheet_name: String) -> bool:
	return load_player_weapon_sheet(sheet_name) != null


static func clear_caches() -> void:
	_json_cache.clear()
	_texture_cache.clear()
	_weapon_sheet_cache.clear()
	_weapon_sheet_status_reported.clear()


static func _report_weapon_sheet(sheet_name: String, path: String, texture: Texture2D, failure_reason: String) -> void:
	if _weapon_sheet_status_reported.has(sheet_name):
		return
	_weapon_sheet_status_reported[sheet_name] = true
	if texture != null:
		print("BONES_WEAPON_ATLAS_READY sheet=%s path=%s size=%dx%d" % [sheet_name, path, texture.get_width(), texture.get_height()])
	else:
		push_warning("Bones weapon atlas unavailable: sheet=%s path=%s reason=%s" % [sheet_name, path, failure_reason])


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


static func _load_skin_png_b64(file_name: String) -> Texture2D:
	var path := SOURCE_DIR + file_name
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not FileAccess.file_exists(path):
		push_warning("AlabasterSourceAssetLibrary: missing %s" % path)
		return null
	var encoded := FileAccess.get_file_as_string(path).strip_edges()
	var raw := Marshalls.base64_to_raw(encoded)
	if raw.is_empty():
		push_warning("AlabasterSourceAssetLibrary: embedded PNG base64 is empty for %s" % path)
		return null
	var image := Image.new()
	var error := image.load_png_from_buffer(raw)
	if error != OK:
		push_warning("AlabasterSourceAssetLibrary: failed to decode embedded PNG %s, error=%s" % [path, error])
		return null
	if not _image_size_is_valid(image, SKIN_SIZE):
		push_warning("AlabasterSourceAssetLibrary: rejected %s size=%sx%s expected=%sx%s" % [
			path, image.get_width(), image.get_height(), SKIN_SIZE.x, SKIN_SIZE.y,
		])
		return null
	_apply_skin_chroma_key(image)
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	return texture


static func _apply_skin_chroma_key(image: Image) -> void:
	# The demo test atlases use opaque RGB magenta (255,0,195) instead of alpha.
	# Convert only that exact source key once when the atlas is loaded.
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.r8 == SKIN_CHROMA.r8 and pixel.g8 == SKIN_CHROMA.g8 and pixel.b8 == SKIN_CHROMA.b8:
				pixel.a = 0.0
				image.set_pixel(x, y, pixel)


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
