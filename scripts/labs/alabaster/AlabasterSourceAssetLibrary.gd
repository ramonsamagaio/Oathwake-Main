extends RefCounted
class_name AlabasterSourceAssetLibrary

const SOURCE_DIR := "res://data/labs/alabaster/source/"
const WEAPON_PLAYER_DIR := "res://assets/sprites/weapons/"
const MAX_JSON_BYTES := 64 * 1024 * 1024
const SKIN_SIZE := Vector2i(672, 120)
const SKIN_CHROMA_RGB := Vector3i(255, 0, 195)
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
	print("ALABASTER_SKIN_SOURCE_REQUEST profile=%s file=%s" % [profile_id, file_name])
	var payload := _load_gzip_json(file_name)
	if payload.is_empty():
		push_error("AlabasterSourceAssetLibrary: empty source payload for %s" % profile_id)
		return {}
	return _extract_skin_figure(payload, profile_id)


static func _extract_skin_figure(payload: Dictionary, profile_id: String) -> Dictionary:
	# Native source files may be either the actual figure at the root or a
	# top-level `figures` wrapper. Keep both forms supported.
	if payload.has("nodes") and payload.has("anims"):
		var direct_figure := _runtime_figure_copy(payload)
		_report_skin_figure(profile_id, get_skin_figure_name(profile_id), direct_figure)
		return direct_figure

	var figure_name := get_skin_figure_name(profile_id)
	if figure_name.is_empty():
		push_error("AlabasterSourceAssetLibrary: unknown skin profile %s" % profile_id)
		return {}

	var figures_value: Variant = payload.get("figures", {})
	if not figures_value is Dictionary:
		push_error("AlabasterSourceAssetLibrary: %s source has no figures dictionary" % profile_id)
		return {}
	var figures := figures_value as Dictionary
	print("ALABASTER_SKIN_SOURCE_FIGURES profile=%s requested=%s available=%s" % [
		profile_id,
		figure_name,
		str(figures.keys()),
	])

	var figure_value: Variant = figures.get(figure_name, {})
	if figure_value is Dictionary and not (figure_value as Dictionary).is_empty():
		var figure := _runtime_figure_copy(figure_value as Dictionary)
		_report_skin_figure(profile_id, figure_name, figure)
		return figure

	if figures.size() == 1:
		var only_key: Variant = figures.keys()[0]
		var only_name := str(only_key)
		var only_value: Variant = figures[only_key]
		if only_value is Dictionary:
			push_warning("AlabasterSourceAssetLibrary: expected figure %s for %s, using sole source figure %s" % [figure_name, profile_id, only_name])
			var sole_figure := _runtime_figure_copy(only_value as Dictionary)
			_report_skin_figure(profile_id, only_name, sole_figure)
			return sole_figure

	push_error("AlabasterSourceAssetLibrary: figure %s not found for profile %s; available=%s" % [figure_name, profile_id, str(figures.keys())])
	return {}


static func _runtime_figure_copy(source: Dictionary) -> Dictionary:
	# Runtime only mutates the top-level nodes/anims containers. Sharing the
	# immutable authored nested animation data avoids a very expensive deep copy.
	var result := source.duplicate(false)
	var nodes_value: Variant = source.get("nodes", {})
	if nodes_value is Dictionary:
		result["nodes"] = (nodes_value as Dictionary).duplicate(false)
	else:
		result["nodes"] = {}
	var anims_value: Variant = source.get("anims", {})
	if anims_value is Dictionary:
		result["anims"] = (anims_value as Dictionary).duplicate(false)
	else:
		result["anims"] = {}
	return result


static func _report_skin_figure(profile_id: String, figure_name: String, figure: Dictionary) -> void:
	var nodes_value: Variant = figure.get("nodes", {})
	var anims_value: Variant = figure.get("anims", {})
	var node_count := (nodes_value as Dictionary).size() if nodes_value is Dictionary else 0
	var anim_count := (anims_value as Dictionary).size() if anims_value is Dictionary else 0
	print("ALABASTER_SKIN_FIGURE_EXTRACTED profile=%s figure=%s nodes=%d anims=%d" % [
		profile_id,
		figure_name,
		node_count,
		anim_count,
	])


