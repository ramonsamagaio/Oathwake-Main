extends RefCounted

# Repository-local animation-bank loader for the Alabaster tools/runtime.
#
# IMPORTANT: the committed *.part files are independent Base64 encodings of
# consecutive COMPRESSED BYTE SLICES. Their Base64 text must never be joined.
# Decode each part independently, append the decoded bytes in logical order,
# then decompress the reconstructed ZSTD frame once.
#
# Several historical uploads combine two logical slices in one repository file
# (05_06, 07_08, 09_10, ...). The standalone 09 file overlaps 09_10 and MUST NOT
# be appended as well. FULL_PARTS is therefore an explicit, non-overlapping
# sequence for logical slices 00..20.

const FULL_PARTS := [
	"res://data/labs/alabaster/anims/juno_anims_bin_00.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_01.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_02.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_03.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_04.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_05_06.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_07_08.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_09_10.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_11_12.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_13_14.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_15_16.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_17_18.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_19_20.part",
]

const FULL_DECOMPRESSED_BYTES := 671589
const EXPECTED_ANIMATIONS := 419

# Repository-only source fallbacks. Runtime never probes Steam or arbitrary
# machine-local paths.
const SOURCE_CANDIDATES := [
	"res://data/labs/alabaster/characters/juno.json",
	"res://data/labs/alabaster/source/juno.json",
	"res://data/labs/alabaster/juno.json",
]

const GAMEPLAY_SEARCH_DIRS := [
	"res://data/labs/alabaster",
	"res://data/labs/alabaster/anims",
]
const GAMEPLAY_PREFIX := "juno_gameplay_anims_"

const REQUIRED_GAMEPLAY_ANIMATIONS := [
	"idle", "walk", "run", "idleJump1", "damage", "dead", "guard", "guardParry", "respawn", "castPoint",
	"atkSwordN1", "atkSwordN2", "atkSwordNFinisher", "atkSwordTripleSlash", "atkSwordCrossStrike",
	"atkHammer1fast", "atkHammer2", "atkHammer3", "atkSpear1", "atkTonfa1-punch",
]

const CATEGORY_NAMES := ["DEFAULT", "COMBAT", "PUZZLE", "OTHER", "CUTSCENE", "DEFAULT"]
const SPLINE_NAMES := ["LINEAR", "EASE_IN", "EASE_OUT", "EASE_IN_OUT", "EASE_IN_STRONG", "EASE_OUT_STRONG"]
const FACE_NAMES := {
	0: "",
	1: "FACE_1",
	2: "FACE_2",
	4: "FACE_4",
	8: "FACE_8",
	16: "FACE_16",
	48: "FACE_48",
}

static var last_source := "NONE"
static var last_error := ""
static var last_animation_count := 0
static var last_part_count := 0


class ByteReader:
	extends RefCounted

	var data: PackedByteArray
	var pos := 0
	var failed := false

	func _init(source: PackedByteArray) -> void:
		data = source

	func _need(count: int) -> bool:
		if failed or count < 0 or pos + count > data.size():
			failed = true
			return false
		return true

	func read_u8() -> int:
		if not _need(1):
			return 0
		var value := int(data[pos])
		pos += 1
		return value

	func read_i8() -> int:
		var value := read_u8()
		return value - 256 if value >= 128 else value

	func read_u16() -> int:
		if not _need(2):
			return 0
		var value := int(data[pos]) | (int(data[pos + 1]) << 8)
		pos += 2
		return value

	func read_i16() -> int:
		var value := read_u16()
		return value - 65536 if value >= 32768 else value

	func read_string() -> String:
		var byte_count := read_u8()
		if not _need(byte_count):
			return ""
		var bytes := data.slice(pos, pos + byte_count)
		pos += byte_count
		return bytes.get_string_from_utf8()

	func read_fixed_string(byte_count: int) -> String:
		if not _need(byte_count):
			return ""
		var bytes := data.slice(pos, pos + byte_count)
		pos += byte_count
		return bytes.get_string_from_utf8()


