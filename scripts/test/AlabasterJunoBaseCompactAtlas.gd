extends SceneTree

const AUDIT_PATH := "res://data/labs/alabaster/juno_base_sprite_audit.json"
const SOURCE_ATLAS_PATH := "res://data/labs/alabaster/juno_base_core_atlas.png"
const COMPACT_ATLAS_PATH := "res://data/labs/alabaster/juno_base_compact_atlas.png"
const COMPACT_MAP_PATH := "res://data/labs/alabaster/juno_base_compact_map.json"
const SOURCE_WIDTH := 672
const WIDTH_STEP := 8


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audit := _load_json_dictionary(AUDIT_PATH)
	if audit.is_empty():
		_fail("could not load JunoBase sprite audit")
		return
	var kept_value: Variant = audit.get("kept_cells", [])
	if not kept_value is Array or (kept_value as Array).is_empty():
		_fail("audit contains no kept_cells")
		return
	var cells: Array[Dictionary] = []
	for cell_value in kept_value as Array:
		if not cell_value is Dictionary:
			continue
		var cell := cell_value as Dictionary
		var w := int(cell.get("w", 0))
		var h := int(cell.get("h", 0))
		if w <= 0 or h <= 0:
			continue
		cells.append({
			"x": int(cell.get("x", 0)),
			"y": int(cell.get("y", 0)),
			"w": w,
			"h": h,
		})
	if cells.is_empty():
		_fail("audit kept_cells contained no valid rectangles")
		return
	cells.sort_custom(_sort_pack_cell)

	# The committed core atlas is already pixel-exact against Juno's source atlas,
	# but keeps the original 672x240 coordinates with unused cells transparent.
	# Packing from it makes CI self-contained while preserving every authored pixel.
	var source_image := Image.new()
	var source_error := source_image.load(SOURCE_ATLAS_PATH)
	if source_error != OK or source_image.is_empty():
		_fail("could not load committed core atlas: %s" % error_string(source_error))
		return
	source_image.convert(Image.FORMAT_RGBA8)

	var max_cell_width := 1
	for cell in cells:
		max_cell_width = maxi(max_cell_width, int(cell["w"]))
	var first_width := maxi(max_cell_width, WIDTH_STEP)
	first_width = int(ceil(float(first_width) / float(WIDTH_STEP))) * WIDTH_STEP
	var upper_width := maxi(SOURCE_WIDTH, first_width)

	var best: Dictionary = {}
	for candidate_width in range(first_width, upper_width + 1, WIDTH_STEP):
		var packed := _pack_shelves(cells, candidate_width)
		if packed.is_empty():
			continue
		var used_width := int(packed.get("width", candidate_width))
		var used_height := int(packed.get("height", 0))
		var area := used_width * used_height
		var score := Vector3i(area, maxi(used_width, used_height), used_width)
		if best.is_empty() or _score_less(score, best.get("score", Vector3i(2147483647, 2147483647, 2147483647)) as Vector3i):
			best = packed
			best["score"] = score
	if best.is_empty():
		_fail("could not pack JunoBase rectangles")
		return

	var packed_width := int(best.get("width", 0))
	var packed_height := int(best.get("height", 0))
	var entries_value: Variant = best.get("entries", [])
	if packed_width <= 0 or packed_height <= 0 or not entries_value is Array:
		_fail("packer returned invalid dimensions")
		return
	var entries := entries_value as Array
	if entries.size() != cells.size():
		_fail("packer lost rectangles: expected=%d packed=%d" % [cells.size(), entries.size()])
		return

	var compact_image := Image.create(packed_width, packed_height, false, Image.FORMAT_RGBA8)
	compact_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var map_entries: Array[Dictionary] = []
	var bounds := Rect2i(Vector2i.ZERO, source_image.get_size())
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var source := entry.get("source", {}) as Dictionary
		var packed_rect := entry.get("packed", {}) as Dictionary
		var source_rect := Rect2i(
			int(source.get("x", 0)), int(source.get("y", 0)),
			int(source.get("w", 0)), int(source.get("h", 0))
		)
		if source_rect != source_rect.intersection(bounds):
			_fail("source rectangle is outside atlas: %s" % _rect_key(source_rect))
			return
		var destination := Vector2i(int(packed_rect.get("x", 0)), int(packed_rect.get("y", 0)))
		compact_image.blit_rect(source_image, source_rect, destination)
		map_entries.append({
			"key": _rect_key(source_rect),
			"source": source.duplicate(true),
			"packed": packed_rect.duplicate(true),
		})

	var png_error := compact_image.save_png(COMPACT_ATLAS_PATH)
	if png_error != OK:
		_fail("could not write compact atlas: %s" % error_string(png_error))
		return

	map_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := a.get("source", {}) as Dictionary
		var sb := b.get("source", {}) as Dictionary
		if int(sa.get("y", 0)) != int(sb.get("y", 0)):
			return int(sa.get("y", 0)) < int(sb.get("y", 0))
		if int(sa.get("x", 0)) != int(sb.get("x", 0)):
			return int(sa.get("x", 0)) < int(sb.get("x", 0))
		if int(sa.get("h", 0)) != int(sb.get("h", 0)):
			return int(sa.get("h", 0)) < int(sb.get("h", 0))
		return int(sa.get("w", 0)) < int(sb.get("w", 0))
	)
	var source_area := source_image.get_width() * source_image.get_height()
	var packed_area := packed_width * packed_height
	var result := {
		"version": 1,
		"profile": "juno_base",
		"source_atlas": SOURCE_ATLAS_PATH,
		"compact_atlas": COMPACT_ATLAS_PATH,
		"source_size": [source_image.get_width(), source_image.get_height()],
		"packed_size": [packed_width, packed_height],
		"cell_count": map_entries.size(),
		"padding": 0,
		"pixel_scale": 1.0,
		"source_area": source_area,
		"packed_area": packed_area,
		"area_ratio": float(packed_area) / maxf(float(source_area), 1.0),
		"entries": map_entries,
	}
	var output := FileAccess.open(COMPACT_MAP_PATH, FileAccess.WRITE)
	if output == null:
		_fail("could not write compact atlas map")
		return
	output.store_string(JSON.stringify(result, "\t"))
	output.flush()

	print("ALABASTER_JUNO_BASE_COMPACT_OK cells=%d source=%dx%d packed=%dx%d area_ratio=%.4f pixel_scale=1.0" % [
		map_entries.size(), source_image.get_width(), source_image.get_height(), packed_width, packed_height,
		float(result["area_ratio"]),
	])
	quit(0)


