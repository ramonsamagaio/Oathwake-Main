extends RefCounted

# Compact animation bank used only by the isolated Alabaster lab.
# The source animation dictionary is packed as JANI1, then ZSTD-compressed
# and base64-split across two text files so it can live safely in Git.

const PARTS := [
	"res://data/labs/alabaster/anims/juno_anims_bin_00.part",
	"res://data/labs/alabaster/anims/juno_anims_bin_01.part",
]
const DECOMPRESSED_BYTES := 671589
const EXPECTED_ANIMATIONS := 419

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


class ByteReader:
	extends RefCounted

	var data: PackedByteArray
	var pos := 0
	var failed := false

	func _init(source: PackedByteArray) -> void:
		data = source

	func _need(count: int) -> bool:
		if failed or pos + count > data.size():
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
	var encoded := ""
	for path_variant in PARTS:
		var path := String(path_variant)
		if not FileAccess.file_exists(path):
			push_warning("AlabasterAnimationBank: missing %s" % path)
			return {}
		encoded += FileAccess.get_file_as_string(path).strip_edges()

	var compressed := Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		push_warning("AlabasterAnimationBank: base64 decode failed")
		return {}

	# PackedByteArray.decompress_dynamic() does not support ZSTD. The JANI1
	# ZSTD frame has a known uncompressed size, so use decompress() instead.
	var raw := compressed.decompress(DECOMPRESSED_BYTES, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != DECOMPRESSED_BYTES:
		push_warning("AlabasterAnimationBank: ZSTD decode failed, expected %d bytes and got %d" % [DECOMPRESSED_BYTES, raw.size()])
		return {}

	var anims := _decode_jani1(raw)
	if anims.size() != EXPECTED_ANIMATIONS:
		push_warning("AlabasterAnimationBank: expected %d animations, decoded %d" % [EXPECTED_ANIMATIONS, anims.size()])
	return anims


static func _decode_jani1(raw: PackedByteArray) -> Dictionary:
	var reader := ByteReader.new(raw)
	if reader.read_fixed_string(5) != "JANI1":
		push_warning("AlabasterAnimationBank: invalid JANI1 header")
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
					push_warning("AlabasterAnimationBank: invalid transform node index %d" % node_index)
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
				push_warning("AlabasterAnimationBank: invalid animated node index %d" % node_index)
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
			push_warning("AlabasterAnimationBank: truncated JANI1 data while decoding %s" % animation_name)
			return {}
		result[animation_name] = anim

	if reader.failed or reader.pos != raw.size():
		push_warning("AlabasterAnimationBank: JANI1 ended at %d/%d bytes" % [reader.pos, raw.size()])
		return {}
	return result


static func _spline_name(code: int) -> String:
	if code >= 0 and code < SPLINE_NAMES.size():
		return String(SPLINE_NAMES[code])
	return "LINEAR"
