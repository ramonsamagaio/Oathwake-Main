extends RefCounted

# Animation-bank loader for the isolated Alabaster lab.
# Priority:
# 1) self-contained full JANI1/ZSTD bank, when complete;
# 2) an original juno.json source placed in one of SOURCE_CANDIDATES;
# 3) the already-committed gameplay ZSTD chunks;
# 4) the three animations embedded in juno_runtime.json.gz.b64 (handled by runtime).
#
# The loader deliberately does not touch the character renderer. It only supplies
# animation dictionaries to the already-working rig.

const FULL_PARTS := [
	"res://data/labs/alabaster/anims/juno_anims_bin_00.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_01.part",
]
const FULL_DECOMPRESSED_BYTES := 671589
const EXPECTED_ANIMATIONS := 419

const SOURCE_CANDIDATES := [
	"res://data/labs/alabaster/source/juno.json",
	"res://data/labs/alabaster/juno.json",
	"res://terra/data/figures/char/player/juno.json",
	"res://data/figures/char/player/juno.json",
	"user://alabaster_juno.json",
]

const GAMEPLAY_SEARCH_DIRS := [
	"res://data/labs/alabaster",
	"res://data/labs/alabaster/anims",
]
const GAMEPLAY_PREFIX := "juno_gameplay_anims_"

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
	if full.size() >= EXPECTED_ANIMATIONS:
		_set_success("FULL_JANI1", full.size(), FULL_PARTS.size())
		return full

	var source_result := _load_source_candidates()
	if source_result.size() >= EXPECTED_ANIMATIONS:
		_set_success("SOURCE_JSON", source_result.size(), 1)
		return source_result

	var gameplay := _load_gameplay_chunks()
	if not gameplay.is_empty():
		_set_success("GAMEPLAY", gameplay.size(), last_part_count)
		push_warning("AlabasterAnimationBank: full 419-animation bank unavailable; loaded gameplay fallback with %d animations" % gameplay.size())
		return gameplay

	if last_error.is_empty():
		last_error = "no usable full/source/gameplay animation payload found"
	push_warning("AlabasterAnimationBank: %s" % last_error)
	return {}


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
	var encoded := ""
	for path_variant in FULL_PARTS:
		var path := String(path_variant)
		if not FileAccess.file_exists(path):
			last_error = "full-bank part missing: %s" % path
			return {}
		encoded += FileAccess.get_file_as_string(path).strip_edges()

	var compressed := Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		last_error = "full-bank base64 decode failed"
		return {}

	var raw := compressed.decompress(FULL_DECOMPRESSED_BYTES, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != FULL_DECOMPRESSED_BYTES:
		last_error = "full-bank ZSTD incomplete (%d/%d bytes); trying source/gameplay fallback" % [raw.size(), FULL_DECOMPRESSED_BYTES]
		return {}

	var anims := _decode_payload(raw)
	if anims.size() != EXPECTED_ANIMATIONS:
		last_error = "full-bank decoded %d/%d animations" % [anims.size(), EXPECTED_ANIMATIONS]
		return {}
	return anims


static func _load_source_candidates() -> Dictionary:
	var environment_path := OS.get_environment("ALABASTER_JUNO_JSON")
	if not environment_path.is_empty() and FileAccess.file_exists(environment_path):
		var env_anims := load_animation_source_file(environment_path)
		if not env_anims.is_empty():
			return env_anims

	for path_variant in SOURCE_CANDIDATES:
		var path := String(path_variant)
		if not FileAccess.file_exists(path):
			continue
		var anims := load_animation_source_file(path)
		if not anims.is_empty():
			return anims
	return {}


static func _load_gameplay_chunks() -> Dictionary:
	for dir_variant in GAMEPLAY_SEARCH_DIRS:
		var dir_path := String(dir_variant)
		var files := _find_part_files(dir_path, GAMEPLAY_PREFIX)
		if files.is_empty():
			continue
		var encoded := ""
		for filename_variant in files:
			var filename := String(filename_variant)
			var path := dir_path.path_join(filename)
			encoded += FileAccess.get_file_as_string(path).strip_edges()
		last_part_count = files.size()

		var compressed := Marshalls.base64_to_raw(encoded)
		if compressed.is_empty():
			last_error = "gameplay-bank base64 decode failed (%d parts)" % files.size()
			continue

		var frame_size := _zstd_frame_content_size(compressed)
		if frame_size <= 0:
			last_error = "gameplay-bank ZSTD frame does not expose a valid content size"
			continue

		var raw := compressed.decompress(frame_size, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != frame_size:
			last_error = "gameplay-bank ZSTD incomplete (%d/%d bytes from %d parts)" % [raw.size(), frame_size, files.size()]
			continue

		var anims := _decode_payload(raw)
		if not anims.is_empty():
			return anims
	return {}


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
	return _extract_anims_from_json_text(raw.get_string_from_utf8())


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

	if root.has("anims") and typeof(root["anims"]) == TYPE_DICTIONARY:
		return root["anims"]

	# Some compact exports are the animation dictionary itself.
	if root.has("idle") and root.has("walk") and root.has("run"):
		return root
	return {}


static func _zstd_frame_content_size(data: PackedByteArray) -> int:
	# Zstandard frame header parser. We only need Frame_Content_Size so Godot's
	# PackedByteArray.decompress(size, ZSTD) can be used without a hard-coded size.
	if data.size() < 6:
		return -1
	if int(data[0]) != 0x28 or int(data[1]) != 0xB5 or int(data[2]) != 0x2F or int(data[3]) != 0xFD:
		return -1

	var descriptor := int(data[4])
	var fcs_flag := (descriptor >> 6) & 0x03
	var single_segment := ((descriptor >> 5) & 0x01) != 0
	var dict_id_flag := descriptor & 0x03
	var pos := 5

	if not single_segment:
		if pos >= data.size():
			return -1
		pos += 1 # Window Descriptor

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