func _pack_shelves(cells: Array[Dictionary], width_limit: int) -> Dictionary:
	var entries: Array[Dictionary] = []
	var cursor_x := 0
	var cursor_y := 0
	var row_height := 0
	var used_width := 0
	for cell in cells:
		var w := int(cell.get("w", 0))
		var h := int(cell.get("h", 0))
		if w > width_limit:
			return {}
		if cursor_x > 0 and cursor_x + w > width_limit:
			cursor_y += row_height
			cursor_x = 0
			row_height = 0
		entries.append({
			"source": cell.duplicate(true),
			"packed": {"x": cursor_x, "y": cursor_y, "w": w, "h": h},
		})
		cursor_x += w
		row_height = maxi(row_height, h)
		used_width = maxi(used_width, cursor_x)
	return {
		"width": used_width,
		"height": cursor_y + row_height,
		"entries": entries,
	}


func _sort_pack_cell(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("h", 0)) != int(b.get("h", 0)):
		return int(a.get("h", 0)) > int(b.get("h", 0))
	if int(a.get("w", 0)) != int(b.get("w", 0)):
		return int(a.get("w", 0)) > int(b.get("w", 0))
	if int(a.get("y", 0)) != int(b.get("y", 0)):
		return int(a.get("y", 0)) < int(b.get("y", 0))
	return int(a.get("x", 0)) < int(b.get("x", 0))


func _score_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _rect_key(rect: Rect2i) -> String:
	return "%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _fail(message: String) -> void:
	push_error("ALABASTER_JUNO_BASE_COMPACT_FAIL %s" % message)
	quit(1)