static func load_full_animation_bank() -> Dictionary:
	_reset_diagnostics()

	var full := _load_known_full_bank()
	if full.size() == EXPECTED_ANIMATIONS:
		_set_success("FULL_JANI1", full.size(), FULL_PARTS.size())
		_report_required_clips("FULL_JANI1", full)
		return full

	var full_error := last_error
	var source_result := _load_source_candidates()
	if source_result.size() == EXPECTED_ANIMATIONS:
		_set_success("SOURCE_JSON", source_result.size(), 1)
		_report_required_clips("SOURCE_JSON", source_result)
		return source_result

	var source_error := last_error
	var gameplay := _load_gameplay_chunks()
	if not gameplay.is_empty():
		_set_success("GAMEPLAY", gameplay.size(), last_part_count)
		_report_required_clips("GAMEPLAY", gameplay)
		push_warning("AlabasterAnimationBank: full 419-animation bank unavailable; loaded repository gameplay fallback with %d animations" % gameplay.size())
		return gameplay

	var gameplay_error := last_error
	last_error = "full=%s | source=%s | gameplay=%s" % [full_error, source_error, gameplay_error]
	push_warning("AlabasterAnimationBank: %s" % last_error)
	return {}


static func load_gameplay_animation_bank() -> Dictionary:
	_reset_diagnostics()
	var gameplay := _load_gameplay_chunks()
	if gameplay.is_empty():
		if last_error.is_empty():
			last_error = "repository gameplay animation payload unavailable"
		return {}
	_set_success("GAMEPLAY", gameplay.size(), last_part_count)
	_report_required_clips("GAMEPLAY", gameplay)
	return gameplay


static func load_animation_source_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		last_error = "source file not found: %s" % path
		return {}
	var text := FileAccess.get_file_as_string(path)
	var anims := _extract_anims_from_json_text(text)
	if anims.is_empty():
		last_error = "source JSON has no animation dictionary: %s" % path
		return {}
	_set_success("SOURCE_JSON", anims.size(), 1)
	return anims


static func get_diagnostics() -> Dictionary:
	return {
		"source": last_source,
		"error": last_error,
		"animation_count": last_animation_count,
		"part_count": last_part_count,
	}


static func _reset_diagnostics() -> void:
	last_source = "NONE"
	last_error = ""
	last_animation_count = 0
	last_part_count = 0


static func _set_success(source: String, count: int, parts: int) -> void:
	last_source = source
	last_error = ""
	last_animation_count = count
	last_part_count = parts


static func _load_known_full_bank() -> Dictionary:
	var compressed := _decode_base64_parts(FULL_PARTS, "full:canonical_00_20")
	if compressed.is_empty():
		return {}

	var raw := _try_zstd_decompress(compressed, FULL_DECOMPRESSED_BYTES)
	if raw.size() != FULL_DECOMPRESSED_BYTES:
		if last_error.is_empty():
			last_error = "full:canonical_00_20 ZSTD got %d/%d bytes" % [raw.size(), FULL_DECOMPRESSED_BYTES]
		return {}

	var anims := _decode_payload(raw)
	if anims.size() != EXPECTED_ANIMATIONS:
		last_error = "full:canonical_00_20 payload decoded %d/%d animations (%s)" % [anims.size(), EXPECTED_ANIMATIONS, last_error]
		return {}

	last_part_count = FULL_PARTS.size()
	print("ALABASTER_BANK_FULL_OK layout=canonical_00_20 parts=%d compressed=%d raw=%d animations=%d" % [
		FULL_PARTS.size(), compressed.size(), raw.size(), anims.size(),
	])
	return anims


static func _load_source_candidates() -> Dictionary:
	for path_variant in SOURCE_CANDIDATES:
		var path := String(path_variant)
		if not FileAccess.file_exists(path):
			continue
		var anims := load_animation_source_file(path)
		if not anims.is_empty():
			return anims
	last_error = "no repository raw Juno source JSON with %d animations" % EXPECTED_ANIMATIONS
	return {}


static func _load_gameplay_chunks() -> Dictionary:
	var attempt_errors: Array[String] = []
	for dir_variant in GAMEPLAY_SEARCH_DIRS:
		var dir_path := String(dir_variant)
		var files := _find_part_files(dir_path, GAMEPLAY_PREFIX)
		if files.is_empty():
			continue

		var paths: Array = []
		for filename_variant in files:
			paths.append(dir_path.path_join(String(filename_variant)))
		last_part_count = files.size()

		var compressed := _decode_base64_parts(paths, "gameplay:%s" % dir_path)
		if compressed.is_empty():
			attempt_errors.append("%s decode: %s" % [dir_path, last_error])
			continue

		var raw := _try_zstd_decompress(compressed, -1)
		if raw.is_empty():
			attempt_errors.append("%s zstd: %s" % [dir_path, last_error])
			continue

		var anims := _decode_payload(raw)
		if not anims.is_empty():
			print("ALABASTER_BANK_GAMEPLAY_OK dir=%s parts=%d compressed=%d raw=%d animations=%d" % [
				dir_path, files.size(), compressed.size(), raw.size(), anims.size(),
			])
			return anims
		attempt_errors.append("%s payload: %s" % [dir_path, last_error])

	last_error = "gameplay-bank failed: %s" % " ; ".join(attempt_errors)
	return {}