static func load_player_weapon_source() -> Dictionary:
	return _load_gzip_json("player-weapon.json.gz.b64")


static func load_skin_texture(profile_id: String) -> Texture2D:
	var file_name := ""
	match profile_id:
		"male_dummy":
			file_name = "dummy.png.b64"
		"male_temp":
			file_name = "male-temp01.png.b64"
		_:
			push_error("AlabasterSourceAssetLibrary: unknown skin texture profile %s" % profile_id)
			return null
	print("ALABASTER_SKIN_ATLAS_REQUEST profile=%s file=%s" % [profile_id, file_name])
	var texture := _load_skin_png_b64(file_name)
	print("ALABASTER_SKIN_ATLAS_RESULT profile=%s ok=%s" % [profile_id, str(texture != null)])
	return texture


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
		var cached_value: Variant = _json_cache[path]
		if cached_value is Dictionary:
			print("ALABASTER_EMBED_JSON_CACHE path=%s" % path)
			return (cached_value as Dictionary).duplicate(false)
		_json_cache.erase(path)

	if not FileAccess.file_exists(path):
		push_warning("AlabasterSourceAssetLibrary: missing %s" % path)
		return {}

	var encoded := FileAccess.get_file_as_string(path).strip_edges()
	if encoded.is_empty():
		push_error("AlabasterSourceAssetLibrary: embedded JSON text is empty: %s" % path)
		return {}
	print("ALABASTER_EMBED_JSON_BEGIN path=%s encoded_chars=%d" % [path, encoded.length()])

	var compressed := Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		push_error("AlabasterSourceAssetLibrary: base64 decode failed for %s" % path)
		return {}

	var expected_size := _gzip_uncompressed_size(compressed)
	print("ALABASTER_EMBED_JSON_BYTES path=%s compressed=%d gzip_size=%d limit=%d" % [
		path,
		compressed.size(),
		expected_size,
		MAX_JSON_BYTES,
	])
	if expected_size > MAX_JSON_BYTES:
		push_error("AlabasterSourceAssetLibrary: %s expands to %d bytes, above safety limit %d" % [path, expected_size, MAX_JSON_BYTES])
		return {}

	var raw := PackedByteArray()
	if expected_size > 0:
		raw = compressed.decompress(expected_size, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		raw = compressed.decompress_dynamic(MAX_JSON_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		push_error("AlabasterSourceAssetLibrary: failed to decompress %s (compressed=%d expected=%d)" % [path, compressed.size(), expected_size])
		return {}
	print("ALABASTER_EMBED_JSON_RAW path=%s raw_bytes=%d" % [path, raw.size()])

	var json := JSON.new()
	var parse_error := json.parse(raw.get_string_from_utf8())
	if parse_error != OK:
		push_error("AlabasterSourceAssetLibrary: invalid JSON in %s line=%d error=%s" % [
			path,
			json.get_error_line(),
			json.get_error_message(),
		])
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		push_error("AlabasterSourceAssetLibrary: JSON root is not a dictionary in %s" % path)
		return {}

	var result := parsed as Dictionary
	_json_cache[path] = result
	print("ALABASTER_EMBED_JSON_OK path=%s root_keys=%s" % [path, str(result.keys())])
	return result.duplicate(false)


static func _gzip_uncompressed_size(data: PackedByteArray) -> int:
	if data.size() < 4:
		return 0
	var n := data.size()
	return (
		int(data[n - 4])
		| (int(data[n - 3]) << 8)
		| (int(data[n - 2]) << 16)
		| (int(data[n - 1]) << 24)
	)


static func _load_skin_png_b64(file_name: String) -> Texture2D:
	var path := SOURCE_DIR + file_name
	if _texture_cache.has(path):
		var cached: Variant = _texture_cache[path]
		if cached is Texture2D:
			print("ALABASTER_SKIN_ATLAS_CACHE path=%s" % path)
			return cached as Texture2D
		_texture_cache.erase(path)

	print("ALABASTER_SKIN_ATLAS_BEGIN path=%s exists=%s" % [path, str(FileAccess.file_exists(path))])
	if not FileAccess.file_exists(path):
		push_warning("AlabasterSourceAssetLibrary: missing %s" % path)
		return null

	var encoded := FileAccess.get_file_as_string(path).strip_edges()
	print("ALABASTER_SKIN_ATLAS_TEXT path=%s chars=%d" % [path, encoded.length()])
	if encoded.is_empty():
		push_warning("AlabasterSourceAssetLibrary: embedded PNG text is empty for %s" % path)
		return null

	var raw := Marshalls.base64_to_raw(encoded)
	print("ALABASTER_SKIN_ATLAS_BYTES path=%s bytes=%d" % [path, raw.size()])
	if raw.is_empty():
		push_warning("AlabasterSourceAssetLibrary: embedded PNG base64 decode failed for %s" % path)
		return null
	if raw.size() < 24 or raw[0] != 137 or raw[1] != 80 or raw[2] != 78 or raw[3] != 71:
		push_warning("AlabasterSourceAssetLibrary: embedded PNG signature is invalid for %s" % path)
		return null

	var image := Image.new()
	var error := image.load_png_from_buffer(raw)
	print("ALABASTER_SKIN_ATLAS_DECODE path=%s error=%d empty=%s size=%dx%d format=%d" % [
		path,
		error,
		str(image.is_empty()),
		image.get_width(),
		image.get_height(),
		int(image.get_format()),
	])
	if error != OK or image.is_empty():
		push_warning("AlabasterSourceAssetLibrary: failed to decode embedded PNG %s, error=%s" % [path, error])
		return null
	if not _image_size_is_valid(image, SKIN_SIZE):
		push_warning("AlabasterSourceAssetLibrary: rejected %s size=%sx%s expected=%sx%s" % [
			path, image.get_width(), image.get_height(), SKIN_SIZE.x, SKIN_SIZE.y,
		])
		return null

	# Work on raw RGBA8 bytes instead of calling get_pixel/set_pixel thousands of
	# times. Besides being much faster, this avoids Color conversion quirks while
	# preserving every authored pixel exactly.
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	print("ALABASTER_SKIN_ATLAS_RGBA path=%s format=%d" % [path, int(image.get_format())])
	var rgba := image.get_data()
	var expected_bytes := image.get_width() * image.get_height() * 4
	print("ALABASTER_SKIN_ATLAS_DATA path=%s bytes=%d expected=%d" % [path, rgba.size(), expected_bytes])
	if rgba.size() != expected_bytes:
		push_error("AlabasterSourceAssetLibrary: unexpected RGBA byte count for %s: %d expected %d" % [path, rgba.size(), expected_bytes])
		return null

	var keyed_pixels := 0
	var i := 0
	while i + 3 < rgba.size():
		if int(rgba[i]) == SKIN_CHROMA_RGB.x and int(rgba[i + 1]) == SKIN_CHROMA_RGB.y and int(rgba[i + 2]) == SKIN_CHROMA_RGB.z:
			rgba[i + 3] = 0
			keyed_pixels += 1
		i += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, rgba)
	print("ALABASTER_SKIN_ATLAS_CHROMA path=%s keyed=%d" % [path, keyed_pixels])

	var texture := ImageTexture.create_from_image(image)
	if texture == null:
		push_error("AlabasterSourceAssetLibrary: ImageTexture creation failed for %s" % path)
		return null
	print("ALABASTER_SKIN_ATLAS_READY path=%s size=%dx%d" % [path, texture.get_width(), texture.get_height()])
	_texture_cache[path] = texture
	return texture


static func _load_png_b64(file_name: String, expected_size: Vector2i = Vector2i.ZERO) -> Texture2D:
	var path := SOURCE_DIR + file_name
	if _texture_cache.has(path):
		var cached: Variant = _texture_cache[path]
		return cached as Texture2D if cached is Texture2D else null
	if not FileAccess.file_exists(path):
		push_warning("AlabasterSourceAssetLibrary: missing %s" % path)
		return null
	return _decode_png_text(path, FileAccess.get_file_as_string(path).strip_edges(), expected_size)


static func _decode_png_text(cache_key: String, encoded: String, expected_size: Vector2i = Vector2i.ZERO) -> Texture2D:
	if _texture_cache.has(cache_key):
		var cached: Variant = _texture_cache[cache_key]
		return cached as Texture2D if cached is Texture2D else null
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