# Each file is its own Base64 unit. Decode it independently and append the raw
# compressed bytes. Joining the text is invalid: the current committed full and
# gameplay sets both produce impossible Base64 length mod 4 == 1 when concatenated.
static func _decode_base64_parts(paths: Array, label: String) -> PackedByteArray:
	var compressed := PackedByteArray()
	for part_index in range(paths.size()):
		var path := String(paths[part_index])
		if not FileAccess.file_exists(path):
			last_error = "%s missing part[%d]: %s" % [label, part_index, path]
			return PackedByteArray()

		var text := _strip_base64_whitespace(FileAccess.get_file_as_string(path))
		if text.is_empty():
			last_error = "%s empty part[%d]: %s" % [label, part_index, path]
			return PackedByteArray()

		var bytes := _safe_base64_decode(text)
		if bytes.is_empty():
			last_error = "%s invalid Base64 part[%d] path=%s chars=%d mod4=%d" % [
				label, part_index, path, text.length(), text.length() % 4,
			]
			return PackedByteArray()

		compressed.append_array(bytes)
		print("ALABASTER_BANK_PART kind=%s index=%d/%d chars=%d bytes=%d total=%d" % [
			label, part_index + 1, paths.size(), text.length(), bytes.size(), compressed.size(),
		])

	if compressed.is_empty():
		last_error = "%s reconstructed zero compressed bytes" % label
		return PackedByteArray()
	if not _looks_like_zstd(compressed):
		last_error = "%s reconstructed bytes are not a ZSTD frame first4=%s" % [label, _first_bytes_hex(compressed, 4)]
		return PackedByteArray()

	print("ALABASTER_BANK_STREAM kind=%s parts=%d compressed=%d zstd=true frame_size=%d" % [
		label, paths.size(), compressed.size(), _zstd_frame_content_size(compressed),
	])
	return compressed


static func _safe_base64_decode(value: String) -> PackedByteArray:
	var clean := _normalize_base64_unit(value)
	if clean.is_empty() or not _looks_like_base64(clean):
		return PackedByteArray()
	return Marshalls.base64_to_raw(clean)


static func _normalize_base64_unit(value: String) -> String:
	var clean := _strip_base64_whitespace(value).replace("-", "+").replace("_", "/")
	if clean.is_empty():
		return ""

	# A part may already have legal trailing padding. Remove it and recreate the
	# exact padding from this PART's own length, never from a concatenated stream.
	var padding_index := clean.find("=")
	if padding_index >= 0:
		for index in range(padding_index, clean.length()):
			if clean.unicode_at(index) != 61:
				return ""
		clean = clean.substr(0, padding_index)

	for index in range(clean.length()):
		var code := clean.unicode_at(index)
		var valid := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 43 or code == 47
		if not valid:
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


# PackedByteArray.decompress_dynamic() does not accept ZSTD. ZSTD must use the
# fixed-size decompress() path, with the known uncompressed size or the content
# size advertised by the ZSTD frame header.
static func _try_zstd_decompress(compressed: PackedByteArray, expected_size: int) -> PackedByteArray:
	if not _looks_like_zstd(compressed):
		last_error = "decoded stream is not ZSTD first4=%s" % _first_bytes_hex(compressed, 4)
		return PackedByteArray()

	var frame_size := expected_size
	if frame_size <= 0:
		frame_size = _zstd_frame_content_size(compressed)
	if frame_size <= 0:
		last_error = "ZSTD frame has no usable content size compressed=%d" % compressed.size()
		return PackedByteArray()

	var raw := compressed.decompress(frame_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != frame_size:
		last_error = "ZSTD fixed decompression failed compressed=%d expected=%d got=%d" % [
			compressed.size(), frame_size, raw.size(),
		]
		return PackedByteArray()
	return raw


static func _report_required_clips(source: String, anims: Dictionary) -> void:
	var missing: Array[String] = []
	for animation_name in REQUIRED_GAMEPLAY_ANIMATIONS:
		if not anims.has(animation_name):
			missing.append(animation_name)
	print("ALABASTER_BANK_REQUIRED source=%s animations=%d required=%d/%d missing=%s" % [
		source,
		anims.size(),
		REQUIRED_GAMEPLAY_ANIMATIONS.size() - missing.size(),
		REQUIRED_GAMEPLAY_ANIMATIONS.size(),
		str(missing),
	])


static func _strip_base64_whitespace(value: String) -> String:
	return value.replace("\r", "").replace("\n", "").replace("\t", "").replace(" ", "").strip_edges()


static func _looks_like_zstd(data: PackedByteArray) -> bool:
	return data.size() >= 4 and int(data[0]) == 0x28 and int(data[1]) == 0xB5 and int(data[2]) == 0x2F and int(data[3]) == 0xFD


static func _first_bytes_hex(data: PackedByteArray, count: int) -> String:
	var result := ""
	var limit := mini(maxi(count, 0), data.size())
	for index in range(limit):
		result += "%02X" % int(data[index])
	return result


static func _find_part_files(dir_path: String, prefix: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for filename_variant in dir.get_files():
		var filename := String(filename_variant)
		if filename.begins_with(prefix) and filename.ends_with(".part"):
			result.append(filename)
	result.sort()
	return result


static func _decode_payload(raw: PackedByteArray) -> Dictionary:
	if raw.size() >= 5 and raw.slice(0, 5).get_string_from_utf8() == "JANI1":
		return _decode_jani1(raw)
	var json_anims := _extract_anims_from_json_text(raw.get_string_from_utf8())
	if json_anims.is_empty() and last_error.is_empty():
		last_error = "payload is neither JANI1 nor a supported animation JSON"
	return json_anims


static func _extract_anims_from_json_text(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var root: Dictionary = parsed

	if root.has("figure") and typeof(root["figure"]) == TYPE_DICTIONARY:
		var figure: Dictionary = root["figure"]
		if figure.has("anims") and typeof(figure["anims"]) == TYPE_DICTIONARY:
			return figure["anims"]

	if root.has("figures") and typeof(root["figures"]) == TYPE_DICTIONARY:
		var figures: Dictionary = root["figures"]
		var default_value: Variant = figures.get("default", {})
		if default_value is Dictionary:
			var default_figure: Dictionary = default_value
			if default_figure.has("anims") and typeof(default_figure["anims"]) == TYPE_DICTIONARY:
				return default_figure["anims"]

	if root.has("anims") and typeof(root["anims"]) == TYPE_DICTIONARY:
		return root["anims"]

	if root.has("idle") and root.has("walk") and root.has("run"):
		return root
	return {}


static func _zstd_frame_content_size(data: PackedByteArray) -> int:
	if data.size() < 6:
		return -1
	if not _looks_like_zstd(data):
		return -1

	var descriptor := int(data[4])
	var fcs_flag := (descriptor >> 6) & 0x03
	var single_segment := ((descriptor >> 5) & 0x01) != 0
	var dict_id_flag := descriptor & 0x03
	var pos := 5

	if not single_segment:
		if pos >= data.size():
			return -1
		pos += 1

	var dict_size := 0
	match dict_id_flag:
		1:
			dict_size = 1
		2:
			dict_size = 2
		3:
			dict_size = 4
	pos += dict_size

	var fcs_size := 0
	match fcs_flag:
		0:
			fcs_size = 1 if single_segment else 0
		1:
			fcs_size = 2
		2:
			fcs_size = 4
		3:
			fcs_size = 8

	if fcs_size == 0 or pos + fcs_size > data.size():
		return -1

	var value: int = 0
	for i in range(fcs_size):
		value |= int(data[pos + i]) << (8 * i)
	if fcs_size == 2:
		value += 256
	return value


static func _decode_jani1(raw: PackedByteArray) -> Dictionary:
	var reader := ByteReader.new(raw)
	if reader.read_fixed_string(5) != "JANI1":
		last_error = "invalid JANI1 header"
		return {}

	var node_names: Array[String] = []
	var node_count := reader.read_u8()
	for _i in range(node_count):
		node_names.append(reader.read_string())

	var animation_count := reader.read_u16()
	var result: Dictionary = {}
	for _animation_index in range(animation_count):
		var animation_name := reader.read_string()
		var category_code := reader.read_u8()
		var repeats := reader.read_u8() != 0
		var facing_code := reader.read_u8()
		var frame_count := reader.read_u16()
		var anim_start := reader.read_i16()
		var frame_repeat := reader.read_u8()
		var loop_start := reader.read_i16()

		var category := "DEFAULT"
		if category_code >= 0 and category_code < CATEGORY_NAMES.size():
			category = String(CATEGORY_NAMES[category_code])

		var anim: Dictionary = {
			"category": category,
			"repeat": repeats,
			"frameCnt": frame_count,
			"animStart": anim_start,
			"frameRepeat": maxi(frame_repeat, 1),
			"loopStart": loop_start,
		}
		if FACE_NAMES.has(facing_code) and not String(FACE_NAMES[facing_code]).is_empty():
			anim["rootFacing"] = String(FACE_NAMES[facing_code])

		var transform_count := reader.read_u16()
		var transforms: Array = []
		for _transform_index in range(transform_count):
			var frame := reader.read_u16()
			var key_frame_repeat := reader.read_u8()
			var key_spline_code := reader.read_u8()
			var key_spline := _spline_name(key_spline_code)
			var node_xfm_count := reader.read_u8()
			var node_xfm: Dictionary = {}

			for _node_xfm_index in range(node_xfm_count):
				var node_index := reader.read_u8()
				var mask := reader.read_u8()
				if node_index < 0 or node_index >= node_names.size():
					last_error = "invalid JANI1 transform node index %d" % node_index
					return {}
				var xfm: Dictionary = {}
				if (mask & 1) != 0:
					xfm["rot"] = [
						float(reader.read_i16()) / 100.0,
						float(reader.read_i16()) / 100.0,
						float(reader.read_i16()) / 100.0,
					]
				if (mask & 2) != 0:
					xfm["trans"] = [
						float(reader.read_i16()) / 1000.0,
						float(reader.read_i16()) / 1000.0,
						float(reader.read_i16()) / 1000.0,
					]
				if (mask & 4) != 0:
					xfm["scale"] = float(reader.read_i16()) / 10000.0
				if (mask & 8) != 0:
					xfm["spline"] = _spline_name(reader.read_u8())
				if (mask & 16) != 0:
					xfm["frameRepeat"] = maxi(reader.read_u8(), 1)
				if (mask & 32) != 0:
					xfm["rotToggle"] = reader.read_u8() != 0
				node_xfm[node_names[node_index]] = xfm

			var key: Dictionary = {
				"frame": frame,
				"frameRepeat": maxi(key_frame_repeat, 1),
				"spline": key_spline,
			}
			if not node_xfm.is_empty():
				key["nodeXfm"] = node_xfm
			transforms.append(key)
		if not transforms.is_empty():
			anim["transforms"] = transforms

		var animated_node_count := reader.read_u8()
		var animated_nodes: Dictionary = {}
		for _animated_node_index in range(animated_node_count):
			var node_index := reader.read_u8()
			var mask := reader.read_u8()
			if node_index < 0 or node_index >= node_names.size():
				last_error = "invalid JANI1 animated node index %d" % node_index
				return {}
			var node_anim: Dictionary = {}
			if (mask & 1) != 0:
				node_anim["visible"] = reader.read_u8() != 0
			if (mask & 2) != 0:
				node_anim["frameRepeat"] = maxi(reader.read_u8(), 1)
			if (mask & 4) != 0:
				var run_count := reader.read_u16()
				var frames: Array = []
				for _run_index in range(run_count):
					var frame_value := reader.read_i8()
					var repeat_count := reader.read_u16()
					for _repeat_index in range(repeat_count):
						frames.append(frame_value)
				node_anim["frames"] = frames
			animated_nodes[node_names[node_index]] = node_anim
		if not animated_nodes.is_empty():
			anim["nodes"] = animated_nodes

		if reader.failed:
			last_error = "truncated JANI1 data while decoding %s" % animation_name
			return {}
		result[animation_name] = anim

	if reader.failed or reader.pos != raw.size():
		last_error = "JANI1 ended at %d/%d bytes" % [reader.pos, raw.size()]
		return {}
	return result


static func _spline_name(code: int) -> String:
	if code >= 0 and code < SPLINE_NAMES.size():
		return String(SPLINE_NAMES[code])
	return "LINEAR"